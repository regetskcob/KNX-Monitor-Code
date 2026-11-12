# Event channel

The server's events for automations (a watcher fired, an alarm or fault came
or went, the bus connection was lost or is back) as a WebSocket. In the Home
Assistant add-on the same events go onto Home Assistant's event bus through the
Supervisor. A Busclear Box or the Docker container has no Supervisor; there the
[Busclear integration](../ha-integration/README.md) (Home Assistant Container)
reads them from this channel, and other systems (a planned ioBroker adapter,
[#3](https://github.com/regetskcob/KNX-Monitor/issues/3)) can do the same.

Available from Busclear 1.12.0 on: `GET /api/ha/state` then carries
`"events": 1`, the format version below. A client connects only when it sees
that field; older servers have no channel.

## One source

Every event of the active installation goes through one function,
`serverEventSink` (`server/lib/src/event_channel.dart`), which hands it to the
channel, to the MQTT device (`knx_monitor/event/…`) and to Home Assistant
(`POST /api/events/<type>` through the Supervisor), in that order and with the
same data. What the add-on fires today is exactly what the channel sends; a
new event type reaches all three at once.

Where the events come from (`server/lib/src/bus.dart`, `BusService._fire`):

| Event | When | Data |
|---|---|---|
| `knx_monitor_watcher` | a watcher fires (after its own dead time for notifications, every hit counts) | `watcher_id`, `name`, `label`, `address`, `source`, `value` (if the watcher decodes one), `raw` (hex) |
| `knx_monitor_alarm` | an alarm or fault object turns on or off, a DALI luminaire or group enters or leaves a fault | `address`, `name`, `kind` (`alarm` or `fault`), `active`; DALI also `dali`: `gateway`, `address`/`group`/`test`, `faults` |
| `knx_monitor_bus` | the bus connection is lost or back (not every connection attempt) | `connected`, `state`, `reason` (only on errors) |

Each also carries `installation` (its name) when the installation has one.
"Stopped sending" is not an event: it is a state the integration polls
(`GET /api/ha/silent`), and the repairs come from there.

No secrets: the data is what the views of the same installation see anyway
(group addresses, names, values of the watched telegrams). No passwords, keys
or tokens, no host of the gateway.

## Access

The same as every other request (`BoxAccess.guard` on box and Docker):

- **Box and Docker:** box password (HTTP Basic or the session cookie of the
  browser) or a paired device (`Authorization: Bearer <key>` from `/pair` or
  `POST /api/box/pair`). Every role may read, `admin`, `device` and `viewer`:
  the events come from telegrams a viewer sees live on `/ws/bus` anyway, and an
  ioBroker adapter or a dashboard needs no right to change anything. The Home
  Assistant integration uses its device with admin rights, because its other
  endpoints (`/api/ha/`) need them.
- **Add-on:** through Ingress like the web app. The integration does not use
  the channel there (it gets the events from the Supervisor), and the add-on's
  own token for `/api/ha/` does not open it.
- **Cross-site WebSocket:** a browser request with an `Origin` other than the
  box's own address is refused (403); a request with only the session cookie
  must carry its origin. Clients outside a browser (the integration, an
  adapter) send no `Origin`.
- Places: at most 8 connections, at most 2 per paired device (with the
  password: per sender address), and the last one only for a device with
  admin rights. A viewer cannot take every place and lock out the Home
  Assistant integration; 2 per device leave room for a reconnect before the
  server noticed the old connection gone.
- When devices are revoked or the password changes, every open connection is
  closed (1008); clients reconnect and are checked again, a revoked one gets 401.

| Answer before the upgrade | Meaning |
|---|---|
| 101 | connected |
| 401 | no or a wrong credential (device revoked) |
| 403 | foreign `Origin` |
| 426 | not a WebSocket request |
| 503 + `Retry-After: 10` | no place: already 8 connections, 2 of this device (or, with the password, of this address), or 7 and the device has no admin rights |

## Messages

Text frames with one JSON object each. Every message has `"v": 1` and a
`type`. A client ignores messages with another `v` or an unknown `type`;
new fields can appear in any message without a new version. `v` changes only
for an incompatible change.

### `hello`

The first message after connecting.

```json
{"v": 1, "type": "hello", "seq": 42, "epoch": "9f2c1e0a7b3d4c51", "server": "1.12.0", "heartbeat_s": 30, "resumed": true}
```

- `seq`: sequence number of the last event so far (0 before the first).
- `epoch`: changes with every start of the server; sequence numbers start at 1
  again after a restart.
- `heartbeat_s`: interval of the heartbeat.
- `resumed`: see "After a dropout".

### `event`

```json
{"v": 1, "type": "event", "seq": 43, "time": "2026-11-11T10:00:00.000Z", "event": "knx_monitor_watcher",
 "data": {"watcher_id": "w1", "name": "Bathroom window open", "label": "1/2/3 Window", "address": "1/2/3",
          "source": "1.1.5", "value": 1, "raw": "01", "installation": "Home"}}
```

- `seq`: one more than the event before, without gaps (per `epoch`).
- `time`: when the server sent it, UTC.
- `event`, `data`: event type and data as in the table above, the same as on
  Home Assistant's event bus.

### `heartbeat`

```json
{"v": 1, "type": "heartbeat", "seq": 43, "time": "2026-11-11T10:00:30.000Z"}
```

Every `heartbeat_s` seconds, also when nothing happens. `seq` is the last
event's: a heartbeat with a higher `seq` than the last event received means
one was lost. Three missing heartbeats mean the connection is dead; reconnect.
Besides, the server pings every 20 seconds (WebSocket ping) and closes a
connection that does not answer two of them.

### From the client

Nothing. The server ignores messages from the client; a frame larger than
1 KiB closes the connection before it is read in (1002). There is no compression (permessage-deflate).

## After a dropout

The server keeps the last 64 events in a ring. A client remembers `epoch` and
the last `seq` it received and reconnects with them:

```
GET /ws/events?since=43&epoch=9f2c1e0a7b3d4c51
```

Right after the `hello` it gets every event after `since` that is still in the
ring, with their original `seq` and `time` (`seq` ≤ the hello's `seq`), then
live events. `resumed` is `true` when nothing is missing: same `epoch` and
every event after `since` still in the ring. Otherwise (`false`) events were
lost, either too many while away or the server restarted (new `epoch`, then
nothing is replayed). The channel has no history beyond the ring; the bus
history is in `/api/export/ets-xml`, and the current state in
`GET /api/ha/state`.

Without `since` (first connection) nothing is replayed.

## Slow clients

Each connection has its own queue of at most 256 KiB. Messages go to the
socket only as fast as the client reads; one that stops reading while events
keep coming is disconnected (the socket is closed at once) instead of holding
back the others or filling the server's memory. Once it reads again, it
reconnects and catches up from the ring.

## Clients

- **Home Assistant (Busclear integration, without Supervisor):**
  `ha-integration/custom_components/knx_monitor/events.py`. It fires each
  event on Home Assistant's event bus under its own type, with the data plus
  `config_entry_id` of its entry, so event entities, device triggers and the
  watcher list work as with the add-on; triggers and entities of a box take
  only events with their entry, never those of an add-on next to it, and those
  of the add-on only events without `config_entry_id`, never those of a box. It
  reconnects after 1, 2, 5, 10, 30 and then every 60 seconds and logs an
  outage once. Refused with 401 or 403, it starts the reauthentication (new
  pairing link). With the add-on it does not connect at all: the Supervisor
  already delivers, there are no doubles.
- **ioBroker (#3, planned):** the same connection with a paired device (a
  viewer is enough), one data point per event type as in the issue.

A minimal client for a test, with a device key from `/pair` (tick "Schlüssel
direkt anzeigen" there; the QR code otherwise carries a one-time code for the
app):

```sh
websocat -H "Authorization: Bearer $KEY" ws://192.168.1.20:8765/ws/events
```

## Tests

- Server: `server/test/event_channel_test.dart` (format, heartbeat, ring and
  sequence numbers, slow client, limits, closing on access changes, the same
  data as the Home Assistant events) and `server/test/server_process_test.dart`
  (roles, `Origin`, the real server).
- Integration: `ha-integration/tests/test_event_channel.py` (connecting, event
  to entity and trigger, reconnecting with `since`, reauth, no channel with
  Supervisor, older server without channel) and `tests/test_api.py`.
