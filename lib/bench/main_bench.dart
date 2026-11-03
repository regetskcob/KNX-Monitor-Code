// Performance measurement on the device under simulated bus load.
//
//   flutter run --profile -d <device> -t lib/bench/main_bench.dart
//
// Feeds telegrams at fixed rates through a simulated tunnel and measures the
// build and raster time of all frames per phase (FrameTiming). Results appear
// on screen and in the console.
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/analysis.dart';
import '../theme/app_theme.dart';
import '../ui/log_view.dart';
import '../ui/monitor_screen.dart';
import '../model/installation.dart';

const _rates = [10, 50, 100, 200];
const _warmUp = Duration(seconds: 3);
const _measure = Duration(seconds: 8);

class _Phase {
  const _Phase(this.rate, this.tab, this.animations);
  final int rate;
  final LogTab tab;
  final bool animations;

  String get label =>
      '${rate.toString().padLeft(3)}/s  ${tab == LogTab.live ? 'Live     ' : 'Übersicht'}  '
      '${animations ? 'Animation an ' : 'Animation aus'}';
}

final _phases = [
  for (final tab in LogTab.values)
    for (final animations in [true, false])
      for (final rate in _rates) _Phase(rate, tab, animations),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await InstallationStore.instance.load();
  await Future.wait([CatalogStore.instance.load(), LocaleController.instance.load()]);
  if (CatalogStore.instance.catalog.isEmpty) CatalogStore.instance.catalog = _syntheticCatalog();
  runApp(const _BenchApp());
}

/// 300 group addresses with mixed DPTs, if no project is imported.
GroupCatalog _syntheticCatalog() {
  const dpts = [Dpt(1, 1), Dpt(5, 1), Dpt(9, 1), Dpt(9, 4), Dpt(14, 56), Dpt(13, 10)];
  return GroupCatalog({
    for (var i = 0; i < 300; i++)
      (((i ~/ 50) + 1) << 11) | i: GroupInfo(
        address: (((i ~/ 50) + 1) << 11) | i,
        name: 'Adresse $i',
        path: 'Bereich ${(i ~/ 50) + 1} › Gruppe ${i % 5}',
        dpt: dpts[i % dpts.length],
      ),
  });
}

class _BenchApp extends StatefulWidget {
  const _BenchApp();

  @override
  State<_BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<_BenchApp> with SingleTickerProviderStateMixin {
  final _random = math.Random(42);
  late final List<GroupInfo> _groups = CatalogStore.instance.catalog.groups.values.toList();
  late final Ticker _ticker = createTicker(_onTick);

  KnxTunnel _tunnel = _newTunnel();
  int _phase = 0;
  DateTime _phaseStart = DateTime.now();
  Duration _lastElapsed = Duration.zero;
  double _carry = 0;
  bool _measuring = false;
  final _timings = <FrameTiming>[];
  final _results = <String>[];

  static KnxTunnel _newTunnel() => KnxTunnel('benchmark')
    ..state.value = TunnelState.connected
    ..deviceName.value = 'Benchmark';

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    final hz = PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 60;
    _log('Display: ${hz.toStringAsFixed(0)} Hz  (Budget ${(1000 / hz).toStringAsFixed(1)} ms/Frame)');
    _log('Projekt: ${_groups.length} Gruppenadressen');
    _startPhase();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _log(String line) {
    debugPrint('[BENCH] $line');
    setState(() => _results.add(line));
  }

  void _startPhase() {
    _tunnel.state.value = TunnelState.disconnected;
    _tunnel = _newTunnel();
    _phaseStart = DateTime.now();
    _measuring = false;
    _timings.clear();
    setState(() {});
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_measuring) _timings.addAll(timings);
  }

  /// Feeds as many telegrams per frame as the rate requires.
  void _onTick(Duration elapsed) {
    if (_phase >= _phases.length) return;
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    final phase = _phases[_phase];
    _carry += phase.rate * dt;
    while (_carry >= 1) {
      _carry -= 1;
      _tunnel.inject(_randomTelegram());
    }

    final inPhase = DateTime.now().difference(_phaseStart);
    if (!_measuring && inPhase >= _warmUp) {
      _measuring = true;
      _timings.clear();
    } else if (_measuring && inPhase >= _warmUp + _measure) {
      _report(phase);
      _phase++;
      if (_phase < _phases.length) {
        _startPhase();
      } else {
        _log('Fertig.');
      }
    }
  }

  Telegram _randomTelegram() {
    final g = _groups[_random.nextInt(_groups.length)];
    final dpt = g.dpt;
    final read = _random.nextDouble() < 0.08;
    final small = dpt == null || dpt.main <= 3;
    final encoded = dpt == null || small ? null : encodeForDpt(dpt, '${_random.nextInt(900) + 10}');
    final size = expectedSize(dpt ?? const Dpt(1, 1)) ?? 1;
    return Telegram(
      time: DateTime.now(),
      source: 0x1100 | _random.nextInt(60),
      destination: g.address,
      type: read ? TelegramType.read : (_random.nextDouble() < 0.1 ? TelegramType.response : TelegramType.write),
      data: Uint8List.fromList(
        small ? [_random.nextInt(2)] : (encoded?.data ?? List.generate(size, (_) => _random.nextInt(256))),
      ),
      isSmall: small,
      repeated: _random.nextDouble() < 0.02,
    );
  }

  void _report(_Phase phase) {
    double pct(List<double> v, double p) => v.isEmpty ? 0 : v[((v.length - 1) * p).round()];
    final build = _timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()..sort();
    final raster = _timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()..sort();
    final hz = PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 60;
    final budget = 1000 / hz;
    final janky = _timings
        .where((t) => t.buildDuration.inMicroseconds / 1000 > budget || t.rasterDuration.inMicroseconds / 1000 > budget)
        .length;
    final avg = build.isEmpty ? 0 : build.reduce((a, b) => a + b) / build.length;
    final fps = _timings.length / _measure.inSeconds;
    String f(double v) => v.toStringAsFixed(1).padLeft(5);
    _log(
      '${phase.label} | ${fps.toStringAsFixed(0).padLeft(3)} fps | Build Ø${f(avg.toDouble())} p90${f(pct(build, .9))} '
      'p99${f(pct(build, .99))} | Raster p90${f(pct(raster, .9))} p99${f(pct(raster, .99))} ms | '
      'über Budget ${(janky * 100 / math.max(1, _timings.length)).toStringAsFixed(1)} %',
    );
  }

  @override
  Widget build(BuildContext context) {
    final phase = _phase < _phases.length ? _phases[_phase] : null;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Stack(
          children: [
            MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: !(phase?.animations ?? true)),
              child: MonitorScreen(key: ObjectKey(_tunnel), tunnel: _tunnel, initialTab: phase?.tab ?? LogTab.overview),
            ),
            // Show the results in the bottom right corner.
            Positioned(
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Container(
                  width: 560,
                  padding: const EdgeInsets.all(10),
                  color: Colors.black.withValues(alpha: 0.78),
                  child: Text(
                    [
                      if (phase != null) '▶ ${phase.label}${_measuring ? '  (misst)' : '  (Einschwingen)'}',
                      ..._results.reversed.take(18).toList().reversed,
                    ].join('\n'),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Menlo', height: 1.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
