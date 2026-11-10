# Working with the XKNX Editor

The [XKNX Editor](https://github.com/XKNX/xknx-editor) is an open KNX project
editor: it opens `.knxproj` files, edits parameters, flags and links, and
programs devices, without ETS. Busclear watches the bus and finds what is
wrong. Together: Busclear finds, the editor fixes.

## Importing an editor project (.xknx)

Busclear opens `.xknx` files like a `.knxproj` (project import in the app,
add-on and box). The result is the same group address catalog: group
addresses with ranges and datapoint types, devices with product, manufacturer,
room and serial number, tunnels of IP interfaces, and the links between
communication objects and group addresses with their flags.

How it works:

- A `.xknx` file is an SQLite database (the editor's schema, `user_version` 5).
  Busclear reads it with a small read-only SQLite reader in plain Dart
  (`lib/knx/sqlite_reader.dart`), so the import works the same in the browser,
  on phones and on the desktop without a native library. It supports rowid
  tables, overflow pages and the UTF-8 encoding; it does not write and needs
  no write-ahead log (the editor saves the file in rollback-journal mode).
- Tables read: `projects`, `areas`, `lines`, `segments`, `devices`,
  `device_additional_addresses`, `spaces`, `group_ranges`, `group_addresses`,
  `com_objects`, `com_object_links` (`lib/knx/xknx_parser.dart`).
- Flags: the project's override (`*_flag_override`) before the application's
  value (`*_flag`). An object sends to its sending address (`is_sending`) only
  with C and T and unless it is an input that accepts values (W and U), as for
  `.knxproj`.
- Object numbers are taken from the reference (`…_O-12_R-9`); objects of
  modules keep no number, since it is only in the application.
- Each link keeps the object reference (`GroupLink.ref`, e.g.
  `M-0083_A-0056-11-A826_O-236_R-62`), which the editor uses to identify an
  object. The `.knxproj` import builds the same reference from application and
  instance.

### Password

The editor encrypts only the KNX Secure keys of a project with the project
password (PBKDF2-SHA256 with the stored salt and iteration count, then
AES-256-GCM). Busclear imports no keys, but it still asks for the password of a
protected project and checks it against the stored check value
(`projects.password_check`), as the editor does. In the browser the key is
derived with Web Crypto.

### Never programmed

The editor and ETS store when a device was last downloaded. A device without
a download, in a project that records downloads at all, is listed in the
project check under "Devices never programmed": not commissioned yet, or not
installed. Older catalogs without this information show nothing.

### Download pending

ETS and the editor track per device which parts of the last download are
still loaded: individual address, application, parameters, group
communication, medium (the "Adr Prg Par Grp Cfg" columns in ETS). A part
changed in the project since then is not loaded any more. The project check
lists such devices under "Download pending" with the parts concerned. ETS
writes `…Loaded="true"` for loaded parts; the editor keeps the columns
`*_loaded` in `devices`.

## Taking the project from Home Assistant

In the add-on, the project tile offers **From Home Assistant**: the project of
Home Assistant's KNX integration, which the XKNX Editor can send there
("Use Project in Home Assistant") or which was uploaded in the KNX panel.

- The add-on server asks Home Assistant through the Supervisor
  (`homeassistant_api`, Core WebSocket API) for `knx/get_knx_project` (the
  project parsed by xknxproject), `knx/get_entities_by_group` and
  `knx/get_expose_groups` (group addresses Home Assistant writes to; older
  Home Assistant versions without these commands simply give none). The app
  gets the answer from `GET /api/knx-project` (admin only;
  `ha-addon/knx_monitor/server/lib/src/ha_knx_project.dart`).
- The app turns it into the catalog (`lib/knx/ha_knx_project_parser.dart`):
  the same fields as from `.knxproj`, the object reference from the object's
  id (`1.1.5/M-0083_…_O-0_R-1`), download state where xknxproject provides
  it.
- The group addresses Home Assistant writes to become
  `GroupCatalog.externalSenders`: the project check no longer lists them as
  "without sender", as the editor does with external senders.

## Handing findings over to the editor

The project check has a button "Hand over to XKNX Editor"
(`lib/ui/xknx_editor_sheet.dart`). It builds the same tasks as "Tasks for
ETS" (`EtsTasks`) and turns them into a handover
(`lib/model/xknx_editor_handover.dart`):

- **Corrections** the editor can apply on its own, as operations of its
  `project_batch` tool, addressed by printed group address and individual
  address: datapoint types set in the app (`set_group_address_dpt`, only with
  a subtype), corrected and learned names (`rename_group_address`), learned
  addresses (`create_group_address`), the C flag of an associated object, and
  the R flag of the object that sends a status nobody can read
  (`set_com_object_flag`, by object reference). With the add-on or box, datapoint types
  suggested from the recorded history with high certainty are added for
  addresses still without a type; likely ones become notes. Only unambiguous changes: an R
  flag on every listener would produce several answers.
- **Notes** for everything that needs a decision in the project: each becomes
  a comment line starting with `[Busclear]` on its group address or device,
  in the app's language, worded as in the PDF. Notices that are often
  intended (several senders, no sender, main groups 14/15, filter
  observations) stay in Busclear. Devices never programmed or with a pending
  download get a note as well.

Two ways to hand over:

- **Directly** (not in the browser, which cannot reach the editor on the
  user's computer): `lib/platform/xknx_editor_client.dart` talks to the
  editor's MCP server (Streamable HTTP, JSON-RPC; default
  `http://127.0.0.1:8766/mcp`, optional bearer token, both under Settings ›
  AI/MCP in the editor; Busclear keeps the address in its preferences and the
  token in the keychain). It checks which project is open and asks when the
  name differs, runs the corrections as a dry run and then for real, and
  writes the notes in one batch. It keeps the user's own comment text and
  replaces earlier `[Busclear]` lines. A line `[Busclear-Index]` in the
  project comment lists the annotated elements, so the next handover also
  clears notes that no longer apply. Nothing is programmed; the editor
  records each change in its history.
- **As a file** (`busclear-xknx-editor`, JSON): the same operations and notes
  for an AI assistant connected to the editor, or for later.

## Comparing a device with the project

In the diagnostics, "Compare with project (XKNX Editor)" next to the device
info runs the editor's download preview (`connection_evaluate_device`): the
editor reads the device over its own bus connection, writes nothing and
reports how many configuration bytes a download would change. 0 means the
device carries the project; anything else means device and project differ,
for example after a change in ETS that was never downloaded.

## Comparing all devices

In "Hand over to XKNX Editor", "Compare all devices" runs the download
preview for every device of the editor's project, one after the other, and
lists the devices that differ from the project or did not answer. It writes
nothing, but it reads each device over the bus and takes up to a few minutes
per device, so it is meant for the evening or the night. It can be stopped
after the current device. The add-on cannot do this on its own: the editor
runs on the user's computer, out of the add-on's reach.

## Tests

`test/xknx_parser_test.dart` runs on synthetic projects built by
`tool/xknx_fixture.py` (`test/fixtures/xknx/`), one of them password-protected.
The reader was also compared cell by cell with Python's `sqlite3` on a real
60-device project.
