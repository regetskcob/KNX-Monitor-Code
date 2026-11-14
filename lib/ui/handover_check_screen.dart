import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/secure/keyring_store.dart';
import '../l10n/locale_controller.dart';
import '../model/handover_check.dart';
import '../knx/telegram.dart';
import '../model/analysis.dart' show expectedSize;
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'tool_shell.dart';

/// Opens the handover checklist; [log] lets it compare the project with the bus.
Future<void> openHandoverCheck(BuildContext context, {TelegramLog? log}) =>
    pushTool<void>(context, (_) => HandoverCheckScreen(log: log));

/// Handover checklist for owners and builders: what the electrician has to hand
/// over, what is already there (the app sees some of it itself), and a message
/// that asks for the rest.
class HandoverCheckScreen extends StatefulWidget {
  const HandoverCheckScreen({super.key, this.log});

  final TelegramLog? log;

  @override
  State<HandoverCheckScreen> createState() => _HandoverCheckScreenState();
}

class _HandoverCheckScreenState extends State<HandoverCheckScreen> {
  final _store = HandoverCheckStore.instance;
  late HandoverEvidence _evidence = _look();

  /// New traffic changes what the app sees; not per telegram.
  late final _timer = Timer.periodic(const Duration(seconds: 5), (_) {
    if (mounted) setState(() => _evidence = _look());
  });

  @override
  void initState() {
    super.initState();
    if (widget.log != null) _timer;
    unawaited(_store.load());
  }

  @override
  void dispose() {
    if (widget.log != null) _timer.cancel();
    super.dispose();
  }

  HandoverEvidence _look() {
    final project = CatalogStore.instance.project;
    final keys = KeyringStore.instance;
    final log = widget.log;
    // Against the imported project alone: what was learned or corrected in the app is not part
    // of the file the electrician handed over.
    var heard = 0, unknown = 0, mismatched = 0;
    if (log != null && !project.isEmpty) {
      for (final t in log.latest.values) {
        if (t.outgoing) continue;
        heard++;
        final info = project[t.destination];
        if (info == null) {
          unknown++;
        } else if (info.dpt case final dpt? when t.type != TelegramType.read) {
          final expected = expectedSize(dpt);
          if (expected != null && expected != (t.isSmall ? 0 : t.data.length)) mismatched++;
        }
      }
    }
    return HandoverEvidence(
      projectDevices: project.devices.length,
      projectGroups: project.groups.length,
      keyring: keys.project != null || keys.tunnels.isNotEmpty,
      heard: heard,
      unknown: unknown,
      mismatched: mismatched,
    );
  }

  static String _title(HandoverItem i) => switch (i) {
    HandoverItem.projectFile => s.hocProjectFile,
    HandoverItem.projectCurrent => s.hocProjectCurrent,
    HandoverItem.keyring => s.hocKeyring,
    HandoverItem.devicePasswords => s.hocDevicePasswords,
    HandoverItem.gatewayAccess => s.hocGatewayAccess,
    HandoverItem.visuAccess => s.hocVisuAccess,
    HandoverItem.circuitPlan => s.hocCircuitPlan,
    HandoverItem.deviceList => s.hocDeviceList,
    HandoverItem.instruction => s.hocInstruction,
  };

  static String _why(HandoverItem i) => switch (i) {
    HandoverItem.projectFile => s.hocProjectFileWhy,
    HandoverItem.projectCurrent => s.hocProjectCurrentWhy,
    HandoverItem.keyring => s.hocKeyringWhy,
    HandoverItem.devicePasswords => s.hocDevicePasswordsWhy,
    HandoverItem.gatewayAccess => s.hocGatewayAccessWhy,
    HandoverItem.visuAccess => s.hocVisuAccessWhy,
    HandoverItem.circuitPlan => s.hocCircuitPlanWhy,
    HandoverItem.deviceList => s.hocDeviceListWhy,
    HandoverItem.instruction => s.hocInstructionWhy,
  };

  /// What the app noticed about [item] by itself, if anything.
  String? _seen(HandoverItem item) {
    final e = _evidence;
    return switch (item) {
      HandoverItem.projectFile when e.hasProjectFile => s.hocSeenProject(e.projectDevices, e.projectGroups),
      HandoverItem.projectFile when e.projectGroups > 0 => s.hocSeenCsv,
      HandoverItem.projectCurrent when e.projectFits == true => s.hocSeenFits(e.heard),
      HandoverItem.projectCurrent when e.projectFits == false => s.hocSeenStale(e.unknown + e.mismatched),
      HandoverItem.projectCurrent when e.hasProjectFile => s.hocSeenNotYet,
      HandoverItem.keyring when e.keyring => s.hocSeenKeyring,
      _ => null,
    };
  }

  /// The message that asks the electrician for what is still missing.
  String _message(List<HandoverItem> missing) =>
      [s.hocMessageIntro, '', for (final i in missing) '- ${_title(i)}', '', s.hocMessageOutro].join('\n');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.hocTitle),
        actions: [InfoAction(title: s.hocTitle, text: s.hocExplain)],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_store, CatalogStore.instance]),
        builder: (context, _) {
          _evidence = _look();
          final check = _store.check;
          final missing = check.missing(_evidence);
          return LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= Breakpoints.expanded;
              final items = HandoverItem.values;
              final half = (items.length / 2).ceil();
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
                  child: ListView(
                    padding: Gap.page,
                    children: [
                      FigureBox(
                        figures: [
                          (label: s.hocDone, value: '${check.done(_evidence)}/${items.length}', status: null),
                          (
                            label: s.hocMissing,
                            value: formatInt(missing.length),
                            status: missing.isEmpty ? HorizontStatus.positive : HorizontStatus.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.item),
                      Text(s.hocIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                      const SizedBox(height: Gap.section),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: Gap.section,
                          children: [
                            for (final part in [items.take(half), items.skip(half)])
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  spacing: Gap.item,
                                  children: [for (final i in part) _item(context, i)],
                                ),
                              ),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: Gap.item,
                          children: [for (final i in items) _item(context, i)],
                        ),
                      const SizedBox(height: Gap.section),
                      if (missing.isEmpty)
                        Text(s.hocAllThere, style: theme.textTheme.titleMedium)
                      else
                        Builder(
                          builder: (context) => FilledButton(
                            onPressed: () => shareFile(
                              context,
                              Uint8List.fromList(utf8.encode(_message(missing))),
                              fileName(s.hocTitle, 'txt'),
                              'text/plain',
                              origin: rectOf(context),
                            ),
                            child: Text(s.hocAsk(missing.length)),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _item(BuildContext context, HandoverItem item) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final check = _store.check;
    final state = check.stateOf(item, _evidence);
    final detected = check.detected(item, _evidence);
    final seen = _seen(item);
    final stale = item == HandoverItem.projectCurrent && _evidence.projectFits == false;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: HzSpace.s8,
        children: [
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(_title(item), style: theme.textTheme.titleMedium),
              HorizontBadge(
                switch (state) {
                  HandoverState.received => HorizontStatus.positive,
                  HandoverState.notNeeded => HorizontStatus.neutral,
                  HandoverState.open => stale ? HorizontStatus.critical : HorizontStatus.warning,
                },
                label: switch (state) {
                  HandoverState.received => detected ? s.hocStateDetected : s.hocStateReceived,
                  HandoverState.notNeeded => s.hocStateNotNeeded,
                  HandoverState.open => s.hocStateOpen,
                },
              ),
            ],
          ),
          Text(_why(item), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          if (seen != null) Text(seen, style: theme.textTheme.bodySmall),
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s4,
            children: [
              for (final (value, label) in [
                (HandoverState.received, s.hocStateReceived),
                (HandoverState.notNeeded, s.hocStateNotNeeded),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: (check.states[item] ?? HandoverState.open) == value,
                  // Tapping the chosen one again opens the item.
                  onSelected: (on) => unawaited(_store.set(item, on ? value : HandoverState.open)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
