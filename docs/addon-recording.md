# Add-on: shared bus connection and continuous recording

Applies to the Home Assistant add-on and the KNX Box, which run the same
server (`ha-addon/knx_monitor/server/`). The native apps (iOS, Android,
desktop) hold their own connection and do not record in the background.

## Overview

The server keeps **one** bus connection open for as long as it runs, records
every group telegram to the daily history and hands the frames to all open
browser views. Without an open browser nothing is lost, and the gateway sees a
single tunnel no matter how many views are open.

```
Gateway ⇄ UDP/TCP ⇄ [server: BusService] ─┬─ Recorder      → installations/<id>/history/*.ndjson[.gz]
                                           ├─ Availability  → installations/<id>/status/availability-*.ndjson
                                           ├─ AlarmWatch, WatchRuleSet → Home Assistant notifications
                                           ├─ WS /ws/bus ⇄ browser view 1 (SharedTunnel)
                                           └─ WS /ws/bus ⇄ browser view 2
Browser ⇄ WS /ws (UDP relay) ⇄ gateway     – gateway discovery, bus monitor tunnel
```

| Part | Code |
| --- | --- |
| Connection, reconnect, fan-out, send | `server/lib/src/bus.dart` (`BusService`, `BusConfig`) |
| Link implementations (UDP/TCP tunnel, routing, IP Secure, HA integration, KNX HAT) | `server/lib/src/link.dart`, `secure/`, `ha_link.dart`, `ft12_link.dart` |
| History, availability | `server/lib/src/recorder.dart` (`Recorder`, `Availability`) |
| Telegram → history line | `server/lib/src/telegram_json.dart` |
| Browser side | `lib/knx/shared_tunnel.dart` (`SharedTunnel extends KnxTunnel`) |
| Routes | `server/bin/server.dart` |

## Connection modes

`BusConfig.mode` in `server.json`:

| Mode | Meaning |
| --- | --- |
| `udp`, `tcp` | Tunnelling. TCP (KNXnet/IP 2.0) copes better with lossy links. Optionally a fixed tunnel address; if it is taken, `fallback` uses any free one. |
| `routing` | Multicast via an IP router; uses no tunnel slot. |
| `secure` | IP Secure tunnel over TCP. |
| `ha` | No own connection: reads and sends through the KNX integration of Home Assistant. Device access (programming mode, address check, bus monitor) is not available. Gaps in the history are filled from the integration's telegram store, see below. |
| `hat` | KNX HAT of the box on a serial port (`/dev/ttyAMA0` by default), no gateway. |

KNX Data Secure group keys come from `secure_keys.json`, which the app writes
when a keyring is imported.

## Configuration and status

`GET/PUT /api/bus` reads and writes `server.json` of the active installation
and returns the status (state, error, tunnel address, gateway description,
telegrams, history size). The gateway is set in the app, which already has
discovery and input. Server settings:

| Field | Default | Range |
| --- | --- | --- |
| `enabled` | `false` | keep the connection and record |
| `retentionDays` | 7 | 0–3650 (0 = no history) |
| `maxMegabytes` | 1000 | 10–1,000,000 |
| `flushSeconds` | 5 | 0–600 |
| `alarms` | `true` | server-side alarm notifications |

Further endpoints: `/api/bus/availability` and `/api/bus/stats` (optionally
`?installation=<id>` for another installation, read-only), `/api/restarts`,
`/api/files/…` for the history and other data files.

## Protocol `/ws/bus`

Binary WebSocket messages, first byte = type. The server forwards cEMI frames
and does not interpret anything the client can decode itself.

| Direction | Type | Content |
| --- | --- | --- |
| S → C | `0x01` frame | cEMI frame from the link (L_Data.ind and L_Data.con, all address types) |
| S → C | `0x02` state | JSON: `connected` / `connecting` / `disconnected` / `yielded`, error, tunnel address, gateway description, settings |
| S → C | `0x03` watcher hit | JSON `{ids, line}`, `line` in history format |
| C → S | `0x10` send | request ID (2 bytes) + cEMI L_Data.req |
| S → C | `0x11` send result | request ID + result byte + text |
| C → S | `0x12` yield tunnel | 1 byte: 1 = release, 0 = take back |

Send results: 0 sent, 1 not connected, 2 link error, 3 invalid frame, 4 device
busy (another view holds a connection-oriented session to it), 5 not allowed
(paired box device without admin rights may only send group values), 6
read-only mode is on.

L_Data.con goes to **all** clients. `KnxTunnel.sendFrame` already matches
confirmations by destination, so other views see foreign sends as outgoing.
This is intended.

`0x12` exists for the bus monitor, which needs its own exclusive tunnel on
most gateways: while a view has released the tunnel, the server is
disconnected (`yielded`) and recording pauses. It reconnects when the view
takes the tunnel back or closes. Releasing requires admin rights.

## Connection handling

- After a loss the server reconnects **immediately**; failed attempts back
  off 1, 2, 4, 8, 15, 30, 60 s. When the gateway reports no free tunnel, it
  retries every 15 s and reports the state to the clients.
- An outage is logged once, not on every attempt.
- Heartbeat every 60 s, ACKs and sequence counters as in
  `lib/knx/knx_tunnel.dart`, but without Flutter (streams instead of
  `ValueNotifier`, errors as codes instead of translated texts).
- On SIGTERM (Supervisor or systemd) the server writes the pending history and
  disconnects the tunnel before exiting.
- In the browser, `AutoReconnect` only reopens the WebSocket; the bus
  connection belongs to the server. Disconnecting a view closes only that view.
- **Pause** on the start screen frees the tunnel, e.g. for ETS.

## History

Format: one JSON line per group telegram in
`installations/<id>/history/YYYY-MM-DD.ndjson`, exactly as `Telegram.toJson()`
writes it, so `HistoryStore.days()`/`open()` in the app read it unchanged.
`test/bus_test.dart` in the server compares `telegramJson` with the app's
format.

- Buffered and written every `flushSeconds`; `fsync` only every 30 s and on
  exit, to spare SD cards. A power cut loses at most that interval.
- Finished days are gzipped (`.ndjson.gz`); leftovers from a crash are packed
  at the next start.
- Retention by days and by total size; the oldest days go first.
- Too little free space (< 256 MB): delete the oldest days (today stays); if
  that is not enough, stop writing and report it.
- A full buffer is counted (`dropped`), never discarded silently.
- On the box without a reliable clock, lines go to
  `history/unsynced-<start>.ndjson` with a monotonic counter and are moved
  into the right days once the clock is set.
- The server timestamps every telegram, so client clocks do not matter.
- Views connected through `SharedTunnel` do not write to `HistoryStore`
  themselves (no duplicate lines).

Size: one line is about 100 bytes. At 5 telegrams/s that is about 43 MB per
day uncompressed, at 20/s about 170 MB; gzip saves roughly a factor of 8–10.

The history, settings and an imported keyring are part of Home Assistant
backups (`backup: hot`); the history is not excluded.

### Telegrams for charts

`GET /api/bus/telegrams?a=<address>[:<main>.<sub>],…&from=<ms>&to=<ms>[&installation=<id>]`
(`history_query.dart`) returns the telegrams of up to 12 group addresses
over at most 31 days as history lines, per address oldest first and with the
last value before `from` in front. The app's charts use it for the periods
Today, 7 and 30 days; "Loaded" stays what the app holds in memory (the latest
5,000 telegrams). Telegrams that arrive after the query are added from the
live view, so the chart keeps running.

- Access like `/api/bus/stats`.
- Only lines of the asked addresses are decoded; the others are skipped by
  their `d` field. Reads are left out.
- Thinned per address to about 4,000 lines: runs of the same value keep only
  their first and last line (a step line still changes at the right time); if
  that is still too many, each of 1,000 time columns keeps its first, last,
  lowest and highest value (the DPT given with the address decides what is a
  number).

### Filling gaps from Home Assistant

In mode `ha` the KNX integration records anyway: since Home Assistant 2026.7
it keeps its telegrams in its own store (library knx-telegram-store, SQLite or
PostgreSQL, retention set in the integration). After every connect,
`ha_history.dart` adds to the history what the integration received while the
add-on was not listening:

- The gap runs from the newest recorded telegram before the subscription
  (`HaLink.liveSince`) up to the subscription; without history it starts at
  the history's retention.
- It is read with the WebSocket command `knx/query_telegrams`, oldest first,
  in pages of 5,000, and written page by page. Each page continues at the
  previous page's last timestamp (the store filters `>=` and orders by
  timestamp); `offset` only skips the telegrams at exactly that timestamp.
- Both sides stamp a telegram with their own time of arrival. At both edges of
  the gap a telegram with the same sender, address, type and data within 3 s
  counts as already recorded; each recorded telegram matches once.
- Lines for days already packed go into a new day file; packing merges it in.
- `knx/query_telegrams` is an interface of the integration's own panel, not a
  documented API. If it is missing (Home Assistant before 2026.7), still
  starting or changed, the gap stays as before and the log says why; the
  connection itself is never affected.

Only the add-on's history is filled. Comments, recordings, watchers and alarms
work on the add-on's own data and do not see these telegrams live.

### Export as ETS file

`GET /api/export/ets-xml?from=<ms>&to=<ms>[&installation=<id>]`
(`ets_xml.dart`) returns the history of `[from, to)` as an ETS group monitor
file (`CommunicationLog`, namespace `http://knx.org/xml/telegrams/01`), with
`Content-Disposition: attachment` and the name
`knx-monitor-<first day>-<last day>.xml`.

- Access like `/api/bus/stats`: every role that may read the history (Ingress
  in the add-on, password or paired device on the box), not only admins.
  `?installation=` reads another installation; unknown ids get 404.
- At most 31 days; missing, reversed or longer ranges get 400 with a reason.
- Streamed day by day in chunks of about 64 KB. Each day is read twice: first
  only the times (first telegram for `RecordStart`, whether the day is in
  order), then the telegrams. A day out of order (lines appended by
  `retime`) is sorted in memory; normally lines go straight through.
- The output is byte for byte what the app's `buildEtsXml` writes:
  `Telegram` with `Timestamp` (UTC, ISO 8601), `Service` (`L_Data.ind`, or
  `L_Data.con` for own telegrams), `FrameFormat="CommonEmi"` and `RawData`
  (cEMI in uppercase hex, the recorded frame or one rebuilt from the fields
  like the app's `cemiOf`). The fixture in
  `server/test/fixtures/ets_xml/` was written by the app; both
  `server/test/ets_xml_test.dart` and the app's `test/telegram_files_test.dart`
  compare against it.

With `?all=1` instead of `from`/`to` the endpoint returns the whole history as
a zip, `knx-monitor-<first day>-<last day>.zip`, with one file
`knx-monitor-YYYY-MM-DD.xml` per day that has telegrams (each written like a
single-day export). SpectrumKNX imports a zip of such files in one go. The zip
is written while it is sent (`zip_stream.dart`: deflate, sizes and CRC in a data
descriptor after each entry, no Zip64), so neither the server nor the browser
holds it in memory; the native app receives it as bytes, about a tenth of the
XML. Without history the answer is 400.

Other programs with this format, checked against their source:

| Program | What it writes | Reads ours |
| --- | --- | --- |
| knx-telegram-store (Home Assistant's KNX integration), `formats/ets_xml.py` | No `RecordStart`/`RecordStop`, optional `ConnectionName`, six fraction digits, uppercase cEMI | Yes; needs the namespace and `Timestamp`/`RawData` on every `Telegram` |
| SpectrumKNX (`backend/telegram_export.py`, `telegram_import.py`) | Uses knx-telegram-store with `ConnectionName="Spectrum KNX Export"`, always `L_Data.ind` | Yes; decodes cEMI `0x29`, `0x2E`, `0x11` |
| ETS 6 | Seven fraction digits, `TransportSecurity` | Yes |
| Gira loggers | `L_Busmon.ind` (cEMI `0x2B` with TP1 frame), local time marked `Z` plus a `timezone offset` comment | – |
| Node-RED knx-ultimate | No XML declaration, lowercase hex | – |

The app's import (`parseEtsXml`) accepts all of them: any namespace prefix,
BOM, timestamps with any number of fraction digits or none, an offset or no
zone (counted as UTC, like knx-telegram-store), the Gira comment, busmonitor
frames (checksum checked), `L_Data.req`, and telegrams without `RawData`
(skipped).

Checked by running, not only by reading (4.11.2026, SpectrumKNX `main`,
knx-telegram-store 0.15.2, xknx 4.0.0): a file written by SpectrumKNX's export
code is a test case in `test/telegram_files_test.dart`, and SpectrumKNX's
reader (`iter_communication_log` plus xknx `CEMIFrame.from_knx`, as in its
import) decodes every telegram of our `history.xml` fixture.

## Availability

Once a minute the server appends a line to
`status/availability-YYYY-MM.ndjson`: connected or not, and the number of
telegrams since the last line. This explains every gap in the history:

| Lines in the gap | Meaning |
| --- | --- |
| connected, 0 telegrams | quiet bus |
| not connected | connection lost |
| no lines | server was not running |

There is deliberately no end marker on shutdown (a power cut would not write
it). Three months are kept. The app shows the result in the day list, e.g.
"add-on not running for 11 h". Unexpected restarts are tracked separately
(`crash_watch.dart`: `running.json`, `restarts.ndjson` in the root of the data
folder, not per installation).

## Server-side features

With continuous recording these run on the server, not in the browser:

- **Alarms** (`alarms.dart`): DPT 1.005, DPT 21.001 and alarm words in names
  create Home Assistant notifications. A view on `SharedTunnel` does not
  notify itself, to avoid duplicates.
- **Watchers** (`watchers.dart`): a hit goes to all views (`0x03`) and as a
  Home Assistant notification.
- **Installation report** (`report.dart`): off until enabled. Daily rollups
  in `reports/days/`, reports in `reports/`, settings in
  `report_settings.json` (blocked for `/api/files/`). Runs hourly from the
  maintenance timer, condensing in its own isolate. Rollups are the only
  source for reports: the history often keeps only a few days, availability
  three months.
- **Outbound requests** (`outbound.dart`): no redirects, timeout, errors only
  as codes so that neither address nor token reaches the log.
- **Data export** (`exporter.dart`, `grafana.dart`): `export.json`, a
  separate port for Prometheus `/metrics` (default 9464), a bounded buffer
  for InfluxDB.

## Code sharing between app and server

App and server share the KNX protocol code through the internal package
`packages/knx` (addresses, cEMI, the history's JSON line `Telegram.toJson`,
KNXnet/IP frames, DPT values, KNX Secure); see
[architecture.md](architecture.md#the-package-knx). Connections, recording and
everything with Flutter stay separate. The server test above still guards the
shared history format.

## Risks and how they are handled

| Risk | Handling |
| --- | --- |
| Connection-oriented diagnostics (T_Connect, device descriptor, address check) run over the shared tunnel address; two views would break each other's session | The server locks each device to one view (send result 4) until T_Disconnect or 10 s of inactivity. |
| The permanent tunnel blocks a slot around the clock; small IP interfaces may have only one, which then blocks ETS | **Pause** in the app; routing or `ha` mode use no slot. |
| Every Home Assistant user with panel access can send through the server tunnel | Add-on option `read_only` (default on) rejects every send, including read requests. |
| Data loss that unit tests do not see | The CI smoke test starts the built image and checks that data lands in `/data` and survives a restart (`.github/workflows/addon.yml`). |

## Tests

- Server: fake gateway `server/test/fake_gateway.dart`; cases include
  connect, heartbeat loss and reconnect, fan-out to two clients, send
  results, recorder format and cleanup (`bus_test.dart`,
  `recorder_*_test.dart`, `robust_frames_test.dart`).
- Process: `/healthz` and the add-on watchdog in `server_process_test.dart`.
- Upgrades with real server versions: `tool/addon_upgrade_test.sh`, see
  [resilience tests](resilience-tests.md).
