import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/active_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/channel_control.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'figure_box.dart';
import 'live_updates.dart';
import 'operate_mode.dart';

/// Rooms: everything the project lets you switch, by room, with its state and
/// a check of why a display may show the wrong one (command against status
/// feedback, and whether the feedback answers a read request). A test page in
/// the project's own names, not a visualization.
class RoomControlScreen extends StatefulWidget {
  const RoomControlScreen({super.key, required this.log});

  final TelegramLog log;

  @override
  State<RoomControlScreen> createState() => _RoomControlScreenState();
}

class _RoomControlScreenState extends State<RoomControlScreen> {
  late final _rooms = roomControls(CatalogStore.instance.catalog);
  late final Listenable _updates = liveUpdates(widget.log);

  /// Feedback addresses that did not answer the last read round.
  final _unanswered = <int>{};
  bool _reading = false;
  int _read = 0;

  @override
  void initState() {
    super.initState();
    operateResult.value = null;
  }

  KnxTunnel? get _tunnel => switch (activeTunnel.value) {
    final t? when t.state.value == TunnelState.connected => t,
    _ => null,
  };

  List<RoomControl> get _all => [for (final r in _rooms.values) ...r];

  /// Reads every status feedback once, one after another, and notes which stay silent.
  Future<void> _readAll() async {
    final tunnel = _tunnel;
    if (tunnel == null || _reading) return;
    final addresses = {for (final c in _all) ?c.control.status};
    setState(() {
      _reading = true;
      _read = 0;
      _unanswered.clear();
    });
    for (final a in addresses) {
      if (!mounted) return;
      final answer = awaitAnswer(widget.log, a);
      final sent = await tunnel.read(a) == true;
      if (!(sent && await answer)) _unanswered.add(a);
      if (mounted) setState(() => _read++);
      // Leave the bus room between the requests.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    if (mounted) setState(() => _reading = false);
  }

  static String _findingText(StatusFinding f) => switch (f) {
    StatusFinding.ok => s.roomsStatusOk,
    StatusFinding.unknown => s.roomsStatusUnknown,
    StatusFinding.noStatus => s.roomsStatusNone,
    StatusFinding.mismatch => s.roomsStatusMismatch,
    StatusFinding.silent => s.roomsStatusSilent,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.roomsTitle),
        actions: [InfoAction(title: s.roomsTitle, text: s.roomsExplain)],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_updates, operateResult, activeTunnel]),
        builder: (context, _) {
          final latest = widget.log.latest;
          final all = _all;
          final issues = all.where((c) => statusFinding(c.control, latest, unanswered: _unanswered).issue).length;
          final statusCount = {for (final c in all) ?c.control.status}.length;
          final result = operateResult.value;
          return LayoutBuilder(
            builder: (context, box) {
              final columns = (box.maxWidth >= 1200 ? 3 : (box.maxWidth >= Breakpoints.expanded ? 2 : 1)).clamp(
                1,
                _rooms.isEmpty ? 1 : _rooms.length,
              );
              final names = _rooms.keys.toList();
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: columns > 1 ? Widths.wide : Widths.reading),
                  child: ListView(
                    padding: Gap.page,
                    children: [
                      FigureBox(
                        figures: [
                          (label: s.roomsCount, value: formatInt(_rooms.length), status: null),
                          (label: s.roomsControls, value: formatInt(all.length), status: null),
                          (
                            label: s.roomsIssues,
                            value: formatInt(issues),
                            status: issues > 0 ? HorizontStatus.warning : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.item),
                      if (all.isEmpty)
                        Text(s.roomsNone, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
                      else ...[
                        Wrap(
                          spacing: HzSpace.s12,
                          runSpacing: HzSpace.s8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton(
                              onPressed: _tunnel == null || _reading || statusCount == 0 ? null : _readAll,
                              child: Text(_reading ? s.roomsReading(_read, statusCount) : s.roomsReadStatus),
                            ),
                            if (_tunnel == null)
                              Text(s.operateOffline, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted))
                            else if (result != null)
                              Semantics(liveRegion: true, child: HorizontBadge(result.$2, label: result.$1)),
                          ],
                        ),
                        const SizedBox(height: Gap.item),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: Gap.section,
                          children: [
                            for (var c = 0; c < columns; c++)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = c; i < names.length; i += columns) _room(context, names[i], latest),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
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

  Widget _room(BuildContext context, String name, Map<int, Telegram> latest) {
    final controls = _rooms[name]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(name.isEmpty ? s.roomsNoRoom : name, count: controls.length),
        RowCard(children: [for (final c in controls) _row(context, c, latest)]),
      ],
    );
  }

  Widget _row(BuildContext context, RoomControl c, Map<int, Telegram> latest) {
    final online = _tunnel != null;
    final finding = statusFinding(c.control, latest, unanswered: _unanswered);
    final on = isOn(c.control, latest);
    void operate() => unawaited(operateChannel(context, c.channel, widget.log, name: c.title));
    return CardRow(
      title: c.title,
      meta: [
        formatGroup(c.control.address),
        if (c.control.kind == ControlKind.toggle) _findingText(finding),
      ].join(metaSeparator),
      chevron: false,
      trailing: switch (c.control.kind) {
        ControlKind.toggle => Switch.adaptive(value: on ?? false, onChanged: online ? (_) => operate() : null),
        ControlKind.blind => OutlinedButton(onPressed: online ? operate : null, child: Text(s.roomsMove)),
      },
    );
  }
}
