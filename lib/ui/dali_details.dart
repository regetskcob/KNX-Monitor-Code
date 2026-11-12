import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:url_launcher/url_launcher.dart';

import '../catalog_store.dart';
import '../knx/dali.dart';
import '../knx/dali_text.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart' show DaliGear, DaliStore;
import '../model/dali_labels.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'dali_screen.dart';
import 'figure_box.dart';

/// Where gateway owners share telegrams that do not fit (issue #6).
const daliIssueUrl = 'https://github.com/regetskcob/KNX-Monitor/issues/6';

/// Section "DALI" of the telegram details: every flag of a telegram with a DALI type as a row
/// (set / not set) with the raw value, and the luminaire it is about. For a payload that does not
/// fit the type it says why the monitor shows hex. Nothing for other telegrams.
class DaliTelegramSection extends StatelessWidget {
  const DaliTelegramSection({super.key, required this.telegram});

  final Telegram telegram;

  @override
  Widget build(BuildContext context) {
    final t = telegram;
    final dpt = CatalogStore.instance.dptOf(t.destination);
    if (dpt == null || !isDaliDpt(dpt.main, dpt.sub) || t.type == TelegramType.read) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hz = context.hz;
    final rows = daliDetailRows(dpt, t);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: Gap.section),
        child: HorizontNotice(
          HorizontStatus.info,
          action: TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            onPressed: () => unawaited(launchUrl(Uri.parse(daliIssueUrl), mode: LaunchMode.externalApplication)),
            child: Text(s.daliIssueLink),
          ),
          child: Text('${daliMismatch(dpt, t) ?? ''} ${s.daliMismatchHint}'.trim()),
        ),
      );
    }
    final gear = _gear(dpt, t);
    final groups = gear == null ? const <int>[] : (gear.groups.toList()..sort());
    return Padding(
      padding: const EdgeInsets.only(top: Gap.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: SectionTitle('DALI$metaSeparator${s.daliDptShort('$dpt')}')),
              Text(
                '${s.daliRaw} ${hex(t.data)}',
                style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted),
              ),
            ],
          ),
          const SizedBox(height: HzSpace.s8),
          RowCard(
            children: [
              for (final r in rows)
                MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
                    child: Row(
                      spacing: HzSpace.s12,
                      children: [
                        Expanded(child: Text(r.label)),
                        if (r.flag case final flag?)
                          HorizontBadge(
                            flag && r.fault ? HorizontStatus.critical : HorizontStatus.neutral,
                            label: r.value,
                          )
                        else
                          Flexible(
                            child: Text(r.value, textAlign: TextAlign.end, style: theme.textTheme.bodyMedium),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (gear != null) ...[
            const SizedBox(height: Gap.inner),
            RowCard(
              children: [
                CardRow(
                  title: daliGearLabel(gear),
                  // A converter is no ECG: its short address as such.
                  value: switch (gear.address) {
                    final a? => gear.emergency ? s.daliAddressShort(a) : s.daliGearN(a),
                    null => null,
                  },
                  chevron: false,
                ),
                if (gear.room case final room?) CardRow(title: s.daliFieldRoom, value: room, chevron: false),
                if (groups.isNotEmpty)
                  CardRow(title: s.daliGroups, value: groups.map((g) => 'G$g').join(' '), chevron: false),
              ],
            ),
          ],
          if (DaliAccess.available && !DaliStore.instance.isEmpty) ...[
            const SizedBox(height: Gap.inner),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: () => openDali(context, gateway: gear?.gateway, gear: gear?.id),
                child: Text(gear == null ? s.daliOpenView : s.daliOpenLuminaire),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The luminaire a telegram is about, as far as the model knows it.
  static DaliGear? _gear(Dpt dpt, Telegram t) {
    final store = DaliStore.instance;
    if (store.isEmpty) return null;
    if (dpt.main == 244 || dpt.main == 245) {
      for (final gw in store.gateways) {
        for (final gear in store.gearOf(gw.address)) {
          if (gear.statusGroup == t.destination || gear.resultGroup == t.destination) return gear;
        }
      }
      return null;
    }
    final report = decodeDaliReport(dpt.main, t.data);
    if (report == null || report.isGroup) return null;
    final senders = store.project.diagnostics[t.destination] ?? const <int>{};
    final pa = store.gateway(t.source) != null || senders.length != 1 ? t.source : senders.first;
    return store.gear(pa, report.address);
  }
}
