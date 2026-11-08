# Busclear

Busclear as a sidebar panel in Home Assistant: group monitor, objects,
communication map, recordings and bus diagnostics – in the browser, on any
device, also on the go via the Home Assistant app.

## How it works

Browsers cannot speak UDP. The small server in the add-on forwards the app's
KNXnet/IP packets via WebSocket to the gateway (tunneling, NAT mode) and stores
the ETS catalog, recordings and long-term history in the add-on's data folder
(included in backups).

- Access only through Home Assistant (Ingress) – requests to the port from
  anywhere else in the LAN are rejected.
- The add-on keeps **one** connection to the bus, shared by all open views
  (tunnel, routing, IP Secure or the Home Assistant KNX integration). While
  the bus monitor tool is open, the add-on hands its tunnel over to it –
  recording pauses for that time and resumes when you close the bus monitor.
- Use **Pause** on the start screen to free the tunnel, e.g. for ETS.
- The add-on uses the host network so it can reach the gateway via UDP and
  discover gateways on your network.

## Getting started

1. Start the add-on and open **Busclear** in the sidebar.
2. Pick your gateway (discovered automatically) or enter its IP address.
3. Optionally import your ETS project (`.knxproj` or group address CSV) to get
   names, datapoint types and devices.

Gateway address and language are chosen in the app and remembered per browser.

## Continuous recording

Once you connect in the app, the add-on stays connected – also when no browser
is open – and reconnects by itself after gateway restarts or network dropouts.
Every telegram goes into the history (Recordings → History), one file per day;
finished days are compressed. Retention (days), size limit and write interval
are set in the app. Writing less often spares an SD card, but a power cut then
loses the last block.

Defaults: 7 days, at most 1,000 MB, written every 5 seconds. The add-on
collects the telegrams of those 5 seconds and appends them in one go instead of
writing each telegram on its own, which spares SD cards and SSDs alike.

How much space the history needs:

| | per telegram | per 1 million telegrams |
| --- | --- | --- |
| Today (plain file) | about 95 bytes | about 95 MB |
| Finished days (compressed) | about 20 bytes | about 20 MB |

For example, 20,000 telegrams a day take about 0.4 MB per finished day, about
12 MB a month and about 150 MB a year; 100,000 a day about 60 MB a month. Measured
with a mix of switching, 1-byte, 2-byte and 4-byte values; buses that repeat the
same values a lot compress better. The day list shows the actual size, and the
MQTT device reports it as "History size".

Names, DPTs and units are not stored with the telegrams. The history keeps the
raw telegram (time, sender, group address, data), and the app reads names and
DPTs from the ETS project that is loaded now. After uploading a changed ETS
project, already recorded telegrams show the new names and values too. Only
PDF and CSV files exported earlier keep the names of that moment; an ETS file
holds raw telegrams only and shows the names of whatever project opens it.

Once a minute the add-on notes whether the bus was connected. Gaps in the
history are explained in the day list ("bus disconnected for 3 min",
"add-on not running for 11 h").

The history, settings and an imported keyring are part of Home Assistant
backups.

## Comments, reporting a problem, exports

- **Comments** can be added to telegrams, charts and recordings, with up to
  three screenshots. They are stored per installation in the add-on's data
  folder and listed under Tools › Comments.
- **Report a problem** (Tools): start it, reproduce the fault and tap "It
  happened now" each time, then create the diagnostic package and send it to
  your electrician. Opening a package shows its findings. Names can be left
  out of the package.
- **Exports** collects everything in one page: telegrams as PDF, CSV or ETS
  file, reports, a combined ZIP and the last exports.

## History as an ETS file (Home Assistant, SpectrumKNX)

Exports › Continuous › "History as ETS file" downloads the add-on's recording
for today, the last 7 or the last 30 days as an ETS group monitor file
(`CommunicationLog` XML). "Everything" downloads the whole history as a zip with
one such file per day, for example to move it to SpectrumKNX in one go. In the
browser the file goes straight to your downloads folder, so long periods do not
pass through the app.

The same format is read and written by the ETS group monitor, by the telegram
store of Home Assistant's KNX integration (library knx-telegram-store) and by
SpectrumKNX:

- **SpectrumKNX:** use its telegram import and choose the downloaded `.xml`
  or `.zip` file. Telegrams already in its database are skipped.
- **ETS:** open the file in the group monitor.
- **Other tools** that use knx-telegram-store can read it as well. Home
  Assistant itself currently offers no file import for its KNX telegram history.

The other way round, Recordings › Import in Busclear opens such files from
the ETS (also ETS 6), Home Assistant / knx-telegram-store, SpectrumKNX, Gira
loggers and Node-RED knx-ultimate. Only group telegrams are taken over.

The app fetches it from `GET /api/export/ets-xml?from=<ms>&to=<ms>` (Unix
time in milliseconds, at most 31 days), or the zip with
`GET /api/export/ets-xml?all=1`. It is reachable only the way the app
is: through Home Assistant Ingress, on the Busclear Box with the box password or a
paired device.

## Connection types

- **UDP / TCP tunnel** – TCP copes better with lossy links (KNXnet/IP 2.0).
  Optionally request a fixed tunnel address; if it is taken, a free one is used.
- **Routing** – multicast 224.0.23.12 via an IP router, uses no tunnel slot.
- **IP Secure** – user and password of the secure tunnel (or import the ETS
  keyring, then they are taken from it).
- **Home Assistant** – no own tunnel: reads what the KNX integration of Home
  Assistant receives and sends via `knx.send` / `knx.read`. Device access
  (programming mode, address check, bus monitor) is not available this way.
  With Home Assistant 2026.7 or newer the add-on also fills gaps in its history
  from the telegram store of the KNX integration: after the first start and after
  every restart it adds what Home Assistant received in the meantime, at most as
  far back as the history's retention.

## Tap points (several connections)

One installation can have up to eight tap points: the normal connection plus
further tunnels or routing, for example one IP interface per line
([#8](https://github.com/regetskcob/KNX-Monitor/issues/8)). Set them up in the
app under Connect (expert mode) › Tap points; the add-on and the box then hold
all of them, also while no app is open.

- A telegram seen at several tap points becomes one entry. The history keeps
  where it was seen first (`tp`) and the other sightings with offset and hop
  count (`sg`). Older apps read such a history as before.
- A telegram seen at one tap point only stayed in its line or was filtered by a
  coupler. The app shows the lines as chips in the list and the path in the
  telegram details.
- Each tunnel tap point occupies a tunnel on its interface. A tap point that
  drops reconnects on its own; the others keep running.
- Over VPN use a TCP tunnel and a larger merge window (e.g. 250 ms): the
  receive time is taken here, not on the bus. Routing usually does not get
  through a VPN.
- KNX Data Secure telegrams are decrypted once, at the tap point that sees them
  first. At further tap points the same telegram counts as a replay and is
  left out.

## KNX Data Secure

Import the keyring exported from ETS (project → export keyring) under
Project → KNX Secure. Secured group telegrams are then decrypted live and in
the recording; writing to secured addresses is encrypted.

## Alarm notifications

When a group address switches to an alarm or fault state, the add-on creates a
Home Assistant notification (at most one per address every 5 minutes; can be
turned off with `alarm_notifications` in the add-on configuration). With
continuous recording this also works without an open browser.

## Watchers

Watchers (Tools → Watchers) report a group address as soon as it is sent,
optionally only for a certain value. In the add-on they run on the server:
they keep working without an open browser and send a Home Assistant
notification (at most one per watcher and minute; also as push if
`notify_service` is set; can be turned off with `watcher_notifications`). An open Busclear additionally plays the sound
and shows the hit. Watchers are stored in the add-on and shared by all
browsers.

## Automations

The add-on fires Home Assistant events you can use as triggers ("Event" in
the automation editor), also without an open browser. They fire whether or
not notifications are on:

| Event | When | Data |
| --- | --- | --- |
| `knx_monitor_watcher` | a watcher fires | `watcher_id`, `name`, `label`, `address`, `source`, `value` (number rules), `raw`, `installation` |
| `knx_monitor_alarm` | an alarm or fault object switches on or off | `address`, `name`, `kind` (`alarm`/`fault`), `active`, `installation` |
| `knx_monitor_bus` | the bus connection is lost or back | `connected`, `state`, `reason`, `installation` |

Blueprints to import with one click:

- [Watcher fired](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Fknx_monitor_watcher.yaml)
- [Alarm or fault](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Fknx_monitor_alarm.yaml)
- [Bus connection lost or back](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Fknx_monitor_bus.yaml)

Example without a blueprint:

```yaml
triggers:
  - trigger: event
    event_type: knx_monitor_alarm
    event_data:
      active: true
actions:
  - action: notify.mobile_app_my_iphone
    data:
      title: "KNX alarm"
      message: "{{ trigger.event.data.name }} ({{ trigger.event.data.address }})"
```

If you notify yourself through automations, turn off `alarm_notifications`
and `watcher_notifications` below, so you do not get two messages.

## Device and entities (MQTT)

If an MQTT broker is set up in Home Assistant (usually the Mosquitto add-on
with the MQTT integration), the add-on appears as the device **Busclear**
by itself; no credentials to enter. It brings:

| Entity | What |
| --- | --- |
| Bus connected | connectivity of the add-on's bus connection |
| Recording | switch to pause and resume continuous recording |
| Telegrams per minute, Telegrams today | bus activity |
| Repeats per minute, Last telegram | diagnostics |
| Bus load | estimated load of the line in % (see below), averaged over the last minute |
| Open alarms | alarm and fault objects that are currently on |
| Last alarm, Last alarm time | name (or group address) and time of the most recent alarm or fault that switched on; attributes `kind`, `address`, `time` |
| Availability 24 h | share of the last 24 hours with a bus connection, in % |
| History size, Free space | diagnostics: disk space used by the recording and free space on the data disk, in MB |
| Low space | diagnostics: on when recording paused because the disk is full |
| Watcher, Alarm | event entities with the same data as the events above |

On the device page under Automations you find **device triggers** for each
watcher, for alarms and faults switching on or off, and for the bus
connection being lost or back, so you do not need to type event names. If the
add-on stops, the device shows as unavailable.

How the key figures are measured:

- **Bus load**: for every telegram the add-on estimates how long it occupies
  a TP line at 9600 bit/s, the same estimate as the app's bus monitor and the
  installation report: (50 + 13 × bytes + 15 + 13) bit times, i.e. idle time,
  13 bit times per character, and the acknowledgement. The load is the
  occupied time per elapsed time since the last update. It only counts what
  the add-on hears: telegrams behind line couplers that the filters keep back
  are missing.
- **Open alarms** and **Last alarm** start empty after a restart of the add-on
  and fill with the next telegrams; the alarm and fault objects come from the
  ETS project, as for the notifications.
- **Availability 24 h** comes from the heartbeats the add-on writes once a
  minute while recording is on. Without recording it stays unknown; time
  before the first heartbeat does not count. It is updated every 15 minutes.
- **Free space** is measured while recording, at least once an hour.

All values are also in the JSON on `knx_monitor/state` and, for systems
without discovery, each on its own topic (`knx_monitor/bus_load`,
`knx_monitor/open_alarms`, `knx_monitor/last_alarm`, `knx_monitor/history_mb`,
`knx_monitor/free_mb`, `knx_monitor/low_space`, `knx_monitor/availability_24h`,
…), sent only when they change. The bus connection triggers use
`knx_monitor/bus/connected` and `knx_monitor/bus/disconnected`.

Example dashboard (entity IDs depend on the language Home Assistant used when
the device first appeared; check them on the device page. Devices set up before
the rename to Busclear keep their IDs starting with `knx_monitor_`):

```yaml
type: vertical-stack
cards:
  - type: gauge
    entity: sensor.busclear_bus_load
    name: Bus load
    max: 100
    severity:
      green: 0
      yellow: 30
      red: 60
  - type: entities
    entities:
      - binary_sensor.busclear_bus_connected
      - sensor.busclear_availability_24h
      - sensor.busclear_telegrams_per_minute
      - sensor.busclear_open_alarms
      - sensor.busclear_last_alarm
      - sensor.busclear_history_size
      - binary_sensor.busclear_low_space
```

Blueprints for the key figures:

- [Bus load high](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Fknx_monitor_bus_load.yaml)
- [Recording space low](https://my.home-assistant.io/redirect/blueprint_import/?blueprint_url=https%3A%2F%2Fgithub.com%2Fregetskcob%2FKNX-Monitor%2Fblob%2Fmain%2Fblueprints%2Fautomation%2Fknx_monitor_low_space.yaml)

Without a broker everything else keeps working; the device appears as soon as
one is set up (the add-on checks every 5 minutes).

## Every telegram to MQTT (preview)

A first version for testing ([issue #11](https://github.com/regetskcob/KNX-Monitor/issues/11)):
the add-on sends every group telegram as JSON to the MQTT broker, with the
receive time and what the ETS project knows. Long-term analysis can then run in
your own database (Node-RED, Telegraf, TimescaleDB, ioBroker, your own scripts).

**Off by default.** Switch it on with the add-on option **Every telegram to
MQTT** (`mqtt_telegrams`) and restart the add-on; Docker and the box use
`MQTT_TELEGRAMS=true` (with `MQTT_HOST` and friends). Anyone who can read the
broker sees the addresses, names and values of your installation.

Topic: `knx_monitor/telegram/<main>/<middle>/<sub>`, e.g.
`knx_monitor/telegram/1/2/3`; subscribe to a range with
`knx_monitor/telegram/1/#`. QoS 0, not retained.

```json
{
  "t": 1794088582430,
  "ts": "2026-11-07T21:56:22.430079Z",
  "inst": "wohnhaus",
  "boot": "4a877bf4-9ac9-45ef-9111-e1109fbba55e",
  "seq": 1237831,
  "ga": "3/1/7",
  "ga_name": "Wohnen Temperatur",
  "src": "1.1.5",
  "src_name": "Präsenzmelder Wohnen",
  "type": "write",
  "dpt": "9.001",
  "value": 21,
  "unit": "°C",
  "hop": 6,
  "raw": "0C1A",
  "repeat": false,
  "project": {"id": "0f3a91c2", "date": "2026-11-02T08:15:00Z"}
}
```

| Field | What |
| --- | --- |
| `t` | receive time in the add-on, Unix time in ms (the same as in the history) |
| `ts` | the same receive time as ISO 8601 in UTC with microseconds |
| `inst` | installation: the id of the active installation, or the option "Installation ID" (`mqtt_installation`, Docker and box `MQTT_INSTALLATION`) if set; tells several servers apart in one database |
| `taps` | only with further tap points: numbers of the tap points that saw the telegram, the first one first (0 = the normal connection) |
| `tap_names` | only with further tap points: the names of the same tap points in the same order, `main` for the normal connection. The numbers shift when a tap point is removed, the names stay |
| `boot` | random id (UUID) of this server start; a new value means `seq` starts over |
| `seq` | running number per server start. A gap means a lost message (rate limit, broker away, QoS 0); a new `boot` is not a gap |
| `ga`, `ga_name` | group address (always three levels) and its name from the ETS project or the app |
| `src`, `src_name` | individual address of the sender and its device name from the ETS project |
| `type` | `write`, `read` or `response` |
| `dpt`, `value`, `unit` | datapoint type from the project, decoded value (`true`/`false` for DPT 1, otherwise a number), unit if known |
| `hop` | hop count (routing counter); below 6 the telegram passed a coupler |
| `raw` | payload as hex; missing for `read` |
| `repeat` | repeated telegram; repeats are only sent with `MQTT_REPEATS=true` |
| `secure` | `true` for a decrypted KNX Data Secure telegram (only sent on request, see below) |
| `outgoing` | `true` for telegrams the add-on sent itself |
| `project` | state of the ETS project that `ga_name`, `src_name` and `dpt` come from. The project file carries no id or date of its own, so `id` is a short checksum of the project as stored in the add-on and `date` the time it was uploaded (UTC). A new upload gives a new `id` |

Without an ETS project `ga_name`, `src_name`, `dpt`, `value`, `unit` and
`project` are missing.
While the broker is unreachable telegrams are not sent and not replayed; the
history and the ETS file still have all of them. At most 500 telegrams per
second are sent (a TP line carries about 50); beyond that they are dropped, so
a flood on the bus cannot clog the broker connection.

Three more options, for databases that keep the stream 1:1 (for example an
EMQX rule into TimescaleDB):

- **Send raw data too** (`mqtt_raw`; Docker and box `MQTT_RAW=true`) adds:

  | Field | What |
  | --- | --- |
  | `cemi` | the complete cEMI frame as hex, as the add-on recorded it |
  | `msg` | frame kind: `ind` from the bus, `con` confirmation of a telegram the add-on sent |
  | `prio` | priority: `system`, `normal`, `urgent` or `low` |
  | `ack_req` | acknowledge request bit from the control field |
  | `key` | checksum (first 16 hex characters of SHA-256) over sender, group address, service (read/response/write) and payload, without hop count, repeat bit and priority |

  The same telegram seen at two tap points, or repeated, has the same `key`.
  Real installations also send identical telegrams shortly one after another,
  so treat a `key` as "the same telegram" only within a short time window.
  For KNX Data Secure telegrams `cemi` is the decrypted frame, as in the
  history. Example with raw data only (next point):

  ```json
  {
    "t": 1794088582430, "ts": "2026-11-07T21:56:22.430079Z",
    "inst": "wohnhaus", "boot": "4a877bf4-9ac9-45ef-9111-e1109fbba55e", "seq": 1237831,
    "ga": "3/1/7", "src": "1.1.5", "type": "write", "hop": 6,
    "raw": "0C1A", "repeat": false,
    "msg": "ind", "prio": "low", "ack_req": false,
    "cemi": "2900BCE0110519070300800C1A", "key": "4476d439076a65ad",
    "project": {"id": "0f3a91c2", "date": "2026-11-02T08:15:00Z"}
  }
  ```

- **Raw data only** (`mqtt_raw_only`; `MQTT_RAW_ONLY=true`): raw data, but
  without `ga_name`, `src_name`, `dpt`, `value` and
  `unit`, for databases that decode the values themselves. It implies raw data.
- **Only these group addresses to MQTT** (`mqtt_filter`; `MQTT_FILTER`):
  three-level addresses or ranges separated by commas, `#` as the last level
  takes everything below it, e.g. `1/#,3/2/#,4/1/7`. Empty sends everything.
  Filtered-out telegrams are not counted and use no `seq`, so they leave no
  gap. Patterns that cannot be read are named in the log and match nothing.

Security:

- **KNX Data Secure telegrams are not sent** by default. The add-on decrypts
  them for the history, but on the broker they would be plain text for every
  MQTT user. Only with the option **KNX Secure telegrams to MQTT too**
  (`mqtt_secure_telegrams`; Docker and box: `MQTT_SECURE_TELEGRAMS=true`) are
  they sent, marked `"secure": true`. Secured telegrams the add-on cannot
  decrypt (no keyring, key missing or invalid) are never sent; import the
  keyring under Project → KNX Secure.
- Mosquitto lets every MQTT user read every topic unless you set up ACLs.
  Other add-ons and devices with MQTT credentials then see your telegrams;
  restrict `knx_monitor/telegram/#` with an ACL if that matters.
- With a broker outside the host (Docker, box) use TLS (`MQTT_SSL=true`),
  otherwise the telegrams cross the network unencrypted.
- Why a telegram stays off the broker is shown in three places: the app under
  Tools → Data export (section "MQTT: every telegram", also in the web app of
  Docker and the box) with sent, dropped and left-out counts and the reason;
  the log, once per group address (add-on log, `docker logs`, box journal);
  and the state topic `knx_monitor/state` with `telegrams_sent`,
  `telegrams_dropped`, `telegrams_secure_skipped` and `telegrams_undecrypted`.
- The stream only sends. The add-on subscribes to nothing under
  `knx_monitor/telegram/`, so nothing on the broker can write to the bus
  through it.

Not in this preview yet (planned in the issue): settings in the app, address
filters, sender device names, retained last values, a switch and counters on
the MQTT device. Feedback is welcome in the issue.

Telegraf example (to InfluxDB or TimescaleDB):

```toml
[[inputs.mqtt_consumer]]
  servers = ["tcp://core-mosquitto:1883"]
  topics = ["knx_monitor/telegram/#"]
  data_format = "json_v2"
  [[inputs.mqtt_consumer.json_v2]]
    measurement_name = "knx"
    timestamp_path = "t"
    timestamp_format = "unix_ms"
    [[inputs.mqtt_consumer.json_v2.tag]]
      path = "ga"
    [[inputs.mqtt_consumer.json_v2.tag]]
      path = "ga_name"
    [[inputs.mqtt_consumer.json_v2.field]]
      path = "value"
      type = "float"
```

## Busclear integration (without MQTT)

Instead of the MQTT device, the add-on can be a device of its own integration:
install **Busclear** from HACS (custom repository
`https://github.com/regetskcob/KNX-Monitor-HA`, type *Integration*), restart
Home Assistant, and confirm "New device found: Busclear". The add-on hands
over address and access by itself; no MQTT broker is needed.

The integration brings the same sensors, recording switch and event entities as
the MQTT device, device triggers for watchers (also one per watcher, with its
name), alarms, faults and the bus connection, device conditions (bus connected or
disconnected, recording on, alarm open, low space), the services
`knx_monitor.create_report` and `knx_monitor.export_history` (ETS file in the
`knx_monitor` folder of the configuration), a diagnostics download and repairs
when the bus has been disconnected for more than 10 minutes, recording paused
because the disk is full, or a group address that usually sends regularly has
stopped (with "Ignore"; it comes back by itself once the address sends again).
The add-on checks the last 7 days of history for that every hour, with the same
rule as the app's health check, and stays quiet while recording is off or the bus
is disconnected.

While it is set up, the add-on stops announcing its MQTT entities; remove the
integration and they come back. The integration reaches only a few endpoints of
the add-on with its own token (`/api/ha/`), everything else stays behind Ingress.

## Dashboard card

Charts you save in Busclear (Tools → Charts) can go straight onto your
dashboards: add the card **Busclear chart** ("Add card", search for
"KNX"), pick the chart and the time range. The card reads the values from
the continuous recording, so it shows the whole range even for addresses
Home Assistant does not know, and updates every minute. Tap or hover to read
the values at a point in time; 1 h, 6 h, 24 h and 7 days can be switched on
the card itself.

Besides group addresses, charts can show the bus itself: telegrams per
minute, repeats per minute and the load per line. In Busclear they are
in the chart library under "Bus"; on the card the add-on computes them from
the continuous recording.

The add-on puts the card into `/config/www/knx-monitor/` and registers it as
a dashboard resource on every start; nothing to install. If `www` did not
exist before, Home Assistant needs one restart (a notification says so).
Dashboards in YAML mode have no resource list; add it there yourself:

```yaml
lovelace:
  resources:
    - url: /local/knx-monitor/knx-monitor-chart-card.js
      type: module
```

```yaml
type: custom:knx-monitor-chart-card
chart: Living room
hours: 24
title: Climate # optional
```

## Installation report

Tools › Installation report. Off by default. Once enabled, the add-on condenses every
day and creates a monthly or quarterly report: availability, traffic, bus load, repeats,
devices that went silent, smoke detectors and batteries, compared with the previous
report. In the app it is available as a PDF.

Notifications are off by default too. You can choose ntfy, a webhook or Home Assistant
as the destination; only a summary line is sent, never addresses, names or values. This
is not an alarm system: urgent findings are checked once a day.

## Data export

Tools › Data export, off by default, for your own Grafana:

- **Prometheus:** a separate port (default 9464) serves `/metrics`, only to the local
  network and only with the bearer token the app shows once. The add-on uses the host
  network, so the port needs no further setting.
- **InfluxDB 1 or 2:** the add-on sends to the address you enter.
- Without "Include addresses, names and values" only bus counters are exported.
- The Grafana templates for both can be saved from the same page.

## Without an own tunnel

If Home Assistant already has the KNX integration set up, the add-on suggests
sharing its connection: connection mode "Home Assistant" instead of an own
tunnel slot on the gateway (see Connection types).

## Configuration

```yaml
read_only: true
alarm_notifications: true
watcher_notifications: true
notify_service: notify.mobile_app_my_iphone
dashboard_card: true
```

- `read_only`: the server sends nothing to the bus, neither from the app nor
  through its relay, not even read requests (default on). Recording,
  evaluations and the health check keep running. Turn off to write or
  request values from the add-on. Docker and the Busclear Box use the
  environment variable `READ_ONLY=1` instead (default off there).
- `alarm_notifications`: Home Assistant notification when an alarm or fault
  object triggers (default on).
- `watcher_notifications`: Home Assistant notification when a watcher fires
  (default on).

- `notify_service` (optional): additionally send a push notification via a
  notify service, e.g. `notify.mobile_app_my_iphone`. Leave empty for a
  Home Assistant notification only. Both link to the add-on: the Home
  Assistant notification with "Busclear →", the push when you tap it.
- `dashboard_card`: install and register the dashboard card (default on,
  see Dashboard card). Turn off if you do not use it.

## Updates and going back

Home Assistant offers a backup before each add-on update – keep it switched on.
If a new version misbehaves, restore that backup (Settings → System → Backups):
it brings back the previous version together with its data. Recordings and
settings live in the add-on's data folder and survive normal updates.

The **Watchdog** switch on the add-on's Info page is off by default. Turned on, Home
Assistant restarts the add-on when its server stops responding. A missing gateway does
not count: the bus reconnects by itself.

## Support

Bugs and feature requests: <https://github.com/regetskcob/KNX-Monitor/issues>

**Vote on what comes next:** planned features are open issues on GitHub –
for example DALI lighting diagnostics, a native Home Assistant integration or
listening on the TP line directly. Give the ones you would use a 👍 and add a
comment with your setup; the votes decide what gets built first:
<https://github.com/regetskcob/KNX-Monitor/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement+sort%3Areactions-%2B1-desc>
