import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart';
import '../model/dali_labels.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate, formatTime;

/// Horizont status of a DALI state: colour and tint. The symbol comes from [daliStateIcon], the
/// word from [daliStateWord]; never colour alone.
HorizontStatus daliStatus(DaliState state) => switch (state) {
  DaliState.unknown => HorizontStatus.neutral,
  DaliState.ok => HorizontStatus.positive,
  DaliState.lampFault || DaliState.testFailed => HorizontStatus.critical,
  DaliState.converterFault || DaliState.gearFault => HorizontStatus.warning,
};

/// Symbol of a DALI state: check, cross (lamp), exclamation mark (control gear), triangle
/// (converter), octagon (emergency test failed), dot (nothing reported).
IconData daliStateIcon(DaliState state) => switch (state) {
  DaliState.unknown => HorizontSymbols.circle,
  DaliState.ok => HorizontSymbols.checkCircle,
  DaliState.lampFault => HorizontSymbols.close,
  DaliState.gearFault => HorizontSymbols.error,
  DaliState.converterFault => HorizontSymbols.warning,
  DaliState.testFailed => HorizontSymbols.report,
};

/// Word of a DALI state.
String daliStateWord(DaliState state) => switch (state) {
  DaliState.unknown => s.daliNoReport,
  DaliState.ok => s.daliOk,
  DaliState.lampFault => s.daliLampFault,
  DaliState.gearFault => s.daliGearFault,
  DaliState.converterFault => s.daliConverterFault,
  DaliState.testFailed => s.daliStateTestFailed,
};

/// State as a symbol in its colour; the word is the semantic label.
class DaliStateIcon extends StatelessWidget {
  const DaliStateIcon(this.state, {super.key, this.size = HzIconSize.row, this.excludeSemantics = false});

  final DaliState state;
  final double size;

  /// The row around it already says the state.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) => Icon(
    daliStateIcon(state),
    size: size,
    color: daliStatus(state).color(context.hz),
    semanticLabel: excludeSemantics ? null : daliStateWord(state),
  );
}

/// The letter that marks an emergency luminaire ("N").
class EmergencyMark extends StatelessWidget {
  const EmergencyMark({super.key, this.failed = false, this.size = 22});

  /// The last test failed: in the critical colour.
  final bool failed;
  final double size;

  @override
  Widget build(BuildContext context) => HorizontLetterBadge(
    s.daliEmergencyLetter,
    semanticLabel: failed ? '${s.daliEmergencyLuminaire}, ${s.daliStateTestFailed}' : s.daliEmergencyLuminaire,
    status: failed ? HorizontStatus.critical : HorizontStatus.neutral,
    outlined: !failed,
    size: size,
  );
}

/// Second line of a luminaire: "Lampenfehler · EVG 12 · G1", "Test durchgefallen · Adr. 16".
String daliGearMeta(DaliGear gear, {DaliState? state}) => [
  if (state == DaliState.testFailed) s.daliStateTestFailed else if (gear.faults != null) daliFaultsText(gear.faults!),
  if (gear.address case final a? when gear.name != null) gear.emergency ? s.daliAddressShort(a) : s.daliGearN(a),
  ?gear.room,
  if (gear.groups.isNotEmpty) (gear.groups.toList()..sort()).map((g) => 'G$g').join(' '),
].join(metaSeparator);

/// One cell of the grid of the 64 short addresses.
class DaliCell extends StatelessWidget {
  const DaliCell({
    super.key,
    required this.address,
    required this.gear,
    required this.selected,
    required this.dimmed,
    required this.onTap,
    this.state,
  });

  final int address;

  /// `null` = free address.
  final DaliGear? gear;

  /// What the cell shows ([DaliStore.overall]); the luminaire's reported state without it.
  final DaliState? state;
  final bool selected;

  /// Not in the selected group.
  final bool dimmed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final gear = this.gear;
    final number = Text(
      '$address',
      style: context.mono(theme.textTheme.labelSmall).copyWith(color: gear == null ? hz.textFaint : hz.textMuted),
    );
    if (gear == null) {
      return Semantics(
        container: true,
        label: s.daliCellFree(address),
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: Radii.tile,
              border: Border.all(color: hz.line, width: Lines.hairline),
            ),
            child: Center(child: number),
          ),
        ),
      );
    }
    final state = this.state ?? gear.state;
    final status = daliStatus(state);
    final attention = state.index > DaliState.ok.index;
    final label = [
      s.daliCellAddress(address),
      daliGearLabel(gear),
      if (gear.emergency) s.daliEmergencyLuminaire,
      daliStateWord(state),
    ].join(', ');
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: ExcludeSemantics(
          child: Material(
            color: state == DaliState.unknown ? hz.surface : status.tint(hz),
            shape: RoundedRectangleBorder(
              borderRadius: Radii.tile,
              side: BorderSide(
                color: selected
                    ? hz.text
                    : attention
                    ? status.color(hz)
                    : hz.line,
                width: selected ? Lines.selection : Lines.hairline,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(HzSpace.s2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: HzSpace.s2,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: HzSpace.s2,
                        children: [
                          if (gear.emergency)
                            Text(
                              s.daliEmergencyLetter,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: attention ? status.color(hz) : hz.text,
                              ),
                            ),
                          if (!gear.emergency || attention)
                            Icon(daliStateIcon(state), size: HzIconSize.inline, color: status.color(hz)),
                        ],
                      ),
                      number,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Legend below the grid: symbol and word per state.
class DaliLegend extends StatelessWidget {
  const DaliLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textMuted);
    Widget entry(Widget symbol, String word) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: HzSpace.s4,
      children: [
        ExcludeSemantics(child: symbol),
        Flexible(child: Text(word, style: style)),
      ],
    );
    return Wrap(
      spacing: HzSpace.s16,
      runSpacing: HzSpace.s8,
      children: [
        for (final state in const [
          DaliState.ok,
          DaliState.lampFault,
          DaliState.gearFault,
          DaliState.converterFault,
          DaliState.testFailed,
        ])
          entry(DaliStateIcon(state, size: HzIconSize.inline, excludeSemantics: true), daliStateWord(state)),
        entry(const EmergencyMark(size: 18), s.daliEmergencyLuminaire),
        entry(Icon(HorizontSymbols.circle, size: HzIconSize.inline, color: hz.textFaint), s.daliNoReport),
        entry(
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: Radii.row,
              border: Border.all(color: hz.line),
            ),
          ),
          s.daliFree,
        ),
      ],
    );
  }
}

/// Date and time of an event, short: today only the time, within a week relative ("gestern,
/// 12:04", "vor 3 Tagen, 12:04"), otherwise the date.
String daliWhen(DateTime t, DateTime now) {
  DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
  final days = day(now).difference(day(t)).inDays;
  final clock = formatTime(t, seconds: false);
  if (days <= 0) return clock;
  if (days == 1) return s.daliYesterdayAt(clock);
  if (days < 7) return s.daliDaysAgoAt(days, clock);
  return '${formatDate(t)} $clock';
}

/// Everything about one luminaire: name, room, groups, state, the last changes. In the wide
/// layout the panel on the right, on the phone the content of a sheet.
class DaliGearDetail extends StatelessWidget {
  const DaliGearDetail({
    super.key,
    required this.gear,
    required this.gateway,
    this.state,
    this.lastTests = const [],
    this.objectText,
    this.onEdit,
    this.onWatch,
    this.onClose,
    this.now,
  });

  final DaliGear gear;
  final DaliGateway gateway;

  /// What the luminaire shows ([DaliStore.overall]): a failed emergency test too.
  final DaliState? state;

  /// The current time (tests set it).
  final DateTime? now;

  /// Last results of the emergency tests from the gateway.
  final List<EmergencyTest> lastTests;

  /// Text of the ETS object the converter was found by (profiles may count differently).
  final String? objectText;
  final VoidCallback? onEdit;
  final VoidCallback? onWatch;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final now = this.now ?? DateTime.now();
    final state = this.state ?? gear.state;
    final status = daliStatus(state);
    final since = gear.since;
    final groups = gear.groups.toList()..sort();
    final eyebrow = [
      if (gear.address case final a?) s.daliCellAddress(a) else formatGroup(gear.anchor ?? 0),
      for (final g in groups) 'G$g',
    ].join(metaSeparator);
    final events = gear.events.reversed.toList();
    final failedTest = lastTests
        .where((e) => e.result == EmergencyResult.failed && e.kind != EmergencyTestKind.partial)
        .fold<EmergencyTest?>(null, (a, e) => a == null || e.time.isAfter(a.time) ? e : a);
    final stateText = switch (state) {
      DaliState.testFailed when failedTest != null => s.daliTestFailedAgo(
        daliTestKindText(failedTest.kind),
        failedTest.first ? s.daliAgeUnknown : daliAgo(failedTest.time, now),
      ),
      DaliState.unknown => daliStateText(gear),
      _ when since != null => '${daliStateText(gear)} ${daliSince(since, now)}',
      _ => daliStateText(gear),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                eyebrow.toUpperCase(),
                style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textMuted),
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                onPressed: onClose,
                icon: const Icon(HorizontSymbols.close),
              ),
          ],
        ),
        const SizedBox(height: HzSpace.s4),
        Row(
          spacing: HzSpace.s8,
          children: [
            if (gear.emergency) EmergencyMark(failed: state == DaliState.testFailed),
            Flexible(
              child: Text(
                daliGearLabel(gear),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: HzSpace.s4),
        Text(
          [
            if (gear.room case final room?) s.daliRoomIs(room),
            if (gear.address case final a? when gear.name != null)
              gear.emergency ? s.daliAddressShort(a) : s.daliGearN(a),
            s.daliGatewayAt(formatIndividual(gateway.address)),
          ].join(metaSeparator),
          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
        ),
        if (objectText case final text?) ...[
          const SizedBox(height: HzSpace.s2),
          Text(s.daliObjectText(text), style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
        ],
        const SizedBox(height: Gap.inner),
        // State on its tint, with symbol and words: a failed emergency test is never "in Ordnung".
        DecoratedBox(
          decoration: BoxDecoration(
            color: state == DaliState.unknown ? hz.sunken : status.tint(hz),
            borderRadius: Radii.tile,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Gap.inner),
            child: Row(
              spacing: HzSpace.s8,
              children: [
                DaliStateIcon(state, excludeSemantics: true),
                Expanded(
                  child: Text(
                    stateText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: state == DaliState.unknown ? hz.textMuted : status.color(hz),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (gear.emergency && (gear.mode != null || lastTests.isNotEmpty)) ...[
          const SizedBox(height: Gap.section),
          SectionTitle(s.daliEmergencyLuminaire),
          const SizedBox(height: HzSpace.s4),
          if (gear.mode case final mode?) _line(context, s.daliRowMode, daliModeText(mode)),
          for (final e in lastTests)
            _line(
              context,
              daliTestKindText(e.kind),
              [
                daliResultText(e.result),
                for (final r in e.reasons) daliReasonText(r),
                if (e.minutes case final m?) daliMinutesText(m),
                if (e.first) s.daliAgeUnknown else daliAgo(e.time, now),
              ].join(metaSeparator),
            ),
        ],
        if (gear.burnHours case final hours?) ...[
          const SizedBox(height: Gap.inner),
          _line(context, s.daliBurnHours, s.daliHours(hours)),
        ],
        const SizedBox(height: Gap.section),
        SectionTitle(s.daliHistory, count: events.isEmpty ? null : events.length),
        const SizedBox(height: HzSpace.s4),
        if (events.isEmpty)
          Text(s.daliNoReport, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
        else
          for (final (i, e) in events.indexed) ...[
            if (i > 0) const Divider(height: Lines.hairline),
            _line(context, daliWhen(e.time, now), daliFaultsText(e.faults)),
          ],
        if (gear.lastReport case final last?) ...[
          const SizedBox(height: HzSpace.s8),
          Text(s.daliLastReport(daliWhen(last, now)), style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
        ],
        if (onEdit != null || onWatch != null) ...[
          const SizedBox(height: Gap.section),
          if (onEdit != null) OutlinedButton(onPressed: onEdit, child: Text(s.daliEdit)),
          if (onWatch != null) ...[
            const SizedBox(height: HzSpace.s8),
            OutlinedButton(onPressed: onWatch, child: Text(s.daliWatchThis)),
          ],
        ],
      ],
    );
  }

  static Widget _line(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HzSpace.s12,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
          ),
          Expanded(flex: 3, child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// Edits what the gateway does not report on KNX: name, room, groups and whether the luminaire
/// is an emergency luminaire.
Future<void> editDaliGear(BuildContext context, DaliGear gear) async {
  final name = TextEditingController(text: gear.name ?? '');
  final room = TextEditingController(text: gear.room ?? '');
  var groups = {...gear.groups};
  var emergency = gear.emergency;
  final save = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: Text(gear.address == null ? s.daliEdit : '${s.daliEdit} · ${s.daliGearN(gear.address!)}'),
        content: SizedBox(
          width: Widths.form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: s.daliFieldName, counterText: ''),
                ),
                const SizedBox(height: Gap.inner),
                TextField(
                  controller: room,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: s.daliFieldRoom, counterText: ''),
                ),
                const SizedBox(height: Gap.section),
                Text(s.daliFieldGroups, style: Theme.of(dialog).textTheme.labelLarge),
                const SizedBox(height: HzSpace.s4),
                Text(
                  s.daliFieldGroupsHint,
                  style: Theme.of(dialog).textTheme.bodySmall?.copyWith(color: dialog.hz.textMuted),
                ),
                const SizedBox(height: HzSpace.s8),
                Wrap(
                  spacing: HzSpace.s4,
                  runSpacing: HzSpace.s4,
                  children: [
                    for (var g = 0; g < 16; g++)
                      FilterChip(
                        label: Text('G$g'),
                        tooltip: s.daliGroupN(g),
                        selected: groups.contains(g),
                        onSelected: (on) => setState(() => on ? groups.add(g) : groups.remove(g)),
                      ),
                  ],
                ),
                const SizedBox(height: Gap.inner),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.daliEmergencyLuminaire),
                  value: emergency,
                  onChanged: (v) => setState(() => emergency = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.commonSave)),
        ],
      ),
    ),
  );
  if (save == true) {
    DaliStore.instance.editGear(gear, name: name.text, room: room.text, groups: groups, emergency: emergency);
  }
  disposeAfterDialog(name);
  disposeAfterDialog(room);
}

/// Asks for a name (group, gateway). Returns `null` if cancelled, an empty text to remove it.
Future<String?> askDaliName(BuildContext context, {required String title, String? current}) async {
  final controller = TextEditingController(text: current ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: Widths.form,
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: s.daliFieldName, counterText: ''),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialog), child: Text(s.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(dialog, controller.text), child: Text(s.commonSave)),
      ],
    ),
  );
  disposeAfterDialog(controller);
  return result;
}
