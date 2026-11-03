import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/connection_options.dart';
import '../platform/addon.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Connection type and details (expert mode): UDP/TCP tunnel, routing, IP
/// Secure, fixed tunnel address, the box's KNX HAT.
class ConnectionOptionsPanel extends StatefulWidget {
  const ConnectionOptionsPanel({super.key, required this.enabled, this.hat = false});

  final bool enabled;

  /// The connected box has a KNX HAT: offer the connection type.
  final bool hat;

  @override
  State<ConnectionOptionsPanel> createState() => _ConnectionOptionsPanelState();
}

class _ConnectionOptionsPanelState extends State<ConnectionOptionsPanel> {
  final _options = ConnectionOptions.instance;
  late final _tunnel = TextEditingController(text: _format(_options.tunnelAddress));
  late final _routing = TextEditingController(text: formatIndividual(_options.routingAddress));
  late final _hatAddress = TextEditingController(text: _format(_options.hatAddress));

  /// Value the address field last knew: when the app takes the address from the
  /// box, the field follows without replacing input mid-edit.
  late int? _hatShown = _options.hatAddress;
  late final _userId = TextEditingController(text: '${_options.secureUserId}');
  late final _password = TextEditingController(text: _options.secureUserPassword);
  late final _deviceAuth = TextEditingController(text: _options.secureDeviceAuthentication);

  static String _format(int? a) => a == null ? '' : formatIndividual(a);

  @override
  void dispose() {
    _tunnel.dispose();
    _routing.dispose();
    _hatAddress.dispose();
    _userId.dispose();
    _password.dispose();
    _deviceAuth.dispose();
    super.dispose();
  }

  void _setMode(ConnectionMode mode) {
    setState(() => _options.mode = mode);
    _options.save();
  }

  String? _validateAddress(String? v, {required bool optional}) {
    final text = v?.trim() ?? '';
    if (text.isEmpty) return optional ? null : s.connectAddressInvalid;
    return parseIndividual(text) == null ? s.connectAddressInvalid : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = context.hzTheme.data;
    final mode = _options.mode;
    if (_options.hatAddress != _hatShown) {
      _hatShown = _options.hatAddress;
      _hatAddress.text = _format(_hatShown);
    }
    final hint = switch (mode) {
      ConnectionMode.udp => s.connectModeUdpHint,
      ConnectionMode.tcp => s.connectModeTcpHint,
      ConnectionMode.routing => s.connectModeRoutingHint,
      ConnectionMode.secure => s.connectModeSecureHint,
      ConnectionMode.homeAssistant => s.connectModeHaHint,
      ConnectionMode.hat => s.connectModeHatHint,
    };
    final modeColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HorizontFieldDropdown<ConnectionMode>(
          value: mode,
          onChanged: widget.enabled ? _setMode : null,
          items: [
            (ConnectionMode.udp, s.connectModeUdp),
            (ConnectionMode.tcp, s.connectModeTcp),
            (ConnectionMode.routing, s.connectModeRouting),
            (ConnectionMode.secure, s.connectModeSecure),
            if (Addon.embedded) (ConnectionMode.homeAssistant, s.connectModeHa),
            // Also the selected type when the HAT is currently missing.
            if (widget.hat || mode == ConnectionMode.hat) (ConnectionMode.hat, s.connectModeHat),
          ],
        ),
        const SizedBox(height: HzSpace.s8),
        Text(hint, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
      ],
    );
    final Widget? addressField = mode == ConnectionMode.homeAssistant
        ? null
        : mode == ConnectionMode.hat
        ? HorizontField(
            label: s.connectHatAddress,
            help: s.connectHatAddressHelp,
            child: TextFormField(
              controller: _hatAddress,
              enabled: widget.enabled,
              style: data,
              // Digits with punctuation; the decimal pad shows a comma in
              // German.
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: const [dotForComma],
              autocorrect: false,
              decoration: InputDecoration(hintText: '15.15.255'),
              validator: (v) => _validateAddress(v, optional: true),
              onChanged: (v) {
                final text = v.trim();
                _options.hatAddress = text.isEmpty ? null : parseIndividual(text) ?? _options.hatAddress;
                _hatShown = _options.hatAddress;
                _options.save();
              },
            ),
          )
        : mode == ConnectionMode.routing
        ? HorizontField(
            label: s.connectRoutingAddress,
            child: TextFormField(
              controller: _routing,
              enabled: widget.enabled,
              style: data,
              // Digits with punctuation; the decimal pad shows a comma in
              // German.
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: const [dotForComma],
              autocorrect: false,
              decoration: InputDecoration(hintText: '0.0.254'),
              validator: (v) => _validateAddress(v, optional: false),
              onChanged: (v) {
                final a = parseIndividual(v);
                if (a != null) {
                  _options.routingAddress = a;
                  _options.save();
                }
              },
            ),
          )
        : HorizontField(
            label: s.connectTunnelAddress,
            help: s.connectTunnelAddressHelp,
            child: TextFormField(
              controller: _tunnel,
              enabled: widget.enabled,
              style: data,
              // Digits with punctuation; the decimal pad shows a comma in
              // German.
              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
              inputFormatters: const [dotForComma],
              autocorrect: false,
              decoration: InputDecoration(hintText: '1.1.240'),
              validator: (v) => _validateAddress(v, optional: true),
              onChanged: (v) {
                final text = v.trim();
                _options.tunnelAddress = text.isEmpty ? null : parseIndividual(text) ?? _options.tunnelAddress;
                _options.save();
              },
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            // Wide (iPad, Mac): connection type and address side by side, half
            // and half; both labelled, fields at the same height.
            if (addressField != null && box.maxWidth >= Widths.form + HzSpace.s96) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.inner,
                children: [
                  Expanded(
                    child: HorizontField(label: s.connectModeLabel, child: modeColumn),
                  ),
                  Expanded(child: addressField),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HorizontField(label: s.connectModeLabel, child: modeColumn),
                if (addressField != null) ...[const SizedBox(height: Gap.inner), addressField],
              ],
            );
          },
        ),
        if (mode == ConnectionMode.hat) ...[
          const SizedBox(height: Gap.inner),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _options.hatBusmonitor,
            onChanged: widget.enabled
                ? (v) {
                    setState(() => _options.hatBusmonitor = v);
                    _options.save();
                  }
                : null,
            title: Text(s.connectHatBusmonitor),
            subtitle: Text(s.connectHatBusmonitorHelp),
          ),
        ],
        if (mode == ConnectionMode.secure) ...[
          const SizedBox(height: Gap.inner),
          Row(
            spacing: HzSpace.s8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: HzSpace.s96,
                child: HorizontField(
                  label: s.connectSecureUser,
                  child: TextFormField(
                    controller: _userId,
                    enabled: widget.enabled,
                    style: data,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final id = int.tryParse(v?.trim() ?? '');
                      return id == null || id < 1 || id > 127 ? '1–127' : null;
                    },
                    onChanged: (v) {
                      final id = int.tryParse(v.trim());
                      if (id != null && id >= 1 && id <= 127) {
                        _options.secureUserId = id;
                        _options.save();
                      }
                    },
                  ),
                ),
              ),
              Expanded(
                child: HorizontField(
                  label: s.connectSecurePassword,
                  child: TextFormField(
                    style: context.hzTheme.field,
                    controller: _password,
                    enabled: widget.enabled,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (v) => _options.secureUserPassword = v,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.inner),
          HorizontField(
            label: s.connectSecureDeviceAuth,
            help: s.connectSecureDeviceAuthHelp,
            child: TextFormField(
              style: context.hzTheme.field,
              controller: _deviceAuth,
              enabled: widget.enabled,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (v) => _options.secureDeviceAuthentication = v,
            ),
          ),
        ],
      ],
    );
  }
}
