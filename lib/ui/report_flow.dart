import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../model/handover.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'annotations.dart';
import 'handover_screen.dart';
import 'recording_timeline.dart';
import 'support_package_screen.dart';
import 'telegram_row.dart';
import 'common.dart';

/// "Fehler melden" (report a fault), guided and without jargon: press start,
/// reproduce the fault and tap "Jetzt ist es passiert" (it just happened) each
/// time it occurs, then describe it and send the package to the electrician.
/// The marks are installation comments and so also end up in the diagnostics package.
class ReportFlowScreen extends StatefulWidget {
  const ReportFlowScreen({super.key, required this.log, required this.session, this.tunnel, this.origin});

  /// Installation from a handover package: the report goes to the company as a
  /// file, not to support as a diagnostics package.
  final HandoverOrigin? origin;

  final TelegramLog log;

  /// All telegrams of the session (the monitor's list is truncated).
  final List<Telegram> session;
  final KnxTunnel? tunnel;

  @override
  State<ReportFlowScreen> createState() => _ReportFlowScreenState();
}

class _ReportFlowScreenState extends State<ReportFlowScreen> {
  DateTime? _since;
  final _marks = <Annotation>[];
  Timer? _tick;

  int get _count => _since == null ? 0 : widget.session.where((t) => !t.time.isBefore(_since!)).length;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _since = DateTime.now());
    // Counter and clock run visibly.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  Future<void> _now() async {
    final a = Annotation(id: Annotation.newId(), time: DateTime.now(), note: s.reportMarkNote(_marks.length + 1));
    await AnnotationStore.instance.add(a);
    setState(() => _marks.add(a));
  }

  Future<void> _edit(Annotation a) async {
    await editAnnotation(context, a);
    final current = AnnotationStore.instance.all.where((x) => x.id == a.id).firstOrNull;
    setState(() {
      final i = _marks.indexWhere((x) => x.id == a.id);
      if (i < 0) return;
      if (current == null) {
        _marks.removeAt(i);
      } else {
        _marks[i] = current;
      }
    });
  }

  Future<void> _finish() async {
    _tick?.cancel();
    final navigator = Navigator.of(context);
    if (widget.origin case final origin?) {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => FaultReportSendScreen(
            origin: origin,
            session: widget.session,
            since: _since ?? DateTime.now(),
            tunnel: widget.tunnel,
            log: widget.log,
          ),
        ),
      );
      if (mounted) navigator.pop();
      return;
    }
    await showSupportPackage(
      context,
      tunnel: widget.tunnel,
      log: widget.log,
      session: widget.session,
      occurred: _marks.lastOrNull?.time ?? DateTime.now(),
      since: _since,
    );
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted);
    final since = _since;
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Gap.gutterFor(width);
    final side = gutter + ((width - 2 * gutter - Widths.reading) / 2).clamp(0, double.infinity);
    return Scaffold(
      appBar: AppBar(title: Text(s.reportTitle)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(side, Gap.page.top, side, Gap.page.bottom),
        children: [
          if (since == null) ...[
            Text(s.reportIntro, style: muted),
            const SizedBox(height: Gap.item),
            SectionCard(
              child: Column(
                spacing: HzSpace.s12,
                children: [
                  for (final (i, step) in [s.reportStep1, s.reportStep2, s.reportStep3].indexed)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: HzSpace.s12,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: hz.accentTint, shape: BoxShape.circle),
                          child: Text(
                            '${i + 1}',
                            style: context
                                .figures(theme.textTheme.bodyMedium)
                                .copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(child: Text(step)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: Gap.item),
            if (widget.tunnel?.state.value != TunnelState.connected)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.item),
                child: Text(s.reportNotConnected, style: TextStyle(color: hz.warning)),
              ),
            FilledButton(onPressed: _start, child: Text(s.reportStart)),
          ] else ...[
            Text(
              s.reportRunning(formatTime(since, millis: false), _count),
              style: context.figures(theme.textTheme.bodyMedium).copyWith(color: hz.textMuted),
            ),
            const SizedBox(height: Gap.section),
            Text(s.reportNowHint, style: theme.textTheme.bodyLarge),
            const SizedBox(height: Gap.section),
            // Big and impossible to miss: the one button that matters.
            SizedBox(
              height: 72,
              child: FilledButton.icon(
                onPressed: _now,
                style: FilledButton.styleFrom(backgroundColor: hz.warning, foregroundColor: hz.onCritical),
                icon: const Icon(AppIcons.annotationSet, size: 28),
                label: Text(s.reportNow, style: theme.textTheme.titleMedium?.copyWith(color: hz.onCritical)),
              ),
            ),
            const SizedBox(height: Gap.section),
            if (_marks.isEmpty)
              Text(s.reportNoMarks, style: muted)
            else ...[
              SectionTitle(s.reportMarks(_marks.length)),
              Text(s.reportMarksHint, style: muted),
              for (final a in _marks) AnnotationTile(annotation: a, onTap: () => _edit(a), onEdit: () => _edit(a)),
            ],
            const SizedBox(height: Gap.section * 2),
            OutlinedButton.icon(onPressed: _finish, icon: const Icon(AppIcons.report), label: Text(s.reportFinish)),
          ],
        ],
      ),
    );
  }
}
