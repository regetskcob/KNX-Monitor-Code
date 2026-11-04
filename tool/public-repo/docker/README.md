# KNX Monitor in Docker (ioBroker, NAS, Proxmox)

The server behind the Home Assistant add-on and the KNX box also runs as a
plain Docker container: bus monitor and diagnostics in the browser,
continuous recording, watchers and alarms, and optionally an MQTT connection
for ioBroker or any other system. Images for amd64 and arm64 (Raspberry Pi 4/5
with a 64-bit OS) under one name: `ghcr.io/regetskcob/knx-monitor`.

Using Home Assistant? Take the [add-on](https://knx-monitor.de/addon/) instead,
it is set up with one click and needs no password.

## Start

1. Copy [`compose.yaml`](compose.yaml) to a folder on the host. Next to it
   create a file `.env` with your own password (at least 8 characters):
   `BOX_PASSWORD=your-own-password`. Without it Compose refuses to start, as
   the container is reachable from your network.
2. `docker compose up -d`
3. Open `http://localhost:8765` on the host itself, sign in with any user name and
   the password. To reach it from other devices, see
   [Access from your network](#access-from-your-network).
4. Pick your KNX IP gateway (or enter its address), import your ETS project.

The container uses the host network, because KNXnet/IP over UDP, the gateway
search and routing need it. History, project and settings live in `./data`.

The Linux app and, later, the other apps can connect to the container too:
in the app "Add KNX box", enter `<host>:8765` and the password (needs
[access from your network](#access-from-your-network)).

Update: `compose.yaml` names a fixed version. Set `KNX_MONITOR_VERSION=x.y.z` in
`.env` (or download the file again), then `docker compose pull && docker compose
up -d`. The image is signed, see [Verify the image](#verify-the-image).

## Access from your network

The default `LAN_ACCESS=no` answers only on the host itself. With `LAN_ACCESS=yes`
in `.env`, every device in your network can reach the login.

**Without HTTPS this is plain HTTP:** your password, device access and all
telegrams cross your network unencrypted, and anyone in the network can read them
or replace the app you load. So use it only in a network you trust, or:

- put a reverse proxy with TLS in front of it, or
- give the container your own certificate: `TLS_CERT` and `TLS_KEY` (PEM files, for
  example under `./data/tls`) and `TLS_PORT`. Pairing links from `/pair` then carry
  the certificate's fingerprint and the apps trust exactly this certificate. HTTP
  stays available on `PORT`; do not expose it beyond the host if you can avoid it.

## Verify the image

Images are signed with [cosign](https://docs.sigstore.dev/) (keyless):

```sh
cosign verify ghcr.io/regetskcob/knx-monitor:<version> \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity-regexp '^https://github.com/regetskcob/KNX-Monitor-Source/\.github/workflows/addon\.yml@refs/tags/addon-v'
```

## Build the image yourself

The source code is in
[KNX-Monitor-Code](https://github.com/regetskcob/KNX-Monitor-Code). Its
`Dockerfile` in the root builds web app and server in one go, no Flutter or
Dart needed on your machine:

```sh
git clone https://github.com/regetskcob/KNX-Monitor-Code.git
cd KNX-Monitor-Code
docker build -t knx-monitor --build-arg BUILD_VERSION="$(sed -n 's/^version: "\(.*\)"/\1/p' ha-addon/knx_monitor/config.yaml)" .
```

Then replace the `image:` line in `compose.yaml` with `image: knx-monitor`.
The build takes a few minutes, mostly for the web app.

## Settings

| Variable | Meaning |
| --- | --- |
| `BOX=1` | Standalone mode with password (required outside Home Assistant). |
| `BOX_PASSWORD` | Password for the browser and for pairing apps, at least 8 characters. Used on the first start; change it later in the app under box settings. |
| `BOX_NAME` | Name shown in the apps. |
| `LAN_ACCESS=yes` | Reachable from your network, not only from the host (default `no`). Plain HTTP unless you set up TLS, see above. |
| `TLS_CERT`, `TLS_KEY`, `TLS_PORT` | Optional HTTPS with your own certificate (PEM files), default port 443. |
| `KNX_MONITOR_VERSION` | Image version (default: the one this file was published for). |
| `PORT` | Web port, default 8765. |
| `READ_ONLY=1` | Read only: the server sends nothing to the bus, neither from the app nor through its relay, not even read requests. Recording and evaluations keep running (default off). |
| `TZ` | Time zone for the daily history files, e.g. `Europe/Berlin`. |
| `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASSWORD`, `MQTT_SSL` | Optional MQTT broker (port 1883 by default, `MQTT_SSL=true` for TLS). |
| `MQTT_DISCOVERY=false` | Leave out the Home Assistant discovery topics (recommended for ioBroker). |

## ioBroker

1. In ioBroker install the **MQTT** adapter (Broker/Client), mode **Server/broker**,
   port 1883, with a user and password.
2. In `compose.yaml` set `MQTT_HOST` to your ioBroker host, `MQTT_USER` and
   `MQTT_PASSWORD`, and `MQTT_DISCOVERY: "false"`. Restart the container.
3. The values appear as states under `mqtt.0.knx_monitor`:

| State | Value |
| --- | --- |
| `connected` | bus connected, `true`/`false` |
| `recording` | continuous recording on, `true`/`false` |
| `per_minute`, `repeats_per_minute` | telegrams and repeats per minute |
| `today` | telegrams today |
| `last` | time of the last telegram (ISO 8601, UTC) |
| `status` | `online`/`offline` (offline if the container stops) |
| `event.watcher` | JSON of the last watcher hit: name, group address, source, value |
| `event.alarm` | JSON of the last alarm or fault change: `event_type` `alarm_on`, `alarm_off`, `fault_on` or `fault_off` |
| `watcher.<id>`, `alarm.<type>` | the same per watcher and per alarm type |
| `state` | all values above as one JSON |

To pause or resume the recording, set `mqtt.0.knx_monitor.recording.set` to
`ON` or `OFF`.

Watchers are set up in KNX Monitor under Tools › Watchers; each hit updates
`event.watcher`, so a script or Blockly trigger on that state can switch,
notify or log.

A native ioBroker adapter (admin tab, states without MQTT) is planned if
enough users want it: vote with 👍 in
[issue #3](https://github.com/regetskcob/KNX-Monitor/issues/3).

## Notes

- 32-bit operating systems (armv7) are not supported; use a 64-bit OS.
- No Home Assistant events or notifications here; use MQTT and your system's
  automations instead.
- On its own the container sends nothing to the internet; data only goes to
  destinations you set up yourself (MQTT, ntfy, webhook, InfluxDB).
- Data in `./data` is not encrypted by the container; protect the folder and its
  backups yourself.
