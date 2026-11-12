# Handover package, fault report and customer files (`.knxhandover`, `.knxreport`, `.knxcustomers`)

Three files travel between people and devices without a server in between:

| File | From | To | Protected |
|---|---|---|---|
| `.knxhandover`, handover package | electrician | home owner | optional, mandatory with KNX Secure keys |
| `.knxreport`, fault report | home owner | electrician | no (it holds no keys) |
| `.knxcustomers`, customer files | electrician's device | electrician's second device | always |

The formats are documented so that the data stays readable without the app and
so that other tools can produce or check such files. Everything on this page
is format version 1.

Implementation: `lib/export/handover_package.dart` (`HandoverPackage`,
`FaultReport`, limits), `lib/export/customer_file.dart` (`CustomerFile`),
`lib/model/handover.dart` (building, opening, matching to an installation),
`lib/model/customer_transfer.dart` (customer files: building, merging), crypto
primitives in `lib/knx/secure/package_crypto.dart`, ZIP limits in
`lib/platform/safe_zip.dart`. Tests: `test/handover_test.dart`,
`test/handover_followup_test.dart`, `test/customer_transfer_test.dart`,
`test/handover_format_doc_test.dart` (every field the code writes is named on
this page).

## Handover package (`.knxhandover`)

A ZIP archive with two entries:

| Entry | Content |
|---|---|
| `handover.json` | the head: readable without a password, enough for the question "Open?" |
| `payload.json` | the content as UTF-8 JSON, in a package without a password |
| `payload.enc` | the content encrypted, in a package with a password (instead of `payload.json`) |

### Head (`handover.json`)

```json
{
  "format": "knx-monitor-handover",
  "version": 1,
  "id": "k3x9a1f0c2",
  "created": "2026-11-10T14:03:12.482",
  "installation": "Haus Muster",
  "contact": {"name": "Elektro Muster", "phone": "0123 456", "email": "info@example.com"},
  "encrypted": true,
  "hasKeys": true,
  "contents": {"groups": 412, "devices": 57},
  "kdf": {"name": "PBKDF2-HMAC-SHA256", "iterations": 210000, "salt": "<Base64>"},
  "cipher": {"name": "AES-256-GCM", "nonce": "<Base64>"}
}
```

| Field | Meaning |
|---|---|
| `format` | Always `knx-monitor-handover`. Anything else is not a handover package. |
| `version` | Format version, currently `1`. A higher one is refused with "from a newer version". |
| `id` | Identifier of this one package (not of the installation). Opening the same package again is recognised by it. |
| `created` | Local time of creation, ISO 8601 without zone. |
| `installation` | Name of the installation at the electrician's. |
| `contact` | The electrician's company as the customer sees it: `name`, and if set `address`, `phone`, `email`, `website`. Each text is cut to 400 characters when read. |
| `encrypted` | `true` if the content is in `payload.enc`. |
| `hasKeys` | `true` if the content has a `keyring`. Only possible together with `encrypted`. |
| `contents` | Counts for the question before opening: `groups` (group addresses), `devices`. |
| `kdf` | Only when encrypted. `name` is always `PBKDF2-HMAC-SHA256`; `iterations` (the app writes 210,000 and accepts 1 to 5,000,000); `salt`: 16 random bytes, standard Base64. |
| `cipher` | Only when encrypted. `name` is always `AES-256-GCM`; `nonce`: 12 random bytes, standard Base64. |

The head names no customer and nothing about the bus besides the two counts.

### Content (`payload.json`, or inside `payload.enc`)

```json
{
  "origin": "3f2a9c01be77",
  "key": "0b6a1c1e-7d0e-4f6e-9a55-3f2a9c01be77",
  "catalog": {"v": 1, "project": "Haus Muster", "groups": [], "devices": [], "manufacturers": {}},
  "overrides": {"2049": [1, 2]},
  "projectNames": {"2049": "Licht Kueche"},
  "gateway": {"host": "192.168.1.22", "port": 3671, "name": "GIRA X1"},
  "connection": {"mode": "secure", "tunnelAddress": 4593, "routingAddress": 254, "secureUserId": 3},
  "keyring": {"project": "Haus Muster", "groupKeys": {}, "sequence": {}, "tunnels": [], "deviceAuthentication": {}}
}
```

| Field | Meaning |
|---|---|
| `origin` | Id of the installation on the electrician's device. A fault report carries it back. Local to that device; `default` on a box or add-on. |
| `key` | Installation key, a UUID ([keys.md](keys.md)). Optional: missing in packages from before keys existed and when the sender only holds a placeholder. Anything that is not a UUID is ignored. |
| `catalog` | Names and structure of the project, see below. |
| `overrides` | Datapoint types the electrician chose by hand: group address (16-bit number as text) to `[main, sub]`; `sub` may be `null`. |
| `projectNames` | Optional. For addresses whose name was corrected in the app: the project's own name. `catalog` holds the corrected one, so older apps show it too. |
| `gateway` | Optional. Last used KNX/IP interface: `host`, `port` (default 3671), and what the device reveals about itself when the installation knows it: `name`, `serial` and `mac` (they identify the interface after its IP address changed). |
| `connection` | `mode` (`udp`, `tcp`, `routing`, `secure` and the other connection types of the app; unknown ones fall back to `udp`), `tunnelAddress` (optional, individual address as a number), `routingAddress`, `secureUserId`. No passwords. |
| `keyring` | Optional, only in an encrypted package. KNX Secure keys as the app stores them: `project`, `groupKeys` (group address to 16-byte key, Base64), `sequence` (individual address to last sequence number), `tunnels` (list of `address`, `host`, `userId`, `password`), `deviceAuthentication` (individual address to code). |

`catalog` is the app's project catalog (`GroupCatalog.toJson`), reduced for the
customer (`handoverCatalog`):

| Field | Meaning |
|---|---|
| `v` | Catalog version, `1`. |
| `project` | Project name. |
| `style` | Optional: `twoLevel` or `free` when the project does not use three-level group addresses. |
| `groups` | List of group addresses: `a` address (16-bit number), `n` name, `p` path of the group ranges, `d` datapoint type `[main, sub]` (optional), `ds` description (always `null` here), `l` links to devices (optional). |
| `l` (in a group) | List of `d` device (individual address as a number), `o` object number, `t` object text, `s` `true` if the object sends, `f` flags as letters out of `CRWTU`, `r` reference of the object in the project. |
| `devices` | List of devices: `a` individual address, `n` name, `p` product, `m` manufacturer, `l` location in the building, `ds` description (always `null` here), `tu` address of the device a tunnel belongs to, `np` never programmed, `pd` parts with a pending download, `rf` radio device. A serial number would be `sn`; a handover package never has it. |
| `manufacturers` | KNX manufacturer id (as text) to name. |
| `xs` | Optional: individual addresses that send from outside the project. |

### Encryption

Only `payload.enc` is encrypted; the head stays readable and is authenticated.

1. Password: the app generates it (24 characters out of
   `3467ABCDEFGHJKMNPQRTUVWXY89`, grouped by hyphens, a good 110 bits) and shows
   it as text and QR code. Before use it is normalised: upper case, spaces and
   hyphens removed. Its characters (all ASCII) are then taken as bytes.
2. Key: PBKDF2-HMAC-SHA256 over the normalised password with `kdf.salt` and
   `kdf.iterations`, 32 bytes.
3. Plain text: the content JSON (UTF-8), gzip-compressed.
4. Cipher: AES-256-GCM with `cipher.nonce`. The additional authenticated data
   is the entry `handover.json` byte for byte as it is in the ZIP. `payload.enc`
   is the ciphertext followed by the 16-byte tag.

Because the head is authenticated, a changed company name or counter makes the
package fail to open. A wrong password and a modified file cannot be told
apart and give the same message.

Opening a protected package without the app, in Python with the
[`cryptography`](https://cryptography.io/) package:

```python
import base64, getpass, gzip, hashlib, json, re, zipfile
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

with zipfile.ZipFile("Haus-Muster.knxhandover") as z:
    head = z.read("handover.json")          # exactly these bytes are the AAD
    sealed = z.read("payload.enc")          # ciphertext + 16-byte tag
j = json.loads(head)
password = re.sub(r"[\s-]", "", getpass.getpass("Package password: ").upper())
b64 = base64.b64decode
key = hashlib.pbkdf2_hmac("sha256", password.encode("latin-1"),
                          b64(j["kdf"]["salt"]), j["kdf"]["iterations"], 32)
plain = AESGCM(key).decrypt(b64(j["cipher"]["nonce"]), sealed, head)
payload = json.loads(gzip.decompress(plain))
print(j["installation"], len(payload["catalog"]["groups"]), "group addresses")
```

The same code opens customer files: the head is `customers.json` there.
`decrypt` raises `InvalidTag` for a wrong password or a modified file.

### What is deliberately not inside

- **Customer data.** No customer name, address, phone number, notes, visits,
  protocols, service reports or photos: the customer file stays with the
  electrician. `test/handover_test.dart` and `test/customer_transfer_test.dart`
  guard that.
- **The ETS project.** Only names, structure, datapoint types and which device
  is linked to which address. No parameters, no application programs.
- **Serial numbers and descriptions of the devices in the project** (`sn`,
  `ds`): removed by `handoverCatalog`. The one serial number that may be
  inside is that of the KNX/IP interface in `gateway`.
- **Passwords of the app, the account, a box or the add-on.** `connection` has
  the tunnel's user id, never its password. The one exception is the `keyring`
  the electrician chooses to include: it holds the KNX Secure keys and with
  them the tunnel passwords and device authentication codes of the
  installation, which is why a package with keys cannot be created without a
  password.
- **Recordings, long-term history, charts, watchers, comments.** A package
  brings a project, it takes nothing of the recipient's.

### Opening, and a later package for the same installation

The app first reads the head and asks. With a password it then decrypts, and
only then decides where the package goes, because the installation key is part
of the content:

1. **The same package** (`id`) was opened here before: that installation.
2. **A later package for an installation that came by handover.** Both carry an
   installation key: the key decides and nothing else. If the package or the
   installation has none (made before keys existed, or by an add-on that only
   holds a placeholder), the company (`contact.name`, compared without case and
   surrounding spaces) must be the same and either `origin` (only an id that is
   unique beyond one device: 12 hex characters, not `default`) or the
   installation name of the earlier package.
3. **Otherwise** a new installation; a freshly installed app uses its still
   empty first one. The add-on and the box's web app hold one installation:
   the package goes there, and the question before opening says that the
   project is replaced.

An installation the user created themselves is never a target, so on the
electrician's own device a package cannot overwrite the installation it was
made from.

In cases 1 and 2 nothing is replaced silently. The app shows what changes
(group addresses and devices added, removed and renamed; whether keys are
replaced or removed) and that the recipient's own history, charts, watchers,
comments and recordings stay, and offers "Update this installation" or "Set up
as a new installation". Replaced are the project (with datapoint types and
name corrections), the keyring, the connection settings, name and gateway of
the installation. If a step fails, a new installation is removed again and an
updated one is put back as it was.

What the installation remembers about its origin is in `handover_origin.json`
in its folder: `handover` (package id), `origin`, `key`, `contact`, `created`
(milliseconds since 1970) and `installation` (the name in the package, so a
package without a key still matches after the customer renamed the
installation).

## Fault report (`.knxreport`)

A [diagnostics package](diagnostics-package.md) with one more entry,
`fault_report.json`. It is not encrypted: it contains no keys, telegrams with
Data Secure only as time and addresses, and the texts pass the same scrubbing
as a diagnostics package. Any tool that reads a diagnostics package reads a
fault report.

```json
{
  "format": "knx-monitor-fault-report",
  "version": 1,
  "id": "k3xb07d21a",
  "created": "2026-11-12T08:41:55.120",
  "origin": "3f2a9c01be77",
  "handover": "k3x9a1f0c2",
  "key": "0b6a1c1e-7d0e-4f6e-9a55-3f2a9c01be77",
  "installation": "Haus Muster"
}
```

| Field | Meaning |
|---|---|
| `format` | Always `knx-monitor-fault-report`. |
| `version` | Currently `1`; a higher one is refused. |
| `id` | Identifier of this report. Opening it twice adds it once. |
| `created` | Local time, ISO 8601. |
| `origin` | Id of the installation at the electrician's, from the handover package. |
| `handover` | `id` of the handover package the installation came with. |
| `key` | Installation key, optional. Finds the installation on a device where it has another id. |
| `installation` | Name of the installation at the customer's. |

At the electrician's the report becomes a recording with comments and
screenshots and an entry in the visit history of the installation with that
`key`, otherwise with the id `origin`; if neither is on the device the app
asks which installation it belongs to.

Not inside, besides what a diagnostics package leaves out: the keyring, the
customer file, and screenshots unless the sender switches them on.

## Customer files (`.knxcustomers`)

The electrician's own data about customers, for a second own device without a
cloud. It is created from the customer files in the app (Pro), for one
installation or for all, and it is never offered in a flow for the customer
and never part of a handover package, a fault report or a diagnostics package.

A ZIP archive with two entries, always encrypted:

| Entry | Content |
|---|---|
| `customers.json` | the head, readable |
| `payload.enc` | the content, encrypted exactly like the handover package (password normalisation, PBKDF2, gzip, AES-256-GCM, the head as authenticated data) |

### Head (`customers.json`)

```json
{
  "format": "knx-monitor-customer-file",
  "version": 1,
  "id": "k3xc55e1b9",
  "created": "2026-11-12T17:20:03.914",
  "company": "Elektro Muster",
  "contents": {"installations": 14, "visits": 96, "documents": 21, "photos": 0},
  "kdf": {"name": "PBKDF2-HMAC-SHA256", "iterations": 210000, "salt": "<Base64>"},
  "cipher": {"name": "AES-256-GCM", "nonce": "<Base64>"}
}
```

| Field | Meaning |
|---|---|
| `format` | Always `knx-monitor-customer-file`. |
| `version` | Currently `1`; a higher one is refused. |
| `id` | Identifier of this file. |
| `created` | Local time of creation, ISO 8601. |
| `company` | The sender's own company name, for the first line on the second device. |
| `contents` | Counts of what is inside: `installations`, `visits`, `documents` (protocols and service reports), `photos`. |
| `kdf`, `cipher` | As in the handover package; always present. |

The head names no customer and no installation.

### Content

```json
{
  "installations": [
    {
      "key": "0b6a1c1e-7d0e-4f6e-9a55-3f2a9c01be77",
      "name": "Haus Muster",
      "record": {"version": 1, "customer": "Familie Muster", "site": "Weg 1\n12345 Ort", "contact": "",
                 "phone": "0171 000", "email": "", "notes": "", "orderNumber": "K-1042",
                 "maintenanceMonths": 12, "maintenanceSince": 1794000000000},
      "visits": [{"id": "k3x9f0", "t": 1794300000000, "k": "manual", "x": "Taster getauscht", "m": 45}],
      "protocols": {"1794300100000.json": {}},
      "serviceReports": {"1794300200000.json": {}},
      "photos": [{"id": "k3xa10", "caption": "Verteiler", "at": "2026-11-10T13:02:11.000Z", "jpeg": "<Base64>"}]
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `installations` | One entry per installation. |
| `key` | Installation key ([keys.md](keys.md)). The second device finds the installation by it and by nothing else. Missing if the sender only holds a placeholder. |
| `name` | Name of the installation on the sending device, for the list before taking over. |
| `record` | The customer record as stored in `customer.json`: `version`, `customer`, `site` (address, multi-line), `contact`, `phone`, `email`, `notes`, `orderNumber`, `maintenanceMonths` and `maintenanceSince` (milliseconds since 1970), the last two optional. |
| `visits` | The visit history as stored in `visits.json`: `id`, `t` time (milliseconds since 1970), `k` kind (`connection`, `commissioning`, `acceptance`, `serviceReport`, `faultReport`, `faultReply`, `handover`, `report`, `manual`; an unknown kind is shown as `manual`), `x` text, `m` minutes, `r` id of a recording (the last three optional). |
| `protocols` | Optional. Acceptance protocols: file name (`<timestamp>.json`) to the document as the app stores it (`Acceptance.toJson`). The file name is the document's id. |
| `serviceReports` | Optional. Service reports in the same way (`ServiceReport.toJson`). |
| `photos` | Optional, only when the sender switches photos on. The photo documentation: `id`, `caption`, `at` (UTC, ISO 8601), `jpeg` (the image, Base64). |

Recordings and the screenshots of comments are not inside; a visit of the kind
`faultReport` keeps the id of its recording (`r`), which the second device may
not have.

### Taking over on the second device

After the password the app shows what the file would add, per installation,
and writes nothing before "Take over":

- **Matching** is by installation key only. A name can be the same for two
  customers, so it never decides. Entries whose installation is not on the
  device are listed; the user can have them created as empty installations
  (with the key and the name from the file) or bring the installation over
  first and open the file again.
- **Merging only adds.** A visit with an id the device knows stays as it is
  there and is not added twice; the same goes for a protocol or service report
  with the same file name and a photo with the same id. Opening the same file
  again changes nothing.
- **The record** is taken when the device has none. Where both have one and
  they differ, the app names the differing fields and asks per installation;
  without an answer the record of this device stays.
- Photos beyond the photo limit of an installation (300 MB) and data that is
  not a JPEG are skipped and counted in the result.

## Limits and errors

| Limit | Value |
|---|---|
| File size | 512 MiB; opened directly from another app (mail, file manager) 128 MiB |
| One ZIP entry, unpacked | 256 MiB, also for the content after decompression |
| ZIP as a whole | 1 GiB unpacked, 100,000 entries (`lib/platform/safe_zip.dart`) |
| PBKDF2 rounds accepted | 1 to 5,000,000 |
| Texts from a customer file | 20,000 characters per field |

Every file from outside is untrusted. The app answers with one of four
messages (`PackageProblem`) and changes nothing:

| Case | Message |
|---|---|
| Not a ZIP, head missing or not JSON, wrong `format`, required field missing, content missing or unreadable, unsupported `kdf` or `cipher` | damaged or not a Busclear file |
| `version` higher than the app knows | from a newer version |
| Password missing or wrong, head or content modified | wrong password |
| The ZIP unpacks to more than a limit | too large |

A file above 512 MiB is not unpacked at all and counts as damaged.

Ids and names from a file never become paths unchecked: a recording gets a new
id, document names must match `<letters, digits, _ or ->.json` (at most 40
characters before `.json`), photo ids `0-9a-z` (at most 32 characters).

## Compatibility

- **Readers ignore fields they do not know**, in head and content. New
  optional fields therefore need no new version; `key` and `projectNames` were
  added that way. A package without them opens as before.
- **`version` only rises when an older app would misread the file**, never for
  an addition. An app refuses a higher version than it knows and says so.
- **Version 1 files stay readable** by every later app.
- **The algorithms are named in the head** (`kdf.name`, `cipher.name`). Another
  name is refused, not guessed; the iteration count is taken from the file.
- **File names of the entries are fixed.** A reader looks for `handover.json`,
  `customers.json` or `fault_report.json` to tell the three files apart, in
  that order, and does not rely on the extension.

## Opening from outside

The apps register the three extensions (and the MIME types
`application/vnd.knx-monitor.handover`, `.report`, `.customers`) on iOS,
iPadOS, macOS and Android, so a file from mail, a messenger or a file manager
opens in the app. On Android customer files are read from `content://` only.
In the app the same files open under "Open package or report" and, for
customer files, in the menu of the customer files.
