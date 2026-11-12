import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../knx/gateway_info.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/connect_help.dart';
import '../model/installation.dart';
import '../platform/addon.dart';
import '../model/tap_points.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'tap_strip.dart' show tapErrorText;

/// Further tap points of the active installation (issue #8, expert mode): list with pause switch
/// and remove, "Add tap point" opens a dialog. Takes effect with the next connection.
class TapPointsPanel extends StatelessWidget {
  const TapPointsPanel({super.key, required this.enabled, this.onDemo});

  final bool enabled;

  /// Opens the demo house with two tap points; `null` hides the button.
  final VoidCallback? onDemo;

  /// Adds [added] to the active installation, without connections it already has and within the
  /// limit of [TapPoint.max].
  static Future<void> _add(List<TapPoint> added) {
    final store = InstallationStore.instance;
    final taps = [...store.active.taps];
    for (final t in added) {
      if (taps.length >= TapPoint.max - 1) break;
      if (!taps.any((o) => o.sameConnection(t))) taps.add(t);
    }
    return store.setTaps(store.active.id, taps);
  }

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
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    await store.setTaps(store.active.id, rest);
                    // A way back: the bin asks nothing, so the removal can be undone.
                    messenger
                      ?..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(s.tapPointRemoved(t.name)),
                          action: SnackBarAction(
                            label: s.tapPointUndo,
                            onPressed: () {
                              final now = [...store.active.taps];
                              if (now.any((o) => o.sameConnection(t)) || now.length >= TapPoint.max - 1) return;
                              store.setTaps(store.active.id, now..insert(i.clamp(0, now.length), t));
                            },
                          ),
                        ),
                      );
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
            if (taps.any((t) => !t.paused)) ...[
              const SizedBox(height: HzSpace.s8),
              // Said before connecting: how many connections open, and who sends.
              Text(
                '${s.tapConnectCount(1 + taps.where((t) => !t.paused).length)} ${s.tapSendVia}',
                style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
              ),
            ],
            const SizedBox(height: HzSpace.s8),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s4,
              children: [
                TextButton.icon(
                  onPressed: !enabled || full
                      ? null
                      : () async {
                          final added = await showDialog<TapPoint>(
                            context: context,
                            builder: (_) => _AddTapDialog(existing: store.active.taps),
                          );
                          if (added != null) await _add([added]);
                        },
                  icon: const Icon(Icons.add),
                  label: Text(s.tapPointAdd),
                ),
                TextButton.icon(
                  onPressed: !enabled || full
                      ? null
                      : () async {
                          final added = await showDialog<Object>(
                            context: context,
                            builder: (_) => _SearchTapDialog(
                              existing: store.active.taps,
                              gateway: store.active.gateway?.host,
                              room: TapPoint.max - 1 - store.active.taps.length,
                            ),
                          );
                          if (added is List<TapPoint> && added.isNotEmpty) await _add(added);
                          // Nothing found, or not in this network: on to the entry by hand.
                          if (added == _SearchTapDialog.byHand && context.mounted) {
                            final tap = await showDialog<TapPoint>(
                              context: context,
                              builder: (_) => _AddTapDialog(existing: store.active.taps),
                            );
                            if (tap != null) await _add([tap]);
                          }
                        },
                  icon: const Icon(Icons.search),
                  label: Text(s.tapSearchRun),
                ),
                if (onDemo != null)
                  Tooltip(
                    message: s.tapDemoHint,
                    child: TextButton.icon(
                      onPressed: enabled ? onDemo : null,
                      icon: const Icon(Icons.play_circle_outline),
                      label: Text(s.tapDemo),
                    ),
                  ),
              ],
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
              // Named, so that several switches can be told apart by a screen reader.
              label: s.tapPointActiveNamed(tap.name),
              child: Switch(value: !tap.paused, onChanged: enabled ? (on) => onPaused(!on) : null),
            ),
            IconButton(
              tooltip: s.tapPointRemoveNamed(tap.name),
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
  const _AddTapDialog({this.existing = const []});

  /// Tap points the installation already has: the same connection is not added twice.
  final List<TapPoint> existing;

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

  String? _duplicate;

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final host = _mode == TapMode.routing ? '' : _host.text.trim();
    final windowMs = int.tryParse(_window.text.trim());
    final name = _name.text.trim();
    final tap = TapPoint(
      name: (name.isEmpty ? (host.isEmpty ? s.connectModeRouting : host) : name).characters.take(80).toString(),
      host: host,
      port: int.tryParse(_port.text.trim()) ?? 3671,
      mode: _mode,
      window: windowMs == null || windowMs <= 0 ? null : Duration(milliseconds: windowMs.clamp(10, 5000)),
    );
    // Routing needs one tap point per multicast address, a tunnel one per interface.
    if (widget.existing.any((o) => o.sameConnection(tap))) {
      setState(() => _duplicate = s.tapDuplicate);
      return;
    }
    Navigator.of(context).pop(tap);
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
                    // Host names are allowed too, so not the digits-only keyboard.
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(hintText: '192.168.1.20'),
                    validator: (v) => TapPoint.validHost((v ?? '').trim()) ? null : s.connectAddressInvalid,
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
              if (_duplicate case final text?) ...[
                const SizedBox(height: HzSpace.s8),
                HorizontNotice(HorizontStatus.warning, child: Text(text)),
              ],
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

/// Searches the network for KNXnet/IP interfaces; tests replace it.
@visibleForTesting
Stream<FoundGateway> Function() tapSearch = _searchNetwork;

Stream<FoundGateway> _searchNetwork() async* {
  if (Addon.box != null) {
    // Via the box: it searches on its own cable.
    for (final g in (await Addon.discover()).whereType<Map<Object?, Object?>>()) {
      final dibs = parseHex(g['dibs'] as String? ?? '');
      final host = g['host'];
      if (dibs == null || host is! String) continue;
      if (GatewayInfo.parse(Uint8List.fromList(dibs)) case final info?) yield FoundGateway(host, info);
    }
    return;
  }
  yield* scanGateways();
}

/// "Search the network": every interface found, several can be ticked (issue #8). Each row says
/// its line, how many tunnels are free and what the tap point would add; an interface without a
/// free tunnel cannot be ticked.
class _SearchTapDialog extends StatefulWidget {
  const _SearchTapDialog({required this.existing, required this.gateway, required this.room});

  final List<TapPoint> existing;

  /// Result when the user wants to enter the address by hand instead.
  static const byHand = 'byHand';

  /// Address of the first tap point (the installation's connection).
  final String? gateway;

  /// How many more tap points fit.
  final int room;

  @override
  State<_SearchTapDialog> createState() => _SearchTapDialogState();
}

class _SearchTapDialogState extends State<_SearchTapDialog> {
  final _found = <FoundGateway>[];
  final _picked = <String>{};
  var _searching = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After the first frame: it calls setState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    if (!mounted) return;
    setState(() {
      _searching = true;
      _error = null;
      _found.clear();
    });
    try {
      await for (final g in tapSearch()) {
        if (!mounted) return;
        setState(
          () => _found
            ..add(g)
            ..sort((a, b) => a.host.compareTo(b.host)),
        );
      }
    } on Object catch (e) {
      // In plain words; what the system reports says nothing to the reader.
      if (mounted) setState(() => _error = tapErrorText('$e'));
    }
    if (mounted) setState(() => _searching = false);
  }

  bool _already(FoundGateway g) => g.host == widget.gateway || widget.existing.any((t) => t.host == g.host);

  static int _free(GatewayInfo info) => info.slots.where((t) => t.free && t.usable).length;

  /// Tunnelling (service family 4) offered, or nothing said about services.
  static bool _tunnels(GatewayInfo info) => info.services.isEmpty || info.services.containsKey(0x04);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    final lastTunnel = [
      for (final g in _found)
        if (_picked.contains(g.host) && g.info.slots.isNotEmpty && _free(g.info) == 1) g.info.name,
    ];
    return AlertDialog(
      title: Text(s.tapSearchTitle),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searching) ...[const LinearProgressIndicator(), const SizedBox(height: HzSpace.s8)],
              if (_error case final e?) HorizontNotice(HorizontStatus.warning, child: Text('${s.tapSearchFailed} $e')),
              if (!_searching && _found.isEmpty) ...[
                if (_error == null) Text(s.tapSearchNone, style: muted),
                const SizedBox(height: HzSpace.s8),
                Text(s.tapSearchByHandHint, style: muted),
                const SizedBox(height: HzSpace.s8),
                Wrap(
                  spacing: HzSpace.s8,
                  runSpacing: HzSpace.s4,
                  children: [
                    OutlinedButton(onPressed: _search, child: Text(s.tapSearchAgain)),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(_SearchTapDialog.byHand),
                      child: Text(s.tapSearchByHand),
                    ),
                  ],
                ),
              ],
              for (final g in _found) _row(context, g, muted),
              if (lastTunnel.isNotEmpty) ...[
                const SizedBox(height: HzSpace.s8),
                HorizontNotice(HorizontStatus.info, child: Text(s.tapSearchLastTunnel(lastTunnel.join(', ')))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.commonCancel)),
        FilledButton(
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final g in _found)
                    if (_picked.contains(g.host))
                      TapPoint(
                        name: s.tapSearchName(formatLine(g.info.address), g.info.name),
                        host: g.host,
                        // Outside the own network (found via the box or a routed search): TCP.
                        mode: tapHostIsRemote(g.host) ? TapMode.tcp : TapMode.udp,
                      ),
                ]),
          // Without a choice it says what it does, not "add 0".
          child: Text(_picked.isEmpty ? s.tapPointSave : s.tapSearchAdd(_picked.length)),
        ),
      ],
    );
  }

  static String formatLine(int address) => '${(address >> 12) & 0x0F}.${(address >> 8) & 0x0F}';

  Widget _row(BuildContext context, FoundGateway g, TextStyle? muted) {
    final info = g.info;
    final already = _already(g);
    final picked = _picked.contains(g.host);
    final free = _free(info);
    final full = info.slots.isNotEmpty && free == 0;
    final routingOnly = !_tunnels(info);
    final otherOnLine = _found.any(
      (o) => o.host != g.host && (_already(o) || _picked.contains(o.host)) && o.info.address >> 8 == info.address >> 8,
    );
    final canPick = !already && !full && !routingOnly && (picked || _picked.length < widget.room);
    // What ticking it means, in words (never by colour alone).
    final note = already
        ? s.tapSearchAlready
        : routingOnly
        ? s.tapSearchRoutingOnly
        : full
        ? s.tapSearchNoTunnel(info.slots.length)
        : otherOnLine
        ? s.tapSearchSameLine
        : s.tapSearchNewLine;
    final line = formatLine(info.address);
    return CheckboxListTile(
      value: already || picked,
      enabled: canPick,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      onChanged: canPick ? (on) => setState(() => on == true ? _picked.add(g.host) : _picked.remove(g.host)) : null,
      title: Text('${info.name} · ${s.topoLine(line)}'),
      subtitle: Text(
        // "All tunnels in use" already says how many are free.
        [g.host, info.addressText, if (!full) ?freeTunnels(info), note].join(metaSeparator),
        style: full || (otherOnLine && !already) ? muted?.copyWith(color: context.hz.warning) : muted,
      ),
    );
  }
}

/// For tests: whether an address counts as outside the local network.
@visibleForTesting
bool tapHostIsRemote(String host) => _AddTapDialogState.remote(host);
