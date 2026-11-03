import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/busmon.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart';

/// Counter per sender in the bus monitor.
class SenderStats {
  int frames = 0;
  int repeated = 0;
  int unacked = 0;
  int negative = 0;

  int get problems => repeated + unacked + negative;
}

/// Bus load: current average, peak and history of the last 60 s.
/// Bars neutral, warning colour from 30 %; the value then also carries the
/// symbol.
class BusLoadCard extends StatelessWidget {
  const BusLoadCard({super.key, required this.load});

  final BusLoad load;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final history = load.history();
    final now = load.average();
    final peak = history.fold(0.0, (a, b) => a > b ? a : b);
    String pct(double v) => localizeDecimal((v * 100).toStringAsFixed(v < 0.1 ? 1 : 0));
    final status = now > 0.5 ? HorizontStatus.critical : (now > 0.3 ? HorizontStatus.warning : null);
    final big = theme.textTheme.headlineMedium;
    return SectionCard(
      title: s.busmonLoad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (status != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: HzSpace.s8),
                  child: Icon(status.icon, size: HzIconSize.row, color: status.color(hz)),
                ),
                const SizedBox(width: HzSpace.s4),
              ],
              Text(
                '${pct(now)} %',
                style: context
                    .figures(big)
                    .copyWith(fontWeight: FontWeight.w700, color: status?.color(hz) ?? hz.accentText),
              ),
              const SizedBox(width: Gap.inner),
              Padding(
                padding: const EdgeInsets.only(bottom: HzSpace.s8),
                child: Text(
                  s.busmonLoadPeak(pct(peak)),
                  style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.inner),
          SizedBox(
            height: HzSpace.s48 + HzSpace.s8,
            width: double.infinity,
            child: CustomPaint(
              painter: _LoadPainter(history, color: hz.textFaint, warn: hz.warning, idle: hz.line),
            ),
          ),
          const SizedBox(height: Gap.item),
          Text(s.busmonLoadHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
        ],
      ),
    );
  }
}

class _LoadPainter extends CustomPainter {
  _LoadPainter(this.values, {required this.color, required this.warn, required this.idle});

  final List<double> values;
  final Color color;
  final Color warn;
  final Color idle;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    // Scale up to at least 20 % so quiet traffic doesn't look exaggerated.
    final top = values.fold(0.2, (a, b) => a > b ? a : b);
    final slot = size.width / values.length;
    final bar = (slot * 0.66).clamp(1.5, 6.0);
    // Flat bars without gradient and without rounding.
    for (final (i, v) in values.indexed) {
      final h = v == 0 ? 2.0 : 3 + (size.height - 3) * (v / top);
      final x = i * slot + (slot - bar) / 2;
      canvas.drawRect(
        Rect.fromLTRB(x, size.height - h, x + bar, size.height),
        Paint()..color = v == 0 ? idle : (v > 0.3 ? warn : color),
      );
    }
    // 50 % line for orientation (hairline) when it is in view.
    if (top > 0.5) {
      final y = size.height - (size.height - 3) * (0.5 / top) - 3;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = warn
          ..strokeWidth = Lines.hairline,
      );
    }
  }

  @override
  bool shouldRepaint(_LoadPainter old) => true;
}

/// Senders, conspicuous ones first (repetitions, missing/negative
/// acknowledgements).
class SendersCard extends StatelessWidget {
  const SendersCard({super.key, required this.stats, this.selected, this.onFilter});

  final Map<int, SenderStats> stats;

  /// Sender the list is currently filtered by.
  final int? selected;

  /// Tapping a sender filters the list (tapping again: filter off).
  final ValueChanged<int>? onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final store = CatalogStore.instance;
    final sorted = stats.entries.toList()
      ..sort((a, b) {
        final p = b.value.problems.compareTo(a.value.problems);
        return p != 0 ? p : b.value.frames.compareTo(a.value.frames);
      });
    return SectionCard(
      title: s.busmonSenders,
      count: stats.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.busmonSendersHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          const SizedBox(height: Gap.item),
          for (final MapEntry(key: address, value: st) in sorted.take(8))
            Material(
              type: MaterialType.transparency,
              child: Ink(
                decoration: horizontSelectionDecoration(
                  hz,
                  selected: address == selected,
                  divider: BorderSide(color: hz.line, width: Lines.hairline),
                ),
                child: InkWell(
                  onTap: onFilter == null ? null : () => onFilter!(address),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(formatIndividual(address), style: data.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text(
                            store.device(address)?.name ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: Gap.item),
                        if (st.problems > 0) ...[
                          Icon(HorizontStatus.warning.icon, size: 14, color: hz.warning),
                          const SizedBox(width: HzSpace.s4),
                        ],
                        Text(
                          [
                            s.busmonSenderStats(st.frames),
                            if (st.repeated > 0) '${st.repeated}× ${s.busmonRepeated}',
                            if (st.unacked > 0) '${st.unacked}× ${s.busmonUnacked}',
                            if (st.negative > 0) '${st.negative}× NAK/BUSY',
                          ].join(' · '),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: st.problems > 0 ? hz.warning : hz.textMuted,
                            fontWeight: st.problems > 0 ? FontWeight.w700 : null,
                            fontFeatures: tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A frame broken down: control field, addresses, hop count, length, payload,
/// checksum, status and acknowledgement.
class BusmonFrameDetails extends StatelessWidget {
  const BusmonFrameDetails({super.key, required this.frame, this.ack, this.withoutAck = false});

  final BusmonFrame frame;
  final BusmonFrame? ack;
  final bool withoutAck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final f = frame;
    final store = CatalogStore.instance;
    final r = f.raw;
    String hx(int v) => '0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    final rows = <(String, String, bool)>[
      (s.columnTime, formatTime(f.time), false),
      if (f.timestamp != null) (s.busmonFieldTimestamp, '${f.timestamp} µs', false),
    ];
    if (f.kind == BusmonKind.data && r.length >= 8) {
      final t = f.telegram;
      final priority = switch ((r[0] >> 2) & 0x03) {
        0 => s.prioritySystem,
        1 => s.priorityNormal,
        2 => s.priorityUrgent,
        _ => s.priorityLow,
      };
      final length = r[5] & 0x0F;
      final end = 6 + length + 1;
      var xor = 0;
      for (var i = 0; i < end && i < r.length; i++) {
        xor ^= r[i];
      }
      final target = f.groupAddressed ? formatGroup(f.destination!) : formatIndividual(f.destination!);
      final targetName = f.groupAddressed ? store.info(f.destination!)?.name : store.device(f.destination!)?.name;
      rows.addAll([
        (s.busmonFieldControl, '${hx(r[0])} · $priority', false),
        (s.busmonFieldRepeat, f.repeated ? s.busmonYes : s.busmonNo, f.repeated),
        (s.busmonFieldSource, [formatIndividual(f.source!), ?store.device(f.source!)?.name].join('  '), false),
        (s.busmonFieldTarget, [target, ?targetName].join('  '), false),
        (s.busmonFieldHops, '${(r[5] >> 4) & 0x07}', false),
        (s.busmonFieldLength, '$length', false),
        if (r.length > 7) (s.busmonFieldPayload, hex(r.sublist(6, end.clamp(6, r.length))), false),
        if (t != null && t.type != TelegramType.read) (s.columnValue, store.value(t), false),
        (
          s.busmonFieldChecksum,
          f.checksumOk ? '${hx(r[end])} · ${s.busmonChecksumOk}' : s.busmonChecksumBad(hx(~xor & 0xFF)),
          !f.checksumOk,
        ),
      ]);
    }
    rows.addAll([
      (
        s.busmonFieldStatus,
        f.hasError && f.checksumOk ? '${hx(f.status)} · ${s.busmonStatusError}' : s.busmonStatusOk(f.status & 0x07),
        f.hasError && f.checksumOk,
      ),
      if (f.kind == BusmonKind.data)
        (
          s.busmonFieldAck,
          switch (ack?.kind) {
            BusmonKind.ack => 'ACK',
            BusmonKind.nak => 'NAK',
            BusmonKind.busy => 'BUSY',
            BusmonKind.nakBusy => 'NAK + BUSY',
            _ => withoutAck ? s.busmonUnacked : '—',
          },
          withoutAck || (ack?.isNegative ?? false),
        ),
      (s.busmonFieldRaw, hex(r), false),
    ]);
    // Table with hairlines, values in Monaspace; anything conspicuous with a
    // symbol.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value, warn) in rows)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: hz.line, width: Lines.hairline),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  ),
                  if (warn) ...[
                    Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                    const SizedBox(width: HzSpace.s4),
                  ],
                  Expanded(
                    child: SelectableText(
                      value,
                      style: data.copyWith(fontWeight: FontWeight.w600, color: warn ? hz.warning : null),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
