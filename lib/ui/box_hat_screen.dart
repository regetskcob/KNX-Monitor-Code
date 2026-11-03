import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Tests the box's KNX HAT (Weinzierl kBerry on GPIO 14/15): the server runs
/// the steps (`/api/box/hat`), the page shows progress and result and copies
/// the report for analysis. See docs/kberry.md.
class BoxHatScreen extends StatefulWidget {
  const BoxHatScreen({super.key});

  @override
  State<BoxHatScreen> createState() => _BoxHatScreenState();
}

class _BoxHatScreenState extends State<BoxHatScreen> {
  Map<String, Object?>? _status;
  String? _error;
  int _seconds = 10;
  Timer? _poll;

  bool get _running => _status?['running'] == true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await Addon.hatStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    _poll?.cancel();
    if (mounted && _running) _poll = Timer(const Duration(seconds: 1), () => unawaited(_load()));
  }

  Future<void> _start() async {
    try {
      await Addon.startHatProbe(_seconds);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _load();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: const JsonEncoder.withIndent('  ').convert(_status)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.boxHatCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    final system = (_status?['system'] as Map?)?.cast<String, Object?>();
    final report = (_status?['report'] as Map?)?.cast<String, Object?>();
    final steps = [for (final step in (report?['steps'] as List?) ?? const []) (step as Map).cast<String, Object?>()];
    return Scaffold(
      appBar: AppBar(title: Text(s.boxHatTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView(
              padding: Gap.page,
              children: [
                Text(s.boxHatIntro, style: muted),
                if (_error case final error?) ...[
                  const SizedBox(height: Gap.section),
                  HorizontStatusLine(HorizontStatus.critical, error),
                ],
                const SizedBox(height: Gap.section),
                Kennung(s.boxHatSystem),
                const SizedBox(height: Gap.item),
                if (system != null) ..._systemLines(system),
                const SizedBox(height: Gap.section),
                Kennung(s.boxHatSeconds),
                const SizedBox(height: Gap.item),
                SegmentedButton<int>(
                  segments: [
                    for (final v in const [5, 10, 30]) ButtonSegment(value: v, label: Text('$v s')),
                  ],
                  selected: {_seconds},
                  onSelectionChanged: _running ? null : (v) => setState(() => _seconds = v.first),
                ),
                const SizedBox(height: Gap.inner),
                Wrap(
                  spacing: Gap.inner,
                  runSpacing: Gap.item,
                  children: [
                    FilledButton(onPressed: _status == null || _running ? null : _start, child: Text(s.boxHatStart)),
                    if (report != null) OutlinedButton(onPressed: _copy, child: Text(s.boxHatCopy)),
                  ],
                ),
                if (_running) ...[
                  const SizedBox(height: Gap.inner),
                  HorizontStatusLine(
                    HorizontStatus.info,
                    s.boxHatRunning(_stepLabel(_status?['step'] as String? ?? 'reset')),
                  ),
                ],
                const SizedBox(height: Gap.section),
                Kennung(s.boxHatResult),
                const SizedBox(height: Gap.item),
                if (report == null)
                  Text(s.boxHatNoReport, style: muted)
                else if (report['error'] case final String error)
                  HorizontStatusLine(HorizontStatus.critical, error)
                else
                  for (final step in steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: HzSpace.s4),
                      child: HorizontStatusLine(
                        _statusOf(step['status']),
                        [_stepLabel(step['id'] as String? ?? ''), ?_detail(step)].join(': '),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _systemLines(Map<String, Object?> system) {
    final device = system['device'] as String? ?? '/dev/ttyAMA0';
    final access = system['access'] as String?;
    final lines = <Widget>[
      if (system['present'] != true)
        HorizontStatusLine(HorizontStatus.critical, s.boxHatDeviceMissing(device))
      else if (access != 'ok')
        HorizontStatusLine(HorizontStatus.critical, s.boxHatDeviceNoAccess(device, access ?? ''))
      else
        HorizontStatusLine(HorizontStatus.positive, s.boxHatSystemOk(device)),
      if (system['serialConsole'] == true) HorizontStatusLine(HorizontStatus.warning, s.boxHatSerialConsole),
    ];
    final details = [
      ?system['model'] as String?,
      ...[for (final o in (system['overlays'] as List?) ?? const []) '$o'],
    ];
    return [
      for (final line in lines)
        Padding(
          padding: const EdgeInsets.only(bottom: HzSpace.s4),
          child: line,
        ),
      if (details.isNotEmpty)
        Text(details.join(' · '), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
    ];
  }

  static HorizontStatus _statusOf(Object? status) => switch (status) {
    'ok' => HorizontStatus.positive,
    'warn' => HorizontStatus.warning,
    'fail' => HorizontStatus.critical,
    _ => HorizontStatus.info,
  };

  static String _stepLabel(String id) => switch (id) {
    'reset' => s.boxHatStepReset,
    'identify' => s.boxHatStepIdentify,
    'serial' => s.boxHatStepSerial,
    'modes' => s.boxHatStepModes,
    'commMode' => s.boxHatStepCommMode,
    'linkLayer' => s.boxHatStepLinkLayer,
    'busmonitor' => s.boxHatStepBusmonitor,
    'restore' => s.boxHatStepRestore,
    _ => id,
  };

  static String _hex(int value) => '0x${value.toRadixString(16).padLeft(2, '0').toUpperCase()}';

  /// Short finding per step from the raw values of the report.
  static String? _detail(Map<String, Object?> step) {
    if (step['status'] == 'skip') return s.boxHatSkipped;
    if (step['error'] case final String error) return error;
    int count(String key) => (step[key] as num?)?.toInt() ?? 0;
    switch (step['id']) {
      case 'reset':
        return step['baud'] is num ? s.boxHatBaud(count('baud')) : s.boxHatNoAnswer;
      case 'identify':
        return step['response'] as String? ?? s.boxHatNoAnswer;
      case 'serial':
        return step['serial'] as String? ?? s.boxHatNoAnswer;
      case 'modes':
        if (step['mask'] is! num) return s.boxHatNoAnswer;
        final modes = [
          if (step['linkLayer'] == true) s.boxHatModeLinkLayer,
          if (step['busmonitor'] == true) s.boxHatModeBusmonitor else s.boxHatNoBusmonitor,
          if (step['transportLayer'] == true) s.boxHatModeTransportLayer,
        ];
        return '${modes.join(', ')} (${_hex(count('mask'))})';
      case 'commMode':
        if (step['mode'] is! num) return s.boxHatNoAnswer;
        final mode = count('mode');
        final name = switch (mode) {
          0x00 => s.boxHatModeLinkLayer,
          0x01 => s.boxHatModeBusmonitor,
          0xF0 => 'BAOS',
          _ => null,
        };
        return [_hex(mode), ?name].join(' ');
      case 'linkLayer':
        return count('frames') == 0 ? s.boxHatNothing : s.boxHatFrames(count('frames'), count('seconds'));
      case 'busmonitor':
        if (count('frames') == 0) return s.boxHatNothing;
        return s.boxHatBusmonCounts(
          count('frames'),
          count('ack'),
          count('nak'),
          count('busy') + count('nakBusy'),
          count('repeated'),
          count('errors'),
        );
    }
    return null;
  }
}
