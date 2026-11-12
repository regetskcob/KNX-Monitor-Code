# Tap points

A tap point is one bus connection at a specific place in an installation: a
tunnel to an IP interface, routing, or the KNX HAT of the box. With several of
them, e.g. one per line, Busclear shows everything in one list and can tell
what a coupler forwarded and what it filtered
([issue #8](https://github.com/regetskcob/KNX-Monitor/issues/8)). The user
guide is in [DOCS.md](../ha-addon/knx_monitor/DOCS.md#tap-points-several-connections);
this page describes how it works.

With a single tap point nothing of this is active: no chips, no column, no
merging, the plain replay check. Tests hold that
(`test/tap_demo_test.dart`, `test/multi_tunnel_test.dart`).

## Where the code is

| Part | App | Server (add-on, Docker, box) |
|---|---|---|
| Several connections as one | `lib/knx/multi_tunnel.dart` (`MultiTunnel`) | `server/lib/src/bus.dart` (`_runTap`, `_handleFrame`) |
| Merging | `TapMerger` in `package:knx` | the same class |
| Window, backlog, silence | `lib/model/tap_points.dart` (`TapWindowMeter`, `TapBacklog`, `TapSilence`) | copies in `server/lib/src/tap_window.dart`, `tap_silence.dart` |
| Gaps | `TapGaps` in `lib/model/tap_points.dart` | `availability.connectionEvent(tap:)`, kind `tap` in the outages |
| Recordings | `TapRecord` (saved as `taps`), `TapScope` (what is on screen) in `lib/model/tap_points.dart` | – (the history keeps `tp`/`sg` per telegram, gaps in the outages) |
| Data Secure | `lib/knx/secure/secure_tap_cache.dart` | `server/lib/src/secure_taps.dart` |
| Filter tables live | `lib/model/tap_coverage.dart`, `tapObservations` in `lib/model/coupler_filter.dart` | – |
| Interface | `lib/ui/tap_points_panel.dart` (set up), `tap_strip.dart` (cards above the list), `TapChips` in `telegram_row.dart`, "Path through the installation" in `details_sheet.dart` | status `taps` over the WebSocket |

The server cannot import Flutter code, so it keeps copies of the small classes.
`server/test/tap_copies_test.dart` fails when a copy differs from the app's.

In the browser (add-on, web) tap points exist only through the server: it sends
frames of the main connection as `0x01` and those of further tap points as
`0x04` with the tap point's number, and the view merges them the same way.

## Merging

A forwarded telegram arrives at several tap points. Sender, destination, type,
payload and repeat flag are equal, the hop count is one lower per coupler, and
the copies lie within a short window (100 ms by default; measured across a line
coupler with a kBerry: median 40 ms, at most 51 ms).

- One entry per telegram with a list of sightings `(tap point, offset, hop
  count)`. Each tap point contributes at most one sighting per entry, matched
  in order of arrival, so two identical telegrams in quick succession stay two
  entries. A repetition (repeat flag) is a different frame and stays separate.
- The entry's tap point (`tp`) is the one with the highest hop count, i.e. on
  the sender's line; its time is the earliest sighting.
- An entry leaves as soon as every listening tap point has seen it, otherwise
  when the window ends. Paused, disconnected and silent tap points are not
  waited for, so a hanging tap point never delays or blocks the others.
- Watchers, alarms, statistics, recorder and MQTT see the entry once. Bus load
  and repetitions are counted per tap point (`TapLoad`).

Memory is bounded: entries leave after their window (at most 5 s), and
`TapBacklog` releases everything at once if more than 1000 telegrams are ever
held back (a clock set back, a flood that never drains). It counts exactly what
is inside the merger (fed minus left, an entry taking its sightings with it),
so steady merged traffic never triggers it. The price of a forced release is a
few telegrams that leave unmerged.

## The window measures itself

The receive time is taken where the software runs, not on the bus. Interfaces
report with different delay, and over VPN latency and jitter add to it.
`TapWindowMeter` therefore measures the lag per tap point from telegrams that
arrive at several of them:

- every merged telegram carries the offsets of its further sightings; the meter
  keeps the last 64 per tap point (`lagOf`, shown on the tap point's card and as
  `lagUs` in the server status) and widens the window as soon as 1.5 × the
  largest one no longer fits;
- a copy that arrives after the window leaves as a second entry; three such
  late pairs widen the window to 1.5 × the largest lag seen.

Windows are rounded up to 10 ms and never exceed 1 s; a lag beyond that is not
taken for a late copy at all, more needs a window set by hand. A widened window
comes back down: after 64 merged telegrams in a row without a late copy it is
set to what their largest offset needs, never below 100 ms. A window set by
hand (`windowMs`, 10 to 5000) wins: that tap point is not adjusted, and a
telegram it took part in does not change its partner either. Measured windows
are for merging only; Data Secure ignores them.

Limit: when the tap point on the sender's line is also the slower one (the
entry's origin is not its first sighting), `TapMerger` does not report that
tap point's offset, so only the other direction is measured.

## Gaps

A tap point that is not reachable (VPN down, interface busy) or paused is not
a bus fault. The app notes when each tap point was away (`TapGaps`, since the
monitor opened; a tap point that never connected is away from the start). A
telegram that is missing at a tap point during such a span is not read as
filtered:

- the banner says "tap point unreachable", names it and states that it is no
  bus fault; the other tap points keep running, the missing one reconnects on
  its own with growing intervals;
- rows from that time carry one mark for all tap points that were not
  reachable (their names in tooltip and semantics), the details say
  "unreachable at that time" instead of "filtered or line-local". Paused tap
  points are named in the strip above the list only;
- the filter "at one tap point only" (`is:single`) skips telegrams from a time
  when no other tap point was listening;
- the live filter table check (`TapCoverage`, `tapObservations`) does not count
  such telegrams against a coupler;
- the live list shows a quiet line where a tap point went away and where it
  came back ("Tap point 1.2 not reachable · 12:03:10", in a recording with
  the saved name: "1.2 (MDT IP-Interface) reachable again · 12:03:23"). The
  lines sit at the edges of the span in which rows get the mark, so a row
  between them is marked and none outside; like that span they include the
  1 s slack, the start counts, the end does not. Paused spans are left to the
  strip;
- the cards above the list show the last gaps with start and end.

The server keeps the gaps in the history (`/api/bus/availability?taps=1`, kind
`tap`), where the recordings show them per day.

## Recordings

A recording saved in the app keeps its tap points under the key `taps`
(`TapRecord`): the chip labels, the names as set up and the gaps that touch the
recording, a gap still open at the end closed there.

```json
"taps": {
  "labels": ["1.1", "1.2"],
  "names": ["Gira X1", "MDT IP-Interface"],
  "gaps": {"since": 1762848000000000, "n": 2, "gaps": [[1, 1762848010000000, 1762848030000000], [1, …, …, 1]]}
}
```

Times are microseconds since the epoch; a trailing `1` marks a paused span.
With a single tap point the key is left out, so the file is as before. Older
versions ignore the key and read the rest unchanged; a recording without it
(saved before, or with one tap point) opens as it always did. Entries that do
not fit (a tap point out of range, an end before its start, gaps for another
number of tap points) are dropped, labels and names lose control characters and
are cut to 80 characters.

While a recording is open, `TapScope` answers with its tap points instead of
the live monitor's: chips, the "seen at" column, "Path through the
installation" (with the name next to the label), the gap marks and lines, the
filters `tap:` and `is:single`, the topology and the CSV export. Closing it
returns to live.

Not covered: a day of the add-on's history opened as a recording carries the
telegrams' `tp`/`sg`, but not the labels or the gaps; it uses those of the
open monitor, as before. Diagnostic packages leave the tap points out too
(their labels can carry names).

## Data Secure

See [security.md](security.md#data-secure). In short: the identical frame from
another tap point is attached as a sighting to the entry of the first copy
while that entry is still open and the pair's hand-set window (default 100 ms)
has not passed. It never becomes an entry of its own; everything else meets the
unchanged replay check.

## Sending

Group telegrams go over the first connected tap point. Access to an individual
address (device diagnostics, programming mode) goes over the connected tap
point whose tunnel address lies on the device's line, which saves coupler hops;
without one, over the first. The send guard of the app and the read-only mode
of the server apply before the tap point is chosen and for every link
(`ReadOnlyLink` wraps each one).

## Limits and validation

- At most eight tap points per installation, the first one included.
- The same connection counts once: the same interface and port (UDP or TCP),
  or the same multicast group for routing.
- The server checks tap points in a request (`BusConfig.invalidTap`): mode
  `udp`, `tcp` or `routing`; host a host name or IP address, for routing an
  IPv4 multicast group or empty; port 1 to 65535; `windowMs` 10 to 5000; name
  at most 80 characters. A stored file is cleaned the same way, names lose
  control characters before they reach the log.
- Further tap points are plain tunnels or routing. A KNX IP Secure tunnel is
  possible as the first tap point only; tap points therefore carry no
  passwords or keys, and none appear in status, history, exports or MQTT.

## Trying it without a second interface

Connect › expert mode › Tap points › "Try it in the demo house" opens the
sample house with two tap points: the gateway on line 1.1 and an interface on
line 1.2 behind the line coupler, about 40 ms later. Weather telegrams from 1.2
with receivers on 1.1 are forwarded, the others stay on their line; two
prepared faults show in the topology (4/0/1 blocked, 5/0/0 passed needlessly);
every 108 seconds the second tap point drops for about 13 seconds. A push
button on a third line (1.3.7, not in the project) sends now and then, so the
topology shows a line that is only indirectly visible.
