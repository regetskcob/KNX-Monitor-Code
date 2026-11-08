import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/installation.dart';
import '../platform/addon.dart';
import '../model/tap_points.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Further tap points of the active installation (issue #8, expert mode): list with pause switch
/// and remove, "Add tap point" opens a dialog. Takes effect with the next connection.
class TapPointsPanel extends StatelessWidget {
  const TapPointsPanel({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = InstallationStore.instance;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final taps = store.active.taps;
        final full = taps.length >= TapPoint.max - 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.tapPointsTitle, style: theme.textTheme.titleSmall),
            const SizedBox(height: HzSpace.s4),
            Text(
              taps.isEmpty ? s.tapPointsHint : '${s.tapPointFirst} ${s.tapPointsHint}',
              style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
            ),
            for (final (i, t) in taps.indexed)
              Padding(
                padding: const EdgeInsets.only(top: HzSpace.s8),
                child: _TapRow(
                  tap: t,
                  number: i + 2,
                  enabled: enabled,
                  onPaused: (paused) {
                    final list = [...taps]..[i] = t.copyWith(paused: paused);
                    store.setTaps(store.active.id, list);
                  },
                  onRemove: () async {
                    final rest = [...taps]..removeAt(i);
                    await store.setTaps(store.active.id, rest);
                    // The last one gone: clear them on the server too (connect sends only non-empty lists).
                    if (rest.isEmpty && Addon.available) {
                      try {
                        await Addon.configure({'taps': <Object?>[]});
                      } on AddonException {
                        // Takes effect with the next change on the box.
                      }
                    }
                  },
                ),
              ),
            const SizedBox(height: HzSpace.s8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: !enabled || full
                    ? null
                    : () async {
                        final added = await showDialog<TapPoint>(
                          context: context,
                          builder: (_) => const _AddTapDialog(),
                        );
                        if (added != null) await store.setTaps(store.active.id, [...store.active.taps, added]);
                      },
                icon: const Icon(Icons.add),
                label: Text(s.tapPointAdd),
              ),
            ),
            if (full) Text(s.tapPointMax, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
          ],
        );
      },
    );
  }
}

class _TapRow extends StatelessWidget {
  const _TapRow({
    required this.tap,
    required this.number,
    required this.enabled,
    required this.onPaused,
    required this.onRemove,
  });

  final TapPoint tap;
  final int number;
  final bool enabled;
  final ValueChanged<bool> onPaused;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = switch (tap.mode) {
      TapMode.udp => s.connectModeUdp,
      TapMode.tcp => s.connectModeTcp,
      TapMode.routing => s.connectModeRouting,
    };
    final address = tap.mode == TapMode.routing
        ? kind
        : '$kind · ${tap.port == 3671 ? tap.host : '${tap.host}:${tap.port}'}';
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.hz.line),
        borderRadius: Radii.box,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(HzSpace.s12, HzSpace.s4, HzSpace.s4, HzSpace.s4),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$number · ${tap.name}',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    tap.paused ? '$address · ${s.tapPointPaused}' : address,
                    style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
                  ),
                ],
              ),
            ),
            Semantics(
              label: s.tapPointActive,
              child: Switch(value: !tap.paused, onChanged: enabled ? (on) => onPaused(!on) : null),
            ),
            IconButton(
              tooltip: s.tapPointRemove,
              onPressed: enabled ? onRemove : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTapDialog extends StatefulWidget {
  const _AddTapDialog();

  @override
  State<_AddTapDialog> createState() => _AddTapDialogState();
}

class _AddTapDialogState extends State<_AddTapDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '3671');
  final _window = TextEditingController();
  var _mode = TapMode.udp;
  var _modeTouched = false;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _window.dispose();
    super.dispose();
  }

  /// Whether [host] is outside private networks (RFC 1918, link-local, loopback): then it is most
  /// likely reached over VPN or the internet, where TCP is the better choice.
  static bool remote(String host) {
    final parts = host.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null || p < 0 || p > 255)) return false;
    final [a, b, ...] = parts.cast<int>();
    final private =
        a == 10 || a == 127 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168) || (a == 169 && b == 254);
    return !private;
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final host = _host.text.trim();
    final windowMs = int.tryParse(_window.text.trim());
    Navigator.of(context).pop(
      TapPoint(
        name: _name.text.trim().isEmpty ? host : _name.text.trim(),
        host: _mode == TapMode.routing && host.isEmpty ? '' : host,
        port: int.tryParse(_port.text.trim()) ?? 3671,
        mode: _mode,
        window: windowMs == null || windowMs <= 0 ? null : Duration(milliseconds: windowMs.clamp(10, 5000)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = context.hzTheme.data;
    final host = _host.text.trim();
    return AlertDialog(
      title: Text(s.tapPointAdd),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HorizontField(
                label: s.tapPointName,
                child: TextFormField(
                  controller: _name,
                  decoration: InputDecoration(hintText: s.tapPointNameHint),
                ),
              ),
              const SizedBox(height: Gap.inner),
              HorizontField(
                label: s.tapPointMode,
                child: HorizontFieldDropdown<TapMode>(
                  value: _mode,
                  onChanged: (m) => setState(() {
                    _mode = m;
                    _modeTouched = true;
                  }),
                  items: [
                    (TapMode.udp, s.connectModeUdp),
                    (TapMode.tcp, s.connectModeTcp),
                    (TapMode.routing, s.connectModeRouting),
                  ],
                ),
              ),
              if (_mode != TapMode.routing) ...[
                const SizedBox(height: Gap.inner),
                HorizontField(
                  label: s.tapPointHost,
                  child: TextFormField(
                    controller: _host,
                    style: data,
                    autocorrect: false,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [dotForComma],
                    decoration: const InputDecoration(hintText: '192.168.1.20'),
                    validator: (v) => (v ?? '').trim().isEmpty ? s.connectAddressInvalid : null,
                    onChanged: (v) => setState(() {
                      // Over VPN TCP is preselected, as long as the user has not chosen.
                      if (!_modeTouched && remote(v.trim())) _mode = TapMode.tcp;
                    }),
                  ),
                ),
                if (remote(host)) ...[
                  const SizedBox(height: HzSpace.s8),
                  Text(s.tapPointRemote, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
                ],
                const SizedBox(height: Gap.inner),
                HorizontField(
                  label: 'Port',
                  child: TextFormField(
                    controller: _port,
                    style: data,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      final p = int.tryParse((v ?? '').trim());
                      return p == null || p < 1 || p > 65535 ? s.connectAddressInvalid : null;
                    },
                  ),
                ),
              ],
              const SizedBox(height: Gap.inner),
              HorizontField(
                label: s.tapPointWindow,
                help: s.tapPointWindowHelp,
                child: TextFormField(
                  controller: _window,
                  style: data,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(hintText: '100'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.commonCancel)),
        FilledButton(onPressed: _submit, child: Text(s.tapPointSave)),
      ],
    );
  }
}

/// For tests: whether an address counts as outside the local network.
@visibleForTesting
bool tapHostIsRemote(String host) => _AddTapDialogState.remote(host);
