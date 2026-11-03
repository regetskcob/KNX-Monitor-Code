import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/gateway_info.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Shows the self-description of the connected gateway.
Future<void> showGatewaySheet(BuildContext context, KnxTunnel tunnel) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (_) => SafeArea(top: false, child: _GatewaySheet(tunnel: tunnel)),
);

class _GatewaySheet extends StatelessWidget {
  const _GatewaySheet({required this.tunnel});

  final KnxTunnel tunnel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return ValueListenableBuilder(
      valueListenable: tunnel.gatewayInfo,
      builder: (context, info, _) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.bottom),
        children: [
          HorizontTitle(kennung: s.gatewayTitle, title: info?.name ?? tunnel.host, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.section),
          HorizontMetricRow(
            children: [
              HorizontMetric(label: s.gatewayAddress, value: '${tunnel.host}:${tunnel.port}'),
              if (tunnel.tunnelAddress != null)
                HorizontMetric(
                  label: s.gatewayTunnel,
                  value: s.gatewayTunnelValue(formatIndividual(tunnel.tunnelAddress!), tunnel.channel),
                ),
              if (info != null) ...[
                HorizontMetric(label: s.gatewayMedium, value: info.mediumText),
                HorizontMetric(label: s.gatewayIndividual, value: info.addressText),
              ],
            ],
          ),
          const SizedBox(height: Gap.section),
          if (info == null)
            Text(s.gatewayUnknown, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted))
          else ...[
            for (final (label, value) in [
              (s.gatewaySerial, info.serial),
              (s.gatewayMac, info.mac),
              (s.gatewayMulticast, info.multicast),
            ])
              _Fact(label, value),
            _Fact(s.gatewayProgMode, info.programmingMode ? s.yes : s.no, measured: false),
            const SizedBox(height: Gap.section),
            Kennung(s.gatewayServices, count: info.services.length),
            const SizedBox(height: HzSpace.s4),
            for (final MapEntry(key: family, value: version) in info.services.entries)
              _Fact(GatewayInfo.serviceName(family), 'v$version'),
            if (info.slots.isNotEmpty) ...[
              const SizedBox(height: Gap.section),
              Kennung(s.gatewaySlots, count: info.slots.length),
              const SizedBox(height: HzSpace.s8),
              // Occupancy as status: free = check mark, in use = triangle, with
              // a word.
              Wrap(
                spacing: HzSpace.s8,
                runSpacing: HzSpace.s8,
                children: [
                  for (final slot in info.slots)
                    HorizontBadge(
                      slot.free ? HorizontStatus.positive : HorizontStatus.warning,
                      label: '${formatIndividual(slot.address)} · ${slot.free ? s.gatewaySlotFree : s.gatewaySlotBusy}',
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Fact with a hairline below: the sheet lists the gateway's properties like a
/// table.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.measured = true});

  final String label;
  final String value;
  final bool measured;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(
        bottom: BorderSide(color: context.hz.line, width: Lines.hairline),
      ),
    ),
    child: HorizontFact(
      term: label,
      value: value,
      measured: measured,
      selectable: true,
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
    ),
  );
}
