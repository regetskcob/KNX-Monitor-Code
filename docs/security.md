# Security

How KNX Monitor protects the user's data and the KNX installation, written for
people who audit the code. Every statement points at the code that implements
it; where the protection ends, the section says so.

KNX Monitor comes in four forms that share one Dart code base:

| Form | Code | Where data lives |
|---|---|---|
| Native apps (iOS, iPadOS, Android, macOS, Windows, Linux) | `lib/` | App data directory, system keychain |
| Home Assistant add-on (web app plus Dart server) | `lib/` (web build), `ha-addon/knx_monitor/server/` | Add-on data folder `/data/app` |
| Docker container (same server, standalone) | `ha-addon/knx_monitor/server/` | Mounted `/data` |
| KNX Box (Raspberry Pi image with the same server) | `ha-addon/knx_monitor/server/`, `box/` | SD card or SSD, `/var/lib/knx-box` |

Paths starting with `server/` are short for `ha-addon/knx_monitor/server/`.

Release and supply chain security has its own document:
[release-security.md](release-security.md). To report a vulnerability, see
[the end of this document](#reporting-a-vulnerability).

## Contents

1. [Encryption at rest in the apps](#1-encryption-at-rest-in-the-apps)
2. [Full backups](#2-full-backups)
3. [App lock](#3-app-lock)
4. [KNX Secure](#4-knx-secure)
5. [Writing to the bus](#5-writing-to-the-bus)
6. [Access to the add-on, Docker and the KNX Box](#6-access-to-the-add-on-docker-and-the-knx-box)
7. [Outbound connections and what leaves the device](#7-outbound-connections-and-what-leaves-the-device)
8. [Known limits](#8-known-limits)
9. [Reporting a vulnerability](#reporting-a-vulnerability)

## 1. Encryption at rest in the apps

Code: `lib/platform/storage_io.dart` (`IoStorage`, `KeychainFileKey`),
`lib/platform/file_cipher.dart` (format), `lib/platform/crypto_worker.dart`
(background isolate), `lib/knx/secure/package_crypto.dart` (`aesGcm`).
Tests: `test/storage_encryption_test.dart`, `test/file_cipher_format_test.dart`.

### Key

One 256-bit file key per installation of the app, generated with
`Random.secure()` and stored in the system keychain under the name
`knx_file_key` through `flutter_secure_storage`:

| Platform | Store | Options |
|---|---|---|
| iOS, iPadOS | Keychain | `first_unlock` (without `this_device`, see below) |
| macOS | Login keychain (not the data protection keychain) | `first_unlock` |
| Android | `flutter_secure_storage` (Android Keystore) | `resetOnError: false` |
| Windows | `flutter_secure_storage` (Windows credential storage) | defaults |
| Linux | libsecret (Secret Service) | defaults |

The file key is deliberately **not** bound to the device (`first_unlock`, not
`first_unlock_this_device`): it travels with an encrypted device backup, so the
files are still readable after restoring a device. All other secrets use
`*_this_device` (section 3 and 4).

`resetOnError: false` on Android keeps a key entry that cannot be decrypted (for
example after a Keystore change) instead of deleting it.

`KeychainFileKey.load` only creates a new key when the old one is really absent:
it reads twice (200 ms apart), writes a new key, reads it back and uses it only if
the read matches. If the keychain throws, it returns `null` and the app runs
without encryption (see Linux below); it never generates a key because of a
transient error.

### File format

Encrypted files start with the header `KNXENC1\n`. Each write or append adds one
line: Base64 of `nonce (12 bytes) || ciphertext || tag (16 bytes)`, AES-256-GCM
with a fresh random nonce per record and no additional data
(`file_cipher.dart`, `encryptRecord`). Appending (history files are NDJSON)
adds records without rewriting the file. A torn last record costs only that
record: `decryptFile` skips unreadable lines and fails only if no line at all
decrypts.

Writes go to a temporary file that is renamed over the target (atomic on the
same file system). The previous version is kept as `<file>.prev` (up to 16 MiB)
and used if the current one cannot be read. A file that cannot be decrypted
with the current key is never overwritten with empty data
(`StorageLockedException`, `StorageCorruptException`).

All encryption and decryption run in a persistent background isolate
(`CryptoWorker`), never on the UI thread.

### What is encrypted, and what is not

| Encrypted | Not encrypted |
|---|---|
| All files the app writes through `IoStorage` in its application support directory: installations, projects (`catalog.json`), recordings and history (`*.ndjson`), comments, settings files of the app's own stores. Existing plain files are encrypted in the background on start (`encryptExisting`, extensions `.json .ndjson .jsonl .bak .csv .txt .log .b64`). | Settings in SharedPreferences (`shared_preferences.json` on Windows and Linux, platform preferences elsewhere), including the gateway address and port, the last connections and UI settings. |
| | File names, directory structure, file sizes and modification times. |
| | Files the user exports or shares (diagnostics packages, CSV, PDF reports, the decrypted contents of a backup). |
| | Data in the web app: it is stored by the add-on or box server (section 6). |

Secrets that are not files never touch the data directory: KNX Secure keyrings,
the KNX Box pairing (device token, Wi-Fi password) and the app lock state are
stored in the keychain directly (`lib/knx/secure/keyring_store.dart`,
`lib/model/box_connection.dart`, `lib/platform/key_vault.dart`).

### Key loss

If the keychain answers but has no key while encrypted files exist (for example a
device restored from an unencrypted backup), the new key would make them
unreadable. `IoStorage._quarantine` moves those files to the folder
`nicht-lesbar/` instead of overwriting them. The app shows them and offers to
restore a full backup or to delete them.

### Linux without libsecret

Without a working Secret Service, `KeychainFileKey.load` returns `null`:

- new files are written in plain text;
- files that are already encrypted are neither read nor overwritten
  (`StorageLockedException`), so a temporary keychain failure does not destroy
  data;
- a KNX Secure keyring is kept in memory for the session only, never written to a
  plain file (`KeyringStore._writeStored`);
- an app lock password hash falls back to SharedPreferences (section 3).

### Limits

- The protection is against someone who reads the disk or the data directory
  from another user account or offline. Malware running as the same user can
  ask the keychain for the key just as the app does.
- Records are authenticated individually, without additional data binding them
  to a file or position. Someone who can write the data directory can delete,
  reorder or copy whole records between files without the app noticing; they
  cannot read or forge record contents.
- The app relies on the operating system's disk encryption (FileVault,
  BitLocker, iOS/Android data protection) for everything listed as not
  encrypted.

## 2. Full backups

Code: `lib/model/full_backup.dart`, `lib/knx/secure/package_crypto.dart`,
`lib/platform/safe_zip.dart`. Tests: `test/full_backup_test.dart`,
`test/backup_hardening_test.dart`. Format: [backup-format.md](backup-format.md).

A full backup (native apps only) contains all app files, settings and KNX
Secure keyrings in one file encrypted with a password of the user's choice
(at least 12 characters):

- Key derivation: PBKDF2-HMAC-SHA256, 600,000 rounds, 16-byte random salt,
  32-byte key.
- Cipher: AES-256-GCM, 12-byte random nonce, additional data
  `knx-monitor-backup/1`.
- Packing, derivation and encryption run in a background isolate (`compute`).

Hardening on restore, all before anything is written:

| Check | Reason |
|---|---|
| `format` and `version` (newer versions refused) | No partial import of a format the app does not know. |
| Rounds from the file within 1,000 to 2,000,000 | A crafted file can neither force a weak derivation nor block the device. |
| GCM tag | Wrong password or tampering. |
| ZIP limits: 512 MiB in total and per entry, 200,000 entries, checked from the central directory before extraction (`decodeZipLimited`) | Zip bombs. |
| Every path relative, no `..`, `.`, empty segments, backslashes, NUL or drive letters; not `shared_preferences.json` or `nicht-lesbar/` (`FullBackup.safePath`) | Path traversal, overwriting plugin settings. |
| Settings keys filtered with the same rule as on export (`FullBackup.keepsOut`) | A file cannot set the app lock, device identifiers or the consent to share a keyring with a KNX Box. |
| Keyrings only under keys starting with `knx_keyring:` | A file cannot write arbitrary keychain entries. |

Limits: the decrypted ZIP holds the project and the KNX Secure keys in plain
text. The backup is only as strong as its password; there is no recovery.

## 3. App lock

Code: `lib/model/app_lock.dart`, `lib/platform/key_vault.dart`,
`lib/ui/app_lock_screen.dart`. Tests: `test/app_lock_test.dart`,
`test/app_lock_gate_test.dart`.

The app lock covers the user interface when the app starts or returns from the
background after a chosen timeout (immediately, 1, 5 or 15 minutes). The bus
connection and alarms keep running behind it. It exists in the native apps only;
in the web app the Home Assistant login or the KNX Box password decides
(`AppLock.available`).

Two modes:

- **System** (`AppLockMode.system`): Face ID, Touch ID, fingerprint, device
  passcode or Windows Hello through `local_auth`, with fallback to the device
  passcode. Not available on Linux.
- **App password** (`AppLockMode.password`): at least 6 characters. Stored as
  `v1:<rounds>:<salt>:<hash>` with PBKDF2-HMAC-SHA256 and a 16-byte salt. The
  rounds are calibrated per device to about 800 ms, clamped to 20,000 to
  600,000. Verification compares in constant time (`verifyHash`).
  Optionally with a recovery code: 24 characters from a 27-character alphabet
  (about 114 bits, generated, not chosen), stored as a hash with 2,000 rounds.

Storage and tamper resistance:

- State (on/off, mode, timeout, failed attempts, wait time) and hashes live in the
  keychain with `first_unlock_this_device` (`SecureKeyVault`): they do not move
  to other devices. SharedPreferences hold only a copy for the case that the
  keychain is unavailable; once the keychain holds the state, editing or deleting
  the copy does not turn the lock off (`_loadState`, `_check`).
- If the keychain does not answer at start, the lock is applied from the copy
  first, so the app never opens unlocked while waiting.
- Failed attempts: four are free, then 30 seconds, doubling up to 15 minutes
  (`waitAfter`). A wait time further in the future than 15 minutes (a clock set
  back) is capped.
- Changing or turning off a running lock requires confirming the current
  password or biometrics within the last 5 minutes (`_mayChange`).
- If the device passcode is removed while the system mode is on, the lock is
  lifted, because whoever removed it knew it (`unlockWithSystem`).
- Optional on Android: `FLAG_SECURE` hides the app in the app switcher and blocks
  screenshots. On iOS and Android the content is covered while the app is
  inactive.
- Forgotten password without recovery code: the only way out is to delete all
  local data, keychain entries and keyrings (`wipeAndExit`). There is no bypass.

Limits:

- The lock protects against someone holding the unlocked device. It is not
  encryption: the files are protected by section 1 and by the operating system.
- Linux without libsecret: the password hash is stored in SharedPreferences
  (`_saveSecret`). Whoever can read that file can also read the then unencrypted
  data files.
- On desktop systems the window stays visible while the app is in the
  background; the lock applies when the app is resumed after the timeout.

## 4. KNX Secure

KNX Monitor implements KNX IP Secure tunnelling (AN159) and KNX Data Secure for
group communication (AN158) itself, using AES from `pointycastle` and an
X25519 implementation in Dart. The structure follows xknx (MIT); the
implementation is checked against the examples of the KNX Association and xknx.

| Part | App | Server (add-on, Docker, box) |
|---|---|---|
| CCM building blocks (CBC-MAC, CTR), X25519, password derivation | `lib/knx/secure/knx_crypto.dart` | `ha-addon/knx_monitor/server/lib/src/secure/knx_crypto.dart` |
| IP Secure session | `lib/knx/secure/ip_secure.dart`, `lib/knx/secure_tunnel.dart` | `server/lib/src/secure/ip_secure.dart`, used by `server/lib/src/link.dart` |
| Data Secure | `lib/knx/secure/data_secure.dart` (receive and send) | `server/lib/src/secure/data_secure.dart` (receive only, for recording) |
| ETS keyring import | `lib/knx/secure/keyring.dart`, `lib/knx/secure/keyring_store.dart` | reads `secure_keys.json` (`server/lib/src/bus.dart`, `_reloadKeys`) |
| Tests | `test/knx_crypto_test.dart`, `test/data_secure_test.dart` | `server/test/secure_test.dart` |

The server keeps its own copies of the crypto files because app and server are
separate Dart packages; the server's `data_secure.dart` says so in its header.

### Keyring import

`Keyring.parse` reads an ETS `.knxkeys` file:

1. The keyring password is derived with PBKDF2-HMAC-SHA256 (65,536 rounds, salt
   `1.keyring.ets.knx.org`, 16 bytes).
2. The signature over the canonicalised XML tree is checked before anything is
   decrypted; a mismatch is reported as a wrong password.
3. Group keys, tunnel passwords and device authentication codes are decrypted
   with AES-128-CBC (IV from the SHA-256 of the `Created` attribute).

Native apps parse in a background isolate. Only what is needed is stored, in
decrypted form: project name, group keys, last known sequence numbers per
sender, tunnel user IDs and passwords, device authentication codes. The backbone
key is parsed but not stored. The original `.knxkeys` file and its password are
not kept.

Where the keyring lives:

- **Native apps:** in the keychain, one entry per installation
  (`knx_keyring:<id>`), with `first_unlock_this_device`: no iCloud keychain
  sync, no migration through device backups. It leaves the device only in a
  full backup (section 2), or on a KNX Box after an explicit question per box
  and certificate (`lib/model/box_keyring_consent.dart`,
  `test/backup_hardening_test.dart`, group "Keyring zur Box").
- **Add-on and box:** as the file `secure_keys.json` in the data folder of the
  installation, unencrypted, because the server needs it to record secured
  telegrams. Over `/api/files/` only the admin role can read or write it
  (`server/lib/src/files.dart`, `_adminOnly`).

### IP Secure

`IpSecureSession` performs the handshake over TCP: X25519 key exchange,
optional check of the gateway's response with the device authentication code
(`IpSecureException('device')` on mismatch), authentication with the user
password, then every frame inside a `SECURE_WRAPPER`. Received wrappers are
checked for session ID, a strictly increasing sequence number (replay) and the
MAC; anything else is dropped. MACs are compared in constant time
(`bytesEqual`).

Limits:

- Without a device authentication code in the keyring or settings, the gateway's
  identity is not verified; the session is encrypted but could be terminated by
  a man in the middle who knows the user password.
- Secure routing (IP Secure multicast) is not implemented. Routing is plain.
- Plain KNXnet/IP tunnelling and routing are unencrypted by design of the
  protocol. The app shows which kind of connection is in use
  (`lib/model/security_check.dart`).

### Data Secure

`DataSecure.receive` handles `S-A_Data` to group addresses only (no tool access,
no system broadcast). It rejects a telegram if the sender is not in the keyring,
if the sequence number is not higher than the last one seen from that sender,
or if the 4-byte MAC does not match. Telegrams without a key are counted
(`withoutKey`), invalid ones too (`rejected`), and shown as encrypted.

`DataSecure.send` (app only) encrypts group telegrams to addresses that have a
key, with the tunnel address as source. The sending sequence number starts at
the milliseconds since 2018-01-05 UTC and counts up, so it increases across
restarts without a stored counter.

Limit: the sending sequence number depends on the device clock. A clock that is
far behind produces numbers that receivers reject as replays (a functional
failure, not a security one).

## 5. Writing to the bus

### In the app

Every user action that sends to the bus (send sheet, value controls, actuator
view, details, replay of a recording) goes through `confirmWrite`,
`requireWriteConfirmation` or `confirmReplay` in `lib/ui/write_confirm.dart`.
Until the user hides it, a dialog states that the value goes to the bus and can
switch real devices, and the user must confirm with "Write". Hiding it is
recorded with the date (`lib/model/write_notice.dart`) and included in
diagnostics packages. Tests: `test/write_notice_test.dart`,
`test/write_path_test.dart`.

This is a user interface safeguard, not an access control: anyone with network
access to an unencrypted gateway can send telegrams without KNX Monitor.

### Read-only mode of the server

`ha-addon/knx_monitor/server/lib/src/read_only.dart`. Test:
`server/test/read_only_test.dart`.

| Where | Default |
|---|---|
| Home Assistant add-on | Option `read_only`, **on** (`ha-addon/knx_monitor/config.yaml`) |
| Docker, KNX Box | `READ_ONLY=1`, off |

With read-only on:

- `ReadOnlyLink` wraps the server's bus connection and rejects every `send`,
  including read requests. The server's own time request for the box clock is
  skipped as well (`BusService._askTime`).
- Clients sending over `/ws/bus` get result 6 ("read-only").
- The UDP relay `/ws` lets only management services through
  (`relayMaySendReadOnly`): search, description, connect, connection state,
  disconnect and acknowledgements. `TUNNELLING_REQUEST`, `ROUTING_INDICATION`,
  `DEVICE_CONFIGURATION_REQUEST`, `TUNNELLING_FEATURE_SET` and `SECURE_WRAPPER`
  are dropped; therefore an IP Secure tunnel through the relay does not work in
  read-only mode.

The server sends nothing on its own except that time request. The MQTT bridge
accepts only the command to start or stop recording, never bus telegrams
(`server/lib/src/mqtt_bridge.dart`).

### What paired devices may send

`ha-addon/knx_monitor/server/lib/src/cemi_policy.dart`, enforced in
`BusService._clientSend` (`server/lib/src/bus.dart`). Test:
`server/test/robust_frames_test.dart`.

On the KNX Box and in Docker, a device paired without the box password (role
`device`) may send over `/ws/bus` only frames for which `deviceMaySend` is true:

- a complete `L_Data.req` whose length byte matches the frame exactly,
- to a group address (not an individual address, not `0/0/0`),
- with `T_Data_Group` and one of `A_GroupValue_Read`, `A_GroupValue_Response`,
  `A_GroupValue_Write`, or `A_SecureService` (Data Secure to a group address).

Everything else (restart, memory and property writes, individual address
programming, connection-oriented services) is refused with result 5. Admin
clients (Home Assistant users through Ingress, browsers with the box password,
devices paired with the box password) may send any `L_Data.req`. Only one client
at a time may hold a connection-oriented session to a given device
(`_lockDevice`).

### UDP relay

The web app cannot open UDP sockets, so the server relays KNXnet/IP packets for
it over the WebSocket `/ws` (`ha-addon/knx_monitor/server/bin/server.dart`,
`_relay`):

- Only packets with the KNXnet/IP header `06 10` are forwarded.
- Only to IPv4 targets that can be a KNX gateway (`_isLocalTarget`): RFC 1918
  networks, `100.64.0.0/10` (CGNAT, VPNs such as Tailscale), link-local,
  loopback, the KNXnet/IP multicast address `224.0.23.12`, and
  `255.255.255.255`. The relay is not a UDP hop into the internet.
- Read-only mode filters services as described above.
- On the box, role `device` gets no access to `/ws` at all
  (`BoxAccess.guard`), because the raw relay could carry any telegram.
- When access is revoked or the box password changes, open relays and bus
  WebSockets are closed (`onAccessChanged`).
- When the browser tab closes, the server sends `DISCONNECT_REQUEST` for tunnels
  that are still open.

## 6. Access to the add-on, Docker and the KNX Box

### Home Assistant add-on: Ingress only

The add-on runs with `host_network: true` and listens on port 8765
(`ingress_port`). `_handle` in `server/bin/server.dart` answers only requests
whose peer address is the Supervisor's Ingress proxy `172.30.32.2`; everything
else gets 403. Home Assistant authenticates the user before Ingress forwards the
request. Ingress users have the admin role.

Exceptions:

- `/healthz` answers `ok` without authentication and without data
  (`server/lib/src/http.dart`), for the Supervisor watchdog.
- `ALLOW_ALL=1` disables the check. It is meant for development and tests
  (`server/test/server_process_test.dart`, CI smoke test) and must not be set in
  production.
- The optional Prometheus endpoint uses its own port (see section 7).

Every response carries `X-Content-Type-Options: nosniff` and
`Referrer-Policy: no-referrer`. The `X-Ingress-Path` header is written into
`index.html` only if it consists of path characters.

### KNX Box and Docker: password, pairing, roles

`BOX=1` switches the server to standalone mode with its own authentication
(`ha-addon/knx_monitor/server/lib/src/box_access.dart`, `BoxAccess.guard`).
Tests: `server/test/box_access_test.dart`, `server/test/box_security_test.dart`.

| Credential | Used by | Stored as | Role |
|---|---|---|---|
| Box password | Browser (HTTP Basic, any user name), then a session cookie | PBKDF2-HMAC-SHA256, 40,000 rounds, 16-byte salt, in `access.json` | `admin` |
| Device token (32 random bytes) from `/pair` in the browser | App, `Authorization: Bearer` | SHA-256 in `access.json` | `device` |
| Device token from `POST /api/box/pair` (requires admin) | App paired with the box password | SHA-256 | `admin` |

- The password hash is computed in a separate isolate. Hashes stored by older
  boxes with more rounds are re-hashed after the next successful login.
- Comparisons of hashes and tokens run in constant time (`_equal`).
- Failed logins per peer address: four are free, from the fifth on 30 seconds,
  doubling up to 15 minutes. At most three password checks run at the same time
  per peer, so parallel requests cannot exhaust the Pi. A valid device token
  does not reset the counter; only the correct password does.
- Session cookie `knx_box_session`: 32 random bytes, stored as SHA-256, valid
  12 hours, at most 32 sessions, kept in memory only. Flags `HttpOnly;
  SameSite=Strict`, plus `Secure` over HTTPS.
- Cross-site protection: a request with an `Origin` header must match the
  `Host`. Requests authenticated only by the cookie must be same-site
  (`Sec-Fetch-Site`) and state-changing requests and WebSockets must carry an
  `Origin`.
- Changing the password or revoking a device clears sessions and cached logins
  and closes open WebSockets.

What the `device` role cannot do: the relay `/ws`, `/pair`, the management API
`/api/box/*` (devices, password, Wi-Fi, LAN access), changing the bus
connection (`/api/bus`), reading or writing `secure_keys.json`, writing files
other than `charts.json` and `watch_rules.json` (at most 1 MiB), forcing the box
clock, changing report and export settings, and sending anything but group
values (section 5). Server-owned files such as `access.json`, `server.json`
(gateway and IP Secure credentials), `report_settings.json` and `export.json`
are never served over `/api/files/` to anyone (`server/lib/src/files.dart`,
`_private`).

### KNX Box specifics

- **Network:** by default the box answers only clients in its own Wi-Fi
  (`10.42.0.0/24`) and itself. Access over Ethernet must be enabled explicitly
  (`LAN_ACCESS=yes` or in the box settings). The firewall enforces this per
  interface (`box/files/lan-access.sh`, nftables); the server's check of the
  peer address is a second layer (`BoxAccess.wlanPeer`). The server cannot
  change the firewall itself; it writes a request file that a host service
  applies.
- **Sticker password:** a new box prints its first password on a sticker and
  on the SD card. Until the user sets an own password, only pairing and
  changing the password are possible (`changeRequired`). When the password is
  changed, devices paired with the sticker password are revoked (except the one
  making the change), and the host removes the passwords from the boot partition
  (`box/files/secrets.sh`).
- **Reset:** a new password can be placed on the SD card (`password-reset`);
  whoever holds the card can regain access. Paired devices stay.
- **TLS:** `box/files/tls-cert.sh` creates a self-signed ECDSA P-256 certificate
  on first boot (one key per box, never in the image). The server serves HTTPS on
  port 443 next to HTTP (`server/lib/src/box_tls.dart`, `server/bin/server.dart`).
  The pairing QR code carries the SHA-256 fingerprint of the certificate (`fp`).
  Apps pin exactly that fingerprint with a client that trusts no root
  certificates (`lib/platform/addon_io.dart`, `pinnedHttpClient`), so a
  certificate from a public CA cannot replace it. Expiry and host name are not
  checked; the fingerprint is.
- **Plain HTTP:** a browser in the box's Wi-Fi uses HTTP, so the Wi-Fi password
  (WPA2) is the protection there. The `/pair` page warns when it is opened over
  plain HTTP from outside the box's Wi-Fi.

### Docker

The Docker template (`tool/public-repo/docker/compose.yaml`) runs the same
server with `BOX=1`, requires `BOX_PASSWORD` (Compose refuses to start without
it), and answers only on the host itself unless `LAN_ACCESS=yes`. HTTPS needs a
certificate of the user's own (`TLS_CERT`, `TLS_KEY`, `TLS_PORT`); without it,
password and data travel in plain HTTP.

## 7. Outbound connections and what leaves the device

### Connections the software makes

| From | To | When |
|---|---|---|
| App | KNX gateway (KNXnet/IP, UDP or TCP) | When the user connects |
| App | KNX Box or Docker server | When paired |
| Web app | Its own server (Ingress, box) | Always |
| Server | KNX gateway, or the KNX HAT on the box | Always while recording |
| Server | Home Assistant Supervisor API (`http://supervisor/`) | Add-on: notifications, KNX integration status, MQTT broker lookup |
| Server | MQTT broker | If a broker is available (Supervisor) or configured (`MQTT_HOST`) |
| Server | ntfy or webhook target | Only if the admin configures reports |
| Server | InfluxDB | Only if the admin enables the export |
| Prometheus | Server `/metrics` (inbound) | Only if the admin enables it |
| Official store builds | App Store or Google Play, through the RevenueCat SDK | To check purchases; only when built with `RC_APPLE_KEY` / `RC_GOOGLE_KEY` (`lib/platform/store_plan.dart`) |
| Official Windows builds | Licence server | To refresh a bought licence; only when built with `LICENSE_PUBLIC_KEY` and `WINDOWS_SHOP` (`lib/platform/license_plan.dart`) |

A build from this source without those keys contacts neither. Which features
it unlocks is decided in `planSourceFor` (`lib/platform/store_plan.dart`): web
and Linux builds (for one installation) and builds with `PLAN_OPEN=true` unlock everything, debug
builds too, release builds without a purchase path stay on the free tier. There is no
telemetry, analytics or crash reporting to a third party in this code.
Diagnostics packages (below) are files the user shares by hand.

### Server: user-defined targets

`ha-addon/knx_monitor/server/lib/src/outbound.dart`. Test:
`server/test/outbound_target_test.dart`.

- Only `http` and `https`, with a host, without credentials in the URL
  (`parseOutboundTarget`). Tokens go in a separate field, are sent only as an
  `Authorization` header and are not logged. The settings API returns only
  whether a token is set (`hasNotifyToken`, `hasInfluxToken`,
  `hasPrometheusToken`); a newly generated Prometheus token is returned once.
- Forbidden targets (`isForbiddenOutboundAddress`): link-local (including cloud
  metadata at `169.254.169.254` and `fd00:ec2::254`), `0.0.0.0/8`, multicast,
  broadcast, the unspecified address, and IPv4-mapped forms of these. Private
  networks and loopback stay allowed, because ntfy and InfluxDB often run there
  and only an admin can set the target.
- Every resolved address is checked, and the client connects to exactly the
  checked address (no second DNS lookup, against DNS rebinding). Redirects are
  not followed, so a token cannot be forwarded to another host.
- Errors are reduced to short codes (`network`, `timeout`, `http<status>`,
  `blocked`, `invalid`) so that URLs with secrets never appear in logs.
- Report messages (`server/lib/src/report.dart`) carry a summary only, not
  addresses, names or values of the installation.
- The InfluxDB export sends bus counters; group addresses, names, values and
  senders only if the admin turns on `includeValues` (`server/lib/src/exporter.dart`).

### Prometheus endpoint

`server/lib/src/exporter.dart`, `_serveMetrics`: own port (default 9464), off by
default. Answers only peers in local networks (`isLocalPeer`), only
`GET /metrics`, and only with the bearer token (generated when the export is
enabled, compared in constant time). It is plain HTTP.

### Diagnostics packages

`lib/export/diagnostics_bundle.dart`. Tests: `test/diagnostics_test.dart`,
`test/support_package_test.dart`.

A diagnostics package is a ZIP the user creates and shares or saves; the app
does not send it anywhere. Before packing:

- `Scrubber` replaces known private names (project, installations, gateway host)
  and patterns in free text: e-mail addresses, URLs, MAC addresses, IPv4 and IPv6
  addresses, KNX serial numbers and host names with common suffixes.
  `Scrubber.tree(dropSecrets: true)` drops JSON keys that look like credentials
  or identifiers (`pass`, `secret`, `key`, `token`, `auth`, `user`, `mail`,
  `serial`, `mac`, `host`, `ip`, `ssid`, `address`, `cert`, `cookie`,
  `session`).
- The project catalog loses its project name and serial numbers; names,
  locations and descriptions can be left out as well (`anonymizeCatalog`,
  `keepNames`).
- Telegrams lose the raw cEMI frame (additional info can carry KNX RF serial
  numbers). Telegrams to Data Secure addresses keep only time, source and
  destination, as they look on the bus without the keyring. The keyring itself
  is never included.
- Screenshots are included only if the user agrees (`includeShots`), and they are
  not filtered.

Limit, as the code states: the scrubber only removes what it recognises. Freely
typed names, names of group addresses and devices (unless left out) and
telegram values remain, and telegrams can reveal presence at home. A
diagnostics package is therefore not free of personal data.

## 8. Known limits

Collected from the sections above, and in `tool/public-repo/SECURITY.md`:

- The app lock and the file encryption do not protect against malware running
  as the same user.
- Without a usable keychain (Linux without libsecret) the app's files stay
  unencrypted. Settings such as the gateway address are never encrypted.
- Add-on, Docker and KNX Box store their data unencrypted, including the KNX
  Secure keyring (`secure_keys.json`) and IP Secure credentials (`server.json`).
  Whoever holds the box's SD card can read everything on it.
- A browser in the box's Wi-Fi uses plain HTTP; Docker uses plain HTTP unless a
  certificate is configured.
- The write confirmation in the app is a safeguard against mistakes, not access
  control. Plain KNXnet/IP and KNX TP have no authentication; use KNX IP Secure
  and Data Secure where the installation supports them.
- IP Secure without a device authentication code does not verify the gateway.
  Secure routing is not implemented.
- Diagnostics packages are scrubbed, not anonymous.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's
[private vulnerability reporting](https://github.com/regetskcob/KNX-Monitor/security/advisories/new)
on the repository `regetskcob/KNX-Monitor`. Only the latest release of the app,
the add-on and the KNX Box receives security fixes. Scope and known limits are
listed in `tool/public-repo/SECURITY.md`, which is published as `SECURITY.md` in
that repository.
