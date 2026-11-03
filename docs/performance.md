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
