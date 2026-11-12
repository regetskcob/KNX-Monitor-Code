# Security

How Busclear protects the user's data and the KNX installation, written for
people who audit the code. Every statement points at the code that implements
it; where the protection ends, the section says so.

Busclear comes in four forms that share one Dart code base:

| Form | Code | Where data lives |
|---|---|---|
| Native apps (iOS, iPadOS, Android, macOS, Windows, Linux) | `lib/` | App data directory, system keychain |
| Home Assistant add-on (web app plus Dart server) | `lib/` (web build), `ha-addon/knx_monitor/server/` | Add-on data folder `/data/app` |
| Docker container (same server, standalone) | `ha-addon/knx_monitor/server/` | Mounted `/data` |
| Busclear Box (Raspberry Pi image with the same server) | `ha-addon/knx_monitor/server/`, `box/` | SD card or SSD, `/var/lib/knx-box` |

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
6. [Access to the add-on, Docker and the Busclear Box](#6-access-to-the-add-on-docker-and-the-knx-box)
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
the Busclear Box pairing (device token, Wi-Fi password) and the app lock state are
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
| Settings keys filtered with the same rule as on export (`FullBackup.keepsOut`) | A file cannot set the app lock, device identifiers or the consent to share a keyring with a Busclear Box. |
| Keyrings only under keys starting with `knx_keyring:` | A file cannot write arbitrary keychain entries. |

Limits: the decrypted ZIP holds the project and the KNX Secure keys in plain
text. The backup is only as strong as its password; there is no recovery.

The Busclear Box, the Docker container and the add-on have a backup of their own
data folder, the [box backup](backup-format.md#box-backup): a plain zip whose
KNX Secure keyring, IP Secure passwords and third-party credentials are in an
encrypted part with the same construction (PBKDF2-HMAC-SHA256 with 600,000
rounds, AES-256-GCM), only if the user sets a password. The box password, paired
devices, TLS key and integration tokens are never in it, so a stolen file opens
no box. Backup and restore are admin only; restoring asks for the current box
password, is locked in read-only mode, checks the zip against path traversal,
zip bombs and unknown paths before anything is moved, and keeps the previous
state.

## 3. App lock

Code: `lib/model/app_lock.dart`, `lib/platform/key_vault.dart`,
`lib/ui/app_lock_screen.dart`. Tests: `test/app_lock_test.dart`,
`test/app_lock_gate_test.dart`.

The app lock covers the user interface when the app starts or returns from the
background after a chosen timeout (immediately, 1, 5 or 15 minutes). The bus
connection and alarms keep running behind it. It exists in the native apps only;
in the web app the Home Assistant login or the Busclear Box password decides
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

Busclear implements KNX IP Secure tunnelling (AN159) and KNX Data Secure for
group communication (AN158) itself, using AES from `pointycastle` and an
X25519 implementation in Dart. The structure follows xknx (MIT); the
implementation is checked against the examples of the KNX Association and xknx.

| Part | Where | Used by the app | Used by the server (add-on, Docker, box) |
|---|---|---|---|
| CCM building blocks (CBC-MAC, CTR), X25519, password derivation | `package:knx` `lib/src/secure/knx_crypto.dart` | keyring, IP Secure, Data Secure | IP Secure, Data Secure |
| IP Secure session | `package:knx` `lib/src/secure/ip_secure.dart` | `lib/knx/secure_tunnel.dart` | `package:knx_io` (`link.dart`) |
| Data Secure | `package:knx` `lib/src/secure/data_secure.dart` | `lib/knx/knx_tunnel.dart` (receive and send) | `server/lib/src/bus.dart` (receive only, for recording) |
| ETS keyring import | `lib/knx/secure/keyring.dart`, `lib/knx/secure/keyring_store.dart` | yes | reads `secure_keys.json` (`server/lib/src/bus.dart`, `_reloadKeys`, `DataSecure.fromJson`) |
| Tests | `knx_crypto_test.dart`, `data_secure_test.dart` in package knx | `test/data_secure_test.dart` (keyring, `secure_keys.json`) | `server/test/robust_frames_test.dart` |

App and server use one implementation from the open-source package [`knx`](https://pub.dev/packages/knx)
(`package:knx/secure.dart`); there are no copies any more.

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
  full backup (section 2), or on a Busclear Box after an explicit question per box
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
password, then every frame inside a `SECURE_WRAPPER`. A gateway key that
yields an all-zero X25519 shared secret (a low-order point, RFC 7748 section
6.1) ends the handshake (`IpSecureException('key')`), since whoever sent it
would know the session key. Received wrappers are
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

The keyring only carries the sequence numbers from the time of its ETS export.
The server therefore keeps the highest valid number per sender in
`secure_sequence.json` next to `secure_keys.json` in the installation folder
(`BusService._noteSequence`, `_saveSequences` in `server/lib/src/bus.dart`),
written atomically at most every 30 seconds and on shutdown, and starts from
the higher of both after a restart or a new keyring. A recorded telegram
replayed after a restart is not recorded as valid. Only senders from the
keyring count; the file is never served or accepted over `/api/files/`. Test:
`server/test/robust_frames_test.dart` ("Folgenummern überstehen einen
Neustart"). Up to 30 seconds of numbers can be lost in a power cut; a replay
of telegrams from exactly that window would pass once.

With several tap points ([tap-points.md](tap-points.md)) a forwarded secured
telegram arrives more than once with the same sequence number. The replay check
stays as it is; `SecureTapCache` (app: `lib/knx/secure/secure_tap_cache.dart`,
server: `server/lib/src/secure_taps.dart`, kept identical by
`server/test/tap_copies_test.dart`) lets exactly one case through before it,
and only as a further sighting of the entry the first copy opened in the
merger:

- the frame is byte-identical in everything the MAC covers, MAC included
  (sender, destination, address type, secured APDU with sequence number). Only
  the repeat flag and the hop count may differ; neither is protected, and the
  copy is given the repeat flag of the first one so both merge under one key;
- it comes from a tap point that has not delivered this telegram yet;
- the entry of the first copy is still waiting in the merger. Once it has left
  (seen by every listening tap point, window over, a silent tap point that is
  not waited for), any copy is a replay;
- it arrives within the merge window of that pair of tap points, counting only
  windows set by hand (default 100 ms, at most 5 s). Windows the meter widened
  on its own never count: lag can be faked with unsecured telegrams.

Everything else goes to `DataSecure.receive` and is rejected and counted as
before. As a last line, a copy that the merger releases on its own after all is
dropped by the caller (`SecureTapCache.released`). A copy therefore never
becomes an entry: nothing passes history, MQTT, alarms or watchers a second
time, and no value can differ from the first copy's. With a single tap point
the cache is not used at all. Residual risk: someone who can inject the
identical frame on another line while the entry is still open, within that
window, makes the telegram show as "also seen there" (a wrong sighting in the
path and in the live filter table check). Tests:
`test/secure_tap_cache_test.dart`, `server/test/tap_points_test.dart`
(variants 1 to 3: wide window of a third tap point, flipped repeat flag, silent
tap point).

`DataSecure.send` (app only) encrypts group telegrams to addresses that have a
key, with the tunnel address as source. The sending sequence number starts at
the milliseconds since 2018-01-05 UTC and counts up, so it increases across
restarts without a stored counter.

Limit: the sending sequence number depends on the device clock. A clock that is
far behind produces numbers that receivers reject as replays (a functional
failure, not a security one).

### DALI reports and the emergency lighting log

Busclear reads the DALI side of an installation from the telegrams a KNX-DALI
gateway sends ([dali.md](dali.md)). Any device on the bus can send any
telegram with any sender address, so these reports are input from outside:

- **Who reported:** a fault report counts only for a gateway in the project or
  one the user took over; a sender heard while listening is a suggestion (at
  most 16, kept in memory, never saved). On the server, with `dali.json` only
  the gateways it names count; without it at most 16 senders are followed. A
  converter status or 1-bit fault object counts only from the gateway the
  project names for it.
- **Emergency lighting log:** every entry keeps the sender (`src`). A result
  from another sender than the gateway is marked (`fx`), shown in the view, PDF
  and CSV, and never counts as a current or failed test. Whether the telegram
  arrived KNX Data Secure is noted (`sec`) wherever the log is written: on the
  add-on and the box by the server, in the apps by their tunnel, which marks a
  telegram it decrypted and checked with the keyring (`markDataSecure` in
  `lib/knx/telegram.dart`, keyed to the frame, so the mark survives merging at
  tap points). A rebuild from the daily history knows no `sec`: the history
  keeps the decrypted frame only. Without Data Secure the
  results are not forgery-proof; the view and the PDF say so. A result seen for
  the first time may be older than its time: it is marked and has an unknown
  age, never "current".
- **Bounded:** at most one entry per object, test kind and origin per hour
  (further changes are only counted), at most 4 MB per year's file with one
  overflow line and a notification, files read up to that limit (never thrown
  away as a whole, the cut is shown). `dali_tests/` is append only through the
  file API: no rewrite, no delete (it goes with the installation).
- **Notifications:** a state counts once it held for 30 seconds; per gateway at
  most five notifications a minute, then one summary; at most 60 events a minute
  for Home Assistant automations; at most 4096 luminaires remembered.
- **Writes:** `dali.json` (names, rooms, what the objects mean) changes only
  with edits and the project; the runtime state lives in `dali_state.json`, a
  fault change is saved within seconds, mere liveness at most every ten minutes.
  Only `dali.json` goes to the box.
- **Reading:** periodic reading of the diagnostic addresses is off by default,
  never runs in read-only mode, starts after a random delay and is left out
  while every gateway reported within the interval, so several views on one
  server do not all read.

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
access to an unencrypted gateway can send telegrams without Busclear.

### Read-only mode of the server

`ha-addon/knx_monitor/server/lib/src/read_only.dart`. Test:
`server/test/read_only_test.dart`.

| Where | Default |
|---|---|
| Home Assistant add-on | Option `read_only`, **on** (`ha-addon/knx_monitor/config.yaml`) |
| Docker, Busclear Box | `READ_ONLY=1`, off |

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

On the Busclear Box and in Docker, a device paired without the box password (role
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

Rules in `ha-addon/knx_monitor/server/lib/src/relay_policy.dart`, tests in
`server/test/docker_hardening_test.dart`:

- Only complete KNXnet/IP packets are forwarded, in both directions
  (`relayPacketWellFormed`): header `06 10`, a service type from an explicit
  list (core, device management, tunnelling, routing, secure) and a total
  length equal to the packet's length. Other UDP protocols do not pass, even
  if they happen to start with `06 10` (a DNS query with that transaction ID
  would need as many questions as it has bytes).
- Only to IPv4 targets that can be a KNX gateway (`relayTargetAllowed`): RFC
  1918 networks, `100.64.0.0/10` (CGNAT, VPNs such as Tailscale), link-local,
  the KNXnet/IP multicast address `224.0.23.12`, and `255.255.255.255`.
  Loopback only on port 3671: with the host network the container shares the
  host's loopback, where services often trust local senders. The relay is
  neither a UDP hop into the internet nor a UDP proxy to other services.
- Packets are handed back only from addresses the relay sent to (any port,
  since a gateway's data endpoint may differ from its control endpoint), plus
  search responses from any gateway. Other hosts on the network cannot inject
  packets into the admin's browser, and only those addresses can register a
  tunnel that is disconnected when the tab closes.
- Read-only mode filters services as described above.
- On the box, role `device` gets no access to `/ws` at all
  (`BoxAccess.guard`), because the raw relay could carry any telegram.
- When access is revoked or the box password changes, open relays, bus
  WebSockets and event channels are closed (`onAccessChanged`).
- The event channel `/ws/events` ([event-channel.md](event-channel.md)) takes
  nothing from the client (a message over 1 KiB closes it with 1009), holds at
  most 256 KiB per connection and cuts off a client that stops reading, and
  accepts at most 8 connections, 2 per device or address, the last one only
  with admin rights.
- When the browser tab closes, the server sends `DISCONNECT_REQUEST` for tunnels
  that are still open.
- `/ws` and `/ws/bus` ping every 20 seconds (`webSocketPing`); a client that
  stops reading or answering is closed instead of the server queueing the bus
  traffic for it in memory.
- `/ws` and `/ws/bus` are upgraded without permessage-deflate
  (`webSocketCompression`): 300 KiB of compressed data used to unpack into
  almost 800 MiB. A client message larger than 64 KiB
  (`BusService.maxClientMessage`) closes the connection with 1009. dart:io
  assembles a message before handing it over, so one such message is still
  held in memory, but no longer more than was actually sent.

## 6. Access to the add-on, Docker and the Busclear Box

### Home Assistant add-on: Ingress only

The add-on runs with `host_network: true` and listens on port 8765
(`ingress_port`). `_handle` in `server/bin/server.dart` answers only requests
whose peer address is the Supervisor's Ingress proxy `172.30.32.2`; everything
else gets 403. Home Assistant authenticates the user before Ingress forwards the
request. Ingress users have the admin role.

The `X-Ingress-Path` header is written into `index.html` as `<base href>` only
inside Home Assistant, only from the Ingress peer and only in the form
`/segment/segment` (a `//host` would load every script from another host).

The peer address is trusted only when the server runs inside Home Assistant,
recognised by `SUPERVISOR_TOKEN`. In a Docker network without `BOX=1`,
`172.30.32.2` can be any container; there every request gets 403, and the
server says so in the log at startup (use `BOX=1` with `BOX_PASSWORD`).

Exceptions:

- `/healthz` answers `ok` without authentication and without data
  (`server/lib/src/http.dart`), for the Supervisor watchdog.
- `ALLOW_ALL=1` disables the check. It is meant for development and tests
  (`server/test/server_process_test.dart`, CI smoke test) and must not be set in
  production; the server says so on stderr at every start. With it the server
  listens on 127.0.0.1 only. A `BIND` other than loopback is refused (exit 78)
  unless `ALLOW_ALL_EXPOSED=1` is set as well (`refuseToStart` in
  `server/lib/src/container_env.dart`): the CI starts its throwaway container
  that way, and a command copied from it without the second variable fails
  instead of opening bus and relay to the network. On
  loopback it also answers only requests whose `Host` is `localhost`,
  `127.0.0.1` or `[::1]` (with any port), so a web page cannot reach it through
  DNS rebinding. With a non-loopback `BIND` the developer chose to expose it,
  and the check is off.
- The optional Prometheus endpoint uses its own port (see section 7).

Every response carries `X-Content-Type-Options: nosniff` and
`Referrer-Policy: no-referrer`. In box mode (Busclear Box, Docker) every response
also carries `X-Frame-Options: DENY` and `Content-Security-Policy:
frame-ancestors 'none'`, so no other page can show the box in a frame
(clickjacking). The add-on cannot send them: Home Assistant shows it in a frame
through Ingress.


The Busclear integration reaches the add-on with its own token on
`/api/ha/*` only. The add-on hands the token to Home Assistant through the
Supervisor discovery (`POST /discovery`). Reading discovery messages
(`GET /discovery`) is restricted by the Supervisor to Home Assistant Core
(`@require_home_assistant` in `supervisor/api/discovery.py`), so other
add-ons cannot read it, also not with the `admin` role. Afterwards the token
lives in the integration's config entry like any other integration secret; the
integration's diagnostics redact it.

Without Supervisor (Busclear Box, Docker; `BOX=1`) there is no discovery and no such
token: the server does not create one (`HaIntegration.tokenAccess`), and one left
from an earlier start in the add-on is removed. Instead `/api/ha/*` takes a paired
device with admin rights, sent as `Authorization: Bearer` (the token from a
link created on `/pair` with "Verwalten" and "Schlüssel direkt anzeigen", or
from `POST /api/box/pair`).
The request first passes `BoxAccess.guard` like any other (network access, rate
limit, constant-time hash comparison), then `bin/server.dart` lets only that
role and kind of credential through: the box password, a browser session and
devices without admin rights get 403. The integration (`config_flow.py`, step
`manual`) sends the token only to the address entered by the user, does not
follow redirects, and with a fingerprint in the link (`fp`, `TLS_CERT`) speaks
HTTPS and accepts only that certificate (`aiohttp.Fingerprint`). Without a
certificate the token crosses the network in plain text, like the app's.

### Busclear Box and Docker: password, pairing, roles

`BOX=1` switches the server to standalone mode with its own authentication
(`ha-addon/knx_monitor/server/lib/src/box_access.dart`, `BoxAccess.guard`).
Tests: `server/test/box_access_test.dart`, `server/test/box_security_test.dart`.

| Credential | Used by | Stored as | Role |
|---|---|---|---|
| Box password | Browser on the login page `/login` (password only), then a session cookie; tools also as HTTP Basic (any user name) | PBKDF2-HMAC-SHA256, 40,000 rounds, 16-byte salt, in `access.json` | `admin` |
| One-time pairing code (32 random bytes) from `/pair` in the browser, in the QR code and link | App, once, in the body of `POST /api/box/claim` | SHA-256, in memory only, 10 minutes | none; exchanged for a device token |
| Device token (32 random bytes), from exchanging a pairing code | App, `Authorization: Bearer` | SHA-256 in `access.json` | `device` |
| Device token from `POST /api/box/pair` (requires the box password itself as HTTP Basic, not a session or token) | App paired with the box password | SHA-256 | `admin` |
| Device token from a code created with "Nur ansehen" | App or browser that only looks | SHA-256, `viewOnly` | `viewer` |
| Device token from `/pair` with "Verwalten" (as a code, or shown directly with "Schlüssel direkt anzeigen") | Home Assistant integration, ioBroker | SHA-256, `admin` | `admin` |

Pairing a device on `/pair` (`BoxAccess.createPairingCode`, `claimPairing`,
tests in `server/test/box_access_test.dart`, group "Kopplungscode"):

- The page creates no device. It shows a QR code and a link
  `knxmonitor://box?url=…&code=…&name=…&fp=…` with a one-time pairing code:
  32 random bytes, valid for 10 minutes, usable once. The box keeps only its
  SHA-256, and only in memory: a restart ends open codes, and so do changing
  the password and "Alle sperren". At most 8 codes are open at a time.
- The app exchanges the code with one request, `POST /api/box/claim`
  `{code, name, app}`, and gets what `POST /api/box/pair` returns: `{key, id,
  name}`. The request needs no other credentials; it runs over the same
  connection as everything else (HTTPS with the pinned certificate when the
  link has `fp`) and is subject to the same network check (box Wi-Fi, or LAN
  access enabled). The code travels in the body, never in a URL or a header.
- The device is created at that moment, with the rights chosen on the page
  ("Nur ansehen", "Verwalten") and the name entered there (without one: the
  name the app gives). Nothing in the request can change the rights.
- A wrong, used or expired code counts as a failed attempt of the sender, like
  a wrong password, and during a lockout no code is checked. A code that was
  exchanged does not clear the counter.
- The page lists codes that wait ("wartet auf die App", with "Verwerfen" to
  withdraw one) and those exchanged during this run ("eingelöst", with the
  time), so a code someone else used does not go unnoticed: the device it
  created is in the list below and can be revoked there.
- **Key shown directly.** Ticking "Schlüssel direkt anzeigen" creates the
  device at once and shows its token, as text and as a link with `key=`, as
  the page did up to 1.11.2. That is for what cannot exchange a code: the Home
  Assistant integration and ioBroker (which take the key), and apps up to
  1.11.2. Such an app treats a code link as a link without access and reports
  that the box refused it; nothing is paired and nothing leaks. The app keeps
  reading links with `key=`.
- The setup link on the sticker (`pw=`) and pairing with the box password
  (`POST /api/box/pair`) are unchanged.

- The password hash is computed in a separate isolate. Hashes stored by older
  boxes with more rounds are re-hashed after the next successful login.
- Comparisons of hashes and tokens run in constant time (`_equal`).
- Failed attempts per peer address (wrong password, wrong device token, wrong
  pairing code): four are free, from the fifth on 30 seconds,
  doubling up to 15 minutes. A valid device token is checked before the
  lockout, so paired apps keep working while one sender is locked out (behind
  a reverse proxy or NAT that is everyone); a wrong token is refused during
  the lockout and counts as a failed attempt. At most three password checks run at the same time
  per peer and four over all peers, so parallel requests, also from many
  addresses, cannot exhaust the Pi. A valid device token does not reset the
  counter; only the correct password does. A flood of new peer addresses does
  not lift a running lockout: expired entries go first, running ones only
  beyond 8,192 peers.
- Counters and running lockouts survive a restart
  (`access-strikes.json` next to `access.json`, written atomically, tests in
  `server/test/box_strikes_test.dart`): pulling the plug or provoking a crash
  buys no fresh attempts. The file is written only when a counter changes (a
  failed attempt, or the correct password after failed ones), never for a
  request refused during a lockout; changes during a write are collected into
  one more write. It holds at most 1,024 senders, those that wait longest
  first. It is not served by `/api/files/` and is not part of a box backup.
- The lockout can never shut the owner out for good. No wait is longer than
  15 minutes. The box often has no clock: a stored lockout that ends later
  than its counter allows (clock set back since) is shortened to that wait,
  counted from now, on start and while running. Counters whose wait ended more
  than 24 hours ago are dropped on start, and an unreadable file is discarded.
  A password reset on the device (`password-reset`, see "Reset" below) clears
  all counters and lockouts. In Docker, deleting `access-strikes.json` from
  the data folder while the container is stopped does the same; whoever can do
  that can read `access.json` as well. Moving the clock forward ends lockouts
  early; setting the clock needs admin rights.
- Connections: at most 64 live views (`/ws/bus`) and 16 UDP relays (`/ws`) at
  once; beyond that the server answers 503 before the WebSocket upgrade.
- Requests: only `GET`, `HEAD`, `POST`, `PUT`, `PATCH` and `DELETE` (405
  otherwise); API paths without a handler answer 404. Settings in `PUT
  /api/bus` are checked for type and range and rejected with 400 instead of
  being clamped (a negative retention used to become 0, which deletes the
  history).
- Session cookie `knx_box_session`: 32 random bytes, stored as SHA-256, valid
  12 hours, at most 32 sessions, kept in memory only. Flags `HttpOnly;
  SameSite=Strict`, plus `Secure` over HTTPS.
- Login page (`BoxAccess._loginOrLogout`, tests in
  `server/test/login_page_test.dart`): browsers get the page `/login` with a
  password field only, instead of the browser's own Basic dialog. A page
  request without a session is redirected there (`?next=` keeps the target,
  limited to local paths by `safeNext`); the browser's other requests get 401
  without `WWW-Authenticate`, so no dialog appears, and the web app then opens
  the login page itself. Requests without `Sec-Fetch-*` headers (curl, scripts)
  still get the Basic challenge. `POST /login` and `POST /logout` must come
  from the box's own form (`Origin` equal to `Host`), and the login goes
  through the same lockout and concurrency limits as Basic. `/logout` (button
  on `/pair`) deletes the session. With the sticker password still valid, the
  login leads to `/pair` first.
- Cross-site protection: a request with an `Origin` header must match the
  `Host`. Requests authenticated only by the cookie must be same-site
  (`Sec-Fetch-Site`) and state-changing requests and WebSockets must carry an
  `Origin`.
- Changing the password or locking out all devices ("Alle sperren") clears
  sessions and cached logins; every change of access closes open WebSockets.
  Changing the password does not revoke paired devices (except after the
  sticker password, see below): remove a lost device, or lock out all.
- Admin device tokens survive a password change, so they are only issued
  against the password itself (`POST /api/box/pair` with HTTP Basic): a
  borrowed browser session or a lost admin tablet cannot mint a lasting one.
- Changing the password and locking out all devices need the current
  password, also with an admin token or a session (a lost tablet must not lock
  the owner out); a wrong one counts as a failed login. Only the required
  first change of the sticker password goes without it.

Error texts of unexpected restarts (`/api/restarts`) only go to `admin`; a
paired device sees time and reason.

The `viewer` role (chosen when pairing on `/pair`) can do what `device` can,
except that it sends nothing to the bus, not even read requests, cannot hand
the connection to an own tunnel and writes no files at all. The server reports
`readOnly` and `viewOnly` to it, so the app hides sending
(`BusService.serve`, `maySend`).

| | `admin` | `device` | `viewer` |
|---|---|---|---|
| Live view `/ws/bus`, event channel `/ws/events`, history, statistics, ETS export, reports (read) | yes | yes | yes |
| Send to the bus | any `L_Data.req` | group values only (section 5) | no |
| Raw relay `/ws`, `/pair`, `/api/box/*` (devices, password, Wi-Fi, LAN access) | yes | no | no |
| Change the bus connection (`/api/bus`), report, export and maintenance date (`/api/report/maintenance`), force the box clock, check the KNX HAT | yes | no | no |
| Gateway search (`/api/discover`), own network address (`/api/network`), name lookup (`/api/resolve`) | yes | empty result or 403 | empty result or 403 |
| Offer the time to an unset box clock (`/api/box/time`, not in Docker) | yes | yes | no |
| Other installations (`/api/installations`, `?installation=`, `/api/installations/<id>/files/`) | all, and manage them | only the active one; others answer 403 | like `device` |
| Read `secure_keys.json` | yes | no | no |
| Write files over `/api/files/` | all except server-owned ones | own entries in `charts.json` and `watch_rules.json` (at most 1 MiB); a broken rule is skipped on its own, the others keep working | nothing |
| Error texts of restarts (`/api/restarts`) | yes | time and reason | time and reason |

Writes of a `device` to `charts.json` and `watch_rules.json` are merged by the
server (`mergeDeviceEntries` in `server/lib/src/files.dart`): every entry the
device sends is marked with its device id (`owner`); entries of other devices
and of the admin (without `owner`) stay as they are, also when the device
leaves them out or sends an entry with the same name or id. All other fields
keep their stored value; in particular `allowed` in `charts.json` (whether the
dashboard card shows values) cannot be changed by a device and is `false` while
none is stored. Writes of the admin replace the whole file, as before: an admin
app that shares its own list removes entries of devices.

Server-owned files such as `access.json`, `server.json` (gateway and IP Secure
credentials), `report_settings.json`, `export.json` and
`secure_sequence.json` are never served or accepted over `/api/files/`, for
any role (`server/lib/src/files.dart`, `_private`). Names are compared in
lower case: on a case-insensitive data folder (Docker Desktop on macOS or
Windows, some NAS shares) `Secure_Keys.json` is the keyring.

When the gateway's host changes, stored IP Secure passwords are only kept if
the request brings them again (`BusService._merged`): IP Secure answers a
foreign host with a MAC over the user password, which could be guessed
offline there.

Limits against overload, for all roles:

- Request bodies: each endpoint has its own limit (64 MiB for a catalog of the
  admin, 1 MiB for a device's file, a few KiB elsewhere). In addition, all
  bodies being read at the same time may hold at most 32 MiB together
  (`bodyBudget` in `server/lib/src/http.dart`); beyond that the server answers
  503 with `Retry-After`. A single request may always use its own limit.
- `/api/bus/availability` evaluates at most 400 days; a negative, reversed or
  longer period answers 400, like the history queries. A history query that
  starts more than a day in the future answers 400 as well, and the search
  for the value at a chart's left edge goes back at most 4,000 days (it used
  to walk back day by day from any start, millions of days in one request).
- The gateway search `/api/discover` sends to every address of every network:
  only one runs at a time, and its result is reused for 10 seconds.
- Files are written to a temporary file with a random name and renamed;
  writes to the same file run one after another (`writeAtomic` in
  `server/lib/src/atomic_file.dart`), so parallel requests cannot interleave.

### Busclear Box specifics

- **Network:** by default the box answers only clients in its own Wi-Fi
  (`10.42.0.0/24`) and itself. Access over Ethernet must be enabled explicitly
  (`LAN_ACCESS=yes` or in the box settings). The firewall enforces this per
  interface (`box/files/lan-access.sh`, nftables); the server's check of the
  peer address is a second layer (`BoxAccess.wlanPeer`). The server cannot
  change the firewall itself; it writes a request file that a host service
  applies. The closed table is loaded before the network and SSH start
  (`knx-box-lan-lock.service`, `box/files/lan.nft`); the request only adds or
  removes an exception, and a failing `nft` leaves the cable closed.
- **Root helpers and the data directory:** `/var/lib/knx-box` belongs to the
  server user. The root helpers that act on its request files (time, LAN,
  Wi-Fi password, boot partition scrub, password reset) never open a file there
  as root: they read and write as the server user (`setpriv`,
  `box/files/box-common.sh`), so a symbolic link planted by a compromised
  server cannot make root read or overwrite other files. The helper units run
  with `NoNewPrivileges`, a reduced capability bounding set and further systemd
  sandboxing; the server itself additionally cannot see the boot partition
  with `knx-box.txt` (`TemporaryFileSystem=/boot:ro`, only `config.txt` bound in).
- **Data drive:** a USB drive or SSD with an ext4 file system labelled
  `KNXBOXDATA` is mounted as the data directory at boot
  (`box/files/data-mount.sh`, with `nosuid,nodev,noexec`). Plugging in such a
  drive is therefore equivalent to access to the SD card: whoever can do it
  decides the server's data, including access tokens and the keyring.
- **Sticker password:** a new box prints its first password on a sticker and
  on the SD card. Until the user sets an own password, only pairing and
  changing the password are possible (`changeRequired`). When the password is
  changed, devices paired with the sticker password are revoked (except the one
  making the change), and the host removes the passwords from the boot partition
  (`box/files/secrets.sh`).
- **Reset:** a new password can be placed on the SD card (`password-reset`);
  whoever holds the card can regain access. Paired devices stay. Failed
  attempts and lockouts are cleared with it.
- **TLS:** `box/files/tls-cert.sh` creates a self-signed ECDSA P-256 certificate
  on first boot (one key per box, never in the image). The server serves HTTPS on
  port 443 next to HTTP (`server/lib/src/box_tls.dart`, `server/bin/server.dart`).
  The pairing QR code carries the SHA-256 fingerprint of the certificate (`fp`).
  Apps pin exactly that fingerprint with a client that trusts no root
  certificates (`lib/platform/addon_io.dart`, `pinnedHttpClient`), so a
  certificate from a public CA cannot replace it. Expiry and host name are not
  checked; the fingerprint is.
- **No secret over plain HTTP to the internet:** without a fingerprint the app
  speaks plain HTTP, which is how a box without a certificate in the home
  network and the box's own Wi-Fi (`10.42.0.1`) work. To an address that is
  not local (`BoxLink.isLocalHost`: private, link-local and loopback
  addresses, `localhost`, `.local`) the app then sends nothing secret: every
  request with the device token (`Authorization: Bearer`, including the
  WebSocket, downloads and uploads), pairing with the box password
  (`Authorization: Basic`) and exchanging a pairing code are refused before a
  connection is opened, with a message that names the address
  (`addonRefusal` in `lib/platform/addon_io.dart`, tests in
  `test/box_plain_http_test.dart`). Pairing says so before the box is stored.
  Names only the home network answers are allowed as well
  (`BoxLink.isHomeName`): a single label such as `nas`, and names under
  `.home.arpa` or `.internal`. Other names count as not local even if they
  resolve to a private address, `nas.fritz.box` for instance (`.box` is a
  public top-level domain): use the IP address, the `.local` name or a
  certificate (`TLS_CERT`) there.
- **Plain HTTP:** a browser in the box's Wi-Fi uses HTTP, so the Wi-Fi password
  (WPA2) is the protection there. The `/pair` page warns when it is opened over
  plain HTTP from outside the box's Wi-Fi.

### Docker

The Docker template (`tool/public-repo/docker/compose.yaml`) runs the same
server with `BOX=1`, requires `BOX_PASSWORD` (Compose refuses to start without
it, and so does the server on its first start, instead of inventing a password
and printing it to the log; shorter than 8 or longer than 128 characters is
refused as well), and answers only on the host itself unless `LAN_ACCESS=yes`.
The template starts read only (`READ_ONLY=1`, `READ_ONLY=0` in `.env` to send).

Without `LAN_ACCESS=yes` the server listens on `127.0.0.1` only, HTTP and
HTTPS, and accepts only requests whose `Host` is `localhost`, `127.0.0.1` or
`[::1]` (`BoxAccess.guard`): a web page that rebinds its own name to
127.0.0.1 gets 403 before the login page. A reverse proxy on the same host
that passes its own host name therefore needs `LAN_ACCESS=yes`, which is
correct: it makes the container reachable from the network.

`BOX_PASSWORD_FILE` and `MQTT_PASSWORD_FILE` read the password from a file
(Docker secrets), so it is not in `docker inspect` (`withSecretFiles`). A
`BOX_PASSWORD` that no longer matches the stored password is ignored, and the
log says so. In Docker the server has no box clock: the host keeps the time,
and no paired device can move the history's time stamps (and with them the
retention). Without `TLS_PORT`, HTTPS uses port 8443, since the template drops
the capability for ports below 1024.
In Docker (`BOX=1` without `BOX_STICKER=1`) `LAN_ACCESS` applies on every start and
cannot be switched in the app, so the container's settings are the only place
that opens it to the network; the password is required either way. The box Wi-Fi range `10.42.0.0/24` counts only on the real box, since in
Docker it can be a home or k3s pod network. The data folder is a bind mount on
the host: the server sets it to 0700 and creates files with umask 077, so the
keyring and IP Secure passwords are not readable by other host accounts
(`server/lib/src/file_mode.dart`). HTTPS needs a
certificate of the user's own (`TLS_CERT`, `TLS_KEY`, `TLS_PORT`); without it,
password and data travel in plain HTTP.

The template drops all capabilities except `CHOWN`, `SETUID`, `SETGID`,
`DAC_OVERRIDE` and `FOWNER` and sets `no-new-privileges`. Despite the host
network, the server can therefore not open raw sockets. With `PUID`/`PGID`
(`1000:1000` in the template) it starts as root only to hand the data folder
to that user (`lchown`, symbolic links not followed, so data folders of older
versions that belong to root keep working) and then switches for good
(`setgroups`, `setgid`, `setuid` through libc in `drop_root.dart`, since the
image has no `su`). It checks that `setuid(0)` fails afterwards and that the
data folder is writable; otherwise it refuses to start (exit 78) instead of
carrying on as root. After the switch the process holds no capabilities.
Without `PUID` (older templates, a plain `docker run`) it runs as root as
before. A `user:` setting is not used: it would make root-owned data folders
unreadable after an update.

### Further hardening (9 November 2026)

Follow-ups of the review of 7 November:

- **Frames of devices without admin rights** are rebuilt before they go on
  the bus (`normalizeDeviceCemi` in `cemi_policy.dart`): standard frame, low
  priority, hop count 6, no additional info, source 0.0.0 (the gateway puts in
  its own address). Such a device can no longer raise its priority, change
  the routing counter or pose as another device.
- **ETS export**: one at a time; a second request gets `429` with
  `Retry-After`.
- **History cache**: a single day bigger than the cache budget is answered
  but not kept, so the cache stays within its budget.
- **Charts**: at most 8 series per chart on the server, as in the app.
- **MQTT `recording/set`**: only `ON` and `OFF` are accepted (anything else
  used to switch the recording off), and every change is logged. Making it
  opt-in would break the existing Home Assistant switch.
- **`/api/files` allowlist** (`knownAppFiles` in `files.dart`): enforced
  from the release after 1.11.2 (the logs of 1.11 stayed quiet). A first path segment
  outside the list is refused with 403 and logged once; the blocklist of the
  server's own files stays as a second line. `test/known_app_files_test.dart`
  checks every file name and every folder in the app's code against the
  list; it found `secure_sequence.json` (the Data Secure sequence counters)
  and `hunts/` (the fault hunt's windows, written by the server and read by
  the app) missing, which the enforced list would have refused.
- **Without root in Docker** (PUID/PGID, see above). Tested with Podman: data
  folder of a root-run container handed over, server as `1000:1000` with no
  effective capabilities, and exit 78 without `SETUID`/`SETGID`.

### Keys of installations and boxes are no credentials

Installations, boxes and app instances have keys that tell them apart across
devices ([keys.md](keys.md)). The installation key travels in handover
packages and fault reports and is treated as public: no request is authorised
by it, no path accepts it in place of an id, and a box that merely names the
key of an installation in the app gets nothing exchanged for it until the
user confirms the connection.

## 7. Outbound connections and what leaves the device

### Connections the software makes

| From | To | When |
|---|---|---|
| App | KNX gateway (KNXnet/IP, UDP or TCP) | When the user connects |
| App | Busclear Box or Docker server | When paired |
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
  `Authorization` header and are not logged. When the target URL of the
  notification or the InfluxDB export changes and no new token comes with the
  same request, the stored token is deleted, so it never goes to a target it
  was not meant for. The settings API returns only
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
- Add-on, Docker and Busclear Box store their data unencrypted, including the KNX
  Secure keyring (`secure_keys.json`) and IP Secure credentials (`server.json`).
  Whoever holds the box's SD card can read everything on it, and whoever can
  plug a drive labelled `KNXBOXDATA` into the box before a restart can replace
  its data.
- Home Assistant backups of the add-on (`backup: hot` in
  `ha-addon/knx_monitor/config.yaml`) contain the add-on's data folder as it is:
  `secure_keys.json`, `server.json`, the tokens for notifications, InfluxDB and
  the Busclear integration, in plain text. Whoever can read a backup can read
  them; Home Assistant can encrypt backups with its own key.
- The add-on maps the Home Assistant configuration writable
  (`homeassistant_config`, `read_only: false`), because it places the
  dashboard card in `/config/www`. A flaw in the server could therefore change
  the Home Assistant configuration. Decided to keep it: without it the card
  would have to be installed by hand. The option `dashboard_card` only stops
  the copying, not the mapping.
- A browser in the box's Wi-Fi uses plain HTTP; Docker uses plain HTTP unless a
  certificate is configured.
- The box hotspot uses WPA2-PSK only; WPA3 (SAE) is not offered, since support
  in access point mode on the Pi's Wi-Fi chip is unverified.
- The MQTT bridge accepts the command to pause or resume recording from
  anyone who may publish to its topic on the broker. Protect the broker with
  a user and password (some ioBroker and Mosquitto setups allow anonymous
  clients).
- KNXnet/IP routing and plain tunnelling have no sender authentication: a
  device in the network can inject telegrams into the recording, watchers and
  alarms, or disconnect a UDP tunnel. Use a TCP or IP Secure tunnel where the
  gateway offers one.
- The Docker image runs the server as root unless `PUID` is set (the template
  sets it). A plain `docker run` without `PUID`, `--cap-drop` and
  `no-new-privileges` keeps root and Docker's default capabilities, including
  `NET_RAW`.
- Behind a reverse proxy every client has the proxy's address: one sender's
  lockout after wrong passwords locks out every browser login (paired apps
  keep working).
- The write confirmation in the app is a safeguard against mistakes, not access
  control. Plain KNXnet/IP and KNX TP have no authentication; use KNX IP Secure
  and Data Secure where the installation supports them.
- IP Secure without a device authentication code does not verify the gateway.
  Secure routing is not implemented.
- Diagnostics packages are scrubbed, not anonymous.
- Pairing and setup links use the custom scheme `knxmonitor://`, which any app
  on the phone can register too, and links end up in histories, logs and
  screenshots. The pairing link from `/pair` therefore carries a one-time
  code (`code=`, 10 minutes, usable once) instead of the device key. Whoever
  catches or photographs it and reaches the box first, within that time, gets
  the device in place of the owner; the owner's app is then refused, and the
  page lists the code as used and the device, which can be revoked there.
  Three kinds of links still carry a lasting secret: the setup link on the
  sticker (the first box password, `pw=`; printed, so it cannot change), a
  link created with "Schlüssel direkt anzeigen" for Home Assistant, ioBroker
  or an app up to 1.11.2 (`key=`), and links created by boxes up to 1.11.2.
  The app confirms every link from outside with the address before it pairs,
  the sticker password must be changed on first use (which revokes devices
  paired with it), and a paired device can be removed on `/pair`. Verified app
  links would need a public web domain for each box, which a box in its own
  Wi-Fi does not have.
- If the answer to exchanging a pairing code is lost on the way, the code is
  spent and the device exists without an app that holds its key: create a new
  code and revoke that device on `/pair`.
- The lockout after failed attempts is kept across restarts, but it counts
  per sender address: an attacker who changes addresses gets four free
  attempts per address. The box password should therefore not be guessable;
  pairing codes and device keys (256 random bits) are not.
- The app pins the box certificate by its fingerprint and ignores its validity
  period and name (the box often has no clock). A pin stays valid until the
  box gets a new certificate: then pair again with the new link. Revoking a
  device on `/pair` takes its key away regardless of the certificate.
- The Prometheus endpoint (section 7) listens on all interfaces, so a scraper
  in the network can reach it; it answers only local addresses with the token,
  over plain HTTP.

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's
[private vulnerability reporting](https://github.com/regetskcob/KNX-Monitor/security/advisories/new)
on the repository `regetskcob/KNX-Monitor`. Only the latest release of the app,
the add-on and the Busclear Box receives security fixes. Scope and known limits are
listed in `tool/public-repo/SECURITY.md`, which is published as `SECURITY.md` in
that repository.

## Software bill of materials

`python3 tool/sbom.py [out-dir]` writes one CycloneDX 1.5 file per product
to `build/sbom/` (`busclear-app.cdx.json` from `pubspec.lock`,
`busclear-server.cdx.json` from the add-on/box server's `pubspec.lock`). Each
component carries version, source, SHA-256 and package URL (`pkg:pub/…`);
git packages carry their repository and commit, dev dependencies are marked
optional. Only the Python standard library is needed. The serial number
depends on the lock file, so the same lock file gives the same document
apart from its time stamp. `tool/release.sh` attaches it to every public
release (`busclear-server.cdx.json` to the add-on release,
`busclear-app.cdx.json` with the Linux build, listed in `SHA256SUMS.txt`), for
the Cyber Resilience Act and for anyone who asks what Busclear contains.
