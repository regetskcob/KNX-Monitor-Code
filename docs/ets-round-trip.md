# Changes from KNX Monitor back into the ETS project

What does it take for datapoint types, flags and links changed or found in
KNX Monitor to end up in the real ETS project? None of this has been tried in
ETS yet; the ETS test procedure is at the end.

## Summary

| What | In the app | Way back into ETS | State |
| --- | --- | --- | --- |
| **Datapoint type of a group address** | can be set ("Set datapoint type", `CatalogStore.overrides`) | **ETS group address import (XML)**, official, no signature | built (`lib/export/ets_ga_export.dart`), not yet tested in ETS |
| Names of unnamed addresses, new addresses | learned without a project (`CatalogStore.learned`) | same XML import | built, not yet tested in ETS |
| **Corrected names** (typos) | per address in the details sheet ("Correct name") or for all project names at once in the project check ("Find and replace in names"), `CatalogStore.names`; they travel with diagnostics and handover packages and to the box | same XML import | built, not yet tested in ETS |
| **Flags of an object** (C R W T U) | read and checked only (project check) | no official file import; only in ETS itself (by hand or via an ETS app) | task list ("Tasks for ETS") |
| **Links** object ↔ group address | read and checked only | as for flags | task list |
| Descriptions of group addresses | cannot be changed | would work with the same XML import | not built |

Approach:

1. Return datapoint types and learned names via the XML import. It is small
   and official.
2. For flags and links, generate a **task list for ETS** stating exactly where
   in ETS what has to be done: "Tasks for ETS" (see below).
3. Do not rewrite the `.knxproj` directly as long as there is no official way
   to sign it.

## 1. Datapoint types: group address import (XML)

ETS can export group addresses as XML and import them again (namespace
`http://knx.org/xml/ga-export/01`). According to the ETS help
([devicebase.net, ETS6 Professional](https://devicebase.net/en/knx-association-ets6-professional/questions/how-to-import-or-export-ets-group-addresses/5kl)),
the import overwrites existing addresses: "import data always has the
priority". The XML format contains name, address, description and datapoint
type (`DPTs="DPST-9-1"`). The CSV export of ETS 4–6 also has a
`DatapointType` column; only the older ETS3 format lacks it. KNX Monitor uses
XML because it carries the range names. Example of the format:
[knx-ets5-ga-reader](https://github.com/snowdd1/knx-ets5-ga-reader/blob/master/myETS5GroupAddressExport-sample.xml).

`etsImportXml(entries, style)` in `lib/export/ets_ga_export.dart` (and
`etsGroupAddressXml(catalog, overrides)` for datapoint types only):

- writes **only the addresses that changed** (datapoint type set in the app,
  corrected name, learned name, learned new address). The import leaves all
  others alone.
- takes name, description and main and middle group from the imported
  project, so nothing changes except the intended field.
- supports three-level addresses only. Two-level and free projects produce
  nothing.
- is tested in `test/ets_ga_export_test.dart` and was tried on the ETS5
  sample project "Beispiel Gruppenadressen – Mittelgruppen-System" (772
  addresses, none with a type). Output:

```xml
<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<GroupAddress-Export xmlns="http://knx.org/xml/ga-export/01">
  <GroupRange Name="Zentral" RangeStart="0" RangeEnd="2047">
    <GroupRange Name="Licht &amp; Steckdosen" RangeStart="0" RangeEnd="255">
      <GroupAddress Name="Licht &amp; Steckdosen   -  Zentral AUS (ALLES)" Address="0/0/1" DPTs="DPST-1-1" />
    </GroupRange>
  </GroupRange>
</GroupAddress-Export>
```

`etsImportCsv` writes the same entries as an ETS CSV (format "3/1" with range
rows, UTF-8 with BOM).

**Still missing:**

- Two-level and free addresses (different `RangeStart`/`RangeEnd`, address
  notation).
- **A test in ETS** (see below). Above all: does the import delete a
  description that is missing in the file? Does it create duplicate group
  ranges if a name differs? Are links and the types of linked objects left
  untouched?
- Afterwards: once the project has been re-imported, the app could offer to
  delete its own overrides, because the project now contains them.

## 2. Flags and links

Both live in the project on the communication objects of the devices
(`ComObjectInstanceRef` with `ReadFlag`, `TransmitFlag` … and `Links`). ETS
offers no file import for them. In a device they also change what is written
to the device on the next download, which should happen deliberately in ETS.

**What would be needed for the app to propose changes:**

- **Editing in the app:** today flags and links are only shown and checked
  (`lib/model/project_check.dart`). It would need pending changes per object
  (set or clear a flag, link or unlink an address, set the sending address),
  stored separately from the imported project like the datapoint type
  overrides.
- After the changes in ETS, re-import the project. The project check shows
  what is done.

## Tasks for ETS (built)

Button at the top right of the project check (`lib/ui/ets_tasks_export.dart`).
The result is a PDF; if there is something to import, a ZIP with the PDF and
the group address import (XML, marked as preview until the ETS test has
passed).

"Tasks for ETS" collects the output of all checks. Tasks are created in
`lib/model/ets_tasks.dart` (`EtsTaskKind`) from these sources:

| Source | Tasks | Where |
| --- | --- | --- |
| Datapoint types set in the app | set datapoint type | import |
| Names corrected in the app (`CatalogStore.names`, `name_overrides.json`) | change the name; wins over a learned name | import |
| Learning without a project (`CatalogStore.learned`) | name for unnamed addresses, new addresses, datapoint types | import |
| Project check (`ProjectLint`) | no name, no datapoint type, no sender, no receiver (also unlinked), main group 14/15 | by hand, at the address |
| Project check (`ProjectLint`) | feedback without T flag, read without R flag, R flag more than once, no C flag, several senders, device without links | by hand, per device |
| Project check (`ProjectLint`) | crowded lines | by hand, in the project |
| Coupler filter check (`lib/model/coupler_filter.dart`, from recordings on known lines) | address seen on one line but not forwarded to another with receivers; line with addresses from other lines whose crossing is not yet observed | by hand, at the address or line |
| Last device inventory (`DeviceInventory.lastFor`, in memory until restart) | on the bus but not in the project; different serial number; does not answer | by hand, per device |

Not included: "central off with on" – that is behaviour on the bus, not a
setting that can be reliably attributed to one object.

- **Overview:** numbers, instructions, the import to tick off (group address,
  in project, new), tasks at group addresses and on the project, then a list
  of devices with their number of tasks and hints.
- **One page per device:** drawing with channel cards (rendered in the app,
  `lib/export/widget_capture.dart`), tasks with check boxes, object and group
  address, what to do and why, then the channel assignment with flags. Rows
  with tasks are highlighted.
- **Hints** (often intended): several senders, no sender, main group 14/15,
  does not answer, crowded line, filter observations.
- Devices known only from the inventory (not in the project) get a page
  without a drawing.
- If the project lacks flags (older import), the PDF says that the project
  should be imported again.

## 3. Why not rewrite the .knxproj directly

Technically this would be simple. The parser knows the places, and the
attributes could be changed (`DatapointType` on `GroupAddress`, flags and
`Links` on `ComObjectInstanceRef`). But:

- **ETS signs exported projects.** Next to the project folder `P-xxxx/` there
  are `P-xxxx.signature` and `P-xxxx.certificate` (licence, customer, public
  key). In the sample project this is an ETS5 Professional certificate. A
  modified `0.xml` no longer matches the signature. Reports show that ETS
  rejects such projects ("signature not valid", "The project has not been
  certified with a valid ETS license"), including unsigned files. See
  [xknx-editor #60](https://github.com/XKNX/xknx-editor/issues/60),
  [#21](https://github.com/knx-ai/xknx-editor/issues/21) and
  [#19](https://github.com/knx-ai/xknx-editor/issues/19).
- **Re-signing requires a key from ETS.** According to its issue tracker, the
  open-source project xknx-editor extracts the signing key from
  `Knx.Ets.XmlSigning.dll` and the certificate via the user's MyKNX login.
  This is legally risky: ETS licence terms and circumvention of protection
  mechanisms.
- Protected projects (password) would also have to be re-encrypted; that
  could be solved.

## 4. Official full path: an ETS app

An ETS app runs inside ETS (Windows, .NET) and may change the open project,
including flags and links. It would be the only official way to apply
everything in one step, e.g. as "Apply changes from KNX Monitor".
Prerequisites: development and distribution through the KNX Association
(membership or app partner programme, licence costs), Windows development next
to the Flutter app, approval by KNX. A large effort, only worthwhile if users
really ask for it.

## Test in ETS (on a copy of a project)

1. Copy a project, import it into KNX Monitor, change the datapoint type of
   two or three addresses, one of them with a description. Also learn a name
   for an unnamed address and learn an address that is missing in the
   project.
2. Project check › "Tasks for ETS" (ZIP with PDF and XML); load the XML in ETS
   via Group Addresses › Import.
3. Check:
   - Type changed, learned name applied, new address created in the right
     range?
   - Name and description unchanged?
   - No duplicate group ranges?
   - Other addresses, links and the types of linked objects unchanged?
   - Which message does ETS show?
4. Counter-check with an address that has no description in the file but has
   one in the project: is the description kept?
5. ETS5 and ETS6, if both are available.
