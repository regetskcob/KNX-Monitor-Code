# Health check on the server

The app has a health check (Tools › Health check). The server (Home Assistant
add-on, Docker container, Busclear Box) can run the part of it that needs
neither the app nor the bus: the rules that work from the recorded history and
the project alone. Home Assistant gets the result through the
[Busclear integration](https://github.com/regetskcob/KNX-Monitor-HA): the
service `knx_monitor.run_health_check`, the sensor "Health" (ok, hints, faults)
and the diagnostic sensor "Health findings".

Code: `ha-addon/knx_monitor/server/lib/src/health_check.dart`, routes in
`ha_integration.dart`, tests in `test/health_check_test.dart` and
`test/health_check_load_test.dart`.

## Switching it on

Off by default.

| Where | Setting |
| --- | --- |
| Home Assistant add-on | option "Health check for Home Assistant" (`health_check: true`) |
| Docker | `HEALTH_CHECK=true` |
| Busclear Box | `HEALTH_CHECK=yes` in `knx-box.txt` before the first boot ([knx-box.md](knx-box.md)), later `HEALTH_CHECK="true"` in `/etc/knx-box/env` |

The server reads the setting at start. The app shows under Tools › Data export
› Home Assistant whether the check is on and when it last ran.

## It never sends

The check reads the history files and `catalog.json`. It has no access to the
bus connection, so it behaves the same with and without read-only mode
(`read_only`, `READ_ONLY`): nothing goes on the bus, not even read requests.

The app's read test (send a read request to every status address and see who
answers: findings `newSilent`, `alwaysSilent`, `unlinked`) is not part of the
server's check. A caller can ask for it with `{"read": true}`; the server
refuses with 422 and `{"error": "read_only"}` in read-only mode, otherwise
`{"error": "read_test_not_supported"}`. Use the app for the read test.

## When it runs

- On request: `POST /api/ha/health/run`.
- Once a day at 3 o'clock local time, so the result is never older than a day.
  The server checks every minute whether a run is due: there is no result yet,
  the last one is 24 hours old, or 3 o'clock has passed since it. A server that
  was off at 3 o'clock catches up after its start.
- One run at a time. A request during a run waits for that run and gets its
  result.

## What it reads

The recorded days of today and yesterday, as the app's check does, and the
project the app stored on the server. Without recording there is nothing to
check (`telegrams` is 0, `recording` false); without a project only the rules
that need no datapoint type find anything (`project` false).

The days are read in a separate isolate, line by line, newest day first, with
only the fields a rule needs. Bounds: at most 2,000,000 lines per run (beyond
that the oldest are left out), at most 8,192 pairs of address and sender per
rule, at most 200 findings in the result. `truncated` says that a bound was
hit; `counts` always cover all findings. Measured with
`dart run tool/health_check_bench.dart` (two days of 100,000 telegrams,
yesterday packed, a project with 2,000 addresses, MacBook, JIT): about 0.55 s
per run, the event loop held up for 3 ms at most, 21 MB more resident memory.
The thresholds are those of the bus view ([performance.md](performance.md)).

## Rules

The same thresholds as in the app (`lib/model/health.dart`). `kind` is the
app's `FindingKind` in snake case.

| `kind` | Severity | Area | Meaning |
| --- | --- | --- | --- |
| `out_of_range` | error | readings | The newest value of a temperature (−30…60 °C), brightness (0…200,000 lx), wind (0…60 m/s, 0…220 km/h), humidity (0…100 %) or CO₂ address (0…10,000 ppm) lies outside the plausible range. |
| `stuck` | warning | readings | A temperature or humidity with at least 12 telegrams in the last 24 hours, spanning at least 12 hours, all with the same value. |
| `dpt_size` | error | dpt | The payload length does not fit the datapoint type of the group address; per address and sender. |
| `dpt_value` | warning | dpt | A value that is invalid for its type: the "invalid" marker 0x7FFF of DPT 9, an HVAC mode above 4 (20.102), a scene number above 63 (17.001); per address and sender. |
| `mixed_sizes` | warning | dpt | An address of the project without a datapoint type receives values of several lengths. |
| `repeats` | warning | bus | A sender with at least 20 telegrams of which at least 5 % are repeated (missing acknowledgements). |
| `unanswered_reads` | info | bus | At least two read requests from other devices to an address without a response within 3 seconds. |
| `overdue` | warning | cycle | An address that usually sends regularly stopped sending. |
| `lamp_fault` | error | lighting | DALI: luminaires behind a gateway report a lamp failure. |
| `gear_fault` | error | lighting | DALI: control gear or converters behind a gateway report a failure. |

Where the server differs from the app:

- `repeats` and `unanswered_reads` look at the two recorded days; the app
  looks at what its live view holds.
- `overdue` is the list of the server's "stopped sending" check (the same
  rule of the package `knx`, over seven days, only after the minimum silence
  `silent_after_hours`, without the time the recording did not cover, and
  without the addresses ignored in a repair). So the finding and the
  integration's repairs never disagree. The app's check applies the rule to
  two days without these corrections.
- `lamp_fault` and `gear_fault` count what the server heard since its start
  ([dali.md](dali.md)); the app keeps the state of each luminaire across
  restarts.
- Not on the server: the read test (see above) and the DALI findings
  `gatewaySilent`, `testOverdue` and `testFailed`, which need the app's
  record of each gateway and its evaluation of the emergency lighting log.

## Routes

Below `/api/ha/`, with the same access as the other routes there
([security.md](security.md)): the integration's token in the add-on, a paired
device with admin rights on the box and in Docker.

| Route | Answer |
| --- | --- |
| `GET /api/ha/health` | the last result; before the first run `status`, `time` and `counts` are `null` |
| `POST /api/ha/health/run` | runs the check and returns the result; body empty or `{}` |
| `GET /api/ha/state` | carries `health_check`: `{"enabled": false}`, or `enabled`, `status`, `time` and `counts` of the last run without the findings |

While the feature is off, both health routes answer 409:

```json
{"enabled": false, "error": "not_enabled", "option": "health_check", "env": "HEALTH_CHECK"}
```

A server before this feature answers 404 and has no `health_check` in its
state.

## Result

```json
{
  "enabled": true,
  "running": false,
  "format": 1,
  "status": "faults",
  "time": "2026-11-11T02:00:00.000Z",
  "duration_ms": 412,
  "trigger": "schedule",
  "read_test": false,
  "recording": true,
  "project": true,
  "days": 2,
  "telegrams": 183204,
  "truncated": false,
  "counts": {
    "total": 2,
    "errors": 1,
    "warnings": 1,
    "infos": 0,
    "by_kind": {"dpt_size": 1, "stuck": 1}
  },
  "findings": [
    {
      "kind": "dpt_size",
      "severity": "error",
      "area": "dpt",
      "text": "healthDptSize",
      "address": "2/0/0",
      "name": "EG FL Ist-Temperatur",
      "source": "1.1.7",
      "source_name": "Taster Flur",
      "actual": 1,
      "expected": 2,
      "dpt": "9.001",
      "count": 2,
      "since": "2026-11-10T18:04:11.000Z"
    },
    {
      "kind": "stuck",
      "severity": "warning",
      "area": "readings",
      "text": "healthStuck",
      "address": "2/1/0",
      "name": "EG FL Feuchte",
      "value": 45.0,
      "unit": "%",
      "since": "2026-11-10T13:00:00.000Z"
    }
  ]
}
```

- `status`: `faults` with at least one finding of severity `error`, `hints`
  with only warnings or hints, `ok` without findings.
- `trigger`: `manual` or `schedule`.
- `findings`: most severe first, then by kind, address and sender; at most
  200.

Every finding has `kind`, `severity` (`error`, `warning`, `info`), `area` and
`text`, and either `address` (group address in the project's style) or
`device` (individual address; `repeats` and the DALI kinds), each with `name`
from the project or `null`. The server sends no sentences: `text` is the key
of the app's sentence for the kind (`lib/l10n/app_de.arb`, `app_en.arb`), which
a client translates and fills with the fields below.

| Field | Kinds | Meaning |
| --- | --- | --- |
| `source`, `source_name` | `out_of_range`, `dpt_size`, `dpt_value` | sender (individual address) and its name |
| `value`, `unit` | `out_of_range`, `stuck` | the value as a number and its unit |
| `actual`, `expected` | `dpt_size` | payload length in bytes; 0 = up to 6 bits |
| `dpt` | `dpt_size`, `dpt_value` | datapoint type of the address, e.g. `9.001` |
| `raw` | `dpt_value` | the payload as hex |
| `count` | `dpt_size`, `dpt_value` (telegrams), `mixed_sizes` (lengths), `repeats` (telegrams of the sender), `unanswered_reads` (requests), `lamp_fault`, `gear_fault` (luminaires) | |
| `rate` | `repeats` | share of repeated telegrams, 0…1 |
| `since` | `out_of_range`, `dpt_size`, `dpt_value` (last such telegram), `stuck` (first telegram with the value), `overdue` (last telegram) | ISO 8601, UTC |
| `interval_s` | `overdue` | usual interval in seconds |

The last result is kept in `health_check.json` of the installation and
survives a restart. It is not part of the box backup: the next run writes it
again.

## Home Assistant

- Service `knx_monitor.run_health_check` (administrators only): runs the
  check and returns the result above as response data, for automations and
  scripts. While the feature is off it says how to switch it on.
- Sensor "Health": `ok`, `hints` or `faults`, with the attributes `last_run`,
  `findings`, `errors`, `warnings` and `infos`.
- Sensor "Health findings" (diagnostic): the number of findings.

Both sensors exist only while the server reports the check as switched on.
There is no repair and no event for a finding.
