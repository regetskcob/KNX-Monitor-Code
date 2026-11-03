# Backup file format (`.knxbackup`)

So that you can get at your data without our app too. Applies to backups created
by the KNX Monitor apps from version 1.9.1.

The file is JSON:

```json
{
  "format": "knx-monitor-backup",
  "version": 1,
  "kdf": {"name": "PBKDF2-HMAC-SHA256", "iterations": 600000, "salt": "<Base64>"},
  "cipher": {"name": "AES-256-GCM", "nonce": "<Base64>", "aad": "knx-monitor-backup/1"},
  "data": "<Base64: ciphertext, the last 16 bytes are the tag>"
}
```

Key: PBKDF2 over the password as UTF-8, 32 bytes. Decrypted, `data` is a ZIP:

| Path | Content |
|---|---|
| `manifest.json` | Format, version, number of files |
| `files/…` | All app files in plain text: JSON and NDJSON, paths as in the app directory |
| `prefs.json` | Settings without lock and device ID |
| `keyrings.json` | KNX Secure keyrings per installation (key `knx_keyring:<id>`) |

Important files: `installations.json` (list of installations),
`installations/<id>/catalog.json` (project), `installations/<id>/history/YYYY-MM-DD.ndjson`
(one telegram per line).

Not included: app lock and the history on a KNX Box.

The decrypted ZIP holds your keys and project in plain text, so treat it like the
keyring itself.
