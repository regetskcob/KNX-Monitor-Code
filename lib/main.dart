import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import 'catalog_store.dart';
import 'model/activity_range.dart';
import 'model/live_plain.dart';
import 'model/app_log.dart';
import 'knx/secure/keyring_store.dart';
import 'model/connection_options.dart';
import 'model/alarm_notifier.dart';
import 'model/annotation.dart';
import 'model/export_history.dart';
import 'model/box_connection.dart';
import 'model/cloud_sync.dart';
import 'model/company.dart';
import 'model/crash_guard.dart';
import 'model/customer.dart';
import 'model/expert_mode.dart';
import 'model/handover.dart';
import 'model/history_store.dart';
import 'model/installation.dart';
import 'model/plan.dart';
import 'model/plant_report.dart';
import 'model/tour.dart';
import 'l10n/locale_controller.dart';
import 'platform/addon.dart';
import 'platform/incoming_files.dart';
import 'platform/prefs_repair.dart';
import 'platform/storage.dart';
import 'platform/store_plan.dart';
import 'model/plan_source.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/common.dart';
import 'ui/app_lock_screen.dart';
import 'ui/connect_screen.dart';
import 'ui/crash_banner.dart';
import 'ui/handover_screen.dart' show openIncomingFile;
import 'ui/plan_screen.dart' show PlanNoticeGate;
import 'ui/support_package_screen.dart' show showSupportPackage;
import 'ui/splash.dart';
import 'model/watch_rules.dart';
import 'model/account.dart';
import 'model/app_lock.dart';
import 'model/betrieb/team.dart';

void main([List<String> args = const []]) {
  WidgetsFlutterBinding.ensureInitialized();
  // Record the latest log messages and errors for the diagnostics package.
  AppLog.instance.install();
  registerHorizontLicenses();
  // Purchase path: stores via RevenueCat, Windows via the account; see planSourceFor.
  PlanSource.forPlatform = storePlanSource;
  // Intercept pairing links of the KNX box (QR code) before the navigator sees them.
  if (!kIsWeb) BoxConnection.instance.listen();
  Account.instance.listen();
  // Files from mail, AirDrop, file manager; opened only once the UI is up.
  IncomingFiles.instance.listen(args);
  // Maintenance date from the customer file to box or add-on (date only).
  MaintenanceSync.instance.start();
  // Android: draw under the system bars – the tab bar colours the area below.
  if (!kIsWeb) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const KnxMonitorApp());
}

class KnxMonitorApp extends StatefulWidget {
  const KnxMonitorApp({super.key});

  @override
  State<KnxMonitorApp> createState() => _KnxMonitorAppState();
}

class _KnxMonitorAppState extends State<KnxMonitorApp> {
  // Loads in parallel with the splash animation. The installation first: project, keyring and
  // settings depend on it. If the installations arrive only after the deadline, the app reloads its
  // stores as soon as the first load has finished ([InstallationStore.loadWithin]).
  final _storesLoaded = Completer<void>();
  late final Future<void> _loading = ensurePreferencesReadable()
      // Before anything else: nothing may flash up unlocked after the splash.
      .then((_) => _guard('App-Sperre', AppLock.instance.load))
      // Before the stores: they keep their state in memory.
      // No timeout: if it kept running after loading, the stores would overwrite the files.
      .then((_) => CloudSync.instance.applyPending().catchError((Object e) => debugPrint('Abgleich: $e')))
      .then((_) => InstallationStore.instance.loadWithin(loadTimeout, storesLoaded: _storesLoaded.future))
      // Newer format: load nothing that could write anything.
      .then((_) => InstallationStore.instance.tooNew ? null : _loadStores())
      .whenComplete(_storesLoaded.complete)
      .whenComplete(() => InstallationStore.instance.tooNew ? null : unawaited(CloudSync.instance.start()));

  @override
  void initState() {
    super.initState();
    _loading; // start immediately, in parallel with the splash animation
  }

  /// The app always starts: every loader gets a deadline and may fail. Whatever is missing then
  /// stays at its default and keeps loading in the background; the message ends up in the log for
  /// the diagnostics package.
  static const loadTimeout = Duration(seconds: 6);

  static Future<void> _guard(String name, Future<void> Function() load, {Duration timeout = loadTimeout}) async {
    try {
      await load().timeout(timeout);
    } on TimeoutException {
      debugPrint('Start: $name nach ${timeout.inSeconds} s noch nicht geladen – weiter ohne');
    } on Object catch (e, st) {
      debugPrint('Start: $name nicht geladen: $e\n$st');
    }
  }

  static Future<void> _accountThenPlan() {
    final account = Account.instance.load();
    return Future.wait([
      _guard('Konto', () => account),
      _guard('Freischaltung', () => account.then((_) {}, onError: (Object _) {}).then((_) => Plan.instance.load())),
    ]);
  }

  static Future<void> _loadStores() =>
      Future.wait([
            // First and with a deadline: detection must never hold up the start.
            _guard('Absturzerkennung', CrashGuard.instance.start),
            // First: in box mode, history and alarms query the box.
            _guard('Box', BoxConnection.instance.load).then(
              (_) => Future.wait([
                _guard('Verlauf', HistoryStore.instance.load),
                _guard('Alarm-Mitteilungen', AlarmNotifySetting.instance.load),
              ]),
            ),
            _guard('Projekt', CatalogStore.instance.load),
            _guard('Wächter', WatchRules.instance.load),
            _guard('Sprache', LocaleController.instance.load),
            _guard('Expertenmodus', ExpertMode.instance.load),
            // The account first: Windows then chooses the purchase source. Unlocking waits for the
            // account to really finish (not just for the deadline), otherwise it would take the
            // wrong source; if the account fails, it loads anyway.
            _accountThenPlan(),
            _guard('Zeitraum', ActivityRangeSetting.instance.load),
            _guard('Klartext', LivePlainSetting.instance.load),
            _guard('Rundgang', TourProgress.instance.load),
            _guard('Verbindungsoptionen', ConnectionOptions.instance.load),
            _guard('Keyring', KeyringStore.instance.load),
            _guard('Kommentare', AnnotationStore.instance.load),
            _guard('Exportverlauf', ExportHistory.instance.load),
            _guard('Firma', CompanyStore.instance.load),
            _guard('Kundenakte', CustomerStore.instance.load),
            _guard('Herkunft', HandoverStore.instance.load),
            // Notifications follow expert mode as soon as both are loaded.
          ])
          .then((_) => _guard('Mitteilungen', () async => AlarmNotifySetting.instance.followExpertMode()))
          .then(
            // Team feature: without the BETRIEB switch or without an account, no network and no
            // effect.
            (_) => _guard('Team', Team.instance.load),
          )
          // Data from older versions; runs alongside and holds nothing up.
          .then((_) => unawaited(encryptExistingFiles().catchError((Object e) => debugPrint('Ablage: $e'))));
  bool _ready = false;
  final _navigator = GlobalKey<NavigatorState>();

  /// Pages above the connect screen show the crash notice as a banner.
  final _routes = PageRouteTracker();

  Future<void> _reportCrash(DateTime when) async {
    final context = _navigator.currentState?.overlay?.context;
    if (context == null) return;
    await showSupportPackage(context, error: s.crashTitle, occurred: when, crash: true);
    CrashGuard.instance.dismiss();
  }

  /// From now on stores and UI are in place: waiting files may open.
  void _openIncomingFiles() {
    IncomingFiles.instance.attach((file) async {
      final context = _navigator.currentState?.overlay?.context;
      if (context != null) await openIncomingFile(context, file);
    });
  }

  Future<void> _splashDone() async {
    // Last safeguard: after this deadline the app shows itself in any case.
    try {
      await _loading.timeout(loadTimeout * 2);
    } on Object catch (e) {
      debugPrint('Start: Laden nicht fertig ($e) – App startet trotzdem');
    }
    if (!mounted) return;
    setState(() => _ready = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIncomingFiles());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        navigatorObservers: [_routes],
        title: 'KNX Monitor',
        debugShowCheckedModeBanner: false,
        scrollBehavior: const AppScrollBehavior(),
        // In the add-on (Ingress) with Home Assistant's neutral colours.
        theme: AppTheme.light(homeAssistant: Addon.embedded),
        darkTheme: AppTheme.dark(homeAssistant: Addon.embedded),
        themeAnimationStyle: AnimationStyle.noAnimation,
        locale: LocaleController.instance.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // The app has no named routes; links open nothing except box pairing.
        initialRoute: '/',
        // Android navigation bar transparent and without contrast scrim, icons matching the
        // brightness.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarContrastEnforced: false,
            systemNavigationBarIconBrightness: Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: AppLockGate(
            child: CrashBannerHost(routes: _routes, onReport: _reportCrash, child: child!),
          ),
        ),
        home: Builder(
          builder: (context) => AnimatedSwitcher(
            duration: Motion.slowOf(context),
            switchInCurve: Motion.curve,
            transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
            child: !_ready
                ? SplashScreen(onDone: _splashDone)
                : InstallationStore.instance.tooNew
                ? const _NewerDataScreen()
                : const PlanNoticeGate(child: ConnectScreen()),
          ),
        ),
      ),
    );
  }
}

/// The data comes from a newer app. It is left untouched.
class _NewerDataScreen extends StatelessWidget {
  const _NewerDataScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                Text(s.installationsNewerTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                Text(s.installationsNewerBody, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
