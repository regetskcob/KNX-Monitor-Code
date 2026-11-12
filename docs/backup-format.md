# Backup file format (`.knxbackup`)

A full backup holds everything the Busclear app keeps on one device, encrypted
with a password the user chooses. The format is documented so that the data stays
readable without the app. It applies to backups created by the native apps
(iOS, iPadOS, Android, macOS, Windows, Linux) from version 1.9.1 on. The web app
of the Home Assistant add-on and of the Busclear Box has no full backup; its data
lives in the server's data folder. That folder has a backup of its own, the
[box backup](#box-backup) further down.

Implementation: `lib/model/full_backup.dart` (`FullBackup`, `_pack`, `_unpack`),
crypto primitives in `lib/knx/secure/package_crypto.dart` (`pbkdf2`, `aesGcm`),
ZIP limits in `lib/platform/safe_zip.dart`. Tests: `test/full_backup_test.dart`,
`test/backup_hardening_test.dart`.

## Outer file

The file is UTF-8 JSON. The default file name is `knx-monitor-sicherung.knxbackup`.

```json
{
  "format": "knx-monitor-backup",
  "version": 1,
  "kdf": {"name": "PBKDF2-HMAC-SHA256", "iterations": 600000, "salt": "<Base64>"},
  "cipher": {"name": "AES-256-GCM", "nonce": "<Base64>", "aad": "knx-monitor-backup/1"},
  "data": "<Base64: ciphertext, the last 16 bytes are the GCM tag>"
}
```

| Field | Meaning |
|---|---|
| `format` | Always `knx-monitor-backup`. Anything else is rejected. |
| `version` | Format version, currently `1`. A file with a higher version is rejected and nothing is changed. |
| `kdf.iterations` | PBKDF2 rounds. The app writes 600,000. |
| `kdf.salt` | 16 random bytes, standard Base64 with padding. |
| `cipher.nonce` | 12 random bytes (96-bit GCM nonce), standard Base64. |
| `cipher.aad` | Additional authenticated data as text: `<format>/<version>`, i.e. `knx-monitor-backup/1`. |
| `data` | AES-256-GCM ciphertext followed by the 16-byte tag, standard Base64. |

Key derivation: PBKDF2-HMAC-SHA256 over the password encoded as UTF-8, with the
salt and iteration count from the file, 32-byte output. The password is used as
typed; it is not normalised (unlike the app's other password-protected packages).
The app requires at least 12 characters when creating a backup
(`FullBackup.minPassword`).

## Reading a backup without the app

Any PBKDF2 and AES-GCM implementation will do. In Python with the
[`cryptography`](https://cryptography.io/) package:

```python
import base64, getpass, hashlib, io, json, pathlib, zipfile
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

j = json.load(open("knx-monitor-sicherung.knxbackup", encoding="utf-8"))
password = getpass.getpass("Backup password: ")
b64 = base64.b64decode
key = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"),
                          b64(j["kdf"]["salt"]), j["kdf"]["iterations"], 32)
plain = AESGCM(key).decrypt(b64(j["cipher"]["nonce"]), b64(j["data"]),
                            j["cipher"]["aad"].encode("utf-8"))

# Extract only plain relative paths, like the app does on restore.
out = pathlib.Path("backup").resolve()
with zipfile.ZipFile(io.BytesIO(plain)) as z:
    for name in z.namelist():
        target = (out / name).resolve()
        if name.endswith("/") or not target.is_relative_to(out):
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(z.read(name))
```

A wrong password and a modified file look the same: the tag check fails.

## Inner ZIP

Decrypted, `data` is a ZIP archive. All entries are UTF-8 text.

| Path | Content |
|---|---|
| `manifest.json` | `{"format": "knx-monitor-backup", "version": 1, "files": <number of entries under files/>}` |
| `files/<path>` | Every data file of the app, decrypted (plain JSON or NDJSON), with the path relative to the app's data directory. |
| `prefs.json` | The app's settings (SharedPreferences) as one JSON object: key to value (bool, int, double, string or list of strings), minus the keys listed under "Not included". |
| `keyrings.json` | KNX Secure keyrings, one per installation: a JSON object from `knx_keyring:<installation id>` to a JSON **string** holding that installation's stored keyring (see below). |

Important files under `files/`:

| Path | Content |
|---|---|
| `installations.json` | List of installations |
| `installations/<id>/catalog.json` | The project (group addresses, devices, datapoint types) |
| `installations/<id>/history/YYYY-MM-DD.ndjson` | Recorded telegrams, one JSON object per line |

The stored keyring (value inside `keyrings.json`) is the decrypted part of an ETS
keyring that the app needs, as written by `KeyringStore.import`
(`lib/knx/secure/keyring_store.dart`):

```json
{
  "project": "<ETS project name>",
  "groupKeys": {"<group address as 16-bit integer>": "<Base64 AES-128 key>"},
  "sequence": {"<individual address as 16-bit integer>": 0},
  "tunnels": [{"address": 4353, "host": 4352, "userId": 2, "password": "<tunnel password>"}],
  "deviceAuthentication": {"<individual address>": "<device authentication code>"}
}
```

## Not included

- The app lock: its state, password hash and recovery code (keys `app_lock_*`).
- Device identifiers and other settings that belong to one device, and the
  consent to share a keyring with a particular Busclear Box (`box_keyring_*`).
- The backup reminder's own timestamps (`backup_*`): a restored file is not a new
  backup on this device.
- Files the app has set aside because it could not decrypt them (folder
  `nicht-lesbar/`), the plugin settings file `shared_preferences.json`, and
  temporary and previous-version files (`*.tmp`, `*.prev`).
- History recorded on a Busclear Box or by the Home Assistant add-on: it stays there
  and goes into the [box backup](#box-backup).

The exact rule for settings keys is `FullBackup.keepsOut`; the same rule applies
on restore, so a file cannot set any of these keys.

## Restore

`FullBackup.restore` decrypts and unpacks the whole file in a background isolate
before it writes anything. It rejects the file, without changing anything, if:

- `format` is not `knx-monitor-backup`, or `version` is higher than 1,
- `kdf.iterations` is below 1,000 or above 2,000,000 (a foreign file can neither
  force a weak derivation nor keep the device busy),
- the password is wrong or the file was modified (GCM tag),
- the ZIP declares more than 512 MiB in total or for one entry, or more than
  200,000 entries (checked from the central directory before extraction),
- any path under `files/` is not a plain relative path: absolute, with a drive
  letter, a backslash, a NUL byte, an empty, `.` or `..` segment, or pointing at
  `shared_preferences.json` or `nicht-lesbar/`.

The app uses its own constant `knx-monitor-backup/1` as additional data and does
not read `cipher.aad`, `kdf.name` or `cipher.name` from the file.

Then it writes each file (a file with the same path is replaced, its previous
version normally kept as `<file>.prev`, except for files above 16 MiB; other
files stay), sets the settings from
`prefs.json`, and writes keyrings whose key starts with `knx_keyring:` into the
system keychain. The app restarts afterwards, because its stores keep the old
state in memory.

When creating a backup the app refuses if the data would exceed 256 MiB
(`FullBackup.maxBytes`), since the file is built in memory.

## Handling

The decrypted ZIP holds the project, the recordings and the KNX Secure keys in
plain text. Treat it like the ETS keyring itself and delete it when you are done.

# Box backup

The box backup holds everything a Busclear Box, the Docker container or the Home
Assistant add-on keeps in its data folder that is needed to set the box up again:
all installations with their history, project, settings, watchers, inspection log
(emergency lighting), home plan and bus view files. It is the way back after a
broken SD card, and the way to move to a new box or from the add-on to a box.

Implementation: `ha-addon/knx_monitor/server/lib/src/box_backup.dart`
(`writeBoxBackup`, `unpackBoxBackup`, `sealSecrets`, `openSecrets`,
`BoxBackupService`), the zip writer in `zip_stream.dart`. App:
`lib/ui/box_backup_screen.dart` (box settings → Box backup). Tests:
`ha-addon/knx_monitor/server/test/box_backup_test.dart`,
`test/box_backup_screen_test.dart`, `test/box_backup_download_test.dart`.

## Where to get it

- **App** (box settings, admin only): *Create backup* downloads it streamed to
  a temporary file and then hands it on, on iPhone, iPad and Android through the
  share sheet ("Save to Files", a cloud drive), on macOS, Windows and Linux into
  a folder the user picks. *Choose backup …* restores one (below).
- **Browser:** the page `/pair` of the box or the container has a *Backup*
  section with a download button (`POST /api/backup/form`). Restoring is in the
  app or through the API, because it asks back before it replaces anything.
- **Home Assistant add-on:** Home Assistant's own backups already contain the
  add-on's data folder (including the keyring, encrypted if the Home Assistant
  backup is). The API below works through Ingress too, for moving from the
  add-on to a box; the add-on's web app has no button for it, and restoring
  into the add-on needs the option `read_only` switched off.

## File

A plain zip (deflate, no Zip64), default name
`busclear-box-sicherung-YYYY-MM-DD-HHMM.zip`. It is written while it is sent:
the server never holds it in memory, and history days the recorder has already
packed (`*.ndjson.gz`) go in as they are, in stored deflate blocks. Without
Zip64 the archive and every entry stay below 4 GiB; a larger backup breaks off
with an error instead of producing a damaged file. With the default retention
(7 days, at most 1000 MB) a backup stays far below that.

| Path | Content |
|---|---|
| `manifest.json` | First entry, see below. |
| `installations.json` | `{"version": 1, "active": "<id>", "list": [{"id", "name", "created", "key"}]}`, the directory of installations without the box's own key. |
| `installations/<id>/<path>` | The files of each installation, with the path relative to its folder. |
| `secrets.json` | Only with a password, always the last entry: the encrypted part, see below. |

`manifest.json`:

```json
{
  "format": "busclear-box-backup",
  "version": 1,
  "created": "2026-11-11T10:11:17.912Z",
  "server": "<server version>",
  "box": {"name": "Busclear Box", "lanAccess": false},
  "active": "default",
  "installations": [{"id": "default", "name": "Musterhaus", "key": "<installation key>", "files": 42, "bytes": 1234567}],
  "secrets": true,
  "withheld": ["keyring", "ipSecure", "dataExport", "report"]
}
```

`box` is informative; nothing is restored from it. `withheld` appears in a
backup made without a password and names what it leaves out.

What goes under `installations/<id>/` is decided by one rule for writing and
restoring (`backupCarries`): the first path segment is a file or folder the app
stores (the allowlist `knownAppFiles` in `files.dart`) or one the server writes
for the installation (`server.json`, `history`, `status`, `reports`,
`cycle_watch.json`), not company data (`team`, `team_*`, `cloud_sync`, left out like in the
app's full backup), every segment is a plain name (`A–Z a–z 0–9 . _ -`, not
starting with a dot), at most 8 levels, and it is neither secret nor a
temporary or set-aside copy (`*.tmp`, `*.bak`, `*.prev`, `*.corrupt-*`).
`server.json` goes in without the IP Secure passwords (`secure.userPassword`,
`secure.deviceAuthentication`).

## Encrypted part (`secrets.json`)

The secrets go in only encrypted, with a password the user chooses when backing
up (at least 12 characters), the same construction as the app's `.knxbackup`. It is the
last entry, because it also authenticates everything before it:

```json
{
  "format": "busclear-box-secrets",
  "version": 1,
  "kdf": {"name": "PBKDF2-HMAC-SHA256", "iterations": 600000, "salt": "<Base64, 16 bytes>"},
  "cipher": {"name": "AES-256-GCM", "nonce": "<Base64, 12 bytes>", "aad": "busclear-box-secrets/1"},
  "data": "<Base64: ciphertext, the last 16 bytes are the GCM tag>"
}
```

Key derivation: PBKDF2-HMAC-SHA256 over the password as UTF-8, as typed. The
server derives in a background isolate; on a Raspberry Pi 4 the 600,000 rounds take about
10 seconds (measured), on a Mac about 1.5; only one derivation runs at a time (another request
gets 429). Hashing the entries adds about a second per 20 MB of history on the Pi. For a prepared download
the server keeps the derived key in memory for at most 10 minutes, not the password. Decrypted,
`data` is JSON:

```json
{"installations": {"<id>": {
  "secure_keys.json": {"groupKeys": {}, "sequence": {}},
  "secure_sequence.json": {"4353": 50},
  "server.secure": {"userId": 2, "userPassword": "…", "deviceAuthentication": "…"},
  "export.json": {},
  "report_settings.json": {}
}},
 "integrity": [["manifest.json", 812, 3735928559, "<SHA-256 hex>"],
               ["installations/default/history/2026-11-01.ndjson.gz", 40211, 305419896, "<SHA-256 hex>"]]}
```

`integrity` lists every entry before `secrets.json` with its uncompressed size, CRC-32 and
SHA-256 of the content. (Files written by a development build before 11 Nov 2026 carry `null`
instead of a SHA-256 for history and status files; those are still accepted with size and CRC-32.)
On restore with the password the plain part must match it exactly: the same entries,
sizes and checksums. Otherwise the file is refused (`tampered`): nobody can change `server.json`
(say, the gateway address) and carry over the original `secrets.json`, so that the box hands its
IP Secure passwords to another host. History and status files are bound the same way, by their
SHA-256; only where an older file lists `null` for one, it is bound by name, size and CRC-32,
which catches damage and swapped files, not a deliberate forgery.

| Key | Content |
|---|---|
| `secure_keys.json` | The installation's KNX Secure keyring as the server stores it (group keys, sequence numbers, tunnel credentials). |
| `secure_sequence.json` | The Data Secure sequence numbers the box has seen. Only here, so a foreign file cannot raise them and make every real telegram look like a replay. |
| `server.secure` | The `secure` part of `server.json` with the IP Secure passwords. |
| `export.json` | Data export settings with their tokens (InfluxDB). |
| `report_settings.json` | Notification settings with their credentials. |

Without a password none of this is in the file. In Python, with the
[`cryptography`](https://cryptography.io/) package:

```python
import base64, getpass, hashlib, json, zipfile
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

j = json.loads(zipfile.ZipFile("busclear-box-sicherung.zip").read("secrets.json"))
b64 = base64.b64decode
key = hashlib.pbkdf2_hmac("sha256", getpass.getpass("Backup password: ").encode("utf-8"),
                          b64(j["kdf"]["salt"]), j["kdf"]["iterations"], 32)
print(json.loads(AESGCM(key).decrypt(b64(j["cipher"]["nonce"]), b64(j["data"]),
                                     j["cipher"]["aad"].encode("utf-8"))))
```

## Never in the box backup

| Left out | Why |
|---|---|
| `access.json`: box password (PBKDF2 hash), paired devices (token hashes), sessions | A stolen backup must not open the box. With the hash the password could be guessed offline; with the device list a restored copy would let in devices of the old box. After restoring, the box keeps its own password and devices; pair the app again if the box is a new one. |
| TLS key and certificate (`/etc/knx-box-tls/`) | They identify this box; a new box makes its own, the app pairs with its fingerprint. |
| `ha_integration.json`, `mcp.json` | Tokens of the Busclear integration and the MCP server: set up again on the new box. |
| `lan-access`, Wi-Fi, box name, request files | Settings of the box itself (`knx-box.txt`, the box settings). `box.lanAccess` in the manifest only says how it was. |
| Crash records (`restarts.ndjson`, `last-error.txt`, `last-exit.json`, `running.json`) | They belong to the old hardware. |
| `restore-staging/`, `restore-previous/` | Earlier states can be downloaded on their own (below). |
| The box key (`box` in `installations.json`) | The restored box keeps its own: the app tells boxes apart by it. The installations keep their keys. |

The history itself is in the file in plain text, as it is on the box (KNX Data
Secure telegrams decrypted if the keyring was on the box). Keep the file like
the ETS project.

## Restore

Restoring takes two steps, so nothing changes before the user has seen what the
file contains and confirmed it:

1. `PUT /api/backup/restore` with the zip as body. The server streams it to
   `restore-staging/upload.zip`, unpacks it into `restore-staging/tree/` and
   checks it (below); the answer is a summary (`stage`, `created`, `box.name`,
   `installations`, `secrets`, `withheld`, `files`, `bytes`). Nothing else on
   the box is touched.
2. `POST /api/backup/restore/apply` with `{stage, password?, withoutSecrets?,
   current}`. The server
   - refuses in read-only mode (409, `readOnly`),
   - on the box and in Docker checks `current`, the current box password. A wrong one counts
     as a failed attempt per sender and per paired device: from the fifth, both wait (30 s,
     doubling up to 15 min) and get 429, also an admin token, which the login lockout lets
     through. The same applies to changing the password and locking out all devices,
   - opens `secrets.json` with `password` (wrong: 422 `backupPassword`, nothing
     changes, the upload stays for another try), then checks the plain part against the
     integrity list (`tampered`). A backup with secrets and no
     password is restored only with `withoutSecrets: true` (otherwise 422
     `passwordMissing`): everything else comes back, the keys do not, and the
     app says to read the keyring from the ETS again and to enter the IP Secure
     passwords again,
   - holds off any other upload, discard or download from the first check on (409),
   - stops the bus connection, writes the journal `restore-swap.json`, moves `installations/` and `installations.json`
     to `restore-previous/<YYYYMMDD-HHMMSS>/`, moves the unpacked tree into place,
     writes the new `installations.json` with the box's own key, writes the
     secrets, removes the journal and starts the bus of the restored active installation. If a
     step fails, the previous state is moved back. If the box goes down meanwhile (power cut),
     the next start finds the journal and moves the previous state back before anything opens
     the installations. While the folders move, `/api/files/` and `/api/installations` answer
     503.
   - KNX Data Secure sequence numbers only rise: for each installation the highest of the
     restored numbers (from the encrypted part only), the previous state's
     `secure_sequence.json` and the `sequence` in its keyring is kept, the previous
     installation found by id or installation key; so a restored older state does not let
     replayed telegrams through. Without a matching previous installation the log says so.

The restored `server.json` brings its retention settings: days older than the
retention are removed by the recorder's next maintenance, as on the old box.
Open views lose their connection and reconnect.

Checks when unpacking (`unpackBoxBackup`), all before anything is moved:

| Check | Reason |
|---|---|
| Only the box's admin (box password, a device paired with it, Ingress in the add-on); devices without admin rights and viewers get 403 on every `/api/backup` path | Backup and restore are the whole box. |
| Central directory at most 24 MiB and 512 bytes per entry, read only then | A crafted end record cannot make the Pi read a gigabyte into memory. |
| Valid end record and central directory, no multi-part archive, no Zip64, no encrypted entries, methods stored or deflate only, local header equal to the central one | Foreign or damaged files. |
| Only `manifest.json`, `installations.json`, `secrets.json` and `installations/<id>/<path>` with `backupCarries(path)`; `<id>` from `installations.json` | Path traversal (ZIP slip), overwriting the server's own files (`access.json`, `installations.json.bak`), injecting a plain `secure_keys.json` or `export.json`. |
| No name twice, also not in other case | Case-insensitive data folders (Docker Desktop, NAS shares). |
| At most 65,535 entries, 4 GiB per entry and in total, 4 MiB per JSON entry, checked from the central directory; while unpacking, more data than declared or a wrong CRC stops it | Zip bombs: deflate is unpacked in steps of 16 KiB and cut off at the declared size. |
| Declared size plus 256 MiB must be free (and twice the upload while receiving it) | The recorder needs its space, a full disk would stop the recording. |
| `manifest.json` with `format` `busclear-box-backup` and `version` at most 1; at least one valid installation | No partial import of an unknown or newer format. |
| `secrets.json`: format, version, rounds between 100,000 and 2,000,000, Base64; after decrypting only known kinds for installations in the backup | A crafted file can neither force a weak derivation nor keep the Pi busy, nor write other files. |
| JSON read defensively: ids `[A-Za-z0-9_-]{1,64}`, unknown or broken entries skipped, `server.json` only as an object | No exceptions from a foreign file, no paths from ids. |

## Earlier states

Every restore leaves the previous state under `restore-previous/<name>/`, with
the same layout as the data folder. `GET /api/backup` lists them (`previous`);
`POST /api/backup {"previous": "<name>"}` downloads one as a box backup (with a
password, its secrets too); `DELETE /api/backup/previous/<name>` deletes it.
They are not removed automatically: on an SD card they take as much space as the
state did.

## API

| Request | Answer |
|---|---|
| `GET /api/backup` | `{readOnly, needsCurrent, minPassword, busy, staged, previous}` |
| `POST /api/backup` `{password?, previous?}` | `{ticket, fileName, secrets, withheld, bytes}`; with a password the key is derived now, `bytes` estimates the size. |
| `GET /api/backup/download?ticket=…` | The zip. A ticket holds for 10 minutes and one download; `check=1` only checks it. One download at a time (429). |
| `POST /api/backup/form` (form fields `password`, `password2`) | The zip straight away (the page `/pair`). |
| `PUT /api/backup/restore` | Summary of the uploaded backup. |
| `POST /api/backup/restore/apply` `{stage, password?, withoutSecrets?, current?}` | `{installations, files, secrets, secretsSkipped, previous, active}` |
| `DELETE /api/backup/restore` | Discards the upload. |
| `DELETE /api/backup/previous/<name>` | Deletes an earlier state. |

Errors come as `{"error": "<German text>", "problem": "<reason>"}` with the
reasons `readOnly`, `passwordShort`, `passwordMissing`, `backupPassword`,
`tampered`, `tooMany`, `invalid`, `newer`, `tooLarge`, `space`, `stage`, `busy`, `ticket`.
The form on `/pair` instead goes back to the page with a notice (`/pair?backup=<reason>`).

The app names the downloaded file itself (`busclear-box-sicherung-<box>-<date>.zip`); it never
takes a name from the box's answer, which could point anywhere on the device. A cancelled or
broken download is deleted, and so is the temporary copy once it was handed on. Over plain
HTTP outside the box Wi-Fi the app asks before passwords or keys go through the network.

With `curl` against a box or a container (`-u :PASSWORD` is the box password):

```bash
# Back up, with the keys
T=$(curl -su :PASSWORD -H 'Content-Type: application/json' \
  -d '{"password":"a long backup password"}' http://box/api/backup | jq -r .ticket)
curl -su :PASSWORD -o busclear-box.zip "http://box/api/backup/download?ticket=$T"

# Restore: upload, read the summary, then confirm
S=$(curl -su :PASSWORD -T busclear-box.zip http://box/api/backup/restore | jq -r .stage)
curl -su :PASSWORD -H 'Content-Type: application/json' \
  -d "{\"stage\":\"$S\",\"password\":\"a long backup password\",\"current\":\"PASSWORD\"}" \
  http://box/api/backup/restore/apply
```

## Scheduled backup to a USB stick: not built

A timed backup onto a USB stick or the SSD was considered and left out for now:
with an SSD the data folder already lives on it (a copy on the same drive does not
survive its failure), a stick would need mounting by root with file systems the
server user may write to and a rotation, and a stick left in the box is lost
together with it (theft, fire, a power supply that kills both). A copy on another
device, made from the app, covers the SD card failure the backup is for.
