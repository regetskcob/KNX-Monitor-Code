# KNX Box

The KNX Box is a Raspberry Pi image that records a KNX installation on site,
around the clock, without Home Assistant and without internet access. It reaches
the bus through a KNXnet/IP interface or router on its Ethernet port, or directly
on KNX TP through a Weinzierl kBerry HAT. It spans its own Wi-Fi, and phones,
tablets and laptops either pair the KNX Monitor app with it or open the web app in
a browser.

```
KNX IP interface ──eth0── Raspberry Pi ──wlan0── Wi-Fi "KNX-Box-XXXX" ── app / browser
  (or kBerry HAT ──UART── /dev/ttyAMA0, see kberry.md)
                             │
                             ├─ knx-box.service    /opt/knx-box/server, BOX=1, ports 80 + 443
                             │    ├─ access control (box password, paired devices)
                             │    ├─ bus connection, recorder → /var/lib/knx-box
                             │    └─ /api/box (status, clock, pairing)
                             ├─ NetworkManager     hotspot (DHCP, DNS), eth0 (DHCP or link-local)
                             ├─ nftables           no forwarding Wi-Fi → LAN, ports 80/443 Wi-Fi only
                             ├─ avahi              knx-box.local
                             └─ chrony             NTP if available, manual time otherwise
```

Related documents: [architecture.md](architecture.md) (how app and server fit
together), [addon-recording.md](addon-recording.md) (the permanent recording
shared with the add-on), [kberry.md](kberry.md) (the KNX HAT),
[security.md](security.md) (access control, pairing, TLS in detail),
[resilience-tests.md](resilience-tests.md) (checks on real hardware).

**Hardware status.** The box has run on a Raspberry Pi 4 with a kBerry on a real
bus, and updates and rollbacks were checked on a Pi 4. Not verified on hardware:
Raspberry Pi 5, Raspberry Pi 3, a battery-backed RTC, pulling the power plug
during recording, the link-local fallback on `eth0` (`link-local=fallback` needs
NetworkManager 1.52 or newer), and the 3D-printed case as a whole.

## Contents

- [Architecture: same server, `BOX=1`](#architecture-same-server-box1)
- [Building the image](#building-the-image)
- [First boot and `knx-box.txt`](#first-boot-and-knx-boxtxt)
- [Passwords, sheet and stickers](#passwords-sheet-and-stickers)
- [Storage and recording](#storage-and-recording)
- [Compression](#compression)
- [Time without an RTC](#time-without-an-rtc)
- [Networking](#networking)
- [Services and logs](#services-and-logs)
- [Updates and rollback](#updates-and-rollback)
- [Crash watch](#crash-watch)
- [The case](#the-case)
- [Tests](#tests)
- [Limits](#limits)

## Architecture: same server, `BOX=1`

The box runs the same Dart server as the Home Assistant add-on
(`ha-addon/knx_monitor/server/`), compiled ahead of time for Linux arm64
(`dart compile exe`, see `box/bundle.sh`) and started as a plain systemd service.
There is no container on the box. The web app served on ports 80/443 is the same
Flutter web build the add-on serves.

The environment variable `BOX=1` (set in `box/files/knx-box.service`) switches the
server into box mode (`ha-addon/knx_monitor/server/bin/server.dart`):

| What `BOX=1` changes | Where |
| --- | --- |
| Access control by box password and paired-device tokens instead of the Home Assistant ingress check | `lib/src/box_access.dart`, details in [security.md](security.md) |
| A box clock that can be set from the app or a KNX time master, and a recorder that copes with an unknown time | `lib/src/box_clock.dart`, `lib/src/recorder.dart` |
| HTTPS on port 443 with the box's own certificate, next to HTTP on port 80 | `lib/src/box_tls.dart` |
| The kBerry HAT as a bus connection (`mode: hat`, `/dev/ttyAMA0`) | `lib/src/kberry.dart`, [kberry.md](kberry.md) |
| Gateway discovery through the server (`GET /api/discover`) | `bin/server.dart` |
| Box management endpoints (`/api/box`, `/api/box/pair`, `/api/box/time`, `/api/box/wifi`, `/api/box/lan`, …) | `lib/src/box_access.dart`, `bin/server.dart` |

Everything else — the permanent bus connection, recorder, availability heartbeat,
alarms, watchers, exporter — is shared with the add-on.

The server runs without privileges. It cannot set the system time, touch the
hotspot, change the firewall or write to the boot partition. For each of these it
writes a request file into its data directory, and a systemd path unit on the
host acts on it after validating the content:

| Request file in `/var/lib/knx-box/` | Watched by | Acted on by |
| --- | --- | --- |
| `time-request.json` | `knx-box-time.path` | `settime.sh` (chrony, RTC) |
| `lan-access` (`yes`/`no`) | `knx-box-lan.path` | `lan-access.sh` (nftables) |
| `wifi-request` | `knx-box-secrets.path` | `secrets.sh` (hotspot password) |
| `sticker-scrub` | `knx-box-secrets.path` | `secrets.sh` (remove passwords from the boot partition) |

`secrets.sh` treats these files as untrusted input: it validates them, never
executes them and deletes symbolic links instead of following them.

## Building the image

All box files live in `box/`:

| File | Purpose |
| --- | --- |
| `bundle.sh` | Builds the package `knx-box-<version>.tar.gz`: server (Linux arm64), web app, `setup.sh`, `files/`, `VERSION`. The version comes from `ha-addon/knx_monitor/config.yaml`. |
| `setup.sh` | Installs or updates the box on Raspberry Pi OS Lite 64-bit (Trixie). Idempotent, with automatic rollback. `--image` mode for the pi-gen chroot. |
| `files/` | systemd units, first-boot and helper scripts, nftables rules, chrony and journald drop-ins, the LAN connection profile, the `knx-box.txt` template. |
| `pi-gen/` | `config` and the stage `stage-knx-box` for [pi-gen](https://github.com/RPi-Distro/pi-gen). |
| `build-image.sh` | Builds the image with pi-gen (Linux with Docker). |
| `test-firstboot.sh`, `test-setup.sh` | Dry runs of `firstboot.sh` and `setup.sh` with stub commands, on Linux or macOS. |

### Locally

```bash
box/bundle.sh --out build/knx-box.tar.gz        # needs Flutter and Dart
PI_GEN_REF=2026-10-06-raspios-trixie-arm64 \
  box/build-image.sh "$PWD/build/knx-box.tar.gz"  # Linux with Docker only
```

`build-image.sh` clones pi-gen at `PI_GEN_REF` (default: the `arm64` branch), and,
if `PI_GEN_COMMIT` is set, refuses to build when the ref points to a different
commit. It copies `stage-knx-box`, unpacks the bundle into it and runs
`build-docker.sh`. The result is `build/knx-box-image/pi-gen/deploy/knx-box-<version>.img.xz`,
to be written to an SD card or SSD with Raspberry Pi Imager ("custom image") or
balenaEtcher. On an x86 host pi-gen builds through QEMU, which is much slower.

The image (`box/pi-gen/config`):

- Raspberry Pi OS Lite 64-bit, Debian Trixie, stages 0–2 plus `stage-knx-box`.
  Only the box stage is exported as an image.
- Hostname `knx-box`, locale `de_DE.UTF-8`, German keyboard, time zone
  `Europe/Berlin`.
- Maintenance account `knxadmin` (first user). pi-gen insists on a password, so
  `build-image.sh` sets a random one and the stage removes it again
  (`usermod -p '*'`). SSH is off (`ENABLE_SSH=0`) unless a key is configured
  (see below).
- Extra packages (`stage-knx-box/00-knx-box/00-packages`): `network-manager`,
  `avahi-daemon`, `chrony`, `nftables`, `qrencode`, `picocom`, `curl`, `openssl`.
- `stage-knx-box/00-knx-box/01-run.sh` runs `setup.sh --image` inside the chroot.
  In image mode nothing is started, nothing is fetched with apt, and no TLS key is
  created: every box generates its own on first boot.

### In CI

`.github/workflows/box-image.yml` runs on tags `box-v<version>` (the tag must
match the version in `config.yaml`) and on manual dispatch:

1. **bundle** (`ubuntu-latest`): `shellcheck` over all box scripts,
   `box/test-firstboot.sh`, `box/test-setup.sh`, then `box/bundle.sh`.
2. **image** (`ubuntu-24.04-arm`, so pi-gen runs natively without QEMU):
   `box/build-image.sh` with pi-gen pinned to the tag
   `2026-10-06-raspios-trixie-arm64` and its commit.

On tags, package and image are signed with cosign (keyless, through the run's
OIDC token); the `.sigstore.json` bundles are uploaded next to the artifacts.
Verification is described in [release-security.md](release-security.md).

### Supported Raspberry Pi models

| Model | Status |
| --- | --- |
| Raspberry Pi 4 | Run on hardware, including the kBerry on a real bus. `setup.sh` adds `dtoverlay=disable-bt` under `[pi4]` so the PL011 UART is free for the HAT. |
| Raspberry Pi 5 | Configured (`dtoverlay=uart0-pi5` under `[pi5]`), not verified on hardware. Has an RTC that needs the optional battery. |
| Raspberry Pi 3 / 3B+ | Runs the arm64 image in principle and fits the case; not verified. `setup.sh` adds no UART overlay for it, so the kBerry is not set up on a Pi 3. |
| Anything 32-bit only | Not supported: `setup.sh` refuses to run on anything but `aarch64`. |

A Pi 4 has no RTC. `setup.sh` does not configure an external RTC module such as a
DS3231; that would need its own `dtoverlay=i2c-rtc,…` line in `config.txt`.

### Installing on a running Pi instead of the image

On Raspberry Pi OS Lite 64-bit (Trixie), preferably over Ethernet because `wlan0`
becomes the hotspot:

```bash
tar -xzf knx-box-<version>.tar.gz
cd knx-box && sudo ./setup.sh          # asks once before taking over wlan0
```

`setup.sh` installs the packages listed above, creates the system user `knx-box`,
copies server and web app to `/opt/knx-box/`, installs units and helpers, the
chrony and journald drop-ins and the LAN connection profile, puts the
`knx-box.txt` template on the boot partition (an already filled-in file is kept),
prepares the UART for the HAT and runs first boot if it has not happened yet.

## First boot and `knx-box.txt`

`knx-box-firstboot.service` runs `box/files/firstboot.sh` exactly once: its
condition is `ConditionPathExists=!/etc/knx-box/env`, and the server unit refuses
to start until that file exists.

1. Read `knx-box.txt` from the boot partition (`/boot/firmware`, or `/boot` on
   older layouts). The file can be filled in on a PC before the first boot. It is
   only parsed with `sed`, never sourced or executed; the last line for a key wins,
   Windows line endings are stripped, and invalid values are replaced by defaults.
2. Generate what is missing (see the table below).
3. Write `/etc/knx-box/env` (directory 0700, file 0600) with `BOX_NAME`,
   `BOX_PASSWORD`, `LAN_ACCESS` and, if requested, `READ_ONLY="1"`.
4. Set the Wi-Fi country (`raspi-config nonint do_wifi_country`), unblock Wi-Fi
   and write the hotspot profile
   `/etc/NetworkManager/system-connections/knx-box-ap.nmconnection` (0600).
5. Disable the forwarding firewall if `INTERNET_SHARING=yes`; install the SSH key
   if one is given.
6. Create the box's own TLS certificate (`tls-cert.sh`), if `openssl` is present.
7. Write all effective values back to `knx-box.txt`, and create the setup link,
   QR codes and the printable sheet on the boot partition (`write_boot_files` in
   `box-common.sh`).

### Keys

| Key | Default | Accepted values | Effect |
| --- | --- | --- | --- |
| `NAME` | `KNX-Box-<last 4 characters of the serial number>` | 1–32 of `A–Z a–z 0–9 . _ -` | Name of the box, shown in the app; default SSID |
| `WLAN_SSID` | same as `NAME` | as `NAME` | SSID of the hotspot |
| `WLAN_PASSWORD` | 12 random characters | 8–63 printable characters, no space and none of `" ' \ $` and backtick | WPA2 passphrase |
| `BOX_PASSWORD` | 10 random characters | as `WLAN_PASSWORD` | First password for browser login and pairing |
| `COUNTRY` | `DE` | two capital letters | Wi-Fi regulatory country; without it the Pi keeps Wi-Fi blocked |
| `INTERNET_SHARING` | `no` | `yes`/`no` | `yes`: devices in the box Wi-Fi may be routed to the Ethernet side (LAN and internet) |
| `LAN_ACCESS` | `no` | `yes`/`no` | `yes`: web app and API also reachable over Ethernet. Can be changed later in the app |
| `READ_ONLY` | `no` | `yes`/`no` | `yes`: the server sends nothing to the bus, not even read requests; recording continues |
| `SSH_PUBKEY` | empty | `ssh-ed25519`, `ecdsa-sha2-nistp256` or `ssh-rsa` key, optional comment, no options | Enables SSH for `knxadmin` with this key only |

Random values use the alphabet `abcdefghjkmnpqrstuvwxyz23456789` (no `0/O`,
`1/l/I`), drawn from `/dev/urandom`. The serial number comes from
`/proc/device-tree/serial-number` (falling back to `/etc/machine-id`), so two boxes
on the same site get different names and SSIDs.

**The file only matters before the first boot.** Afterwards it is a record of the
values, and editing it changes nothing. What can be changed later:

- box password and Wi-Fi password: in the app (box settings), or by a reset file
  (below);
- LAN access: in the app or on `/pair` in the browser;
- everything else (name, SSID, country, Internet sharing, read-only, SSH key): only
  by hand over SSH — `/etc/knx-box/env` for the server values, the NetworkManager
  profile for the hotspot, `systemctl enable/disable knx-box-firewall.service`
  for sharing — or by re-flashing.

`READ_ONLY` is read by the server from its environment at start
(`env['READ_ONLY'] == '1'` in `bin/server.dart`). It wraps the bus connection in
`ReadOnlyLink` and filters the raw KNXnet/IP relay `/ws` down to management
frames (`lib/src/read_only.dart`). It also stops the box from asking a KNX time
master for the time on connect.

### SSH

With a valid `SSH_PUBKEY`, first boot appends it to `~knxadmin/.ssh/authorized_keys`,
writes `/etc/ssh/sshd_config.d/knx-box.conf` with
`PasswordAuthentication no` and `KbdInteractiveAuthentication no`, gives
`knxadmin` passwordless sudo (`/etc/sudoers.d/010_knx-box-admin`; the account has
no password, so sudo could not ask for one) and enables `ssh`. Without a key, SSH
stays off and there is no way to log in over the network.

## Passwords, sheet and stickers

After first boot the boot partition holds:

| File | Content |
| --- | --- |
| `knx-box.txt` | All effective values, including both passwords until they are changed |
| `knx-box-link.txt` | Setup link for the app, for pasting on devices without a camera |
| `knx-box-app.png` | QR code of the setup link |
| `knx-box-wlan.png` | Standard Wi-Fi QR code (`WIFI:T:WPA;S:…;P:…;;`) for phone cameras |
| `knx-box-de.pdf`, `knx-box-en.pdf` | One A4 sheet per language: two stickers to cut out, access data, link as text, LAN access state, next steps |

The setup link has the form

```
knxmonitor://box?url=http%3A%2F%2F10.42.0.1%2F&name=…&ssid=…&fp=…&wifi=…&pw=…
```

`fp` is the SHA-256 fingerprint of the box certificate (base64url): an app that
knows it switches to HTTPS and pins exactly that certificate. `wifi` and `pw` are
left out once the respective password has been changed. The app joins the Wi-Fi,
pairs with `POST /api/box/pair` and offers its clock; pairing and the link format
are covered in [security.md](security.md) and `lib/platform/box_link.dart`.

The PDF is produced by the server binary itself (`server sheet <dir>`,
`lib/src/box_sheet.dart`); the values are passed through environment variables, not
arguments, so they never appear in the process list. It uses only the PDF standard
fonts. The two stickers have a fixed size of 270 × 134 pt (95.25 × 47.27 mm) with a
6 pt (2.12 mm) corner radius (`stickerWidth`, `stickerHeight`, `stickerRadius`):
sticker 1 goes on top of the box (setup link, "scan in the app"), sticker 2 on the
bottom (Wi-Fi name and password). A test measures the dashed outlines in the
generated PDF. Keep these dimensions; only the content may change.

### The sticker password must be replaced

The first box password is printed in plain text and lies on the SD card. The
service sets `BOX_STICKER=1`, and as long as that password is valid the server
only allows pairing and changing the password (`mustChangePassword`; other
requests get `428` or a redirect to `/pair`). After the change the server drops
devices that were paired with the sticker password (except the one making the
change) and writes `sticker-scrub`; `secrets.sh` then removes the password from
`knx-box.txt`, `/etc/knx-box/env`, the link, both QR codes and the PDFs. A Wi-Fi
password changed in the app (`POST /api/box/wifi`) is applied to the hotspot
profile and scrubbed in the same way; the hotspot restarts three seconds later, so
every client, including the app, has to reconnect. Printed stickers are invalid
from then on.

On a FAT boot partition, overwritten data can remain physically readable. Scrubbing
protects against photos and copies of the card, not against someone who reads the
card itself — they have access to all data anyway, since nothing on the box is
encrypted at rest.

The server stores the box password only as PBKDF2-HMAC-SHA256 in
`/var/lib/knx-box/access.json` (with `access.json.bak`); `/api/files/` never serves
that file, `server.json`, `time-request.json` or `lan-access`.

### Password reset

Put a file `knx-box-reset.txt` on the boot partition with one or both lines

```
BOX_PASSWORD=new-box-password
WLAN_PASSWORD=new-wifi-password
```

and restart the box. `knx-box-reset.service` (only started when the file exists)
runs `secrets.sh --reset`: it deletes the file first, so no plain text stays on the
card even if the content is invalid, then hands the box password to the server
through `/var/lib/knx-box/password-reset` (0600) and writes the Wi-Fi password
into the hotspot profile. The server consumes `password-reset` on start
(`_consumeReset` in `box_access.dart`). Paired devices stay paired.

If `access.json` and its backup are both unreadable, the server moves them aside
and starts fresh. When `BOX_PASSWORD` is no longer in `/etc/knx-box/env` (it was
scrubbed), it generates a random password and prints it once to the journal
(`journalctl -u knx-box`); the reset file is the way back.

## Storage and recording

### Where data lives

| Path | Content |
| --- | --- |
| `/opt/knx-box/` | `server`, `web/`, `VERSION`, and after an update `server.prev`, `web.prev`, `VERSION.prev` |
| `/usr/local/lib/knx-box/` | Helper scripts and `firewall.nft` |
| `/etc/knx-box/env` | Server environment written by first boot (0600) |
| `/etc/knx-box-tls/` | `cert.pem` (0644), `key.pem` (0640, group `knx-box`) |
| `/boot/firmware/` | `knx-box.txt`, link, QR codes, PDFs, optional `knx-box-reset.txt` |
| `/var/lib/knx-box/` | All server data (`StateDirectory=knx-box`, mode 0750) |

Inside `/var/lib/knx-box/`, the root holds only the server's own files:
`access.json` (+ `.bak`), `installations.json`, the request files listed above,
and the crash-watch files `running.json`, `restarts.ndjson`, `last-error.txt`.
Everything that belongs to an installation lives in `installations/<id>/`:

| Path in `installations/<id>/` | Content |
| --- | --- |
| `server.json` (+ `.bak`) | Bus connection and recording settings |
| `catalog.json`, `dpt_overrides.json` | Group address catalog from the ETS project |
| `secure_keys.json` | Keys from the ETS keyring, readable only by the server (and admins) |
| `history/YYYY-MM-DD.ndjson[.gz]`, `history/unsynced-*.ndjson` | The recording (below) |
| `status/availability-YYYY-MM.ndjson` | Heartbeat once a minute: `{"t", "c" (connected), "n" (telegrams)}`, kept 3 months |
| `status/busmon-YYYY-MM-DD.json` | Daily counters in kBerry bus monitor mode (data, ACK, NAK, busy, damaged) |
| `recordings/`, `charts.json`, `export.json`, … | Data the app stores through `/api/files/` |

### Data partition and optional SSD

By default everything lives on the SD card. To keep the recording on a USB SSD
or an NVMe drive, create an ext4 file system labelled `KNXBOXDATA`:

```bash
sudo mkfs.ext4 -L KNXBOXDATA /dev/sda1   # erases that partition
```

`knx-box-data.service` runs `box/files/data-mount.sh` early in boot (before
`paths.target` and the server, so the path units watch the mounted directory):

1. If `/var/lib/knx-box` is already a mount point, stop.
2. Wait for udev to settle (up to 10 s) and up to 3 s more for
   `/dev/disk/by-label/KNXBOXDATA`, since USB drives can appear late.
3. Run `fsck.ext4 -p`. Exit code 0 (clean) or 1 (repaired) continues; anything
   higher keeps the data on the SD card.
4. Mount with `noatime,commit=5`. On failure, keep the data on the SD card.

There is deliberately no `/etc/fstab` entry. `StateDirectory=` and the path units
add `RequiresMountsFor=/var/lib/knx-box`, so a missing drive would have taken the
server down with it despite `nofail` (up to version 1.8.3 the box did not start
without the SSD; `setup.sh` removes that old fstab line).

Consequences worth knowing:

- The data partition is mounted *over* `/var/lib/knx-box`. Adding a drive after
  first boot hides everything recorded on the SD card so far, including
  `access.json` with the password and paired devices; the box then behaves like a
  freshly set up one on that drive. Data is not migrated automatically.
- If the drive is missing or fails its check, the box silently falls back to the SD
  card (the reason is in the journal of `knx-box-data.service`), and the app sees
  the SD-card data set.

### History format

The recorder (`lib/src/recorder.dart`) writes one file per local calendar day,
`history/YYYY-MM-DD.ndjson`, with one JSON object per line and per group telegram.
It is the same format the app reads and writes (`Telegram.toJson()`); the server
builds it in `lib/src/telegram_json.dart`:

| Key | Type | Meaning |
| --- | --- | --- |
| `t` | int | Time stamp, microseconds since the Unix epoch |
| `s` | int | Source individual address (16 bit, `area.line.device` packed) |
| `d` | int | Destination group address (16 bit) |
| `y` | int | `0` GroupValueRead, `1` GroupValueResponse, `2` GroupValueWrite |
| `x` | string | Payload as hex |
| `m` | `true` | Small payload (≤ 6 bits, carried in the APCI byte) |
| `o` | `true` | Own telegram (L_Data.con, sent by this server) |
| `p` | int | Priority, only if not `3` (low) |
| `rp` | `true` | Repeated frame |
| `h` | int | Hop count, only if not `6` |
| `ce` | `true` | Confirmation error on an own telegram |
| `r` | string | Complete cEMI frame as hex |
| `mono` | int | Only in `unsynced-*` files: monotonic microseconds since server start |

Only group telegrams (read, response, write) are recorded. Individually addressed
and management traffic is not. KNX Data Secure telegrams are decrypted before
recording if the keyring is on the box, so the history contains them in plain text.

Example line:

```json
{"t":1761474000123456,"s":4353,"d":2305,"y":2,"x":"01","m":true,"r":"2900bce011010901010081"}
```

This is a GroupValueWrite of the value 1 from 1.1.1 (`4353`) to 1/1/1 (`2305`)
with low priority and hop count 6, so `p` and `h` are omitted.

### Write path and power loss

| Setting | Default | Range / source |
| --- | --- | --- |
| Flush interval (buffer → `write`) | 5 s | `flushSeconds` in `server.json`, 0–600 (0 means "as soon as possible", at least 250 ms) |
| `fsync` interval | 30 s | `syncInterval`, fixed; also on shutdown |
| Retention | 7 days | `retentionDays`, 0–3650 (0 turns recording off and deletes the history) |
| Size limit | 1000 MB | `maxMegabytes`, 10–1,000,000 |
| Buffer limit | 200,000 telegrams | `Recorder.maxBuffered`; overflow is counted (`dropped`), not silent |

Telegrams are buffered in memory and appended to the day file at the flush
interval, without `fsync` per write to spare SD cards. Files written since the
last sync are `fsync`ed every 30 s and on shutdown. On `SIGTERM` (systemd stop,
reboot) the server flushes, closes the bus connection and exits within 8 s;
`TimeoutStopSec=20` leaves systemd room before it kills the process.

On power loss, at most the telegrams of the last flush interval (still in memory)
plus whatever the kernel had not yet written are lost. The data partition is
mounted with `commit=5`; the SD-card root file system uses the ext4 default of 5 s
as well. Appending to NDJSON means a crash can leave a half line at the end of a
file; readers skip lines that do not parse. Hard limits are only those stated by
the code and the recorder tests; the real-device power-cut checklist in
[resilience-tests.md](resilience-tests.md) has not been run on the box.

### Free space

The recorder checks free space with `statvfs` (`lib/src/free_space.dart`, no `df`
needed) at most once a minute and on every maintenance run:

1. Below 256 MiB free, it deletes the oldest history files — orphaned `unsynced`
   files first, then day files — until 384 MiB (1.5×) are free. Today's file and
   the current start's `unsynced` file are never deleted. This happens regardless
   of `maxMegabytes`, because a small card fills up long before the configured
   limit.
2. If that is not enough, it stops writing (`lowSpace`), counts the discarded
   telegrams (`droppedLowSpace`) and logs it. Writing resumes at 384 MiB free, so it
   does not flap.
3. Write errors (`FileSystemException`) are counted the same way, not swallowed.

`GET /api/bus` includes the storage usage: bytes, days, first day, free
bytes, `lowSpace`, `droppedLowSpace`, number of `unsynced` files.

Maintenance runs at server start (catching up on anything a crash left behind),
every hour, and when the first telegram of a new day arrives. It compresses
finished days and applies retention by age, then by total size (oldest first,
today is kept).

The journal is capped by `box/files/journald-knx-box.conf` so it can neither fill
the card nor take the recorder's space: `SystemMaxUse=64M`, `SystemKeepFree=256M`,
`RuntimeMaxUse=32M`.

## Compression

What is and is not compressed on the box:

| Data | Compressed? | How |
| --- | --- | --- |
| Finished history days | **Yes** | gzip (Dart `gzip` codec, default level), `YYYY-MM-DD.ndjson` → `YYYY-MM-DD.ndjson.gz` |
| Today's history file | No | Plain NDJSON, appended to |
| `unsynced-*.ndjson` (recorded without a known time) | No | Never compressed, also not after they become orphans |
| Availability and bus-monitor status files | No | Plain NDJSON / JSON |
| `restarts.ndjson`, `last-error.txt` | No | |
| Settings, catalog, keys, `access.json` | No | Plain JSON |
| Web app in `/opt/knx-box/web` | No | Served as is |
| HTTP responses | No | The server sets no `Content-Encoding`; packed days are decompressed on the fly |
| Exports, backups, diagnostics packages | Not on the box | These ZIP files are built by the app on the client device; the server creates no archives |
| Images (QR PNGs, PDFs on the boot partition) | PNG/PDF intrinsic only | `qrencode` PNG; the sheet PDF uses the PDF library's stream compression |
| Data at rest | Not encrypted | Neither the SD card nor the data partition |

Packing (`Recorder._gzip`) streams the plain file through `gzip.encoder` into
`<day>.ndjson.gz.tmp`, renames it to `<day>.ndjson.gz` and deletes the plain
file. If a `.gz` for that day already exists (the clock briefly stood on another
day), the old content is decompressed and the new lines appended, so nothing is
replaced (`recorder_merge_test.dart`). Readers handle both forms:
`Recorder.dayLines` reads the `.gz`, the plain file, or both in order, and
`/api/files/history/` lists `.ndjson.gz` under the `.ndjson` name and serves it
decompressed, so the app never sees the difference. Retention and the size limit
count the compressed size.

Only packaging artefacts are compressed beyond this, and they never live on a
running box: the bundle (`.tar.gz`) and the image (`.img.xz`,
`DEPLOY_COMPRESSION="xz"`).

Space estimate, not measured on a real installation: a typical line is about
100 bytes, so 5 telegrams per second come to roughly 43 MB per day before
compression. The compression ratio of real recordings is not recorded in this
repository.

## Time without an RTC

A Raspberry Pi 4 has no real-time clock; a Pi 5 has one but only keeps time with
the optional battery. Without internet, the system clock after boot can be wrong,
and day files would get the wrong date. The box therefore tracks where its time
comes from (`lib/src/box_clock.dart`).

### Sources

In increasing order of trust (`ClockSource`):

| Source | Detected by |
| --- | --- |
| `none` | Nothing better since start |
| `rtc` | `/sys/class/rtc/rtc0/since_epoch` later than 2025-01-01 |
| `knx` | A time master on the bus (below) |
| `client` | The clock of a phone or tablet running the app (`POST /api/box/time`) |
| `ntp` | `chronyc -c tracking`: valid reference ID, stratum 1–15, leap status `Normal` |

`rtc` and `ntp` are probed when the server starts; `knx` and `client` are offered
while it runs.

### Decision rules

`BoxClock.offer` decides on every offered time:

| Box clock | Difference | Action |
| --- | --- | --- |
| Unknown (`none`) | any | Set immediately |
| Known | < 2 s | Nothing; a more trusted source is recorded as the current source |
| Known | ≥ 2 s, source more trusted and ≤ 15 min | Set |
| Known | otherwise | Report the offset (`offsets` in `/api/box`); set only when the app explicitly asks (`force`) |

So a KNX time master never overrules a phone, and a phone with a wrong clock cannot
silently shift a recording that already has a trusted time.

### Setting the system clock

The server has no `CAP_SYS_TIME`. It writes `{"epochMs": …}` to
`/var/lib/knx-box/time-request.json`. `knx-box-time.path` starts `settime.sh`,
which accepts only a 13-digit millisecond value between 2025-01-01 and 2100-01-01,
deletes the request, calls `chronyc settime` and, if `/dev/rtc0` exists,
`hwclock -w`. Until the system clock has actually moved, `BoxClock.now()` adds the
correction itself (anchored to a monotonic stopwatch), so no telegram is stamped
with the old time.

chrony (`box/files/chrony-knx-box.conf`): `manual` permits `chronyc settime`,
`rtcsync` keeps an RTC in step, and `makestep 1 3` corrects large offsets
immediately during the first updates instead of slewing.

### KNX time from the bus

`KnxTimeWatch` (enabled by `clockFromKnx`, default on) looks at responses and writes:

- **DPT 19.001** (date and time, 8 bytes): with an ETS project that types the group
  address, accepted at once. Without a project, two telegrams from the same group
  address must agree with the box's own elapsed time within ±3 s, since 8 bytes can
  be anything. Telegrams with the fault, no-year, no-date or no-time flags are
  ignored.
- **DPT 10.001 + 11.001** (time and date, 3 bytes each): only with a project, and the
  date must be at most 24 h older than the time; without a project these are too
  easily confused with colours or counters.

KNX time is local time without a zone; the server interprets it in its `TZ`, which
the unit fixes to `Europe/Berlin`. When the box connects with an unknown time, it
sends one GroupValueRead to the project's DPT 19 (or DPT 10) address instead of
waiting for the next cycle, unless it is read-only.

### Recording with an unknown time

Recording has priority: the box records from the first second.

- While the time is unknown, lines go to `history/unsynced-<start>.ndjson` with an
  extra `mono` field (microseconds on the server's monotonic stopwatch).
- When the clock is set, `Recorder.retime` converts that file into the right day
  files (`t = set time − (mono at set − mono of line)`) and deletes it.
- The availability heartbeat is suspended while the time is unknown, since it would
  land on the wrong day.
- With `recordOnlyWithTime` (app setting), telegrams before a known time are only
  counted (`waiting`), not recorded.
- If the box is switched off before the time is ever set, the file cannot be placed
  later: the monotonic counter restarts with every server start. It stays readable
  as a section without time. On the first maintenance with a known clock it is
  renamed `unsynced-<start>-<detected>.ndjson`, and retention counts from that
  moment, because the start stamp in its name came from the wrong clock.

## Networking

### Wi-Fi hotspot (`wlan0`)

Written by first boot as a NetworkManager profile `knx-box-ap`: access point mode,
2.4 GHz (`band=bg`), channel 6, WPA2-PSK (RSN, CCMP only), `ipv4.method=shared` with
the fixed address `10.42.0.1/24` (NetworkManager runs DHCP and DNS through
dnsmasq), IPv6 off. Phones report "no internet" and stay connected.

### Ethernet (`eth0`)

`box/files/knx-box-lan.nmconnection`: DHCP with a 20 s timeout, then link-local
(169.254.x.x) as fallback, so a gateway with AutoIP that is plugged in directly is
reachable. IPv6 auto. A gateway with a fixed address on a cable without DHCP needs
a matching address on `eth0`, which the box does not configure; there is no
setting for it.

`setup.sh` disables `NetworkManager-wait-online.service`: the hotspot never has
internet, and waiting would only delay boot.

### Firewall

Two nftables tables:

| Table | Unit / script | Rule |
| --- | --- | --- |
| `inet knx_box` | `knx-box-firewall.service`, `firewall.nft` | Forward chain: drop everything from `wlan0` to another interface. Devices in the box Wi-Fi cannot reach the LAN or the internet through the box. Off with `INTERNET_SHARING=yes`; an update keeps that choice. |
| `inet knx_box_lan` | `knx-box-lan.service`, `lan-access.sh` | Input chain: accept `lo` and `wlan0`, reject TCP 80 and 443 from anywhere else. Deleted when LAN access is on. |

LAN access is decided by interface, not by source address, because a customer
network may itself use `10.42.0.0/24`. The server additionally answers requests from
outside `10.42.0.0/24` with `403` while LAN access is off (`BoxAccess.wlanPeer`),
as a second layer. The choice comes from the app (`POST /api/box/lan`, or the
switch on `/pair`): the server writes `yes`/`no` to `/var/lib/knx-box/lan-access`,
`knx-box-lan.path` re-runs `lan-access.sh`. Without that file the script uses
`LAN_ACCESS` from `/etc/knx-box/env`, and otherwise blocks.

The LAN switch covers only ports 80 and 443. KNXnet/IP and gateway discovery use
UDP and are not affected. Other listening services are not filtered by it: SSH
(only if a key was configured) and the Prometheus exporter (off by default,
port 9464, token-protected when enabled) are reachable over Ethernet.

### Name

The hostname is `knx-box` and avahi announces `knx-box.local`. Every box has the
same name; on a shared LAN, avahi's own conflict handling applies. The fixed address
`http://10.42.0.1` always works inside the box Wi-Fi and is what the setup link uses.

### HTTPS

`box/files/tls-cert.sh` creates a self-signed certificate on first boot or on the
first update that finds none — never in the image, so every box has its own key:
EC P-256 (named curve, which Dart's TLS stack requires), valid 20 years,
`CN=knx-box`, `subjectAltName=DNS:knx-box.local,IP:10.42.0.1`. An existing
certificate is kept, otherwise printed QR codes would no longer match. The script
prints the fingerprint: SHA-256 over the DER certificate, base64url without
padding, the same value `certificateFingerprint` in `lib/src/box_tls.dart`
computes.

The server serves HTTPS on port 443 next to HTTP on port 80. If the certificate is
missing or unreadable, or port 443 is taken, it stays on HTTP and logs why. The
app pins the certificate by the `fp` parameter of the setup link; browsers show a
warning for the self-signed certificate. HTTP remains for browsers in the box
Wi-Fi and for older apps.

### Access control (summary)

Browsers log in with HTTP Basic and the box password, then get a session cookie;
paired apps send a per-device bearer token. Devices paired with the box password
are administrators; devices paired through a QR code on `/pair` may read and send
group values but not manage the box or read the keyring. Login attempts are
rate-limited per IP. `GET /healthz` answers without login and returns no data. The
full model, including origin checks and roles, is in [security.md](security.md).

## Services and logs

All units are in `box/files/` and installed to `/etc/systemd/system/` by `setup.sh`.

| Unit | Type | Purpose |
| --- | --- | --- |
| `knx-box.service` | simple | The server: `User=knx-box`, `BOX=1`, `PORT=80`, `TLS_PORT=443`, `TZ=Europe/Berlin`, `EnvironmentFile=/etc/knx-box/env`. `Restart=always`, `RestartSec=3`, `TimeoutStopSec=20`. Starts only after first boot (`ConditionPathExists=/etc/knx-box/env`). |
| `knx-box-firstboot.service` | oneshot | First boot, once (`firstboot.sh`) |
| `knx-box-data.service` | oneshot | Mounts `KNXBOXDATA` (`data-mount.sh`), before `paths.target` and the server |
| `knx-box-firewall.service` | oneshot | Loads `firewall.nft` before NetworkManager; `ExecStop` removes the table |
| `knx-box-lan.service` + `.path` | oneshot | LAN access on boot and on every change of `lan-access` |
| `knx-box-time.service` + `.path` | oneshot | Sets the clock on every change of `time-request.json` |
| `knx-box-secrets.service` + `.path` | oneshot | New Wi-Fi password, boot partition scrub |
| `knx-box-reset.service` | oneshot | Password reset from `knx-box-reset.txt`, only when that file exists |

Hardening of `knx-box.service`: only `CAP_NET_BIND_SERVICE` (ambient and bounding
set), `NoNewPrivileges`, `ProtectSystem=strict` (writable only through
`StateDirectory`), `ProtectHome`, `PrivateTmp`, `ProtectKernelTunables`,
`ProtectControlGroups`, address families `AF_INET`, `AF_INET6`, `AF_UNIX`,
`AF_NETLINK`. Device access is closed except `char-ttyAMA` (the HAT's UART), with
the supplementary group `dialout`.

Logs go to the journal:

```bash
journalctl -u knx-box                # server
journalctl -u knx-box-firstboot      # first boot
journalctl -u knx-box-data           # which storage is in use
journalctl -u knx-box-time -u knx-box-secrets -u knx-box-lan
```

The server logs to stdout/stderr; it never writes passwords to the log, with the
one exception of a regenerated password after an unrecoverable `access.json`
(see [Password reset](#password-reset)). Reading the journal needs SSH, which is
off unless a key was configured.

## Updates and rollback

The box does not update itself and needs no internet. An update is the same
package as for a manual install:

```bash
tar -xzf knx-box-<version>.tar.gz && cd knx-box
sudo ./setup.sh --yes        # update
sudo ./setup.sh --rollback   # back to the version before the last update
```

`setup.sh` keeps the running version as `server.prev`, `web.prev`, `VERSION.prev`,
installs the new one atomically (`*.new` then `mv`), restarts the services and
waits up to 40 s for any HTTP answer from `http://127.0.0.1/healthz`. If the
service does not start or does not answer, it restores the previous version on its
own and exits with an error. Passwords, Wi-Fi settings, paired devices, the
certificate, the firewall choice and the recording stay untouched. `setup.sh` also
adds a certificate to boxes that predate HTTPS, and removes the old `KNXBOXDATA`
fstab line.

Changes to `config.txt` or `cmdline.txt` for the HAT UART take effect after a
reboot; `setup.sh` says so.

## Crash watch

`lib/src/crash_watch.dart` records unexpected ends of the server process locally;
nothing is sent anywhere.

- At start the server writes `running.json` (start time, version, kernel boot ID)
  and touches its modification time once a minute (metadata only, to spare the
  card). A clean exit on `SIGTERM`/`SIGINT` deletes it.
- If the next start finds the marker, the previous run ended unexpectedly. The
  reason is `error` if `last-error.txt` exists (an unhandled error, written
  synchronously before the process exits with code 255, at most 8000 characters),
  `host` if the boot ID changed (power loss, reboot), otherwise `unknown` (crash,
  `SIGKILL`). The last sign of life is the marker's modification time.
- Entries are appended to `restarts.ndjson` (at most 200 kept; the file is rewritten
  when it exceeds 256 KiB). The 30-day summary is part of the box status, the full
  list is at `GET /api/restarts` and goes into a diagnostics package only if the
  user creates and shares one.
- Every step catches its own errors: a full or read-only disk never prevents the
  server from starting.

The shutdown handler gives cleanup 8 s (a hanging serial line to the HAT would
otherwise let systemd kill the process after 20 s, which would count as a crash)
and always marks the exit as clean.

## The case

`box/case/` contains the STL files of a screwed, 3D-printed case for a Raspberry Pi
3B, 3B+, 4B or 5 with a kBerry on top, plus a DIN-rail (TS35) base with a separate
latch clip. Outside dimensions 100 × 69 × 29.5 mm (32.5 mm with the DIN-rail base),
6–8 mm walls, recessed connectors, the KNX terminal unpluggable through the lid
with the case closed. It is a preview: insert holes are calibrated with a
step test, but the complete assembly and the DIN-rail base are not fully verified,
and the case has no IP rating. Parts list, print settings and assembly:
[box/case/README.md](../box/case/README.md). Every box release includes the folder
as `knx-box-case-<version>.zip`.

## Tests

| Test | What it covers | Runs in |
| --- | --- | --- |
| `box/test-firstboot.sh` | `firstboot.sh` in a temp root with stubs for `systemctl`, `nmcli`, `raspi-config`, `rfkill`, `qrencode` and the server: generated and given values, invalid input, certificate and fingerprint, scrubbing, Wi-Fi change, reset file (including symlinks and invalid content), missing `qrencode`, `lan-access.sh`, SSH key handling, `data-mount.sh` with clean, repaired and failing `fsck`, ordering lines of the units | `box-image.yml`, `tool/release.sh verify` |
| `box/test-setup.sh` | `setup.sh` in a temp root: first install, update with rollback copy, certificate kept, firewall choice kept, automatic rollback for a server that does not start or does not answer, manual `--rollback`, broken previous version, missing package | `box-image.yml`, `tool/release.sh verify` |
| `server/test/box_access_test.dart`, `box_security_test.dart` | Login, tokens, roles, rate limit, origin checks, LAN check, sticker password flow | server tests |
| `server/test/box_clock_test.dart` | Decision table, `now()` correction, DPT 19/10/11 parsing, retiming of `unsynced` lines, strict mode | server tests |
| `server/test/recorder_space_test.dart` | `fsync` cadence (5 s / 30 s), deleting oldest days, pause and resume on low space, error counting, `statvfs` | server tests |
| `server/test/recorder_unsynced_test.dart` | Retention and size limit for `unsynced` files, marking orphans | server tests |
| `server/test/recorder_merge_test.dart` | Packing a day that already has a `.gz` | server tests |
| `server/test/crash_watch_test.dart` | Clean exit, unexpected end, host restart, recorded error, limits | server tests |
| `server/test/read_only_test.dart` | Read-only link and relay filter | server tests |
| `server/test/box_sheet_test.dart` | Sheet content and sticker geometry | server tests |
| `.github/workflows/addon.yml`, step "Box mode (BOX=1) access" | The server container with `BOX=1`: 401 without login, 403 from outside the Wi-Fi with LAN access off, pairing, device roles, time request, protected files | add-on CI |

What only real hardware shows is listed in
[resilience-tests.md](resilience-tests.md).

## Limits

- **Time zone and locale are fixed** to `Europe/Berlin` and German in the image
  and the unit; KNX local time is interpreted in that zone.
- **Ethernet to a gateway with a fixed address** and no DHCP server does not work
  without configuring `eth0` by hand.
- **One tunnel, permanently.** Connected through an IP interface, the box keeps one
  tunnel open around the clock. If the ETS needs the only free tunnel, pause the connection in the app.
- **No data encryption at rest.** Whoever has the SD card or SSD has the recording,
  the keyring and, until changed, the passwords.
- **The bus recording reveals presence.** A recording shows when people are in the
  building. Keep retention short in occupied buildings.
- **Reading a day while it is both packed and open.** If a day exists as `.gz` and
  as plain file at the same time (possible only after a clock jump back to an
  already packed day), `/api/files/history/<day>.ndjson` serves only the plain part
  until the next maintenance merges them; `Recorder.dayLines` (statistics) reads both.
- **Packing is not crash-atomic in every window.** `_gzip` renames the finished
  `.gz` and then deletes the plain file; a power cut exactly between the two would
  leave both, and the next maintenance would merge the plain lines into the `.gz` a
  second time. The `.gz.tmp` is not `fsync`ed before the rename.
- **No notifications to phones** without internet; the app shows what it sees live
  and what the box recorded.
