# Group address schemes

KNX prescribes neither a structure nor a naming convention for group
addresses. The app therefore only uses what names, the ETS path and the
datapoint type reveal. Test projects for the schemes below are in
`test/naming_schemes_test.dart`; the vocabulary is in
`lib/model/object_groups.dart` (`ObjectIndex`).

## Where names matter

| Place | Based on | Languages |
| --- | --- | --- |
| Objects (related addresses grouped together) | name, ETS path | German, English |
| Overview sections | datapoint type, keywords in name and path | German, English |
| Alarms and faults (`lib/model/alarms.dart`) | DPT 1.005 and 21.001, keywords | German, English |
| Feedback detection (commissioning "Read status", topology, teach-in, cause chain, Home Assistant export) | keywords (Status, RM, Rückmeldung, Feedback …) | German, English |
| Filter | free text, address patterns | – |

Values, units and devices come from the project and do not depend on names.

## Recognized object schemes

| Scheme | Example |
| --- | --- |
| Element abbreviation | `EG FL F01 Auf/Ab fahren`, `EG FL F01 Aktuelle Position` |
| Function at the end | `Küche Decke Schalten`, `Küche Decke Status` |
| Function first | `Status Steckdose Garten`, `Verbrauch Wohnzimmer` |
| Separators | `OG – Diele – Sollwert`, `EG Flur — Licht schalten` |
| Abbreviations with `_` or `.` | `EG_KUE_LI_Decke_RM`, `EG.BAD.HZG.IstTemp` |
| Function only in the middle group | `Schalten › Küche Decke`, `Rückmeldung › Küche Decke` |
| Room only in the middle group | `Küche › Licht schalten`, `Wohnen › Licht schalten` |
| English with separators | `GF - Kitchen - Downlights - Switch Feedback` |
| English without separators | `Living Room Blind Up/Down`, `Bedroom Temperature Actual` |
| English, function first | `Status Porch Lamp`, `Porch Lamp Toggle` |
| Series | `Rollladen EG Auf/Ab fahren`, `Rollladen EG Auf/Ab anhalten` |

Feedback addresses are recognized by words such as Status, RM, Rückmeldung,
Zustand, Ist, Aktuell, Feedback, State, Actual, Current, Geöffnet/Opened,
Geschlossen/Closed. Setpoints count as commands, except as feedback
("Aktueller Sollwert", current setpoint).

## Address format

Three-level (`1/2/3`), two-level (`1/515`) and free (`2563`) addresses are
taken from the ETS project (`GroupAddressStyle`) or the CSV. Display, input
and filters follow this format.

## Limits

- Names without a recognizable function word and without separators
  ("Küche Decke", "Küche Wand") stay single addresses.
- Abbreviations outside the vocabulary (e.g. custom abbreviations for trades)
  are treated as part of the object name.
- Rooms are guessed: the part before the first trade word, floor + room, or
  the middle group. With unusual structures, objects end up under "Other".

Sources of the schemes: KNX-User-Forum (group address structures by
room/trade/function), KNX Association "Best practices for KNX group address
structures", smart-home-feeling.de, dietechwerkstatt.de, ioBroker forum
(status detection by name).
