# Performance under bus load

Measured on 14 October 2026 on an iPad (120 Hz, budget 8.3 ms per frame) with a
profile build. The benchmark feeds telegrams at fixed rates through a simulated
tunnel and records build and raster times of every frame (`FrameTiming`):

```
flutter run --profile -d <device> -t lib/bench/main_bench.dart
```

The numbers predate later UI changes; run the benchmark again after larger
changes to the overview or the live list.

Context: a KNX TP line physically carries at most about 40–50 telegrams/s.
100–200/s corresponds to a heavily loaded main line or several lines behind an
IP router.

## Before optimization

| Load | Overview (animation on / off) | Live (animation on / off) |
|---|---|---|
| 10/s | 118 / 114 fps | 120 / 120 fps |
| 50/s | 118 / 120 fps | 120 / 120 fps |
| 100/s | 96 / 102 fps (11.5 % over budget) | 117 / 120 fps |
| 200/s | 69 / 71 fps (72 % over budget) | 109 / 120 fps (8.5 % over budget) |

## After optimization

| Load | Overview (animation on / off) | Live (animation on / off) |
|---|---|---|
| 10/s | 120 / 117 fps | 120 / 120 fps |
| 50/s | 120 / 120 fps | 120 / 120 fps |
| 100/s | 119 / 120 fps | 119 / 120 fps |
| 200/s | 120 / 120 fps | 120 / 120 fps |

At most 1 % of frames are still over budget.

## Measures

1. **Throttled rebuilds** (`ThrottledListenable` in `lib/ui/log_view.dart`):
   the overview rebuilds at most about 15 times per second, the live list about
   30 times. Animations keep running at full frame rate.
2. **Cached section assignment:** previously four regex checks ran per frame
   for every address.
3. **Response analysis via a dedicated list of read requests** instead of
   scanning all 5,000 telegrams of the log (`MonitorModel`). The sent and
   repeated counters are maintained incrementally.
4. **No arrival animations above 60 telegrams/s**
   (`TelegramLog.animationRateLimit`): at this rate nobody can read along, and
   reordering the list cost frame rate.

## Raw data (after optimization)

```
 10/s  Overview   animation on  | 120 fps | build avg  1.3 p90  4.5 p99  7.3 | Raster p90  1.9 p99  2.9 ms | over budget 0.5 %
 50/s  Overview   animation on  | 120 fps | build avg  2.4 p90  4.6 p99  5.4 | Raster p90  1.2 p99  1.4 ms | over budget 0.0 %
100/s  Overview   animation on  | 119 fps | build avg  3.8 p90  4.8 p99  6.0 | Raster p90  1.4 p99  1.6 ms | over budget 0.0 %
200/s  Overview   animation on  | 120 fps | build avg  4.7 p90  5.0 p99  6.3 | Raster p90  1.5 p99  1.6 ms | over budget 0.1 %
 10/s  Overview   animation off | 117 fps | build avg  0.9 p90  4.7 p99  8.1 | Raster p90  2.2 p99  3.0 ms | over budget 1.0 %
 50/s  Overview   animation off | 120 fps | build avg  2.4 p90  4.7 p99  5.6 | Raster p90  1.2 p99  1.4 ms | over budget 0.0 %
100/s  Overview   animation off | 120 fps | build avg  3.9 p90  4.8 p99  5.9 | Raster p90  1.4 p99  1.6 ms | over budget 0.0 %
200/s  Overview   animation off | 120 fps | build avg  4.8 p90  5.0 p99  5.4 | Raster p90  1.6 p99  1.7 ms | over budget 0.2 %
 10/s  Live       animation on  | 120 fps | build avg  1.6 p90  1.6 p99  4.8 | Raster p90  1.8 p99  2.0 ms | over budget 0.0 %
 50/s  Live       animation on  | 120 fps | build avg  3.0 p90  4.6 p99  5.1 | Raster p90  2.7 p99  3.0 ms | over budget 0.0 %
100/s  Live       animation on  | 119 fps | build avg  3.4 p90  4.0 p99  6.0 | Raster p90  1.2 p99  1.3 ms | over budget 0.0 %
200/s  Live       animation on  | 120 fps | build avg  4.2 p90  4.4 p99  6.7 | Raster p90  1.2 p99  1.3 ms | over budget 0.0 %
 10/s  Live       animation off | 120 fps | build avg  0.7 p90  0.8 p99  6.0 | Raster p90  2.2 p99  3.3 ms | over budget 0.0 %
 50/s  Live       animation off | 120 fps | build avg  2.2 p90  4.0 p99  4.2 | Raster p90  1.3 p99  1.5 ms | over budget 0.0 %
100/s  Live       animation off | 120 fps | build avg  3.3 p90  3.9 p99  5.8 | Raster p90  1.3 p99  1.4 ms | over budget 0.0 %
200/s  Live       animation off | 120 fps | build avg  4.1 p90  4.3 p99  6.8 | Raster p90  1.3 p99  1.4 ms | over budget 0.0 %
Done.
```

## History scan of the bus view

The bus view on the floor plan ([floor-view.md](floor-view.md)) reads up to
seven days of history on the server the first time a plan's addresses are
asked for (`FloorViewService._seed` in `server/lib/src/floor_view.dart`), to
know when each address was last on the bus. Measured on 11 November 2026 with a
reproducible load test in the add-on server:

```
cd ha-addon/knx_monitor/server
dart compile exe tool/floor_view_bench.dart -o /tmp/fvb && /tmp/fvb      # AOT, as on the box
dart run tool/floor_view_bench.dart --per-day 400000 --addresses 600    # options
```

It writes a synthetic history in the box's layout: six finished days packed as
`.ndjson.gz`, today as plain `.ndjson`, lines as the recorder writes them with
the raw frame, 2,000 group addresses (30 % of the traffic on 40 busy ones), 10 %
reads. Then, in a fresh process so generating does not count, it measures the
scan until the answer no longer says `loading`, the resident memory above the
start, the lateness of a 5 ms timer (how long bus, WebSocket and HTTP would
wait) and whether 50 telegrams per second fed meanwhile into the recorder and
the view are taken in on time. `test/floor_view_load_test.dart` runs a smaller
version (7 × 20,000) in every server test run, with the thresholds at a factor
of 2 so a slow CI machine still passes; memory only counts in the tool, which
measures in a process of its own.

| History | Mac (M2 Pro, AOT) | Raspberry Pi 4 |
|---|---|---|
| 7 × 100,000 telegrams, 18.9 MB packed, 200 addresses | scan 0.51 s, memory +11.6 MB, event loop at most 2.3 ms late, 0 telegrams late | measured: scan 3.0 s, memory +12.4 MB, event loop at most 8.6 ms late, 0 telegrams late |
| 7 × 400,000 telegrams, 74.7 MB packed, 600 addresses | scan 2.2 s, memory +32 MB, event loop at most 1.9 ms late, 0 telegrams late | estimate: about 13 s |

With `dart run` (JIT): 0.53 s, at most 12.6 ms late (compilation).

**On the Pi:** measured on 11 Nov 2026 on a Busclear Box (Raspberry Pi 4, 8 GB,
history in `/tmp`, that is in memory), three runs, the slowest shown. The Pi
is about 6 times slower than the Mac here, less than the factor of 10 the
thresholds assume. The tool is cross-compiled on the Mac and copied over, the
box has no Dart SDK:
`dart compile exe --target-os linux --target-arch arm64 tool/floor_view_bench.dart -o fvb`.
The larger history is estimated with the measured factor.

**Thresholds** (`overLimits` in the tool, which exits with 1 above them): on
the Pi the scan ends within 30 s (the card shows live times meanwhile and says
`loading`), the event loop never waits longer than 250 ms (a tunnel must
acknowledge within 1 s or the gateway drops the connection), at most 64 MB on
top (the add-on shares the Pi with Home Assistant), and no telegram is taken in
late. All are met with a wide margin, also at four times the traffic, so the
scan stays as it is: it reads only the addresses on the plan, field by field
without decoding the line, and pauses every 2,000 lines. Not done, because not
needed: a separate isolate, stopping early once every address is found (a day
corrected by the clock may hold later times), a per-day cache across restarts.
Memory grows with the number of lines read, as garbage the collector has not
freed yet: about +12 MB at 0.7 to 0.8 million lines, +32 MB at 2.8 million.

