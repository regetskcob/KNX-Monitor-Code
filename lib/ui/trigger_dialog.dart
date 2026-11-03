import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/trigger.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';

/// Sets up the trigger recording. Result: a new configuration, `null` on
/// cancel; "Trigger aus" (trigger off) returns a configuration with
/// [TriggerDialogResult.disarm].
Future<TriggerDialogResult?> showTriggerDialog(BuildContext context, TriggerConfig? current) =>
    showDialog<TriggerDialogResult>(
      context: context,
      builder: (_) => _TriggerDialog(current: current),
    );

class TriggerDialogResult {
  const TriggerDialogResult(this.config);
  const TriggerDialogResult.disarm() : config = null;

  final TriggerConfig? config;
}

class _TriggerDialog extends StatefulWidget {
  const _TriggerDialog({required this.current});

  final TriggerConfig? current;

  @override
  State<_TriggerDialog> createState() => _TriggerDialogState();
}

class _TriggerDialogState extends State<_TriggerDialog> {
  late TriggerKind _kind = widget.current?.kind ?? TriggerKind.address;
  late final _address = TextEditingController(
    text: widget.current?.address == null ? '' : formatGroup(widget.current!.address!),
  );
  late final _value = TextEditingController(text: widget.current?.value ?? '');
  late double _pre = (widget.current?.pre ?? 50).toDouble();
  late double _post = (widget.current?.post ?? 50).toDouble();
  late bool _rearm = widget.current?.rearm ?? false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _value.dispose();
    super.dispose();
  }

  void _arm() {
    final address = parseGroup(_address.text);
    if (_kind == TriggerKind.address && address == null) {
      setState(() => _error = s.triggerInvalidAddress);
      return;
    }
    Navigator.pop(
      context,
      TriggerDialogResult(
        TriggerConfig(
          kind: _kind,
          address: address,
          value: _value.text.trim().isEmpty ? null : _value.text.trim(),
          pre: _pre.round(),
          post: _post.round(),
          rearm: _rearm,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = parseGroup(_address.text) == null ? null : CatalogStore.instance.info(parseGroup(_address.text)!);
    // Deliberately no AlertDialog.adaptive: a form with selection, fields and
    // sliders does not fit into the 270 pt wide Cupertino alert.
    return AlertDialog(
      title: Text(s.triggerTitle),
      content: SizedBox(
        width: Widths.form + HzSpace.s64,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.triggerExplain, style: theme.textTheme.bodyMedium?.copyWith(color: context.hz.textMuted)),
              const SizedBox(height: Gap.section),
              HorizontField(
                label: s.triggerCondition,
                child: DropdownButtonFormField<TriggerKind>(
                  initialValue: _kind,
                  decoration: InputDecoration(isDense: true),
                  items: [
                    for (final (kind, label) in [
                      (TriggerKind.address, s.triggerKindAddress),
                      (TriggerKind.alarm, s.triggerKindAlarm),
                      (TriggerKind.repeated, s.triggerKindRepeated),
                      (TriggerKind.unanswered, s.triggerKindUnanswered),
                      (TriggerKind.unknown, s.triggerKindUnknown),
                    ])
                      DropdownMenuItem(value: kind, child: Text(label)),
                  ],
                  onChanged: (k) => setState(() => _kind = k!),
                ),
              ),
              if (_kind == TriggerKind.address) ...[
                const SizedBox(height: Gap.inner),
                HorizontField(
                  label: s.triggerKindAddress,
                  child: TextField(
                    controller: _address,
                    autocorrect: false,
                    style: context.hzTheme.data,
                    decoration: InputDecoration(
                      hintText: '8/1/0',
                      helperText: info?.name,
                      errorText: _error,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                ),
                const SizedBox(height: Gap.inner),
                HorizontField(
                  label: s.triggerValue,
                  child: TextField(
                    style: context.hzTheme.field,
                    controller: _value,
                    autocorrect: false,
                    decoration: InputDecoration(hintText: s.dpt1On, isDense: true),
                  ),
                ),
              ],
              const SizedBox(height: Gap.section),
              Text(s.triggerPre(_pre.round())),
              Slider.adaptive(value: _pre, min: 0, max: 500, divisions: 50, onChanged: (v) => setState(() => _pre = v)),
              Text(s.triggerPost(_post.round())),
              Slider.adaptive(
                value: _post,
                min: 0,
                max: 500,
                divisions: 50,
                onChanged: (v) => setState(() => _post = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(s.triggerRearm),
                value: _rearm,
                onChanged: (v) => setState(() => _rearm = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const TriggerDialogResult.disarm()),
            child: Text(s.triggerDisarm),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
        FilledButton(onPressed: _arm, child: Text(s.triggerArm)),
      ],
    );
  }
}
