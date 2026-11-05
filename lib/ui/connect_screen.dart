import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_screen.dart';
import 'cloud_sync_screen.dart';
import 'full_backup_screen.dart';
import '../model/write_notice.dart';
import '../model/app_lock.dart';
import '../knx/gateway_info.dart';
import '../knx/secure/keyring_store.dart';
import '../knx/knx_tunnel.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart' show parseIndividual;
import '../model/alarm_notifier.dart';
import '../model/box_connection.dart';
import '../model/box_keyring_consent.dart';
import '../model/connection_options.dart';
import '../model/crash_guard.dart';
import '../model/history_store.dart';
import '../platform/addon.dart';
import '../platform/box_link.dart';
import '../platform/storage.dart';
import '../platform/native_bridge.dart';
import 'box_screens.dart';
import 'connection_options_panel.dart';
import '../catalog_store.dart';
import '../model/commissioning.dart';
import '../model/health.dart';
import '../knx/demo_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../model/expert_mode.dart';
import '../platform/udp.dart';
import '../theme/brand.dart';
import 'monitor_screen.dart';
import 'telegram_row.dart';
import 'support_package_screen.dart';
import 'server_restarts.dart';
import 'recordings_screen.dart';
import '../theme/app_icons.dart';
import 'common.dart';
import 'home_plan/home_plan_screen.dart';
import '../model/installation.dart';
import 'installation_list.dart';
import '../model/cloud_sync.dart';
import '../model/plan.dart';
import 'tour_screen.dart';
import 'plan_screen.dart';
import '../model/connect_help.dart';
import 'catalog_actions.dart' show importKeyring;
import 'learn_screen.dart';
import 'project_file_help_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  static const _hostKey = 'gateway_host';
  static const _portKey = 'gateway_port';
  static const _historyKey = 'gateway_history';

  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '3671');
  bool _busy = false;
  String? _error;

  /// Known cause of the last error, for the help with a next step.
  ConnectProblem? _problem;
  List<String> _history = const []; // „host:port“, neueste zuerst

  /// Status of continuous recording in the add-on (browser only).
  Map<String, Object?>? _addon;

  /// On first start in the add-on, go straight to the monitor if the server is
  /// already connected; after that the connect screen stays.
  static bool _autoOpened = false;

  /// In the Home Assistant panel at startup: while attaching to the server,
  /// show only a notice instead of the form (HA rebuilds the panel on every
  /// switch).
  late bool _attaching = Addon.embedded && !_autoOpened;

  /// Notice "KNX integration found" dismissed (per browser).
  bool _haHintDismissed = true;
  static const _haHintKey = 'ha_knx_hint_dismissed';

  @override
  void initState() {
    super.initState();
    unawaited(WriteNotice.instance.load());
    LocaleController.instance.addListener(_onLocale);
    // Expert mode shows and hides port, connection type and keyring.
    ExpertMode.instance.addListener(_onExpert);
    BoxConnection.instance.incoming.addListener(_onIncoming);
    BoxKeyringConsent.ask = _askKeyring;
    unawaited(_loadQuarantine());
    // Another installation: its gateway and history.
    InstallationStore.instance.addListener(_restore);
    _restore();
    if (Addon.available) {
      _loadAddon(autoOpen: !_autoOpened, report: Addon.box != null);
      // Cold start in box mode: the box has no battery-backed clock.
      if (Addon.box != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(syncBoxTime(context));
          unawaited(_shareWithBox());
          // Box updated from 1.9.1: the password from the sticker may still be
          // valid.
          if (mounted) unawaited(offerBoxPassword(context));
        });
      }
    }
    if (Addon.embedded) _loadHaHint();
    // Link the app was launched with.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onIncoming());
  }

  void _onExpert() => setState(() {});

  /// Notice after the app ended unexpectedly (never sent automatically).
  Widget _crashNotice(BuildContext context) => ListenableBuilder(
    listenable: CrashGuard.instance,
    builder: (context, _) {
      final when = CrashGuard.instance.unclean;
      if (when == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.section),
        child: CrashNotice(
          time: when,
          onReport: () async {
            await showSupportPackage(context, error: s.crashTitle, occurred: when);
            CrashGuard.instance.dismiss();
          },
          onDismiss: CrashGuard.instance.dismiss,
        ),
      );
    },
  );

  Future<void> _loadHaHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _haHintDismissed = prefs.getBool(_haHintKey) ?? false);
  }

  Future<void> _dismissHaHint() async {
    setState(() => _haHintDismissed = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_haHintKey, true);
  }

  Future<void> _adoptHat(Map<String, Object?> config) async {
    final options = ConnectionOptions.instance;
    options
      ..mode = ConnectionMode.hat
      ..hatAddress = switch (config['hatAddress']) {
        final String a => parseIndividual(a),
        _ => null,
      }
      ..hatBusmonitor = config['hatBusmonitor'] == true;
    await options.save();
  }

  /// Share the Home Assistant KNX integration: no tunnel of our own.
  Future<void> _useHaKnx() async {
    final options = ConnectionOptions.instance;
    options.mode = ConnectionMode.homeAssistant;
    await options.save();
    if (!mounted) return;
    setState(() {});
    await _connect();
  }

  Future<void> _loadAddon({bool autoOpen = false, bool report = false}) async {
    try {
      final status = await Addon.status();
      if (!mounted) return;
      setState(() => _addon = status);
      final config = (status['config'] as Map?)?.cast<String, Object?>() ?? const {};
      final host = config['host'] as String? ?? '';
      if (host.isNotEmpty && (_host.text.isEmpty || Addon.box != null)) _host.text = host;
      // Box on the KNX HAT: keep it, otherwise "Verbinden" (connect) would
      // reset it to the last selected IP connection.
      if (Addon.box != null && config['mode'] == 'hat') await _adoptHat(config);
      if (autoOpen && config['enabled'] == true) {
        _autoOpened = true;
        await _openShared();
      }
    } on AddonException catch (e) {
      // Box: show the reason (Wi-Fi, access). Add-on: older version without
      // continuous recording.
      if (report && mounted) setState(() => _error = e.message);
    } on Object {
      // Older add-on version without continuous recording.
    } finally {
      if (_attaching && mounted) setState(() => _attaching = false);
    }
  }

  // --- KNX-Box (nativ) ----------------------------------------------------------

  /// Pairing link from the QR code: ask, then connect via the box. If the
  /// monitor is currently running, the link waits until it is closed.
  ///
  /// Such a link can come from any app, web page or QR code: the box it leads
  /// to gets no project before the user confirmed that separately
  /// ([BoxProjectConsent]).
  Future<void> _onIncoming() async {
    final incoming = BoxConnection.instance.incoming;
    final link = incoming.value;
    if (link == null || !mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    incoming.value = null;
    // Foreign address: the clear warning in [_setupBox] is enough.
    if (!link.isLocal) return _setupBox(link, external: true);
    if (await _confirmBoxLink(link)) await _setupBox(link, external: true);
  }

  /// Plain confirmation (the platform's system dialog). The address comes first:
  /// the name is whatever the link says. Without a certificate fingerprint a
  /// clear warning that the connection is unencrypted.
  Future<bool> _confirmBoxLink(BoxLink link) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(s.boxPairTitle),
          content: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.item,
              children: [
                Text(
                  link.address,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (link.name.isNotEmpty) Text(s.boxPairNamed(link.name)),
                Text(s.boxPairBody),
                if (!link.encrypted) HorizontNotice(HorizontStatus.warning, child: Text(s.boxPairUnencrypted)),
              ],
            ),
          ),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: s.connectButton,
              onPressed: () => Navigator.pop(context, true),
              primary: true,
            ),
          ],
        ),
      ) ==
      true;

  static bool _sameBox(BoxLink saved, BoxLink link) {
    if (saved.url.host != link.url.host) return false;
    if (saved.fp.isNotEmpty && saved.fp != link.fp) return false;
    final sameAddress = saved.url.scheme == link.url.scheme && saved.url.port == link.url.port;
    final upgrade = saved.fp.isEmpty && link.fp.isNotEmpty && link.url.scheme == 'https';
    return sameAddress || upgrade;
  }

  static String _boxLabel(BoxLink box) => box.name.isEmpty ? box.address : '${box.name} (${box.address})';

  /// Another box is paired already: replacing it needs an explicit yes. The same
  /// box (same address including scheme and port; a box that only gained HTTPS
  /// with a fingerprint on the same host) does not ask.
  Future<bool> _confirmReplaceBox(BoxLink link) async {
    final saved = BoxConnection.instance.saved;
    if (saved == null || _sameBox(saved, link)) return true;
    return await showAdaptiveDialog<bool>(
          context: context,
          builder: (context) => AlertDialog.adaptive(
            title: Text(s.boxReplaceTitle),
            content: Text(s.boxReplaceBody(_boxLabel(saved), _boxLabel(link))),
            actions: [
              horizontDialogAction(
                context,
                label: s.commonCancel,
                primary: true,
                onPressed: () => Navigator.pop(context, false),
              ),
              horizontDialogAction(
                context,
                label: s.boxReplaceConfirm,
                destructive: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ==
        true;
  }

  /// Boxes whose project question was answered in this run: "not yet" is asked
  /// again only after the next start.
  static final _projectAsked = <String>{};

  /// Whether the project may go to [box]; asks once for a box paired via a link
  /// from outside ([BoxProjectConsent]).
  Future<bool> _projectAllowed(BoxLink box) async {
    if (!await BoxProjectConsent.pending(box)) return true;
    if (!mounted || !_projectAsked.add('${box.url}#${box.fp}')) return false;
    final ok =
        await showAdaptiveDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog.adaptive(
            title: Text(s.boxProjectTitle),
            content: Text(s.boxProjectBody(_boxLabel(box))),
            actions: [
              horizontDialogAction(context, label: s.boxProjectDeny, onPressed: () => Navigator.pop(context, false)),
              horizontDialogAction(
                context,
                label: s.boxProjectAllow,
                primary: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ==
        true;
    if (ok) await BoxProjectConsent.confirm(box);
    return ok;
  }

  /// Address not in the local network: connecting would send the project and
  /// more there.
  Future<bool> _confirmForeignBox(BoxLink link) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(s.boxForeignTitle),
          content: Text(s.boxForeignBody(link.address)),
          actions: [
            horizontDialogAction(
              context,
              label: s.commonCancel,
              primary: true,
              onPressed: () => Navigator.pop(context, false),
            ),
            horizontDialogAction(
              context,
              label: s.boxForeignConfirm,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ==
      true;

  /// Separate question before the keyring goes to this box for the first time.
  Future<bool?> _askKeyring(BoxLink box) async {
    if (!mounted) return null;
    return showAdaptiveDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.boxKeyringTitle),
        content: Text(s.boxKeyringBody(box.address)),
        actions: [
          horizontDialogAction(context, label: s.boxKeyringDeny, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.boxKeyringAllow,
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }

  StorageExtras _extras = noStorageExtras;

  Future<void> _loadQuarantine() async {
    try {
      final extras = await storageExtras();
      if (mounted) setState(() => _extras = extras);
    } on Object catch (e) {
      debugPrint('Ablage: $e');
    }
  }

  Future<void> _deleteQuarantine() async {
    final sure = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.quarantineDelete),
        content: Text(s.quarantineDeleteBody),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.quarantineDelete,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (sure != true) return;
    await deleteQuarantinedFiles();
    await _loadQuarantine();
  }

  /// Files whose key is missing: the app carries on empty, so the user must see
  /// that and how the data comes back.
  Widget _quarantineNotice() {
    final bytes = _extras.quarantinedBytes;
    final size = bytes < 1024 * 1024 ? '${(bytes / 1024).ceil()} KB' : '${(bytes / 1024 / 1024).round()} MB';
    return Padding(
      padding: const EdgeInsets.only(bottom: HzSpace.s16),
      child: SectionCard(
        title: s.quarantineTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: HzSpace.s8,
          children: [
            Text(s.quarantineBody(_extras.quarantinedFiles, size)),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              children: [
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FullBackupScreen())),
                  child: Text(s.quarantineRestore),
                ),
                OutlinedButton(onPressed: () => unawaited(_deleteQuarantine()), child: Text(s.quarantineDelete)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Setup from the sticker QR code: Wi-Fi, pairing, clock, gateway. [external]:
  /// the link came from outside the app ([_onIncoming]).
  Future<void> _setupBox(BoxLink link, {bool external = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!link.isLocal && !await _confirmForeignBox(link)) return;
    // Scanned or pasted without a certificate fingerprint: the same confirmation
    // with the warning (a link from outside has shown it already).
    if (!external && link.isLocal && !link.encrypted && (!mounted || !await _confirmBoxLink(link))) return;
    if (!mounted || !await _confirmReplaceBox(link)) return;
    if (!mounted || !await unlock(context, Feature.box) || !mounted) return;
    // Newly paired: ask again before sending the keyring.
    await BoxKeyringConsent.forget(link);
    // A link from outside may lead to a box someone else set up: the project
    // waits for an explicit yes. The app's own scanner and the pairing dialog
    // count as that yes.
    if (external) {
      await BoxProjectConsent.markPending(link);
    } else {
      await BoxProjectConsent.confirm(link);
    }
    if (!mounted) return;
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BoxSetupScreen(link: link, deviceName: boxDeviceName(context)),
      ),
    );
    if (done != true || !mounted) return;
    // Paired with the password from the sticker: offer to set a custom one
    // right away.
    await offerBoxPassword(context);
    if (!mounted) return;
    if (Addon.box case final box? when !await _projectAllowed(box)) {
      // Paired, but nothing of the project goes there yet.
      await _modeChanged();
      await _loadAddon(autoOpen: true, report: true);
      return;
    }
    // The box records for the active installation: same id, project, keyring
    // and gateway as this device. That way it knows names, types and timers,
    // records Secure readably, and the history is assigned.
    final installations = InstallationStore.instance;
    try {
      await installations.syncBox(adopt: false);
      await installations.useOnBox(installations.active.id);
    } on AddonException {
      // Older box without installations: project and keyring as before, if it
      // has none.
      try {
        if (await Addon.getFile('catalog.json') == null) await CatalogStore.instance.shareWithBox();
        if (await Addon.getFile('secure_keys.json') == null) await KeyringStore.instance.shareWithBox();
      } on AddonException {
        // Not essential for the setup.
      }
    }
    await _modeChanged();
    await _loadAddon(autoOpen: true, report: true);
  }

  /// "KNX-Box hinzufügen" (add KNX box): scan the QR code, paste it on desktop.
  Future<void> _addBox() async {
    if (!await unlock(context, Feature.box) || !mounted) return;
    if (canScanBox) {
      final text = await Navigator.of(context)
          .push<String>(MaterialPageRoute(builder: (_) => const BoxScannerScreen()));
      if (!mounted || text == null) return;
      if (text.isNotEmpty) {
        final link = BoxLink.parse(text);
        if (link != null) await _setupBox(link);
        return;
      }
    }
    await _pairBox();
  }

  /// Switches to the box: the gateway field, history and alarms then belong to
  /// it.
  Future<void> _useBox(BoxLink link) async {
    FocusManager.instance.primaryFocus?.unfocus();
    // Saved box: rejoin its Wi-Fi first (the system does not ask again).
    if (link.ssid.isNotEmpty && link.wifi.isNotEmpty) await NativeBridge.joinWifi(link.ssid, link.wifi);
    await BoxConnection.instance.use(link);
    await _modeChanged();
    if (mounted) await syncBoxTime(context);
    if (mounted) await offerBoxPassword(context);
    await _loadAddon(autoOpen: true, report: true);
  }

  Future<void> _leaveBox() async {
    await BoxConnection.instance.leave();
    await NativeBridge.leaveWifi();
    await _modeChanged();
    await _restore();
  }

  Future<void> _forgetBox() async {
    await BoxConnection.instance.forget();
    await _modeChanged();
  }

  Future<void> _modeChanged() async {
    if (!mounted) return;
    setState(() {
      _addon = null;
      _error = null;
      _problem = null;
    });
    // Via the box: learn its installations; the app follows the one the box is
    // currently recording (live view, project and history match).
    final installations = InstallationStore.instance;
    await installations.syncBox();
    if (installations.boxActive case final id? when id != installations.active.id) await installations.switchTo(id);
    await Future.wait([HistoryStore.instance.load(), AlarmNotifySetting.instance.load()]);
    await _shareWithBox();
  }

  /// Box (back) online: catch up on what it missed. If it has a different
  /// state, the user decides.
  Future<void> _shareWithBox() async {
    final installations = InstallationStore.instance;
    final box = Addon.box;
    if (box == null || !await _projectAllowed(box)) return;
    if (installations.boxList.isEmpty) await installations.syncBox(adopt: false);
    if (!await installations.shareChangesWithBox() || !mounted) return;
    final replace = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.boxShareDiffersTitle),
        content: Text(s.boxShareDiffersBody),
        actions: [
          horizontDialogAction(context, label: s.boxShareKeep, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.boxShareReplace,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (replace != true) return;
    try {
      await CatalogStore.instance.shareWithBox();
      await KeyringStore.instance.shareWithBox();
    } on Object catch (e) {
      debugPrint('An die Box geben: $e');
      if (mounted) setState(() => _error = s.boxShareFailed);
    }
  }

  Future<void> _pairBox() async {
    final link = await showAdaptiveDialog<BoxLink>(context: context, builder: (_) => const _PairDialog());
    if (link != null) await _setupBox(link);
  }

  /// Opens the monitor on the add-on's shared tunnel.
  Future<void> _openShared() async {
    final config = (_addon?['config'] as Map?)?.cast<String, Object?>() ?? const {};
    final tunnel = SharedTunnel(host: config['host'] as String? ?? '', port: config['port'] as int? ?? 3671);
    try {
      await tunnel.connect();
    } on KnxException catch (e) {
      // Server reachable, bus not (yet): open the monitor anyway; the server
      // keeps connecting and the view shows the reason.
      if (!tunnel.attached) {
        if (mounted) setState(() => _error = e.message);
        tunnel.dispose();
        return;
      }
    }
    if (!mounted) {
      tunnel.dispose();
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MonitorScreen(tunnel: tunnel)));
    tunnel.dispose();
    if (mounted) _loadAddon();
    await _onIncoming();
  }

  /// Pauses continuous recording (frees the tunnel, e.g. for the ETS) or
  /// resumes it.
  Future<void> _toggleAddon(bool enabled) async {
    try {
      final status = await Addon.configure({'enabled': enabled});
      if (mounted) setState(() => _addon = status);
    } on AddonException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Language change: rebuild texts (they read [s] directly).
  void _onLocale() => setState(() {});

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Without saved input, the gateway attached to the installation.
    final gateway = InstallationStore.instance.active.gateway;
    final saved = prefs.getString(InstallationStore.instance.key(_hostKey)) ?? '';
    _host.text = saved.isNotEmpty ? saved : gateway?.host ?? '';
    _port.text = '${prefs.getInt(InstallationStore.instance.key(_portKey)) ?? gateway?.port ?? 3671}';
    setState(() => _history = prefs.getStringList(InstallationStore.instance.key(_historyKey)) ?? const []);
  }

  @override
  void dispose() {
    LocaleController.instance.removeListener(_onLocale);
    ExpertMode.instance.removeListener(_onExpert);
    BoxConnection.instance.incoming.removeListener(_onIncoming);
    BoxKeyringConsent.ask = null;
    InstallationStore.instance.removeListener(_restore);
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    // Close the keyboard including the iPad shortcut bar before the monitor
    // appears.
    FocusManager.instance.primaryFocus?.unfocus();
    final host = _host.text.trim();
    final port = int.parse(_port.text.trim());
    setState(() {
      _busy = true;
      _error = null;
      _problem = null;
    });
    await _followInstallation(host, port);

    final options = ConnectionOptions.instance;
    final KnxTunnel tunnel;
    if (Addon.available) {
      // In the add-on the server connects and keeps the connection permanently.
      // It switches continuous recording and fault hunting over only once the
      // new connection is up; otherwise the previous one stays.
      try {
        _addon = await Addon.configure(await options.toAddonAsked(host: host, port: port), probe: true);
      } on AddonException catch (e) {
        if (mounted) {
          setState(() {
            _error = e.message;
            _problem = connectProblemNamed(e.problem);
            _busy = false;
          });
        }
        return;
      }
      tunnel = SharedTunnel(host: host, port: port);
    } else {
      try {
        tunnel = options.create(host, port);
      } on KnxException catch (e) {
        if (mounted) {
          setState(() {
            _error = e.message;
            _problem = e.problem;
            _busy = false;
          });
        }
        return;
      }
    }
    try {
      await tunnel.connect();
    } on KnxException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _problem = e.problem;
        });
      }
      tunnel.dispose();
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(InstallationStore.instance.key(_hostKey), host);
    await prefs.setInt(InstallationStore.instance.key(_portKey), port);
    final entry = '$host:$port';
    _history = [entry, ..._history.where((h) => h != entry)].take(5).toList();
    await prefs.setStringList(InstallationStore.instance.key(_historyKey), _history);
    if (!mounted) {
      tunnel.dispose();
      return;
    }
    // The monitor may report the installation the gateway belongs to.
    final switchTo = await Navigator.of(context)
        .push(MaterialPageRoute<String>(builder: (_) => MonitorScreen(tunnel: tunnel)));
    tunnel.dispose();
    if (mounted && Addon.available) _loadAddon();
    await _onIncoming();
    // Switch from the monitor: go there and reconnect right away.
    final target = InstallationStore.instance.byId(switchTo);
    if (target != null && mounted) {
      await InstallationStore.instance.switchTo(target.id);
      _host.text = host;
      _port.text = '$port';
      await _connect();
    }
  }

  /// Demo without an installation: sample house project in memory only; the
  /// user's own stays untouched and is back afterwards.
  Future<void> _demo() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final store = CatalogStore.instance;
    store.beginDemo(demoCatalog());
    HealthCheck.instance.startDemo();
    Commissioning.instance.startDemo();
    final tunnel = DemoTunnel();
    // Also on error or when the screen was closed: disconnect and restore the
    // user's own state.
    try {
      await tunnel.connect();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => MonitorScreen(tunnel: tunnel)));
    } finally {
      await tunnel.disconnect();
      tunnel.dispose();
      store.endDemo();
      // In demo mode, discard learned data and reload the saved state.
      await HealthCheck.instance.reload();
      await Commissioning.instance.reload();
    }
  }

  /// Next step from the help.
  Future<void> _helpAction(HelpAction action) => switch (action) {
    HelpAction.scan => _scan(),
    HelpAction.keyring => importKeyring(context),
    HelpAction.projectHelp => openProjectFileHelp(context),
    HelpAction.demo => _demo(),
  };

  bool _scanning = false;
  List<FoundGateway>? _found;

  Future<void> _scan() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _scanning = true;
      _found = [];
    });
    if (Addon.box != null) {
      // Via the box: it searches on its own cable; the app would not get
      // through its firewall.
      try {
        final found = [
          for (final g in (await Addon.discover()).cast<Map<Object?, Object?>>())
            if (GatewayInfo.parse(_hexBytes(g['dibs'] as String? ?? '')) case final info?)
              FoundGateway(g['host']! as String, info),
        ];
        if (mounted) setState(() => _found = found);
      } on AddonException catch (e) {
        if (mounted) setState(() => _error = e.message);
      }
    } else {
      await for (final g in scanGateways()) {
        if (!mounted) return;
        setState(() => _found = [..._found!, g]..sort((a, b) => a.host.compareTo(b.host)));
      }
    }
    if (mounted) setState(() => _scanning = false);
  }

  static Uint8List _hexBytes(String s) => Uint8List.fromList([
    for (var i = 0; i + 1 < s.length; i += 2) int.tryParse(s.substring(i, i + 2), radix: 16) ?? 0,
  ]);

  /// Expert mode: if the address belongs to another installation, switch there
  /// first (project, keyring and connection type then match).
  Future<void> _followInstallation(String host, int port) async {
    final store = InstallationStore.instance;
    if (!expert || !store.switchable) return;
    final other = store.byHost(host, port);
    if (other == null || other.id == store.active.id) return;
    await store.switchTo(other.id);
    // Switching loads the installation's gateway fields; the typed input wins.
    _host.text = host;
    _port.text = '$port';
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.installationSwitched(other.name))));
    }
  }

  /// Installation selected: connect with its gateway, otherwise fill in the
  /// fields. Installation switched: put its input or its gateway into the
  /// fields without connecting.
  void _switchedInstallation(Installation i) => _restore();

  void _useHistory(String entry) {
    final i = entry.lastIndexOf(':');
    _host.text = entry.substring(0, i);
    _port.text = entry.substring(i + 1);
    _connect();
  }

  String? _validateHost(String? v) {
    final text = v?.trim() ?? '';
    // Routing needs no gateway (multicast).
    if (text.isEmpty &&
        const {
          ConnectionMode.routing,
          ConnectionMode.homeAssistant,
          ConnectionMode.hat,
        }.contains(ConnectionOptions.instance.mode)) {
      return null;
    }
    if (text.isEmpty) return s.connectHostEmpty;
    if (text.contains(':')) return s.connectHostIpv4Only; // IPv6
    if (parseIPv4(text) == null && !RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(text)) {
      return s.connectHostInvalid;
    }
    return null;
  }

  String? _validatePort(String? v) {
    final p = int.tryParse(v?.trim() ?? '');
    return (p == null || p < 1 || p > 65535) ? s.connectPort : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Gap.gutterFor(width);
    // From tablet width two columns: connection on the left; history, box,
    // offline and settings on the right. Without expert mode the right column
    // is almost empty, so then one column even when wide. In portrait (iPad
    // upright) there is enough height: one column, stacked.
    final size = MediaQuery.sizeOf(context);
    final wide = width >= Breakpoints.expanded && size.width > size.height && ExpertMode.instance.value;
    final content = wide ? Widths.dashboard : Widths.form;
    // Large windows on desktop and in the browser: the content as a sheet with
    // a hairline on a lighter surface. iPhone and iPad stay borderless.
    final touch = switch (theme.platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final framed = !touch && width >= Breakpoints.large && width >= content + 2 * (_sheetPadding + gutter);

    if (_attaching) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: Gap.section,
            children: [
              const CircularProgressIndicator.adaptive(),
              Text(Addon.box != null ? s.boxAttaching : s.addonAttaching, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: framed ? context.hz.surface : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(gutter),
            child: ConstrainedBox(
              // Wide: use the space, up to Horizont's page width.
              constraints: BoxConstraints(maxWidth: content + (framed ? 2 * _sheetPadding : 0)),
              child: _sheet(
                framed: framed,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header: icon and name, the eyebrow label above,
                      // left-aligned.
                      Row(
                        children: [
                          const AppIconImage(size: HzSpace.s48),
                          const SizedBox(width: HzSpace.s16),
                          Expanded(
                            child: HorizontTitle(kennung: s.connectSubtitle, title: appName),
                          ),
                        ],
                      ),
                      const SizedBox(height: HzSpace.s32),
                      if (_extras.quarantinedFiles > 0) _quarantineNotice(),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // The connection gets more width than the secondary
                            // paths.
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _primary(context),
                              ),
                            ),
                            const SizedBox(width: HzSpace.s64),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: _secondary(context, first: true),
                              ),
                            ),
                          ],
                        )
                      else ...[
                        ..._primary(context),
                        ..._secondary(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Inner padding of the sheet in large windows.
  static const _sheetPadding = HzSpace.s48;

  /// The sheet around the content: paper with a hairline, only if [framed].
  Widget _sheet({required bool framed, required Widget child}) {
    if (!framed) return child;
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.bg,
        borderRadius: Radii.card,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Padding(padding: const EdgeInsets.all(_sheetPadding), child: child),
    );
  }

  /// Verbindung: Gateway, Optionen, Projekt, Verbinden, gefundene Gateways.
  List<Widget> _primary(BuildContext context) {
    final data = context.hzTheme.data;
    return [
      _crashNotice(context),
      const BackupReminderNotice(),
      if (Addon.box case final box?) ...[
        _BoxBar(
          box: box,
          onLeave: _busy ? null : _leaveBox,
          onSettings: () =>
              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BoxSettingsScreen())),
        ),
        const SizedBox(height: Gap.section),
      ],
      // The installation ties gateway, connection type, keyring and project
      // together; its tile therefore sits above everything that belongs to it.
      InstallationCard(
        busy: _busy,
        onSwitched: _switchedInstallation,
        switchable: expert && InstallationStore.instance.switchable,
        showKeyring: expert,
      ),
      const SizedBox(height: Gap.section),
      // Gateway and port as rows of a card: label on the left, field without
      // its own border on the right (focus shows the input while typing).
      AnimatedSize(
        duration: Motion.of(context),
        curve: Motion.curve,
        alignment: Alignment.topCenter,
        child: _SettingsCard(
          children: [
            _FieldRow(
              label: s.connectGateway,
              field: TextFormField(
                controller: _host,
                enabled: !_busy,
                // URL keyboard: dot (also on German iPhones) and host names.
                keyboardType: TextInputType.url,
                inputFormatters: const [dotForComma],
                textInputAction: TextInputAction.go,
                autocorrect: false,
                textAlign: TextAlign.end,
                style: data,
                decoration: _FieldRow.decoration.copyWith(
                  hintText: '192.168.1.10',
                  // Gateway search right in the field.
                  suffixIcon: HorizontFieldIconButton(
                    tooltip: s.scanGateways,
                    onPressed: _scanning || _busy ? null : _scan,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: HzSpace.s16,
                            child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
                          )
                        : const Icon(AppIcons.search),
                  ),
                ),
                validator: _validateHost,
                onFieldSubmitted: (_) => _connect(),
              ),
            ),
            // Port is almost always 3671; only for experts or if it differs.
            if (expert || _port.text.trim() != '3671')
              _FieldRow(
                label: s.connectPort,
                field: TextFormField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.end,
                  style: data,
                  // Invisible space the height of the search button in the
                  // gateway field: it keeps that field at the touch-target
                  // height, even when a smaller system font (iPad) shrinks the
                  // text field below.
                  decoration: _FieldRow.decoration.copyWith(
                    suffixIcon: const SizedBox.shrink(),
                    suffixIconConstraints: BoxConstraints(minHeight: context.hzTheme.controlHeight),
                  ),
                  validator: _validatePort,
                  onFieldSubmitted: (_) => _connect(),
                ),
              ),
          ],
        ),
      ),
      // Connection type and keyring only in expert mode, animated.
      AnimatedSize(
        duration: Motion.of(context),
        curve: Motion.curve,
        alignment: Alignment.topCenter,
        child: !expert
            ? const SizedBox(width: double.infinity)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Gap.inner),
                  ListenableBuilder(
                    listenable: ConnectionOptions.instance,
                    builder: (context, _) => ConnectionOptionsPanel(
                      enabled: !_busy,
                      // Box with HAT: the server offers the connection type.
                      hat: (_addon?['hat'] as Map?)?['present'] == true,
                    ),
                  ),
                ],
              ),
      ),
      // In the add-on with a configured KNX integration: share its connection
      // instead of a tunnel of our own.
      ListenableBuilder(
        listenable: ConnectionOptions.instance,
        builder: (context, _) =>
            Addon.embedded &&
                _addon?['haKnx'] == true &&
                !_haHintDismissed &&
                ConnectionOptions.instance.mode != ConnectionMode.homeAssistant
            ? Padding(
                padding: const EdgeInsets.only(top: Gap.inner),
                child: _HaKnxHint(onUse: _busy ? null : _useHaKnx, onDismiss: _dismissHaHint),
              )
            : const SizedBox.shrink(),
      ),
      if (_addon != null) ...[
        const SizedBox(height: Gap.inner),
        _AddonCard(status: _addon!, onOpen: _busy ? null : _openShared, onToggle: _busy ? null : _toggleAddon),
      ],
      const SizedBox(height: Gap.section),
      // The single primary action.
      FilledButton(
        onPressed: _busy ? null : _connect,
        child: _busy
            ? const SizedBox.square(
                dimension: HzSpace.s16,
                child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
              )
            : Text(s.connectButton),
      ),
      AnimatedSize(
        duration: Motion.of(context),
        curve: Motion.curve,
        child: _error == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(top: Gap.section),
                child: HorizontNotice(
                  HorizontStatus.critical,
                  action: IconButton(
                    tooltip: s.diagTitle,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showSupportPackage(context, error: _error, occurred: DateTime.now()),
                    icon: const Icon(AppIcons.supportPackage, size: HzIconSize.row),
                  ),
                  child: Text(_error!),
                ),
              ),
      ),
      if (_error != null)
        if (connectHelp(_problem, mode: ConnectionOptions.instance.mode, port: int.tryParse(_port.text.trim()) ?? 3671)
            case final help?)
          Padding(
            padding: const EdgeInsets.only(top: Gap.inner),
            child: ConnectHelpCard(help: help, onAction: _busy ? null : _helpAction),
          ),
      _GatewayResults(
        found: _found,
        running: _scanning,
        box: Addon.box != null,
        onHelpAction: _busy ? null : _helpAction,
        onPick: (host) {
          _host.text = host;
          _port.text = '3671';
          setState(() => _found = null);
          _connect();
        },
      ),
    ];
  }

  /// Recently used, KNX box, offline, settings. [first]: own column, no spacing
  /// at the top.
  List<Widget> _secondary(BuildContext context, {bool first = false}) {
    final data = context.hzTheme.data;
    // Expert mode: installations (in the tile on the left) instead of the
    // recently used addresses.
    final installations = expert && InstallationStore.instance.switchable;
    final history = !installations && _history.isNotEmpty;
    return [
      // Native, expert mode: via the KNX box instead of directly at the
      // gateway. Sits as the second path right below "Verbinden" (connect).
      if (expert && !Addon.embedded && Addon.box == null) ...[
        if (!first) const SizedBox(height: HzSpace.s8),
        if (BoxConnection.instance.saved case final saved?)
          Padding(
            padding: const EdgeInsets.only(bottom: HzSpace.s8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
                    icon: const Icon(AppIcons.box, size: 18),
                    label: Text(saved.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: _busy ? null : () => _useBox(saved),
                  ),
                ),
                IconButton(
                  tooltip: s.boxForget,
                  onPressed: _busy ? null : _forgetBox,
                  icon: const Icon(AppIcons.delete),
                ),
              ],
            ),
          ),
        _SideButton(label: s.boxAdd, onPressed: _busy ? null : _addBox),
      ],
      if (history) ...[
        const SizedBox(height: HzSpace.s32),
        SectionTitle(s.connectRecent, count: _history.length),
        const SizedBox(height: HzSpace.s8),
        Wrap(
          spacing: HzSpace.s8,
          runSpacing: HzSpace.s8,
          children: [
            for (final h in _history)
              OutlinedButton.icon(
                icon: const Icon(AppIcons.history, size: 18),
                label: Text(h.endsWith(':3671') ? h.substring(0, h.length - 5) : h, style: data),
                onPressed: _busy ? null : () => _useHistory(h),
              ),
          ],
        ),
      ],
      const SizedBox(height: HzSpace.s32),
      SectionTitle(s.connectWithout),
      const SizedBox(height: HzSpace.s8),
      // Demo for everyone (professionals too: training, presentations), the
      // introduction next to it, highlighted while a chapter is unseen;
      // recordings in expert mode in the row below.
      //
      // In pairs side by side, equal height even when a label wraps to two
      // lines; with large text stacked, otherwise "Introduction" would break
      // mid-word.
      ..._pairs([
        _TourButton(onDemo: _busy ? null : _demo),
        _SideButton(label: s.connectDemoShort, onPressed: _busy ? null : _demo),
        if (expert)
          _SideButton(
            label: s.recordingsTitle,
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RecordingsScreen())),
          ),
        // For beginners: glossary and quiz, help with the project file.
        if (!expert) ...[
          _SideButton(label: s.lessonsTitle, onPressed: () => openLearn(context)),
          _SideButton(label: s.projectHelpShort, onPressed: () => openProjectFileHelp(context)),
        ],
        if (homePlanAvailable)
          _SideButton(
            label: s.hpEntry,
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const HomePlanScreen())),
          ),
      ]),
      const SizedBox(height: HzSpace.s32),
      SectionTitle(s.menuGroupSettings),
      const SizedBox(height: HzSpace.s8),
      ListenableBuilder(
        listenable: Listenable.merge([WriteNotice.instance, Plan.instance]),
        builder: (context, _) {
          final plan = Plan.instance;
          return _SettingsCard(
            children: [
              const _ExpertSwitch(),
              if (WriteNotice.instance.dismissed)
                _LinkRow(label: s.writeNoticeRestore, onTap: WriteNotice.instance.restore),
              if (plan.purchasable || plan.beta) const _PlanRow(),
              // Also reachable offline: whoever wants to back up or lock is
              // often not at the installation.
              if (AppLock.instance.available) ...[
                _LinkRow(
                  label: s.appLockSettings,
                  onTap: () =>
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const AppLockSettingsScreen())),
                ),
                _LinkRow(
                  label: s.backupTitle,
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FullBackupScreen())),
                ),
                if (CloudSync.instance.supported)
                  _LinkRow(
                    label: s.cloudSyncTitle,
                    onTap: () async {
                      if (!await unlock(context, Feature.cloudSync) || !context.mounted) return;
                      await Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const CloudSyncScreen()));
                    },
                  ),
              ],
            ],
          );
        },
      ),
      const SizedBox(height: HzSpace.s16),
      const Center(child: _LanguageSwitch()),
    ];
  }

  /// Buttons in rows of two; with large text each at full width.
  List<Widget> _pairs(List<Widget> buttons) {
    if (MediaQuery.textScalerOf(context).scale(10) > 13) {
      return [
        for (final (i, b) in buttons.indexed) ...[if (i > 0) const SizedBox(height: HzSpace.s8), b],
      ];
    }
    return [
      for (var i = 0; i < buttons.length; i += 2) ...[
        if (i > 0) const SizedBox(height: HzSpace.s8),
        IntrinsicHeight(
          child: Row(
            spacing: HzSpace.s8,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: buttons[i]),
              if (i + 1 < buttons.length) Expanded(child: buttons[i + 1]) else const Spacer(),
            ],
          ),
        ),
      ],
    ];
  }
}

/// Card with rows separated by hairlines: gateway fields and settings.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: context.hz.surface,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.box,
      side: BorderSide(color: context.hz.line, width: Lines.hairline),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const Divider(height: Lines.hairline, indent: HzSpace.s16, endIndent: HzSpace.s16),
          child,
        ],
      ],
    ),
  );
}

/// Row with a label on the left and a borderless input field on the right.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.field});

  final String label;
  final Widget field;

  /// Borderless at rest; focus and errors stay visible.
  static const decoration = InputDecoration(
    filled: false,
    isDense: true,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
    errorMaxLines: 3,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(HzSpace.s16, HzSpace.s4, HzSpace.s8, HzSpace.s4),
    child: Row(
      spacing: HzSpace.s12,
      children: [
        ExcludeSemantics(child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
        Expanded(
          child: Semantics(label: label, child: field),
        ),
      ],
    ),
  );
}

/// Settings row: text, an optional value, chevron.
class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap, this.value});

  final String label;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final theme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: HzSpace.s48),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(HzSpace.s16, HzSpace.s8, HzSpace.s12, HzSpace.s8),
          child: Row(
            spacing: HzSpace.s8,
            children: [
              Expanded(child: Text(label, style: theme.bodyLarge)),
              if (value case final value?) Text(value, style: theme.bodyMedium?.copyWith(color: hz.textMuted)),
              Icon(AppIcons.next, size: HzIconSize.row, color: hz.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// Expert mode also before connecting: port, connection type, keyring and all
/// tools.
class _ExpertSwitch extends StatelessWidget {
  const _ExpertSwitch();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: ExpertMode.instance,
    builder: (context, on, _) => MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: HzSpace.s48),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(HzSpace.s16, HzSpace.s4, HzSpace.s8, HzSpace.s4),
          child: Row(
            children: [
              Expanded(child: Text(s.expertMode, style: Theme.of(context).textTheme.bodyLarge)),
              Switch.adaptive(value: on, onChanged: ExpertMode.instance.set),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Tier before connecting: view prices, restore purchases, manage subscription
/// (payment page). Only where there is something to buy, or in the beta.
class _PlanRow extends StatelessWidget {
  const _PlanRow();

  @override
  Widget build(BuildContext context) {
    final plan = Plan.instance;
    final beta = plan.beta && !plan.betaStore;
    return _LinkRow(
      label: beta ? s.planBetaTitle : s.planTitle,
      value: beta ? 'Beta' : tierName(plan.value),
      onTap: () => beta ? showBetaInfo(context) : showPlanScreen(context),
    );
  }
}

/// Surface with hairline and radius 6 (like fields and buttons) for the box and
/// add-on notices.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(Gap.card, Gap.inner, HzSpace.s8, Gap.inner),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.surface,
        border: Border.all(color: hz.line, width: Lines.hairline),
        borderRadius: Radii.tile,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Notice at the top in box mode: which box the app runs through, back to the
/// gateway.
class _BoxBar extends StatelessWidget {
  const _BoxBar({required this.box, required this.onLeave, required this.onSettings});

  final BoxLink box;
  final VoidCallback? onLeave;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return _Panel(
      child: Row(
        children: [
          Icon(AppIcons.box, color: hz.textMuted, size: HzIconSize.row),
          const SizedBox(width: Gap.inner),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.boxVia(box.label), style: theme.textTheme.titleSmall),
                const SizedBox(height: HzSpace.s2),
                Text(s.boxGatewayHint, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ],
            ),
          ),
          IconButton(tooltip: s.boxSettings, onPressed: onSettings, icon: const Icon(AppIcons.expert)),
          TextButton(onPressed: onLeave, child: Text(s.boxLeave)),
        ],
      ),
    );
  }
}

/// Manual pairing: paste the link from the QR code or enter the address and box
/// password (desktop without camera, e.g. the Linux app).
class _PairDialog extends StatefulWidget {
  const _PairDialog();

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  final _text = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  /// If the clipboard holds a pairing link, take it right away.
  Future<void> _prefill() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted || _text.text.isNotEmpty) return;
    if (clip.contains('${BoxLink.scheme}:') && BoxLink.parse(clip) != null) _text.text = clip.trim();
  }

  @override
  void dispose() {
    _text.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final link = BoxLink.parse(_text.text);
    if (link == null) {
      setState(() => _error = s.boxLinkInvalid);
      return;
    }
    Navigator.pop(context, link.withPassword(_password.text.trim()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    icon: const Icon(AppIcons.box),
    title: Text(s.boxPair),
    // Material for the text field in the Cupertino dialog.
    content: Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.boxPairHint),
          const SizedBox(height: Gap.section),
          HorizontField(
            label: s.boxPairField,
            child: TextField(
              controller: _text,
              autofocus: true,
              autocorrect: false,
              style: context.hzTheme.data,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(hintText: '10.42.0.1', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: Gap.section),
          HorizontField(
            label: s.boxPairPassword,
            help: s.boxPairPasswordHint,
            child: TextField(
              controller: _password,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
      horizontDialogAction(context, label: s.connectButton, primary: true, onPressed: _submit),
    ],
  );
}

/// Continuous recording in the add-on: status, open monitor, pause/resume. "KNX
/// Monitor wurde unerwartet beendet" (quit unexpectedly) with the way to the
/// diagnostics bundle.
class CrashNotice extends StatelessWidget {
  const CrashNotice({super.key, required this.time, required this.onReport, required this.onDismiss});

  final DateTime time;
  final VoidCallback onReport;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(HorizontStatus.warning.icon, color: hz.warning, size: HzIconSize.row),
              const SizedBox(width: Gap.inner),
              Expanded(child: Text(s.crashTitle, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: Gap.item),
          Text(
            s.crashBody('${formatDate(time)} ${formatTime(time, seconds: false)}'),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
          const SizedBox(height: Gap.item),
          Wrap(
            spacing: Gap.item,
            children: [
              OutlinedButton(onPressed: onReport, child: Text(s.crashReport)),
              TextButton(onPressed: onDismiss, child: Text(s.crashDismiss)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddonCard extends StatelessWidget {
  const _AddonCard({required this.status, required this.onOpen, required this.onToggle});

  final Map<String, Object?> status;
  final VoidCallback? onOpen;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final config = (status['config'] as Map?)?.cast<String, Object?>() ?? const {};
    final enabled = config['enabled'] == true;
    final configured =
        (config['host'] as String? ?? '').isNotEmpty || const {'routing', 'ha', 'hat'}.contains(config['mode']);
    if (!configured) return const SizedBox.shrink();
    final connected = status['state'] == 'connected';
    final since = status['since'] as int?;
    final target = switch (config['mode']) {
      'routing' => s.connectModeRouting,
      'ha' => s.connectModeHa,
      'hat' => s.connectModeHat,
      _ => '${config['host']}',
    };
    // Broken server.json without backup: the server stays idle until
    // reconnected.
    final lost = status['configLost'] == true;
    final line = lost
        ? s.addonConfigLost
        : !enabled
        ? s.addonPaused
        : connected
        ? s.addonConnectedSince(
            target,
            since == null ? '–' : formatTime(DateTime.fromMillisecondsSinceEpoch(since), seconds: false),
            status['today'] as int? ?? 0,
          )
        : (status['error'] as String?) ?? (Addon.box != null ? s.boxConnecting : s.addonConnecting);
    // State shown as symbol, word (the row) and color.
    final state = lost
        ? HorizontStatus.critical
        : !enabled
        ? HorizontStatus.neutral
        : connected
        ? HorizontStatus.positive
        : status['error'] != null
        ? HorizontStatus.critical
        : HorizontStatus.info;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(Gap.card, Gap.inner, HzSpace.s8, HzSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status['restarts'] case final Map<dynamic, dynamic> restarts) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s4),
              child: ServerRestartsLine(restarts.cast<String, Object?>()),
            ),
          ],
          if (status['lowSpace'] == true)
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s4),
              child: HorizontStatusLine(HorizontStatus.critical, s.boxLowSpace),
            ),
          Row(
            children: [
              Icon(AppIcons.sensors, color: hz.textMuted, size: HzIconSize.row),
              const SizedBox(width: Gap.inner),
              Expanded(
                child: Text(Addon.box != null ? s.boxRecordingTitle : s.addonTitle, style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          const SizedBox(height: HzSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(state.icon, size: 16, color: state.color(hz)),
              const SizedBox(width: HzSpace.s8),
              Expanded(
                child: Text(
                  line,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: state == HorizontStatus.critical ? hz.critical : hz.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: HzSpace.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: HzSpace.s8,
            children: [
              TextButton(
                onPressed: onToggle == null ? null : () => onToggle!(!enabled),
                child: Text(enabled ? s.addonPause : s.addonResume),
              ),
              if (enabled) OutlinedButton(onPressed: onOpen, child: Text(s.addonOpen)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Suggestion in the add-on: Home Assistant has a KNX integration, the add-on
/// can share its connection.
class _HaKnxHint extends StatelessWidget {
  const _HaKnxHint({required this.onUse, required this.onDismiss});

  final VoidCallback? onUse;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return _Panel(
      padding: const EdgeInsets.fromLTRB(Gap.card, Gap.inner, HzSpace.s8, HzSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(AppIcons.installation, color: hz.textMuted, size: HzIconSize.row),
              const SizedBox(width: Gap.inner),
              Expanded(child: Text(s.haKnxHintTitle, style: theme.textTheme.titleSmall)),
            ],
          ),
          const SizedBox(height: HzSpace.s4),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: HzSpace.s8),
            child: Text(s.haKnxHintBody, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ),
          const SizedBox(height: HzSpace.s4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: HzSpace.s8,
            children: [
              TextButton(onPressed: onDismiss, child: Text(s.haKnxHintDismiss)),
              OutlinedButton(onPressed: onUse, child: Text(s.haKnxHintUse)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Language choice German/English; applies to the whole app immediately.
class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch();

  @override
  Widget build(BuildContext context) {
    final controller = LocaleController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.language, size: 18, color: context.hz.textMuted),
          const SizedBox(width: HzSpace.s8),
          // Language names deliberately untranslated, so everyone finds their
          // language.
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'de', label: Text('Deutsch')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {controller.locale.languageCode},
            onSelectionChanged: (v) => controller.setLocale(Locale(v.first)),
          ),
        ],
      ),
    );
  }
}

/// Result of the gateway search (magnifier in the field): devices found as rows
/// with hairlines, IP and addresses in Monaspace.
class _GatewayResults extends StatelessWidget {
  const _GatewayResults({
    required this.found,
    required this.running,
    required this.onPick,
    this.box = false,
    this.onHelpAction,
  });

  final List<FoundGateway>? found;
  final bool running;
  final ValueChanged<String> onPick;

  /// Searched via the box (it searches on its own cable).
  final bool box;
  final ValueChanged<HelpAction>? onHelpAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final found = this.found;
    final line = BorderSide(color: hz.line, width: Lines.hairline);
    return AnimatedSize(
      duration: Motion.of(context),
      curve: Motion.curve,
      child: found == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: Gap.inner),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (running && found.isEmpty)
                    Text(s.scanRunning, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                  if (!running && found.isEmpty)
                    ConnectHelpCard(
                      help: noGatewayHelp(box: box),
                      onAction: onHelpAction,
                    ),
                  for (final (i, g) in found.indexed)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(top: i == 0 ? line : BorderSide.none, bottom: line),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(AppIcons.sensors, color: hz.textMuted),
                        title: Text(g.info.name.isEmpty ? g.host : g.info.name),
                        subtitle: Text(
                          [g.host, g.info.mediumText, g.info.addressText, ?freeTunnels(g.info)].join(metaSeparator),
                          style: data.copyWith(color: hz.textMuted),
                        ),
                        trailing: Icon(AppIcons.next, color: hz.textFaint),
                        onTap: () => onPick(g.host),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Equal-width secondary button: outlined, shape from the theme. Opens the
/// introduction; while a chapter of the user's tier is unseen (also after an
/// upgrade), with border and icon in the accent color.
class _TourButton extends StatelessWidget {
  const _TourButton({required this.onDemo});

  /// Opens the demo house (last card of the introduction); `null` disables the
  /// button while a connection is being established.
  final Future<void> Function()? onDemo;

  Future<void> _open(BuildContext context) async {
    final result = await showTour(context);
    if (result == TourResult.demo) await onDemo?.call();
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    // Disabled while a connection is being established (like the buttons next
    // to it).
    onPressed: onDemo == null ? null : () => _open(context),
    child: Text(s.tourButton, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
  );
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onPressed,
    child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
  );
}

/// Help for a connection error: title, next steps, buttons.
class ConnectHelpCard extends StatelessWidget {
  const ConnectHelpCard({super.key, required this.help, this.onAction});

  final ConnectHelp help;
  final ValueChanged<HelpAction>? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return SectionCard(
      soft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(help.title, style: theme.textTheme.titleSmall),
          const SizedBox(height: HzSpace.s8),
          for (final (i, step) in help.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: HzSpace.s24,
                    child: Text('${i + 1}.', style: context.hzTheme.data.copyWith(color: hz.textMuted)),
                  ),
                  Expanded(child: Text(step, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          if (help.actions.isNotEmpty) ...[
            const SizedBox(height: HzSpace.s8),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              children: [
                for (final a in help.actions)
                  OutlinedButton(
                    onPressed: onAction == null ? null : () => onAction!(a),
                    child: Text(switch (a) {
                      HelpAction.scan => s.helpActionScan,
                      HelpAction.keyring => s.helpActionKeyring,
                      HelpAction.projectHelp => s.helpActionProject,
                      HelpAction.demo => s.helpActionDemo,
                    }),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
