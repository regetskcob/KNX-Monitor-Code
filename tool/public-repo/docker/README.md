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
   `BOX_PASSWORD=your-own-password`. Without it Compose refuses to start, and
   so does the server with a shorter one.
2. `docker compose up -d`
3. Open `http://localhost:8765` on the host itself and sign in with the
   password. To reach it from other devices, see
   [Access from your network](#access-from-your-network).
4. Pick your KNX IP gateway (or enter its address), import your ETS project.

The container uses the host network, because KNXnet/IP over UDP, the gateway
search and routing need it. History, project and settings live in `./data`.

Out of the box the container only reads the bus (`READ_ONLY=1` in
`compose.yaml`): monitor, recording, watchers and evaluations work, but the app
cannot switch devices or send values. To allow that, add `READ_ONLY=0` to `.env`
and run `docker compose up -d`.

The Linux app and, later, the other apps can connect to the container too:
in the app "Add KNX box", enter `<host>:8765` and the password (needs
[access from your network](#access-from-your-network)).

Update: `compose.yaml` names a fixed version. Set `KNX_MONITOR_VERSION=x.y.z` in
`.env` (or download the file again), then `docker compose pull && docker compose
up -d`. The image is signed, see [Verify the image](#verify-the-image).

## Security

KNX itself has no authentication: whoever can send to your KNX IP gateway can
switch every device in the house. KNX Monitor is built not to become that way in,
but how you run it matters:

- **Never forward the port to the internet** (router port forwarding, DMZ,
  exposed host). From outside, use a VPN into your home network (WireGuard, the
  VPN of your router, Tailscale) and open KNX Monitor as if you were at home.
- **Read only unless you need to write.** `READ_ONLY=1` (default in
  `compose.yaml`) means the server sends nothing to the bus, whatever happens to
  the password or a paired device.
- **Only the host by default.** Without `LAN_ACCESS=yes` the server listens on
  `127.0.0.1` only, and only answers requests addressed to `localhost`. Open it
  to the network only when you need it.
- **A strong password**, at least 8 characters, better a long passphrase. It
  is checked slowly on purpose, and repeated wrong attempts lock the sender out
  for up to 15 minutes. Paired apps keep working during such a lockout.
- **Keep the password out of the environment** if others can run `docker
  inspect` or see your Portainer stacks: put it into a file and pass
  `BOX_PASSWORD_FILE=/run/secrets/knx_password` (Compose `secrets:`) instead.
  In `compose.yaml`, replace the `BOX_PASSWORD` line with that variable, since
  the template otherwise insists on `BOX_PASSWORD` in `.env`. The same works
  for `MQTT_PASSWORD_FILE`.
- **Changing `BOX_PASSWORD` later has no effect**: it only sets the first
  password. Change it in the app or on `/pair`; the log warns when the variable
  no longer matches.
- **Lost a phone or tablet?** Remove it in the app under box settings, or lock
  out everything ("Alle sperren"): that also ends browser sessions. Changing the
  password does not remove paired devices.
- **Updates:** security fixes come with new versions. Watch the
  [releases](https://github.com/regetskcob/KNX-Monitor/releases).
- **Use KNX IP Secure and Data Secure** where your installation supports them;
  plain KNXnet/IP can be read and written by every device in the network,
  with or without KNX Monitor.

`ALLOW_ALL=1` is for development and the project's own tests only. It turns off
every login; the server refuses it together with a network `BIND` unless a
second variable says so explicitly. Never copy it into a deployment.

## Access from your network

The default `LAN_ACCESS=no` answers only on the host itself. With `LAN_ACCESS=yes`
in `.env`, every device in your network can reach the login; the password is
still required. The setting applies on every start: change it in `.env`, then
`docker compose up -d`. Started without Compose (`docker run`)? Pass it there,
for example `-e LAN_ACCESS=yes`.

**Without HTTPS this is plain HTTP:** your password, device access and all
telegrams cross your network unencrypted, and anyone in the network can read them
or replace the app you load. So use it only in a network you trust, or:

- put a reverse proxy with TLS in front of it (the proxy makes the container
  reachable from the network, so set `LAN_ACCESS=yes` for it; with
  `LAN_ACCESS=no` the server refuses requests that do not name `localhost`), or
- give the container your own certificate: `TLS_CERT` and `TLS_KEY` (PEM files, for
  example under `./data/app/tls`) and `TLS_PORT` (default 8443). Pairing links from `/pair` then carry
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

## Without Compose

`compose.yaml` sets everything the container needs. With `docker run`, pass the
same settings yourself, at least `BOX=1`, the password and the host network:

```sh
docker run -d --name knx-monitor --restart unless-stopped --network host \
  --cap-drop ALL --cap-add DAC_OVERRIDE --cap-add FOWNER \
  --security-opt no-new-privileges:true \
  -e BOX=1 -e BOX_PASSWORD='your-own-password' -e LAN_ACCESS=yes -e READ_ONLY=1 \
  -e TZ=Europe/Berlin -v "$PWD/data:/data" \
  ghcr.io/regetskcob/knx-monitor:<version>
```

`<version>` is the one in `compose.yaml`, or any newer one from the
[releases](https://github.com/regetskcob/KNX-Monitor/releases). Without `-e LAN_ACCESS=yes` only the host itself gets in.
To let the app send to the bus, use `-e READ_ONLY=0` instead of `-e READ_ONLY=1`. To change a
setting later, remove the container and run it again with the new values;
`./data` keeps history, project and paired devices.

Bridge network instead of the host network (`-p 8765:8765` without
`--network host`, the default in some NAS interfaces): the gateway search and
routing do not work there, only a tunnel to the gateway's address. The server
then never sees requests from `localhost`, so it needs `LAN_ACCESS=yes`. Publish
the port on one address only, for example `-p 192.168.1.10:8765:8765`, and note
that Docker's published ports bypass firewalls such as `ufw`.

Space for the history: about 20 MB per million telegrams for finished days
(compressed), about 95 MB per million for the current day; with the default
retention of 7 days and 1,000 MB this stays small. Details in the
[add-on docs](https://github.com/regetskcob/KNX-Monitor/blob/main/ha-addon/knx_monitor/DOCS.md#continuous-recording).
Images exist for amd64 and arm64 only, so a Raspberry Pi needs the 64-bit OS
(Pi 3 or newer).

## Settings

| Variable | Meaning |
| --- | --- |
| `BOX=1` | Standalone mode with password (required outside Home Assistant). |
| `BOX_PASSWORD` | Password for the browser and for pairing apps, at least 8 characters. Used on the first start; change it later in the app under box settings. |
| `BOX_PASSWORD_FILE`, `MQTT_PASSWORD_FILE` | Read the password from a file instead (Docker secrets). A variable set directly wins. |
| `BOX_NAME` | Name shown in the apps. |
| `LAN_ACCESS=yes` | Reachable from your network, not only from the host (default `no`). Applies on every start (since 1.9.9). Plain HTTP unless you set up TLS, see above. |
| `TLS_CERT`, `TLS_KEY`, `TLS_PORT` | Optional HTTPS with your own certificate (PEM files), default port 8443. |
| `KNX_MONITOR_VERSION` | Image version (default: the one this file was published for). |
| `PORT` | Web port, default 8765. |
| `READ_ONLY=1` | Read only: the server sends nothing to the bus, neither from the app nor through its relay, not even read requests. Recording and evaluations keep running. On in `compose.yaml`, off without it. |
| `TZ` | Time zone for the daily history files, e.g. `Europe/Berlin`. |
| `MQTT_HOST`, `MQTT_PORT`, `MQTT_USER`, `MQTT_PASSWORD`, `MQTT_SSL` | Optional MQTT broker (port 1883 by default, `MQTT_SSL=true` for TLS). |
| `MQTT_DISCOVERY=false` | Leave out the Home Assistant discovery topics (recommended for ioBroker). |

## Home Assistant Container

Without the Supervisor (Home Assistant Container) there is no add-on, but the
[KNX Monitor integration](https://github.com/regetskcob/KNX-Monitor-HA) (1.1.0 or
newer, through HACS) can still talk to this container:

1. Set `LAN_ACCESS=yes` unless Home Assistant runs on the same host with host
   networking.
2. Open `http://<host>:8765/pair`, log in with the password, tick **Verwalten**
   (the integration needs a device with admin rights) and create the link.
3. In Home Assistant: *Settings → Devices & services → Add integration → KNX
   Monitor*, enter the container's address (e.g. `192.168.1.20:8765`) and paste
   the link (`knxmonitor://box?url=…&key=…`).

You get the sensors, the recording switch, device conditions, the services and
the repairs (bus lost, disk full, an address stopped sending). Event entities and
device triggers need the add-on for now; use MQTT for those. Revoke the device on
`/pair` and the integration loses access. With `TLS_CERT` the link carries the
certificate's fingerprint and the integration accepts only that certificate;
without it, the connection is not encrypted.

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

## Troubleshooting

**"Zugriff aus dem Netzwerk ist aus" / "Zugriff über das Kabel ist aus"** (HTTP 403):
the container only answers the host itself. Open `http://localhost:8765` there, or
set `LAN_ACCESS=yes` and restart the container (Compose: `docker compose up -d`).
The password is still required.

Up to version 1.9.8, `LAN_ACCESS` only counted on the very first start, and the
message spoke of a box Wi-Fi that does not exist in Docker. On those versions,
either open `http://localhost:8765/pair` on the host and allow access there, or
update to 1.9.9 or later and restart.

**Container stops right away, log says `BOX_PASSWORD fehlt` or `zu kurz`:** set
`BOX_PASSWORD` (8 to 128 characters). It is only needed on the first start;
after that the stored password counts, and you change it in the app or on `/pair`.

**"Nur über http://localhost erreichbar"** (HTTP 403): with `LAN_ACCESS=no` the
server only accepts requests to `localhost`, `127.0.0.1` or `[::1]`. Behind a
reverse proxy, or to reach it under the host's name, set `LAN_ACCESS=yes`.

**The app no longer switches anything, "Nur-Lesen ist an":** `compose.yaml`
starts read only since 1.9.10. Add `READ_ONLY=0` to `.env` and run
`docker compose up -d`.

**HTTPS no longer answers on port 443:** since 1.9.10 the container's default
`TLS_PORT` is 8443 (with `cap_drop: ALL` it cannot open ports below 1024).
Set `TLS_PORT` explicitly to keep another port.

## Notes

- 32-bit operating systems (armv7) are not supported; use a 64-bit OS.
- No Home Assistant events or notifications here; use MQTT and your system's
  automations instead (or the integration above for sensors, conditions and
  repairs).
- On its own the container sends nothing to the internet; data only goes to
  destinations you set up yourself (MQTT, ntfy, webhook, InfluxDB).
- Data in `./data` is not encrypted by the container; protect the folder and its
  backups yourself.
