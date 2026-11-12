# DALI lighting through KNX

Busclear shows the DALI side of an installation as far as a KNX-DALI gateway
reports it on the KNX bus: faults per luminaire, the state of emergency
converters and their test results. It has no connection to the DALI line, it
never addresses or commissions DALI devices, and it never sends one of the
DALI datapoint types. What a gateway does not send to a group address stays
invisible.

## Datapoint types

Decoded for display (`lib/knx/dali.dart`, plain Dart, values without texts):

| DPT | Size | Fields, most significant bit first |
|---|---|---|
| 237.600 DALI control gear diagnostic | 2 bytes | 5 reserved, CE converter error (bit 10), BF ballast failure (9), LF lamp failure (8), RR read request (7), AI address is a group (6), address (5..0) |
| 238.600 DALI diagnostics | 1 byte | BF ballast failure (7), LF lamp failure (6), address (5..0) |
| 244.600 converter status | 2 bytes | CM mode (4 bits), 2 reserved, hardwired switch (9), hardwired inhibit (8), then four 2-bit fields: function test pending, duration test pending, partial duration test pending, converter failure (0 unknown, 1 no, 2 yes) |
| 245.600 converter test result | 6 bytes | LTRF, LTRD, LTRP (4 bits each: 0 unknown, 1 passed, 2 passed late, 3 failed, 4 failed late, 5 stopped), 4 reserved, SF, SD, SP (2 bits each: 0 unknown, 1 automatic, 2 gateway), 2 reserved, LDTR discharge time in minutes (16 bits, 0..510), LPDTR battery charge (8 bits, 0..254, 255 unknown) |

Source: KNX System Specifications 03_07_02 "Datapoint Types" v02.02.01,
clauses 6.7.1, 6.8.1, 6.11 and 6.12, cross-checked with the field order in the
ETS master data (`knx_master.xml`). The layouts are from the specification;
they have not yet been checked against telegrams of a real gateway. The
fixtures in `test/fixtures/dali/codec.json` are built by hand from the
specification.

A wrong length or a reserved value (set reserved bits, mode 10 to 15, a 2-bit
field with value 3, a result 6 to 15, a group above 15, a discharge time above
510) is not decoded: the monitor shows hex and the telegram details say why.
Main type 238 needs the subtype, because 238.001 is the scene configuration.
A telegram with RR set is a query to the gateway and carries no state.
DPT 244.600 and 245.600 carry no DALI address: which luminaire an object
belongs to comes from the project.

The add-on server keeps a byte-identical copy of `lib/knx/dali.dart`
(`ha-addon/knx_monitor/server/lib/src/dali.dart`); tests on both sides compare
the two files and decode the same fixture. The file has no dependency on the
app and can move to the `knx` package (dart-knx) later.

## Model

`lib/model/dali_project.dart` derives the DALI side from the imported project:

- A device is a gateway if one of its objects carries a DALI type, or if a
  profile matches its manufacturer and product.
- Objects get a role: `diagnostic`, `lampFault`, `gearFault`, `groupFault`,
  `faultCount`, `faultCode`, `burnHours`, `emergencyStatus`,
  `emergencyResult`, `groupSwitch`, `groupDim`, `groupValue`, `groupStatus`,
  `groupValueStatus`. Without a profile the role comes from the datapoint type
  and from object texts and group address names ("EVG 12 Lampenfehler",
  "Gruppe 3 Schalten"), only on devices that are gateways.
- Numbers printed in texts count from 1 if a text reaches 64 (16 for groups),
  from 0 if a text prints 0; otherwise they are taken as printed. With one
  fault object per control gear this can be off by one; the addresses in
  DPT 237.600 and 238.600 come from the payload and are not affected.

`lib/model/dali.dart` keeps gateways, luminaires and groups in two files next
to the project: `dali.json` holds what was entered in the app and what the
objects mean (shared with the server and the box), `dali_state.json` what the
bus reported (local). Older single-file versions are read as both. Together:

```json
{
  "v": 1,
  "seen": 1794222251000,
  "settings": {"functionDays": 30, "durationDays": 365, "pollMinutes": 60},
  "gateways": [{"a": 4392, "pn": "DALI-Gateway", "l": "EG › Flur", "t": 1794222251000}],
  "gear": [{"gw": 4392, "a": 12, "n": "Flur EG Leuchte 2", "r": "Flur EG", "g": [1],
            "f": 1, "since": 1794222251000, "h": [[1794222251000, 1]]}],
  "groups": [{"gw": 4392, "g": 1, "n": "Flur EG"}],
  "objects": {"3092": {"gw": 4392, "r": "diagnostic"}}
}
```

`f` is a bit set (1 lamp, 2 control gear, 4 converter). Names, rooms, the
groups of a luminaire and whether it is an emergency luminaire are entered in
the app: a gateway does not report them on KNX. `objects` repeats the roles for
the server. Installations without DALI never get the file, older versions
ignore it. Everything read from it is checked field by field; a file that is
not JSON, has wrong types or is larger than 4 MB is set aside and the view
starts empty.

Without a project a gateway appears while listening, as soon as the type of
the diagnostic address is chosen in the telegram details ("DALI diagnostics").
It stays a suggestion until the user takes it over: its reports do not count,
it is not saved, and there are at most 16 suggestions (any device can pose as
a gateway, see [security.md](security.md#dali-reports-and-the-emergency-lighting-log)).

A luminaire shows its reported faults, or "test failed" when its last function
or duration test failed; groups and gateways take the worst of their
luminaires, so a failed emergency test is never shown as "OK".

One diagnostic address reports many luminaires, so state counts per gateway
and DALI address. The gateway of a report is its sender.

## Alarms and watchers

- `activeAlarm` treats a diagnostic telegram with a fault flag as an active
  fault (chip in the monitor). Notifications are sent per luminaire on the
  change into a fault and, for a reported fault, on the way back
  (`lib/model/dali_alarms.dart`, in the server `dali_watch.dart`), with the
  same setting as the other alarm notifications, through a debouncer shared by
  app and server (`FaultDebouncer`): a state counts once it held for 30
  seconds, at most five notifications per gateway and minute and then one
  summary, at most 60 events a minute. A failed emergency test notifies too. On
  a shared tunnel the server sends them if it reports the feature `dali`.
- Watchers get the check kind `bits` for flag datapoints
  (`check: {"bits": {...}}` in `watch_rules.json`):

  | Key | Meaning |
  |---|---|
  | `bytes` | payload length |
  | `mask` | flags looked at (payload as a number, most significant byte first) |
  | `set` | optional: the masked flags must equal it; without it any masked flag matches |
  | `zero` | optional: bits that must be 0 |
  | `addr`, `addrMask` | optional: `value & addrMask == addr`, `addrMask` defaults to `0x3F` |

  The server lists what it can do in its status (`features`: `bitsCheck`,
  `dali`). The app hands a `bits` rule only to a server with `bitsCheck` and
  checks it itself otherwise. A watcher fires on every matching telegram; the
  change into and out of a fault is the alarm's job.

## Reading

Gateways that report faults only on request can be read: once ("Read
diagnostics now") or periodically (setting per installation, off by default,
because it sends). Both use `ReadSweep` (group value reads, 5 per second) on
the diagnostic, fault and converter objects whose flags allow reading. Nothing
is read on a server in read-only mode. The query form of DPT 237.600 (RR set)
is not sent.

## Emergency lighting log

Every new test result becomes one JSON line in `dali_tests/<year>.ndjson`,
append only:

```json
{"t": 1794186903000, "ga": 10768, "gw": 4392, "a": 16, "k": "duration", "r": "failed",
 "s": "automatic", "why": ["delayExceeded"], "x": "140050005CFF"}
```

`k` is `function`, `duration` or `partial`, `r` is `passed`, `failed` or
`unknown`, `min` the discharge time of a passed duration test, `lvl` the
battery charge after a partial test (0..254), `first` marks the first result
seen for an object (the test may be older than `t`: its age counts as unknown,
never as current), `src` the sender, `fx` a sender other than the gateway (the
entry never counts), `sec` arrival KNX Data Secure (decrypted and checked
with the keyring, by the server or by the app's tunnel; not after a rebuild
from the history). An overflow line
`{"overflow": true, "t": …}` ends a year that reached its limit.

DPT 245.600 always carries the last result of all three kinds, without a time.
`EmergencyTracker` creates an entry for a kind when its fields differ from the
previous telegram at the same address, or when the converter status (from the
gateway) showed that test since then: running (mode), or pending and then no
longer pending. A repeated identical result without such a hint creates
nothing: the datapoint has no time stamp and gateways also repeat their state
on reads and cyclically, so the same bytes cannot tell a new test from an old
one. A luminaire whose gateway sends no converter status then becomes overdue
although it tests; the view says "no new result for 41 days" and explains why.
At most one entry per object, kind and origin per hour; a result from another
sender gets its own comparison and is marked. DPT 245.600 knows the reasons "late" and "stopped"
only; battery or lamp as reasons need other datapoints and are not filled.

On the add-on and the box the server writes the log, also without an open app
and only with a known time; otherwise the app writes while connected. The log
can be rebuilt from the daily history as far as it reaches. The view lists the
days without a recording. Export as PDF and CSV with the same columns. The log
documents what the luminaires report; whether it replaces a mandatory
inspection is for the operator or inspector to decide.

Limits against flooding: at most 4 MB per year's file (one overflow line and a
notification), files read up to that size, `dali_tests/` append only through
the file API.

## Health check, commissioning, service report

- Health check area "Lighting": luminaires with a lamp failure, control gear
  with a failure, emergency luminaires overdue or failed, per gateway. A
  gateway counts as silent if nothing from it was seen for 48 hours while the
  bus was heard for at least 24 of them.
- Commissioning: DALI groups are switched one by one through the normal write
  path (notice before the first write, confirmation of the company edition,
  not in read-only mode). If no feedback comes from the switched group but the
  gateway reports the switched value on another group's status address, the
  item is marked `foreign` with a note.
- Service report: one item per luminaire with a fault and per emergency
  luminaire with a failed or overdue test.

## Gateway profiles

`assets/dali_profiles/*.json`, one per gateway family:

```json
{
  "id": "example",
  "name": "Example gateway",
  "status": "documented",
  "statusNote": "from documentation, not yet verified against real telegrams",
  "source": "manual, version, pages",
  "note": "what the profile leaves out or assumes",
  "match": {"manufacturer": ["acme"], "product": ["dg 64"]},
  "gearBase": 1,
  "groupBase": 1,
  "rules": [
    {"role": "gearFault", "first": 230, "step": 11, "count": 64},
    {"role": "groupSwitch", "text": "^G(\\d{1,2}),? .*Switching"}
  ]
}
```

A rule matches by object number (`first`, every `step` objects, `count`
times; the n-th object belongs to index n, counted from 0) or by object text
(regular expression, first group is the number as printed, minus `gearBase`
or `groupBase`). `status` is `documented` unless a profile was checked against
real telegrams (`verified`); the view says which.

Shipped profiles, both from documentation only:

- ABB DG/S x.64.1.1 (Product Manual 2CDC507164D0211 Rev B): output A by object
  number. The manual prints the first two numbers of each series; the step of
  11 per group and ballast and 3 per converter follows from them. Output B of
  the two-channel device is not mapped.
- MDT DaliControl SCN-DALI64.03 (Technical Manual, firmware 3.0.0 or higher):
  by object text only, because the manual gives no numbering rule.

Gateways without a profile work through the standard datapoint types and
object texts.

## Demo

The demo house has a DALI gateway 1.1.40 (main group 10): 16 control gear with
a driver failure at address 3 and a lamp that fails at address 12 about half a
minute after the start, four groups (switching group 2 answers on group 3's
status address), three emergency converters with a failed duration test and an
overdue function test in the log.
