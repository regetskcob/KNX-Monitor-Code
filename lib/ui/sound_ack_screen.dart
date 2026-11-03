import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart';
import '../model/plan.dart';
import '../model/sound_ack.dart';
import '../platform/native_bridge.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'figure_box.dart';
import 'plan_screen.dart';
import 'telegram_row.dart' show formatTime;

/// Turns the sound acknowledgement for [target] on or off (device sheet,
/// address details, topology). Pro.
Future<void> toggleSoundAck(BuildContext context, AckTarget target) async {
  final ack = SoundAck.instance;
  if (ack.target == target) return ack.stop();
  if (!await unlock(context, Feature.soundAck) || !context.mounted) return;
  if (!await confirmAckSound(context) || !context.mounted) return;
  ack.start(target);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${s.ackTitle}: ${target.describe()}')));
}

/// Test tone before the first sound acknowledgement of a session: anyone who
/// walks off with the device in their pocket should know beforehand that they
/// will hear something. The app deliberately does not check the mute switch and
/// volume itself; it simply asks. Returns whether to start.
Future<bool> confirmAckSound(BuildContext context) async {
  if (_ackSoundHeard) return true;
  NativeBridge.ackSound(AckSound.write);
  final ok = await showAdaptiveDialog<bool>(context: context, builder: (_) => const _AckSoundTest()) ?? false;
  if (ok) _ackSoundHeard = true;
  return ok;
}

bool _ackSoundHeard = false;

class _AckSoundTest extends StatefulWidget {
  const _AckSoundTest();

  @override
  State<_AckSoundTest> createState() => _AckSoundTestState();
}

class _AckSoundTestState extends State<_AckSoundTest> {
  bool _notHeard = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(s.ackTestTitle),
      content: Text(_notHeard ? s.ackTestNotHeard : s.ackTestText),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(s.commonCancel)),
        TextButton(
          onPressed: () {
            NativeBridge.ackSound(AckSound.write);
            setState(() => _notHeard = true);
          },
          child: Text(_notHeard ? s.ackTestAgain : s.ackTestNo),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(s.ackTestYes)),
      ],
    );
  }
}

/// "Klangquittung" (sound acknowledgement) button for [target]: highlighted while it runs.
class SoundAckButton extends StatelessWidget {
  const SoundAckButton({super.key, required this.target});

  final AckTarget target;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return ListenableBuilder(
      listenable: SoundAck.instance,
      builder: (context, _) {
        final on = SoundAck.instance.target == target;
        return IconButton(
          tooltip: on ? s.ackStop : s.ackTitle,
          isSelected: on,
          onPressed: () => toggleSoundAck(context, target),
          icon: Icon(AppIcons.ack, color: on ? hz.accentText : hz.textMuted),
        );
      },
    );
  }
}

/// Whose telegrams become audible; selection on the screen.
enum _Kind { checklist, line, device, group }

/// Sound acknowledgement (Pro): choose a target, start, press push buttons and listen.
class SoundAckScreen extends StatefulWidget {
  const SoundAckScreen({super.key});

  @override
  State<SoundAckScreen> createState() => _SoundAckScreenState();
}

class _SoundAckScreenState extends State<SoundAckScreen> {
  final _ack = SoundAck.instance;
  final _address = TextEditingController();
  _Kind _kind = Commissioning.instance.items.isEmpty ? _Kind.line : _Kind.checklist;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  /// Line "1.1" (area.line) from the input.
  static AckLine? _parseLine(String text) {
    final m = RegExp(r'^\s*(\d{1,2})\.(\d{1,2})\s*$').firstMatch(text);
    if (m == null) return null;
    final area = int.parse(m[1]!);
    final line = int.parse(m[2]!);
    return area > 15 || line > 15 ? null : AckLine(area, line);
  }

  AckTarget? _target() => switch (_kind) {
    _Kind.checklist => const AckChecklist(),
    _Kind.line => _parseLine(_address.text),
    _Kind.device => switch (parseIndividual(_address.text.trim())) {
      final a? => AckDevice(a),
      null => null,
    },
    _Kind.group => switch (parseGroup(_address.text.trim())) {
      final a? => AckGroup(a),
      null => null,
    },
  };

  Future<void> _start() async {
    final target = _target();
    if (target == null) {
      setState(() => _error = s.ackInvalid);
      return;
    }
    setState(() => _error = null);
    if (!await confirmAckSound(context) || !mounted) return;
    _ack.start(target);
  }

  String get _hint => switch (_kind) {
    _Kind.checklist => '',
    _Kind.line => '1.1',
    _Kind.device => '1.1.12',
    _Kind.group => '1/2/3',
  };

  /// What works in the background, honestly per platform.
  String get _platformNote {
    if (kIsWeb) return s.ackForegroundOnly;
    if (Platform.isAndroid) return s.ackAndroidBackground;
    if (Platform.isIOS) return s.ackIosForeground;
    return s.ackForegroundOnly;
  }

  /// Target selection: segments, chips that wrap with large text; the narrow
  /// segments would otherwise break words in the middle ("Devic-e").
  Widget _kindPicker(BuildContext context, {required bool hasChecklist}) {
    final options = [
      if (hasChecklist) (_Kind.checklist, s.ackKindChecklist),
      (_Kind.line, s.ackKindLine),
      (_Kind.device, s.ackKindDevice),
      (_Kind.group, s.ackKindGroup),
    ];
    final selected = !hasChecklist && _kind == _Kind.checklist ? _Kind.line : _kind;
    void choose(_Kind k) => setState(() {
      _kind = k;
      _error = null;
    });
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return Wrap(
        spacing: HzSpace.s8,
        runSpacing: HzSpace.s8,
        children: [
          for (final (k, label) in options)
            ChoiceChip(label: Text(label), selected: k == selected, onSelected: (_) => choose(k)),
        ],
      );
    }
    return FilterBar<_Kind>(
      segments: [for (final (k, label) in options) ButtonSegment(value: k, label: Text(label))],
      selected: selected,
      onChanged: choose,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasChecklist = Commissioning.instance.items.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.ackTitle),
        actions: [InfoAction(title: s.ackTitle, text: '${s.ackExplain}\n\n${s.ackSoundsExplain}\n\n$_platformNote')],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListenableBuilder(
            listenable: _ack,
            builder: (context, _) {
              final target = _ack.target;
              return ListView(
                padding: Gap.page,
                children: [
                  if (target != null || _ack.count > 0) ...[
                    FigureBox(
                      above: target == null
                          ? null
                          : Text(
                              '${s.ackRunning}: ${target.describe()}',
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                      figures: [
                        (label: s.ackSounds, value: formatInt(_ack.count), status: null),
                        if (_ack.recent.firstOrNull case final last?)
                          (label: s.ackLast, value: formatGroup(last.destination), status: null),
                      ],
                    ),
                    const SizedBox(height: Gap.item),
                  ],
                  if (target != null)
                    FilledButton(onPressed: _ack.stop, child: Text(s.ackStop))
                  else ...[
                    _kindPicker(context, hasChecklist: hasChecklist),
                    if (_kind != _Kind.checklist) ...[
                      const SizedBox(height: Gap.item),
                      TextField(
                        controller: _address,
                        style: context.mono(context.hzTheme.field),
                        decoration: InputDecoration(hintText: '${s.ackAddress}, z. B. $_hint', errorText: _error),
                        keyboardType: TextInputType.text,
                        autocorrect: false,
                        onSubmitted: (_) => _start(),
                      ),
                    ],
                    const SizedBox(height: Gap.item),
                    FilledButton(onPressed: _start, child: Text(s.ackStart)),
                  ],
                  if (_ack.recent.isNotEmpty) ...[
                    SectionHead(s.ackHeard, count: _ack.recent.length),
                    RowCard(
                      flat: true,
                      children: [
                        for (final t in _ack.recent)
                          CardRow(
                            address: formatGroup(t.destination),
                            title: CatalogStore.instance.info(t.destination)?.name ?? '',
                            meta: [
                              formatTime(t.time, millis: false),
                              [formatIndividual(t.source), ?CatalogStore.instance.device(t.source)?.name].join(' '),
                            ].join(metaSeparator),
                            trailing: Text(
                              CatalogStore.instance.value(t),
                              style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
