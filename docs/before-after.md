# Before/after: comparing the state of an installation

"Before/after" (`lib/ui/snapshot_screen.dart`, `lib/model/value_snapshot.dart`)
freezes the state of the installation and compares it later. It is meant for
anything done to the installation: power off, a device swapped, a download from
the ETS.

A snapshot holds, per group address, the last value (as bytes for comparing and
as text for reading) and the set of devices that had sent a value. It is stored
per installation in `snapshot.json` until it is discarded.

The comparison sorts every address into one of four groups:

| Group | Condition |
| --- | --- |
| Changed | sent again after the snapshot, with another value |
| Unchanged | sent again with the same value |
| Still the old value | not sent since the snapshot |
| New since then | not in the snapshot |

"Silent devices" are those that had sent before the snapshot and have not
since. After a power failure these are the devices that did not start again,
or simply have not had a reason to send yet: a device that sends rarely shows
as silent until it does. Reading its status feedback ("Rooms") makes it answer.

Nothing is sent. Read requests are not values and do not count.
