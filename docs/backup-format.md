# Backup file format (`.knxbackup`)

A full backup holds everything the KNX Monitor app keeps on one device, encrypted
with a password the user chooses. The format is documented so that the data stays
readable without the app. It applies to backups created by the native apps
(iOS, iPadOS, Android, macOS, Windows, Linux) from version 1.9.1 on. The web app
of the Home Assistant add-on and of the KNX Box has no full backup; its data
lives in the server's data folder.

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
  consent to share a keyring with a particular KNX Box (`box_keyring_*`).
- The backup reminder's own timestamps (`backup_*`): a restored file is not a new
  backup on this device.
- Files the app has set aside because it could not decrypt them (folder
  `nicht-lesbar/`), the plugin settings file `shared_preferences.json`, and
  temporary and previous-version files (`*.tmp`, `*.prev`).
- History recorded on a KNX Box or by the Home Assistant add-on: it stays there.

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
