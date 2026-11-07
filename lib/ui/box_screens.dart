import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../l10n/locale_controller.dart';
import '../model/box_connection.dart';
import '../model/box_setup.dart';
import '../platform/addon.dart';
import '../platform/box_link.dart';
import '../platform/native_bridge.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'box_hat_screen.dart';
import 'common.dart';
import 'server_restarts.dart';

/// Whether this device can read QR codes with the camera (iPhone, iPad,
/// Android).
bool get canScanBox => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// Name for the box's device list, e.g. "iPad".
String boxDeviceName(BuildContext context) {
  if (kIsWeb) return 'Browser';
  if (Platform.isIOS) return MediaQuery.sizeOf(context).shortestSide >= 600 ? 'iPad' : 'iPhone';
  if (Platform.isAndroid) return 'Android';
  return Platform.localHostname;
}

/// Short duration for deviations: "12 s", "3 min", "2 h 5 min".
String formatOffset(int ms) {
  final d = Duration(milliseconds: ms.abs());
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  final minutes = d.inMinutes % 60;
  return minutes == 0 ? '${d.inHours} h' : '${d.inHours} h $minutes min';
}

String clockSourceText(String? source) => switch (source) {
  'rtc' => s.boxClockRtc,
  'knx' => s.boxClockKnx,
  'client' => s.boxClockClient,
  'ntp' => s.boxClockNtp,
  _ => s.boxClockNone,
};

/// Offers this device's time to the box. If the box's (trusted) clock is far
/// off, asks first and only then sets it.
Future<void> syncBoxTime(BuildContext context) async {
  if (Addon.box == null) return;
  try {
    final answer = await Addon.offerTime();
    if (answer['result'] != 'differs' || !context.mounted) return;
    final clock = (answer['clock'] as Map?)?.cast<String, Object?>() ?? const {};
    final offset = ((clock['offsets'] as Map?)?['client'] as num?)?.toInt() ?? 0;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.boxTimeAskTitle),
        content: Text(s.boxTimeAskBody(formatOffset(offset))),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.boxClockSetNow,
            onPressed: () => Navigator.pop(context, true),
            primary: true,
          ),
        ],
      ),
    );
    if (ok == true) await Addon.offerTime(force: true);
  } on AddonException {
    // Older box without a clock, or currently unreachable: don't bother the
    // user.
  }
}

// --- Scanner -------------------------------------------------------------------

/// Reads the QR code from the box's sticker. Result: the link, `''` for
/// "manually" (paste/address), or `null` if cancelled.
class BoxScannerScreen extends StatefulWidget {
  const BoxScannerScreen({super.key});

  @override
  State<BoxScannerScreen> createState() => _BoxScannerScreenState();
}

class _BoxScannerScreenState extends State<BoxScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue ?? '';
      if (BoxLink.parse(text) == null) continue;
      _done = true;
      Navigator.pop(context, text);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(title: Text(s.boxScanTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: HorizontEmptyHint(text: scannerProblem(error), status: HorizontStatus.warning),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.gutter, Gap.section, Gap.gutter, Gap.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.inner,
              children: [
                Text(s.boxScanHint, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                OutlinedButton(onPressed: () => Navigator.pop(context, ''), child: Text(s.boxScanManual)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Einrichtung ---------------------------------------------------------------

/// Sets up the box with [link] and shows every step. Returns `true` if the app
/// then runs through the box.
class BoxSetupScreen extends StatefulWidget {
  const BoxSetupScreen({super.key, required this.link, required this.deviceName, this.setup});

  final BoxLink link;
  final String deviceName;

  /// Shows a setup that has already run instead of starting one (image for the
  /// box page, test/layout_shots_test.dart).
  @visibleForTesting
  final BoxSetup? setup;

  @override
  State<BoxSetupScreen> createState() => _BoxSetupScreenState();
}

class _BoxSetupScreenState extends State<BoxSetupScreen> {
  late final _setup =
      widget.setup ??
      BoxSetup(
        widget.link,
        deviceName: widget.deviceName,
        choosePassword: () => askBoxPassword(context, required: true),
      );

  @override
  void initState() {
    super.initState();
    _setup.addListener(_changed);
    if (widget.setup == null) _setup.run();
  }

  @override
  void dispose() {
    _setup.removeListener(_changed);
    if (widget.setup == null) _setup.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  String _label(BoxSetupStep step) {
    final ssid = widget.link.ssid;
    return switch (step) {
      BoxSetupStep.wifi => s.boxStepWifi(ssid),
      BoxSetupStep.reach => s.boxStepReach,
      BoxSetupStep.pair => s.boxStepPair,
      BoxSetupStep.time => s.boxStepTime,
      BoxSetupStep.gateway => s.boxStepGateway,
    };
  }

  /// Result or hint below the step.
  String? _detail(BoxSetupStep step, BoxStepState state) => switch ((step, state)) {
    (BoxSetupStep.wifi, BoxStepState.manual) => s.boxStepWifiManual(widget.link.ssid),
    (BoxSetupStep.wifi, BoxStepState.failed) => _setup.error == 'denied' ? s.boxStepWifiDenied : _setup.error,
    (BoxSetupStep.reach, BoxStepState.failed) => s.boxStepReachFailed,
    (BoxSetupStep.pair, BoxStepState.failed) =>
      _setup.error == BoxSetup.passwordMissing ? s.boxPasswordRequired : _setup.error,
    (BoxSetupStep.time, BoxStepState.done) when _setup.timeResult == 'differs' => s.boxStepTimeDiffers,
    (BoxSetupStep.gateway, BoxStepState.done) => s.boxStepGatewayFound(_setup.gateway ?? ''),
    (BoxSetupStep.gateway, BoxStepState.manual) => s.boxStepGatewayChoose,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.boxSetupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.form),
          child: ListView(
            padding: Gap.page,
            children: [
              Kennung(widget.link.label),
              const SizedBox(height: Gap.inner),
              for (final step in BoxSetupStep.values)
                if (_setup.states[step] case final state? when state != BoxStepState.skipped)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.inner),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox.square(
                          dimension: HzSpace.s24,
                          child: switch (state) {
                            BoxStepState.running => const Padding(
                              padding: EdgeInsets.all(HzSpace.s4),
                              child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
                            ),
                            BoxStepState.done => Icon(HorizontStatus.positive.icon, color: hz.positive),
                            BoxStepState.failed => Icon(HorizontStatus.critical.icon, color: hz.critical),
                            BoxStepState.manual => Icon(HorizontStatus.info.icon, color: hz.info),
                            _ => Icon(HorizontStatus.neutral.icon, color: hz.textFaint),
                          },
                        ),
                        const SizedBox(width: Gap.inner),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _label(step),
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: state == BoxStepState.waiting ? hz.textMuted : null,
                                ),
                              ),
                              if (_detail(step, state) case final detail?)
                                Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              const SizedBox(height: Gap.section),
              if (_setup.failed)
                FilledButton(onPressed: _setup.run, child: Text(s.boxSetupRetry))
              else if (_setup.finished)
                FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(s.boxSetupDone)),
            ],
          ),
        ),
      ),
    );
  }
}

/// After pairing with the password from the sticker: set your own so the
/// sticker and SD card can no longer pair new devices (e.g. at a customer's
/// site). Asks for the own box password and sets it; `true` if that worked.
/// With [required] the dialog cannot be dismissed: the box allows nothing else
/// before.
Future<bool> askBoxPassword(BuildContext context, {bool required = false, bool needsCurrent = false}) async =>
    await showAdaptiveDialog<bool>(
      context: context,
      barrierDismissible: !required,
      builder: (_) => _BoxPasswordDialog(required: required, needsCurrent: needsCurrent),
    ) ==
    true;

bool _passwordOffered = false;

/// If the paired box still uses the password from the sticker (e.g. after
/// updating an older box), suggest setting your own once per app start.
Future<void> offerBoxPassword(BuildContext context) async {
  if (_passwordOffered || Addon.box == null) return;
  try {
    final info = await Addon.boxInfo();
    if (info['mustChangePassword'] != true || info['role'] != 'admin' || !context.mounted) return;
    _passwordOffered = true;
    // Only while the change is not yet required does the box ask for the current one.
    await askBoxPassword(context, needsCurrent: info['passwordChangeRequired'] != true);
  } on AddonException {
    // Box currently unreachable: try next time.
  }
}

class _BoxPasswordDialog extends StatefulWidget {
  const _BoxPasswordDialog({required this.required, this.needsCurrent = false});

  final bool required;

  /// Field for the current password (the sticker one, see [askBoxPassword]).
  final bool needsCurrent;

  @override
  State<_BoxPasswordDialog> createState() => _BoxPasswordDialogState();
}

class _BoxPasswordDialogState extends State<_BoxPasswordDialog> {
  final _password = TextEditingController();
  final _current = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _current.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final next = _password.text;
    if (next.length < 8) {
      setState(() => _error = s.boxPasswordHint);
      return;
    }
    setState(() => _busy = true);
    try {
      await Addon.changeBoxPassword(next, current: widget.needsCurrent ? _current.text : null);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(s.boxPasswordChanged)));
    } on AddonException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.status == 403 ? s.boxPasswordCurrentWrong : e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(widget.required ? s.boxPasswordMustTitle : s.boxPasswordAskTitle),
    // Material for the text field in the Cupertino dialog.
    content: Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.boxPasswordAskBody),
          const SizedBox(height: Gap.section),
          if (widget.needsCurrent) ...[
            HorizontField(
              label: s.boxPasswordCurrent,
              child: TextField(
                controller: _current,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
              ),
            ),
            const SizedBox(height: Gap.item),
          ],
          HorizontField(
            label: s.boxPasswordChange,
            help: s.boxPasswordHint,
            child: TextField(
              controller: _password,
              autofocus: !widget.needsCurrent,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      if (!widget.required)
        horizontDialogAction(context, label: s.boxPasswordAskLater, onPressed: () => Navigator.pop(context, false)),
      horizontDialogAction(
        context,
        label: s.boxPasswordChange,
        primary: true,
        onPressed: () {
          if (!_busy) unawaited(_submit());
        },
      ),
    ],
  );
}

// --- Box-Einstellungen -------------------------------------------------------------

/// Clock, paired devices and password of the box: what the browser used to
/// handle on `/pair`.
class BoxSettingsScreen extends StatefulWidget {
  const BoxSettingsScreen({super.key});

  @override
  State<BoxSettingsScreen> createState() => _BoxSettingsScreenState();
}

class _BoxSettingsScreenState extends State<BoxSettingsScreen> {
  Map<String, Object?>? _info;
  Map<String, Object?> _config = const {};
  List<Map<String, Object?>> _devices = const [];
  String? _error;
  final _password = TextEditingController();
  final _currentPassword = TextEditingController();
  String? _passwordError;
  final _wifi = TextEditingController();
  String? _wifiError;
  bool _lowSpace = false;

  bool get _admin => _info?['role'] == 'admin';

  /// Over the cable or another network without HTTPS: everything goes in plain
  /// text.
  bool get _plainOutsideBoxWifi {
    final url = Addon.box?.url;
    return url != null && url.scheme == 'http' && url.host != '10.42.0.1' && !url.host.endsWith('.local');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _password.dispose();
    _currentPassword.dispose();
    _wifi.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await Addon.boxInfo();
      final status = await Addon.status();
      final devices = info['role'] == 'admin'
          ? [for (final d in await Addon.boxDevices()) (d! as Map).cast<String, Object?>()]
          : const <Map<String, Object?>>[];
      if (!mounted) return;
      setState(() {
        _info = info;
        _config = (status['config'] as Map?)?.cast<String, Object?>() ?? const {};
        _lowSpace = status['lowSpace'] == true;
        _devices = devices;
        _error = null;
      });
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _configure(Map<String, Object?> changes) async {
    setState(() => _config = {..._config, ...changes});
    try {
      await Addon.configure(changes);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _load();
  }

  Future<void> _setTime() async {
    try {
      await Addon.offerTime(force: true);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _load();
  }

  Future<void> _revoke(String id) async {
    try {
      await Addon.revokeDevice(id);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    await _load();
  }

  Future<void> _setLanAccess(bool enabled) async {
    if (!enabled) {
      final ok = await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(s.boxLanAccessOffTitle),
          content: Text(s.boxLanAccessOffBody),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: s.boxLanAccessOff,
              primary: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await Addon.setBoxLanAccess(enabled);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }
    if (!mounted) return;
    setState(() => _info = {...?_info, 'lanAccess': enabled});
    // When connected over the cable, the box is no longer reachable after
    // locking; only reload if it stays reachable.
    if (enabled) await _load();
  }

  Future<void> _changePassword() async {
    final next = _password.text;
    if (next.length < 8) {
      setState(() => _passwordError = s.boxPasswordHint);
      return;
    }
    final needsCurrent = _info?['passwordChangeRequired'] != true;
    if (needsCurrent && _currentPassword.text.isEmpty) {
      setState(() => _passwordError = s.boxPasswordCurrentWrong);
      return;
    }
    try {
      await Addon.changeBoxPassword(next, current: needsCurrent ? _currentPassword.text : null);
      _password.clear();
      _currentPassword.clear();
      if (!mounted) return;
      setState(() => _passwordError = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.boxPasswordChanged)));
    } on AddonException catch (e) {
      if (mounted) setState(() => _passwordError = e.status == 403 ? s.boxPasswordCurrentWrong : e.message);
    }
  }

  /// New Wi-Fi password: the box disconnects everyone from its Wi-Fi; the app
  /// remembers it and rejoins on its own.
  Future<void> _changeWifi() async {
    final next = _wifi.text;
    if (next.length < 8 || next.length > 63) {
      setState(() => _wifiError = s.boxWifiHint);
      return;
    }
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.boxWifiChange),
        content: Text(s.boxWifiConfirm),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.boxWifiChange,
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Addon.changeBoxWifi(next);
      if (BoxConnection.instance.saved case final link?) {
        await BoxConnection.instance.use(
          BoxLink(url: link.url, key: link.key, name: link.name, ssid: link.ssid, wifi: next, fp: link.fp),
        );
        if (link.ssid.isNotEmpty) {
          // The box only changes the password after this response.
          unawaited(
            Future<void>.delayed(const Duration(seconds: 6)).then((_) => NativeBridge.joinWifi(link.ssid, next)),
          );
        }
      }
      _wifi.clear();
      if (!mounted) return;
      setState(() => _wifiError = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.boxWifiChanged)));
    } on AddonException catch (e) {
      if (mounted) setState(() => _wifiError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textMuted);
    final clock = (_info?['clock'] as Map?)?.cast<String, Object?>() ?? const {};
    final synced = clock['synced'] == true;
    final offsets = (clock['offsets'] as Map?)?.cast<String, Object?>() ?? const {};
    final waiting = (_info?['waiting'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(BoxConnection.instance.saved?.label ?? s.boxSettings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView(
              padding: Gap.page,
              children: [
                if (_error case final error?) ...[
                  HorizontStatusLine(HorizontStatus.critical, error),
                  const SizedBox(height: Gap.section),
                ],
                if (_info?['restarts'] case final Map<dynamic, dynamic> restarts) ...[
                  ServerRestartsLine(restarts.cast<String, Object?>(), box: true),
                  const SizedBox(height: Gap.section),
                ],
                if (_lowSpace) ...[
                  HorizontStatusLine(HorizontStatus.critical, s.boxLowSpace),
                  const SizedBox(height: Gap.section),
                ],
                if (_info?['mustChangePassword'] == true && _admin) ...[
                  HorizontStatusLine(HorizontStatus.warning, s.boxPasswordStillSticker),
                  const SizedBox(height: Gap.section),
                ],
                if (_plainOutsideBoxWifi) ...[
                  HorizontStatusLine(
                    HorizontStatus.warning,
                    _info?['tls'] == null ? s.boxPlainWarning : s.boxPlainWarningTls,
                  ),
                  const SizedBox(height: Gap.section),
                ],
                if (_info?['health'] case final Map<dynamic, dynamic> health) ...[
                  BoxHealthSection(health.cast<String, Object?>()),
                  const SizedBox(height: Gap.section),
                ],
                // Docker has no box clock: the host keeps the time.
                if (_info == null || _info?['clock'] != null) ...[
                  Kennung(s.boxClock),
                  const SizedBox(height: Gap.item),
                  HorizontStatusLine(
                    synced ? HorizontStatus.positive : HorizontStatus.warning,
                    clockSourceText(clock['source'] as String?),
                  ),
                  for (final MapEntry(:key, :value) in offsets.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: HzSpace.s4),
                      child: HorizontStatusLine(
                        HorizontStatus.warning,
                        s.boxClockOffset(clockSourceText(key), formatOffset((value as num?)?.toInt() ?? 0)),
                      ),
                    ),
                  if (waiting > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: HzSpace.s4),
                      child: Text(s.boxWaiting(waiting), style: muted),
                    ),
                  const SizedBox(height: Gap.inner),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      icon: const Icon(AppIcons.dateTime, size: 18),
                      label: Text(s.boxClockSetNow),
                      onPressed: _info == null ? null : _setTime,
                    ),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.boxClockFromKnx),
                    subtitle: SwitchHint(s.boxClockFromKnxHint),
                    value: _config['clockFromKnx'] != false,
                    onChanged: _info == null ? null : (v) => _configure({'clockFromKnx': v}),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.boxRecordOnlyWithTime),
                    subtitle: SwitchHint(s.boxRecordOnlyWithTimeHint),
                    value: _config['recordOnlyWithTime'] == true,
                    onChanged: _info == null ? null : (v) => _configure({'recordOnlyWithTime': v}),
                  ),
                ],
                const SizedBox(height: Gap.section),
                Kennung(s.boxDevices, count: _admin ? _devices.length : null),
                const SizedBox(height: Gap.item),
                if (!_admin && _info != null)
                  HorizontStatusLine(HorizontStatus.info, s.boxNotAdmin)
                else
                  for (final d in _devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(d['name'] as String? ?? ''),
                      subtitle: Text(
                        [
                          if (d['self'] == true) s.boxDeviceSelf,
                          if (d['admin'] == true) s.boxDeviceAdmin,
                          if (d['viewOnly'] == true) s.boxDeviceViewOnly,
                        ].join(' · '),
                        style: muted,
                      ),
                      trailing: d['self'] == true
                          ? null
                          : TextButton(onPressed: () => _revoke(d['id']! as String), child: Text(s.boxDeviceRevoke)),
                    ),
                if (_admin) ...[
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxNetwork),
                  // Docker: the setting comes from LAN_ACCESS and only shows here.
                  if (_info?['container'] == true)
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.boxContainerLanAccess),
                      subtitle: SwitchHint(s.boxContainerLanAccessHint),
                      value: _info?['lanAccess'] == true,
                      onChanged: null,
                    )
                  else
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.boxLanAccess),
                      subtitle: SwitchHint(s.boxLanAccessHint),
                      value: _info?['lanAccess'] == true,
                      onChanged: _setLanAccess,
                    ),
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxHat),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.boxHatTitle),
                    subtitle: Text(s.boxHatHint),
                    trailing: const Icon(AppIcons.next),
                    onTap: () =>
                        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BoxHatScreen())),
                  ),
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxPasswordChange),
                  const SizedBox(height: Gap.item),
                  if (_info?['passwordChangeRequired'] != true) ...[
                    HorizontField(
                      label: s.boxPasswordCurrent,
                      child: TextField(
                        style: context.hzTheme.field,
                        controller: _currentPassword,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                      ),
                    ),
                    const SizedBox(height: Gap.item),
                  ],
                  HorizontField(
                    label: s.boxPasswordChange,
                    help: s.boxPasswordHint,
                    child: TextField(
                      style: context.hzTheme.field,
                      controller: _password,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(errorText: _passwordError),
                      onSubmitted: (_) => _changePassword(),
                    ),
                  ),
                  const SizedBox(height: Gap.inner),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton(onPressed: _changePassword, child: Text(s.boxPasswordChange)),
                  ),
                  if (_info?['wifiChange'] == true) ...[
                    const SizedBox(height: Gap.section),
                    Kennung(s.boxWifiChange),
                    const SizedBox(height: Gap.item),
                    HorizontField(
                      label: s.boxWifiChange,
                      help: s.boxWifiHint,
                      child: TextField(
                        style: context.hzTheme.field,
                        controller: _wifi,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        decoration: InputDecoration(errorText: _wifiError),
                        onSubmitted: (_) => _changeWifi(),
                      ),
                    ),
                    const SizedBox(height: Gap.inner),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton(onPressed: _changeWifi, child: Text(s.boxWifiChange)),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SoC temperature and throttling of the box's Raspberry Pi (`health` in
/// `/api/box`, server `box_health.dart`).
class BoxHealthSection extends StatelessWidget {
  const BoxHealthSection(this.health, {super.key});

  final Map<String, Object?> health;

  /// From here the temperature is shown as a warning (the firmware starts
  /// throttling at 80 °C) and as critical.
  static const warnFrom = 70.0;
  static const criticalFrom = 80.0;

  static String _degrees(num value) => value.toStringAsFixed(1).replaceAll('.', decimalSeparator);

  static String _flag(Object? flag) => switch (flag) {
    'underVoltage' => s.boxHealthFlagUnderVoltage,
    'freqCapped' => s.boxHealthFlagFreqCapped,
    'throttled' => s.boxHealthFlagThrottled,
    'softTempLimit' => s.boxHealthFlagSoftTempLimit,
    _ => '$flag',
  };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    final temp = health['temp'] as num?;
    final max = health['maxTemp'] as num? ?? temp;
    final now = (health['throttled'] as List?) ?? const [];
    final before = (health['throttledBefore'] as List?) ?? const [];
    // Bit 'throttled' is also set by under-voltage: only call it heat when the
    // soft temperature limit is active or the SoC is at the firmware's threshold.
    final hot = now.contains('softTempLimit') || (now.contains('throttled') && (temp ?? 0) >= criticalFrom);
    final lines = <Widget>[
      if (temp != null)
        HorizontStatusLine(
          temp >= criticalFrom || hot
              ? HorizontStatus.critical
              : temp >= warnFrom
              ? HorizontStatus.warning
              : HorizontStatus.positive,
          s.boxHealthTemp(_degrees(temp), _degrees(max!)),
        ),
      if (now.contains('underVoltage')) HorizontStatusLine(HorizontStatus.critical, s.boxHealthUnderVoltage),
      if (hot) HorizontStatusLine(HorizontStatus.critical, s.boxHealthThrottled),
      if (health.containsKey('throttled') && now.isEmpty && before.isEmpty)
        HorizontStatusLine(HorizontStatus.positive, s.boxHealthOk),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kennung(s.boxHealth),
        const SizedBox(height: Gap.item),
        for (final (i, line) in lines.indexed)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : HzSpace.s4),
            child: line,
          ),
        if (before.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: HzSpace.s4),
            child: Text(
              (health['throttledSince'] == 'serverStart' ? s.boxHealthBeforeServer : s.boxHealthBefore)(
                before.map(_flag).join(', '),
              ),
              style: muted,
            ),
          ),
      ],
    );
  }
}
