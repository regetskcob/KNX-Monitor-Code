import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/dali.dart';
import '../model/dali_labels.dart';
import '../model/dali_watch.dart';
import '../model/plan.dart';
import '../model/watch_rules.dart';
import '../platform/notify.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'plan_screen.dart';

enum _Scope { all, group, gear }

/// Watcher template "DALI-Fehler melden": per gateway, optionally only one group or luminaire
/// (preselected with [gear]). Creates the rules on the gateway's diagnostic addresses. Plus, like
/// every watcher. Only for adopted ([DaliGateway.trusted]) gateways: the rules match group address
/// and payload, so a gateway merely seen on the bus could be any device posing as one.
Future<void> addDaliWatch(BuildContext context, {DaliGateway? gateway, DaliGear? gear}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  if (gateway != null ? !gateway.trusted : !DaliStore.instance.gateways.any((g) => g.trusted)) {
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.daliWatchUntrusted, status: HorizontStatus.info));
    return;
  }
  if (!await unlock(context, Feature.watcher) || !context.mounted) return;
  final rules = await showDialog<List<WatchRule>>(
    context: context,
    builder: (_) => _DaliWatchDialog(gateway: gateway, gear: gear),
  );
  if (rules == null) return;
  if (rules.isEmpty) {
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.daliWatchNone, status: HorizontStatus.info));
    return;
  }
  for (final rule in rules) {
    await WatchRules.instance.add(rule);
  }
  await requestNotificationPermission();
  messenger.showSnackBar(SnackBar(content: Text(s.watchAdded(rules.first.describe()))));
}

class _DaliWatchDialog extends StatefulWidget {
  const _DaliWatchDialog({this.gateway, this.gear});

  final DaliGateway? gateway;
  final DaliGear? gear;

  @override
  State<_DaliWatchDialog> createState() => _DaliWatchDialogState();
}

class _DaliWatchDialogState extends State<_DaliWatchDialog> {
  final _store = DaliStore.instance;
  late DaliGateway _gateway = widget.gateway ?? _store.gateways.firstWhere((g) => g.trusted);
  late _Scope _scope = widget.gear == null ? _Scope.all : _Scope.gear;
  late int? _address = widget.gear?.address;
  int? _group;
  bool _sound = true;

  DaliTarget? get _target => switch (_scope) {
    _Scope.all => null,
    _Scope.group =>
      _group == null ? null : (_store.group(_gateway.address, _group!) ?? DaliGroup(_gateway.address, _group!)),
    _Scope.gear =>
      _address == null
          ? null
          : (_store.gear(_gateway.address, _address!) ?? DaliGear(_gateway.address, address: _address)),
  };

  bool get _complete => _scope == _Scope.all || _target != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final gateways = _store.gateways.where((g) => g.trusted).toList();
    final groups = _store.groupsOf(_gateway.address);
    final gear = _store.gearOf(_gateway.address).where((g) => g.address != null).toList()
      ..sort((a, b) => a.address!.compareTo(b.address!));
    final count = _complete ? daliWatchRules(_gateway, target: _target).length : 0;
    return AlertDialog(
      title: Text(s.daliWatchTemplate),
      content: SizedBox(
        width: Widths.form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (gateways.length > 1)
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _gateway.address,
                  decoration: InputDecoration(labelText: s.daliGateway),
                  items: [
                    for (final g in gateways)
                      DropdownMenuItem(
                        value: g.address,
                        child: Text(
                          '${formatIndividual(g.address)} ${daliGatewayLabel(g)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _gateway = gateways.firstWhere((g) => g.address == v);
                    _address = null;
                    _group = null;
                  }),
                )
              else
                Text(
                  '${daliGatewayLabel(_gateway)} ${formatIndividual(_gateway.address)}',
                  style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                ),
              const SizedBox(height: Gap.inner),
              SegmentedButton<_Scope>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: _Scope.all, label: Text(s.daliWatchAll)),
                  ButtonSegment(value: _Scope.group, label: Text(s.daliWatchGroup)),
                  ButtonSegment(value: _Scope.gear, label: Text(s.daliWatchGear)),
                ],
                selected: {_scope},
                onSelectionChanged: (v) => setState(() => _scope = v.first),
              ),
              if (_scope == _Scope.group) ...[
                const SizedBox(height: Gap.inner),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _group,
                  decoration: InputDecoration(labelText: s.daliWatchGroup),
                  items: [
                    for (var g = 0; g < 16; g++)
                      DropdownMenuItem(
                        value: g,
                        child: Text(
                          switch (groups.where((x) => x.group == g).firstOrNull) {
                            final known? => daliGroupLabel(known),
                            null => s.daliGroupN(g),
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _group = v),
                ),
              ],
              if (_scope == _Scope.gear) ...[
                const SizedBox(height: Gap.inner),
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: _address,
                  decoration: InputDecoration(labelText: s.daliWatchGear),
                  items: [
                    for (var a = 0; a < 64; a++)
                      DropdownMenuItem(
                        value: a,
                        child: Text(
                          switch (gear.where((x) => x.address == a).firstOrNull) {
                            final known? when known.name != null => '${s.daliGearN(a)} · ${known.name}',
                            _ => s.daliGearN(a),
                          },
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _address = v),
                ),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(s.watchWithSound),
                value: _sound,
                onChanged: (v) => setState(() => _sound = v),
              ),
              Text(
                _complete && count == 0 ? s.daliWatchNone : s.daliWatchHint,
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
        FilledButton(
          onPressed: !_complete || count == 0
              ? null
              : () => Navigator.pop(context, daliWatchRules(_gateway, target: _target, sound: _sound)),
          child: Text(s.daliWatchCreate),
        ),
      ],
    );
  }
}
