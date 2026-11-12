import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../model/customer.dart';
import '../model/app_lock.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/tokens.dart';
import '../theme/brand.dart';
import '../model/alarm_notifier.dart';
import '../knx/demo_tunnel.dart';
import '../knx/secure/keyring_store.dart';
import 'catalog_actions.dart' show importKeyring;
import '../knx/shared_tunnel.dart';
import '../model/send_scheduler.dart';
import '../model/auto_reconnect.dart';
import '../model/health.dart';
import '../model/history_store.dart';
import '../model/recording.dart';
import '../monitor_model.dart';
import '../platform/native_bridge.dart';
import '../platform/notify.dart';
import 'busmonitor_screen.dart';
import 'common.dart';
import 'company_screen.dart';
import 'customers_screen.dart';
import 'handover_screen.dart';
import 'commissioning_screen.dart';
import 'floor_view_screen.dart';
import 'health_screen.dart';
import 'home_plan/home_plan_screen.dart';
import 'diagnostics_screen.dart';
import 'trigger_dialog.dart';
import '../theme/palette.dart';
import 'gateway_sheet.dart';
import 'log_view.dart';
import 'recordings_screen.dart';
import 'tap_strip.dart';
import 'telegram_row.dart';
import 'betrieb/betrieb_menu.dart';
import 'betrieb/site_notes_screen.dart';
import 'more_menu.dart';
import 'plan_screen.dart';
import '../theme/app_icons.dart';
import '../model/expert_mode.dart';
import '../model/live_plain.dart';
import '../model/plan.dart';
import '../model/handover.dart';
import '../model/installation.dart';
import '../model/sound_ack.dart';
import '../model/watch_rules.dart';
import '../platform/addon.dart';
import '../catalog_store.dart';
import 'fault_hunt_screen.dart';
import 'sound_ack_screen.dart';
import 'watch_screen.dart';
import 'app_lock_screen.dart';
import 'full_backup_screen.dart';
import 'annotations.dart';
import 'annotations_screen.dart';
import 'data_export_screen.dart';
import 'plant_report_screen.dart';
import 'report_flow.dart';
import 'support_package_screen.dart';
import '../knx/active_tunnel.dart';
import '../model/learning.dart';
import 'learn_screen.dart';
import 'teach_in_screen.dart';
import 'tool_shell.dart';
import 'cause_chain_view.dart';
import 'ha_config_screen.dart';
import 'resident_manual_screen.dart';
import 'security_screen.dart';
import 'service_report_screen.dart';
import 'load_values_screen.dart';
import 'site_docs_screen.dart';
import 'dali_screen.dart';
import '../model/dali_alarms.dart';
import '../model/server_features.dart';

/// Live monitor after connecting: listens immediately, starts in the overview.
class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key, required this.tunnel, this.initialTab = LogTab.overview});

  final KnxTunnel tunnel;

  /// View shown when opening (default: overview).
  final LogTab initialTab;

  /// Demo house: the quiet check without a read test runs this long after opening, once the
  /// initial state and the first traffic are there.
  static const demoPassiveAfter = Duration(seconds: 45);

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> with WidgetsBindingObserver {
  late final _model = MonitorModel(widget.tunnel);
  late final StreamSubscription<Recording> _triggerSub;
  late final StreamSubscription<Telegram> _historySub;
  late final _background = BackgroundController(_model);
  late final _auto = AutoReconnect(widget.tunnel);
  // In the add-on the server reports alarms itself, even without an open browser.
  late final _alarms = AlarmNotifier(widget.tunnel is SharedTunnel ? const Stream.empty() : widget.tunnel.telegrams);

  KnxTunnel get _tunnel => widget.tunnel;

  late final _daliAlarms = DaliAlarmNotifier(
    serverNotifies: () => widget.tunnel is SharedTunnel && ServerFeatures.instance.dali,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SendScheduler.instance.attach(_tunnel);
    activeTunnel.value = _tunnel;
    _triggerSub = _model.triggeredRecordings.listen(_onTriggered);
    // Comment on a fresh telegram: offer a recording with lead time.
    // Only offer what works: expert mode, no running recording and room for
    // another one (Free stores one).
    AnnotationScope.recordOffer = () =>
        !expert || _model.recording || RecordingStore.instance.summaries.length >= Plan.instance.maxRecordings
        ? null
        : (from) => _startWithPreRoll(preRoll: DateTime.now().difference(from));
    ExpertMode.instance.addListener(_onExpert);
    _tunnel.gatewayInfo.addListener(_checkOwner);
    // Do not write demo telegrams into the daily history.
    // In the add-on the server writes the history (persistently, without a browser).
    _historySub = _tunnel.telegrams
        .where((_) => _tunnel is! DemoTunnel && _tunnel is! SharedTunnel)
        .listen(HistoryStore.instance.add);
    _alarms; // report alarms from now on
    // DALI: faults per luminaire; on the add-on or box the server reports them if it can.
    _daliAlarms;
    DaliAccess.attach(_tunnel, _model);
    unawaited(DaliAccess.prepare());
    if (_tunnel is SharedTunnel) _tunnel.state.addListener(_onSharedState);
    _watchSub = WatchRules.instance.hits.listen(_onWatchHit);
    WatchRules.instance.addListener(_syncAwake);
    SoundAck.instance.addListener(_syncAwake);
    Plan.instance.addListener(_syncAwake);
    _syncAwake();
    if (AlarmNotifySetting.instance.value) requestNotificationPermission();
    // Automatic health check (if enabled, at most once per day), shortly after
    // connecting so that normal traffic gets going first.
    _healthTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _tunnel.state.value == TunnelState.connected) {
        HealthCheck.instance.maybeAutoRun(_tunnel, _model);
      }
    });
    // Without automation: check quietly after a while (without reading) so that
    // the traffic light on the start page has something to say. In the demo house sooner
    // ([MonitorScreen.demoPassiveAfter]): nobody stays there for ten minutes, and the light would read
    // "not checked yet" for the whole visit. Its run stays in memory (HealthCheck.startDemo).
    _passiveTimer = Timer(_tunnel is DemoTunnel ? MonitorScreen.demoPassiveAfter : const Duration(minutes: 10), () {
      if (mounted && _tunnel.state.value == TunnelState.connected) {
        HealthCheck.instance.maybePassiveRun(_tunnel, _model);
      }
    });
  }

  /// Box or add-on is back: catches up on what did not arrive in the meantime.
  void _onSharedState() {
    if (_tunnel.state.value == TunnelState.connected) unawaited(InstallationStore.instance.shareChangesWithBox());
  }

  Timer? _healthTimer;
  Timer? _passiveTimer;
  late final StreamSubscription<WatchHit> _watchSub;

  /// Tapping a watcher's notification: details in the live list.
  final _openAddress = StreamController<int>.broadcast();
  final _openTab = StreamController<LogTab>.broadcast();

  /// Search set by tools outside the log view (diagnostics), see [_filterAndReturn].
  final _filter = StreamController<String>.broadcast();

  /// Watcher armed: the screen stays on so the app keeps listening in the
  /// foreground (otherwise iOS disconnects the tunnel in the background).
  /// Sound acknowledgement running: also stay awake, on Android additionally the
  /// foreground service (keeps listening with the screen locked).
  void _syncAwake() {
    final ack = SoundAck.instance.active;
    NativeBridge.keepAwake((WatchRules.instance.armed && Plan.instance.allows(Feature.watcher)) || ack);
    if (ack == _listening) return;
    _listening = ack;
    unawaited(_listenInBackground(ack));
  }

  Future<void> _listenInBackground(bool on) async {
    if (on) await NativeBridge.androidNotifyPermission();
    // Finished in the meantime: then do not start any more.
    if (on != SoundAck.instance.active) return;
    await NativeBridge.listenInBackground(on, title: s.ackTitle, text: SoundAck.instance.target?.describe() ?? '');
  }

  bool _listening = false;

  /// Sound at most every 5 s, notification including vibration every 30 s per
  /// watcher; the in-app hint comes on every match.
  final _alerts = WatchAlertThrottle();

  /// A watcher match: sound, notification (iOS, Android; in the add-on via
  /// Home Assistant) and an in-app hint.
  void _onWatchHit(WatchHit hit) {
    final t = hit.telegram;
    final what = '${hit.rule.describe()}$metaSeparator${CatalogStore.instance.value(t)}';
    final alert = _alerts.hit(
      hit.rule.id,
      DateTime.now(),
      wantsSound: hit.rule.sound,
      // In the add-on the server has already sent the notification to Home Assistant.
      canNotify: !(hit.fromServer && Addon.embedded),
    );
    if (alert.sound) NativeBridge.alertSound(vibrate: alert.vibrate);
    // Without a system sound the app plays the sound itself (or deliberately none).
    if (alert.notify) sendNotification(id: 'watch-${hit.rule.id}', title: s.watchTitle, body: what, silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          // Tapping opens the details of the address (no separate button). The
          // padding sits inside so the edge of the notice reacts too.
          padding: EdgeInsets.zero,
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              if (!_openAddress.isClosed) _openAddress.add(t.destination);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s12),
              child: Row(
                children: [
                  const Icon(AppIcons.watch, size: 18),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(s.watchHit(what))),
                ],
              ),
            ),
          ),
        ),
      );
  }

  @override
  void dispose() {
    AnnotationScope.recordOffer = null;
    if (activeTunnel.value == _tunnel) activeTunnel.value = null;
    _watchSub.cancel();
    _openAddress.close();
    _openTab.close();
    _filter.close();
    WatchRules.instance.removeListener(_syncAwake);
    SoundAck.instance.removeListener(_syncAwake);
    Plan.instance.removeListener(_syncAwake);
    // No monitor, no telegrams: acknowledgement and service end with it.
    SoundAck.instance.stop();
    if (_listening) NativeBridge.listenInBackground(false);
    NativeBridge.keepAwake(false);
    WidgetsBinding.instance.removeObserver(this);
    ExpertMode.instance.removeListener(_onExpert);
    _tunnel.gatewayInfo.removeListener(_checkOwner);
    _tunnel.state.removeListener(_onSharedState);
    SendScheduler.instance.detach(_tunnel);
    _auto.dispose();
    _healthTimer?.cancel();
    _passiveTimer?.cancel();
    HealthCheck.instance.cancel();
    _alarms.dispose();
    _daliAlarms.dispose();
    DaliAccess.detach(_tunnel);
    _triggerSub.cancel();
    _historySub.cancel();
    HistoryStore.instance.flush();
    _background.dispose();
    _model.dispose();
    super.dispose();
  }

  /// Background: grace period (see [BackgroundController]); reconnects on
  /// return if needed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        HistoryStore.instance.flush();
        _background.onBackground();
      case AppLifecycleState.resumed:
        _background.onForeground();
        if (_tunnel.state.value == TunnelState.disconnected) _auto.reconnectNow();
      default:
        break;
    }
  }

  /// "Back" from the monitor disconnects; ask first so it is not an accident.
  /// "Trennen" (disconnect) in the menu does not ask.
  Future<bool> _confirmLeave() async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.monitorLeaveTitle),
        content: Text(s.monitorLeaveText),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.monitorDisconnect,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// "Try it" of a lesson: to the place in the monitor it talks about.
  void _tryLesson(LessonTarget target) {
    switch (target) {
      case LessonTarget.live:
        _openTab.add(LogTab.live);
      case LessonTarget.overview:
        _openTab.add(LogTab.overview);
      case LessonTarget.health:
        _openHealth();
      case LessonTarget.gateway:
        unawaited(showGatewaySheet(context, _tunnel));
    }
  }

  void _openRecordings() => pushTool<void>(context, (_) => const RecordingsScreen());

  void _openHealth() =>
      pushTool<void>(context, (_) => HealthScreen(tunnel: _tunnel, log: _model, gateway: _model.gatewayLabel));

  /// Sets the search in the monitor and returns there from the tools.
  void _filterAndReturn(String query) {
    final route = ModalRoute.of(context);
    if (!_filter.isClosed) _filter.add(query);
    Navigator.of(context).popUntil((r) => r == route || r.isFirst);
  }

  void _openDiagnostics() => pushTool<void>(
    context,
    (_) => DiagnosticsScreen(
      tunnel: _tunnel,
      log: _model,
      onFilter: _filterAndReturn,
      // On top of the diagnostics so that "Back" leads to the diagnostics.
      onHealth: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => HealthScreen(tunnel: _tunnel, log: _model, gateway: _model.gatewayLabel),
        ),
      ),
      onSecurity: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SecurityScreen(tunnel: _tunnel, log: _model),
        ),
      ),
    ),
  );

  /// Trigger recording finished: save and report.
  Future<void> _onTriggered(Recording recording) async {
    await RecordingStore.instance.save(recording);
    if (!mounted) return;
    showHorizontMessage(
      context,
      s.triggerFired(recording.name),
      status: HorizontStatus.positive,
      action: SnackBarAction(label: s.recordingView, onPressed: () => openRecording(context, recording.id)),
    );
  }

  /// Expert mode: if the gateway (serial number) belongs to another
  /// installation, offers to switch; disconnects and reconnects there.
  void _checkOwner() {
    final info = _tunnel.gatewayInfo.value;
    if (!expert || info == null || !mounted) return;
    final owner = InstallationStore.instance.ownerElsewhere(info);
    if (owner == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 10),
        content: Text(s.installationGatewayElsewhere(owner.name)),
        action: SnackBarAction(label: s.installationSwitch, onPressed: () => Navigator.of(context).pop(owner.id)),
      ),
    );
  }

  /// Recording exists only in expert mode: when turning it off, releases the
  /// trigger and saves a running recording (a running trigger recording ends
  /// and saves itself).
  Future<void> _onExpert() async {
    if (expert) return;
    _model.armTrigger(null);
    if (!_model.recording || _model.triggerRecording) return;
    final recording = _model.stopRecording(name: _defaultName(_model.recorder!.started));
    if (recording != null) await RecordingStore.instance.save(recording);
  }

  Future<void> _editTrigger() async {
    if (!await unlock(context, Feature.trigger) || !mounted) return;
    final result = await showTriggerDialog(context, _model.trigger);
    if (result != null) _model.armTrigger(result.config);
  }

  static String _defaultName(DateTime started) {
    final date = formatDate(started);
    final shortDate = s.localeName.startsWith('de') ? date.substring(0, 6) : date.substring(5);
    return s.recordingDefaultName(shortDate, formatTime(started, seconds: false));
  }

  /// Long press: starts a recording with the last 10 seconds.
  Future<bool> _startWithPreRoll({Duration preRoll = MonitorModel.preRoll}) async {
    if (_model.recording || !await _mayRecord() || !mounted) return false;
    unawaited(HapticFeedback.mediumImpact());
    _model.startRecording(preRoll: preRoll);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s.recordingPreRollStarted(preRoll.inSeconds))));
    return true;
  }

  /// Free stores one recording: before the next one, the paywall first.
  Future<bool> _mayRecord() async {
    final plan = Plan.instance;
    if (await RecordingStore.instance.count() < plan.maxRecordings) return true;
    if (!mounted) return false;
    await showPlanScreen(context, reason: s.planMoreRecordings);
    return await RecordingStore.instance.count() < plan.maxRecordings;
  }

  Future<void> _toggleRecording() async {
    if (!_model.recording) {
      if (await _mayRecord()) _model.startRecording();
      return;
    }
    final result = await showAdaptiveDialog<({String name, String? note})>(
      context: context,
      builder: (_) => SaveRecordingDialog(
        initialName: _defaultName(_model.recorder!.started),
        count: _model.recorder!.telegrams.length,
      ),
    );
    if (!mounted || result == null) return; // keep recording
    final recording = _model.stopRecording(name: result.name, note: result.note);
    if (recording == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    await RecordingStore.instance.save(recording);
    if (!mounted) return;
    messenger.showSnackBar(
      horizontMessageSnackBar(
        colors,
        s.recordingSaved(recording.name, recording.telegrams.length),
        status: HorizontStatus.positive,
        action: SnackBarAction(label: s.recordingView, onPressed: () => openRecording(context, recording.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_model, _tunnel.deviceName, _auto, ExpertMode.instance, LivePlainSetting.instance]),
      builder: (context, _) => LogView(
        data: _model,
        tunnel: _tunnel,
        confirmLeave: _confirmLeave,
        initialTab: widget.initialTab,
        openAddress: _openAddress.stream,
        openTab: _openTab.stream,
        filter: _filter.stream,
        title: InkWell(
          borderRadius: Radii.tile,
          onTap: () => showGatewaySheet(context, _tunnel),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s4),
            child: _Title(tunnel: _tunnel, pulse: _model.pulse),
          ),
        ),
        exportTitle: s.monitorExportTitle,
        gateway: _model.gatewayLabel,
        floatingStart: _PauseButton(model: _model),
        liveAction: TextButton(
          onPressed: () => _model.setPaused(!_model.paused),
          child: Text(
            _model.paused
                ? '${s.monitorResume}${_model.pending > 0 ? ' · ${_model.pending > 999 ? '999+' : _model.pending}' : ''}'
                : s.monitorPauseShort,
          ),
        ),
        floatingStartLiveOnly: true,
        onReadStatus: _openHealth,
        banner: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConnectionBanner(
              tunnel: _tunnel,
              busy: _auto.busy,
              retryAt: _auto.retryAt,
              onReconnect: _auto.reconnectNow,
              onReport: () => showSupportPackage(
                context,
                tunnel: _tunnel,
                log: _model,
                session: _model.session,
                error: _tunnel.error.value ?? s.monitorConnectionLost,
              ),
            ),
            _TapBanner(tunnel: _tunnel),
            TapStrip(tunnel: _tunnel, log: _model),
            const _SecureBanner(),
            const _AckBanner(),
            const SiteNotesBanner(),
          ],
        ),
        actions: [
          // Recording only in expert mode.
          if (expert && _model.trigger != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4),
              child: ActionChip(
                onPressed: _editTrigger,
                // State in words (armed / recording), color only in addition.
                avatar: Icon(
                  AppIcons.trigger,
                  size: 18,
                  color: _model.triggerRecording ? context.hz.critical : context.hz.warning,
                ),
                label: Text(_model.triggerRecording ? s.triggerRecording : s.triggerArmed),
                tooltip: _model.trigger!.describe(),
              ),
            ),
          // While the trigger is recording, do not start a second (manual) recording.
          if (expert && !_model.triggerRecording)
            RecordButton(recorder: _model.recorder, onPressed: _toggleRecording, onLongPress: _startWithPreRoll),
        ],
        menuToggles: betriebToggles,
        tools: [
          ...betriebTools(context, tunnel: _tunnel, history: _model.log),
          ToolEntry(
            icon: AppIcons.diagnostics,
            expertOnly: true,
            title: s.diagnosticsTitle,
            feature: Feature.diagnostics,
            subtitle: s.toolDiagnostics,
            group: ToolGroup.check,
            order: 2,
            open: (_) => _openDiagnostics(),
          ),
          if (_tunnel.supportsBusMonitor)
            ToolEntry(
              icon: AppIcons.live,
              expertOnly: true,
              title: s.busmonTitle,
              feature: Feature.busMonitor,
              subtitle: s.busmonTool,
              group: ToolGroup.bus,
              open: (_) => pushTool<void>(
                context,
                (_) => BusMonitorScreen(monitor: _tunnel, log: _model, onFilter: _filterAndReturn),
              ),
            ),
          ToolEntry(
            icon: AppIcons.recordings,
            expertOnly: true,
            title: s.recordingsTitle,
            subtitle: s.toolRecordings,
            group: ToolGroup.record,
            open: (_) => _openRecordings(),
          ),
          // Report a fault: for residents, without expert mode or tier.
          ToolEntry(
            icon: AppIcons.report,
            title: s.reportTitle,
            subtitle: s.reportTool,
            group: ToolGroup.check,
            order: -1,
            open: (_) =>
                pushTool<void>(context, (_) => ReportFlowScreen(log: _model, session: _model.session, tunnel: _tunnel)),
          ),
          ToolEntry(
            icon: AppIcons.annotation,
            title: s.annotationsTitle,
            subtitle: s.annotationsTool,
            group: ToolGroup.documents,
            order: 5,
            open: (_) => pushTool<void>(context, (_) => const AnnotationsScreen(), title: s.annotationsTitle),
          ),
          // Teach-in without an ETS project: for beginners, Free.
          ToolEntry(
            icon: AppIcons.teachIn,
            title: s.learnTitle,
            subtitle: s.learnTool,
            group: ToolGroup.data,
            order: -1,
            open: (_) => openTeachIn(context, _tunnel, history: _model.log),
          ),
          ToolEntry(
            icon: AppIcons.learn,
            title: s.lessonsTitle,
            subtitle: s.lessonsTool,
            group: ToolGroup.learn,
            order: 0,
            open: (_) => openLearn(context, onTry: _tryLesson),
          ),
          ToolEntry(
            icon: AppIcons.health,
            title: s.healthTitle,
            subtitle: s.healthTool,
            group: ToolGroup.check,
            open: (_) => _openHealth(),
          ),
          // DALI lighting: only where the installation has a gateway or a DALI type (the demo house
          // has one).
          if (daliKnown())
            ToolEntry(
              icon: AppIcons.light,
              title: s.daliTitle,
              subtitle: s.daliTool,
              group: ToolGroup.check,
              order: 2,
              open: (_) => openDali(context, asTool: true),
            ),
          ToolEntry(
            icon: AppIcons.commissioning,
            expertOnly: true,
            title: s.commTitle,
            feature: Feature.commissioning,
            subtitle: s.commTool,
            group: ToolGroup.check,
            order: 1,
            open: (_) => pushTool<void>(
              context,
              (_) => CommissioningScreen(
                tunnel: _tunnel,
                gateway: _model.gatewayLabel,
                log: _model,
                onFilter: _filterAndReturn,
              ),
            ),
          ),
          ToolEntry(
            icon: AppIcons.ack,
            expertOnly: true,
            title: s.ackTitle,
            feature: Feature.soundAck,
            subtitle: s.ackTool,
            group: ToolGroup.check,
            order: 1,
            open: (_) => pushTool<void>(context, (_) => const SoundAckScreen()),
          ),
          // Fault hunt (Pro): runs on the box or add-on, offer it only there.
          if (Addon.available)
            ToolEntry(
              icon: AppIcons.hunt,
              expertOnly: true,
              title: s.huntTitle,
              feature: Feature.faultHunt,
              subtitle: Addon.onBox ? s.huntTool : s.huntToolAddon,
              group: ToolGroup.record,
              order: 4,
              open: (_) => pushTool<void>(context, (_) => const FaultHuntScreen()),
            ),
          // Installation report: created on the box or add-on, offer it only there.
          if (Addon.available)
            ToolEntry(
              icon: AppIcons.report,
              expertOnly: true,
              title: s.plantTitle,
              feature: Feature.plantReport,
              subtitle: s.plantTool,
              group: ToolGroup.documents,
              order: 4,
              open: (_) => pushTool<void>(context, (_) => const PlantReportScreen()),
            ),
          // Data export: runs on the box or add-on. No tier of its own:
          // the add-on is free, the app on the box is Pro.
          if (Addon.available)
            ToolEntry(
              icon: AppIcons.chart,
              expertOnly: true,
              title: s.dataExportTitle,
              subtitle: s.dataExportTool,
              group: ToolGroup.record,
              order: 5,
              open: (_) => pushTool<void>(context, (_) => const DataExportScreen()),
            ),
          // Watcher (Plus): also without expert mode, for everyday use and troubleshooting.
          ToolEntry(
            icon: AppIcons.watch,
            title: s.watchTitle,
            subtitle: s.watchTool,
            group: ToolGroup.record,
            order: 2,
            feature: Feature.watcher,
            open: (_) => pushTool<void>(context, (_) => const WatchScreen()),
          ),
          ToolEntry(
            icon: AppIcons.trigger,
            expertOnly: true,
            title: s.triggerTitle,
            feature: Feature.trigger,
            subtitle: s.toolTrigger,
            group: ToolGroup.record,
            order: 1,
            open: (_) => _editTrigger(),
          ),
          // Enthusiast tools (Plus): Home Assistant, response times, security.
          // The Home Assistant configuration exists only on the server, not in the apps.
          if (Addon.inHomeAssistant)
            ToolEntry(
              icon: AppIcons.fileCode,
              title: s.haTitle,
              subtitle: s.haTool,
              group: ToolGroup.data,
              order: 3,
              feature: Feature.haConfig,
              open: (_) => pushTool<void>(context, (_) => const HaConfigScreen()),
            ),
          ToolEntry(
            icon: AppIcons.statistics,
            expertOnly: true,
            title: s.reactTitle,
            subtitle: s.reactTool,
            group: ToolGroup.analyze,
            order: 2,
            feature: Feature.causeChain,
            open: (_) => pushTool<void>(context, (_) => ReactionTimesScreen(log: _model)),
          ),
          ToolEntry(
            icon: AppIcons.secure,
            title: s.secTitle,
            subtitle: s.secTool,
            group: ToolGroup.check,
            order: 3,
            feature: Feature.securityCheck,
            open: (_) => pushTool<void>(context, (_) => SecurityScreen(tunnel: _tunnel, log: _model)),
          ),
          // Bus on the floor plan: with any floor plan of one's own, no tier for the first level.
          ToolEntry(
            icon: AppIcons.place,
            title: s.floorTitle,
            subtitle: s.floorTool,
            group: ToolGroup.bus,
            order: 3,
            open: (_) => pushTool<void>(context, (_) => FloorViewScreen(log: _model), title: s.floorTitle),
          ),
          // House plan with the bus attached, opened on "after moving in": that part needs the
          // live stream. Planning itself starts from the start screen.
          if (homePlanAvailable)
            ToolEntry(
              icon: AppIcons.homePlan,
              title: s.hpaTab,
              subtitle: s.floorPlanTool,
              group: ToolGroup.check,
              order: 4,
              open: (_) => pushTool<void>(
                context,
                (_) => HomePlanScreen(log: _model, tunnel: _tunnel, initialTab: HomePlanScreen.afterMoveInTab),
              ),
            ),
          // Installation from a handover package: reporting works on every tier.
          if (HandoverStore.instance.origin case final origin?)
            ToolEntry(
              icon: AppIcons.report,
              title: s.faultReportTo(origin.contact.name.isEmpty ? s.handoverUnknownCompany : origin.contact.name),
              subtitle: s.faultReportTool,
              group: ToolGroup.check,
              open: (_) => pushTool<void>(
                context,
                (_) => ReportFlowScreen(log: _model, session: _model.session, tunnel: _tunnel, origin: origin),
              ),
            ),
          ToolEntry(
            icon: AppIcons.handover,
            expertOnly: true,
            title: s.handoverTitle,
            subtitle: s.handoverTool,
            group: ToolGroup.documents,
            order: 2,
            feature: Feature.handover,
            open: (_) => pushTool<void>(context, (_) => const HandoverScreen()),
          ),
          ToolEntry(
            icon: AppIcons.customers,
            expertOnly: true,
            title: s.customerTitle,
            subtitle: s.customerTool,
            group: ToolGroup.documents,
            // Existing records stay readable after the subscription ends.
            feature: CustomerStore.instance.entries.isEmpty ? Feature.customerRecords : null,
            open: (_) => pushTool<void>(context, (_) => const CustomersScreen()),
          ),
          ToolEntry(
            icon: AppIcons.serviceReport,
            expertOnly: true,
            title: s.srTitle,
            subtitle: s.srTool,
            group: ToolGroup.documents,
            order: 1,
            feature: Feature.serviceReport,
            open: (_) => pushTool<void>(
              context,
              (_) => ServiceReportScreen(gateway: _model.gatewayLabel, tunnel: _tunnel, log: _model),
            ),
          ),
          ToolEntry(
            icon: AppIcons.live,
            expertOnly: true,
            title: s.loadTitle,
            subtitle: s.loadTool,
            group: ToolGroup.analyze,
            order: 5,
            feature: Feature.loadValues,
            open: (_) => pushTool<void>(context, (_) => LoadValuesScreen(log: _model)),
          ),
          ToolEntry(
            icon: AppIcons.qrCode,
            expertOnly: true,
            title: s.siteDocsTitle,
            subtitle: s.siteDocsTool,
            group: ToolGroup.documents,
            order: 2,
            feature: Feature.siteDocs,
            open: (_) => pushTool<void>(context, (_) => SiteDocsScreen(log: _model)),
          ),
          ToolEntry(
            icon: AppIcons.manual,
            expertOnly: true,
            title: s.manualTitle,
            subtitle: s.manualTool,
            group: ToolGroup.documents,
            order: 3,
            feature: Feature.residentManual,
            open: (_) => pushTool<void>(context, (_) => const ResidentManualScreen()),
          ),
          ToolEntry(
            icon: AppIcons.company,
            expertOnly: true,
            title: s.companyTitle,
            subtitle: s.companyTool,
            group: ToolGroup.documents,
            order: 9,
            feature: Feature.letterhead,
            open: (_) => pushTool<void>(context, (_) => const CompanyScreen()),
          ),
        ],
        menuFooter: () => [
          if (AppLock.instance.available)
            MenuAction(
              icon: AppIcons.locked,
              title: s.appLockSettings,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AppLockSettingsScreen())),
            ),
          if (AppLock.instance.available)
            MenuAction(
              icon: AppIcons.supportPackage,
              title: s.backupTitle,
              onTap: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FullBackupScreen())),
            ),
          // Third-party licenses (MIT, BSD, Apache, MPL) require the notice in the app.
          MenuAction(
            icon: AppIcons.info,
            title: s.aboutLicenses,
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Busclear',
              applicationIcon: const Padding(
                padding: EdgeInsets.symmetric(vertical: HzSpace.s8),
                child: SenderLine(),
              ),
              applicationLegalese: s.aboutLegalese,
            ),
          ),
          // For support: for everyone, without tier or expert mode; at the bottom
          // under "Über" (about), because it is not a testing tool.
          MenuAction(
            icon: AppIcons.supportPackage,
            title: s.diagTitle,
            onTap: () => showSupportPackage(context, tunnel: _tunnel, log: _model, session: _model.session),
          ),
          MenuAction(
            icon: AppIcons.clear,
            title: s.monitorClear,
            enabled: _model.log.isNotEmpty,
            onTap: () => setState(() {
              _model.clear();
              _model.session.clear();
            }),
          ),
          MenuAction(
            icon: AppIcons.disconnect,
            title: s.monitorDisconnect,
            danger: true,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

/// Starts a recording, or shows a running one with symbol, word, duration and
/// count (no glow; tapping stops and saves).
class RecordButton extends StatelessWidget {
  const RecordButton({super.key, required this.recorder, required this.onPressed, this.onLongPress});

  final Recorder? recorder;
  final VoidCallback onPressed;

  /// Starts with lead time (only while no recording is running).
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final r = recorder;
    if (r == null) {
      // Tooltip only on hover: the long press belongs to the lead time.
      return Tooltip(
        message: s.recordingStartHint(MonitorModel.preRoll.inSeconds),
        triggerMode: onLongPress == null ? null : TooltipTriggerMode.manual,
        child: Semantics(
          onLongPressHint: onLongPress == null ? null : s.recordingPreRoll(MonitorModel.preRoll.inSeconds),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(AppIcons.record, color: hz.critical, semanticLabel: s.recordingStart),
            ),
          ),
        ),
      );
    }
    final d = DateTime.now().difference(r.started);
    String two(int v) => v.toString().padLeft(2, '0');
    final time = d.inHours > 0
        ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
        : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: hz.critical,
          backgroundColor: hz.criticalTint,
          side: BorderSide(color: hz.critical, width: Lines.hairline),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12),
        ),
        icon: const _BlinkingDot(),
        label: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '${s.hzCRecordingLive}  '),
              TextSpan(
                text: '$time · ${r.telegrams.length}',
                style: context.hzTheme.data.copyWith(color: hz.critical),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recording symbol that pulses slowly (still under reduced motion).
class _BlinkingDot extends StatefulWidget {
  const _BlinkingDot();

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.calm);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 0;
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 1.0, end: 0.35).animate(CurvedAnimation(parent: _c, curve: Motion.curve)),
    child: const Icon(AppIcons.stop, size: 18),
  );
}

/// Name and note for a recording. "Weiter aufnehmen" (keep recording) closes without a result.
class SaveRecordingDialog extends StatefulWidget {
  const SaveRecordingDialog({super.key, required this.initialName, required this.count, this.initialNote});

  final String initialName;
  final String? initialNote;

  /// Number of telegrams; `null` when renaming.
  final int? count;

  @override
  State<SaveRecordingDialog> createState() => _SaveRecordingDialogState();
}

class _SaveRecordingDialogState extends State<SaveRecordingDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late final _note = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    Navigator.pop(context, (
      name: name.isEmpty ? widget.initialName : name,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final rename = widget.count == null;
    return AlertDialog.adaptive(
      title: Text(rename ? s.recordingEdit : s.recordingSave),
      // Material ancestor for the text fields, also in the Cupertino dialog.
      content: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!rename) ...[Text(s.recordingCaptured(widget.count!)), const SizedBox(height: HzSpace.s16)],
              HorizontField(
                label: s.recordingName,
                child: TextField(
                  style: context.hzTheme.field,
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(),
                  textInputAction: TextInputAction.next,
                ),
              ),
              const SizedBox(height: HzSpace.s12),
              HorizontField(
                label: s.recordingNoteLabel,
                child: TextField(
                  style: context.hzTheme.field,
                  controller: _note,
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(hintText: s.recordingNoteHint),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        horizontDialogAction(
          context,
          label: rename ? s.commonCancel : s.recordingContinue,
          onPressed: () => Navigator.pop(context),
        ),
        horizontDialogAction(
          context,
          label: rename ? s.commonSave : s.recordingStopAndSave,
          primary: true,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _Title extends StatelessWidget {
  const _Title({required this.tunnel, required this.pulse});

  final KnxTunnel tunnel;
  final ValueNotifier<int> pulse;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([tunnel.state, tunnel.deviceName, ExpertMode.instance, InstallationStore.instance]),
      builder: (context, _) {
        // Several installations (expert mode): which one is currently running.
        final installations = InstallationStore.instance;
        final place = expert && installations.list.length > 1 ? '${installations.active.name} · ' : '';
        // State with symbol, word and color; never color alone.
        final (status, word) = switch (tunnel.state.value) {
          TunnelState.connected => (HorizontStatus.positive, tunnel.host),
          TunnelState.connecting => (HorizontStatus.warning, s.monitorConnecting),
          TunnelState.disconnected => (HorizontStatus.critical, s.monitorDisconnected),
        };
        final color = status == HorizontStatus.positive ? null : status.color(context.hz);
        return Semantics(
          label: tunnel.state.value == TunnelState.connected ? s.monitorConnected : word,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(color: status.color(context.hz), pulse: pulse, icon: status.icon),
              const SizedBox(width: HzSpace.s4),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(
                    '$place${tunnel.deviceName.value ?? appName} · $word'.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context
                        .mono(Theme.of(context).textTheme.labelSmall)
                        .copyWith(color: color ?? context.hz.textMuted, letterSpacing: 0.3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Play/pause of the display as a floating button at the bottom left.
class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.model});

  final MonitorModel model;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final paused = model.paused;
    return Badge(
      isLabelVisible: model.pending > 0,
      label: Text(model.pending > 999 ? '999+' : '${model.pending}'),
      offset: const Offset(-4, -2),
      // Only an icon, same height as "Schreiben" (write) (phone 56, otherwise 48);
      // secondary with an outline, tinted with the selection color when paused.
      child: SizedBox.square(
        dimension: MediaQuery.sizeOf(context).width < Breakpoints.medium ? HzSpace.s48 + HzSpace.s8 : HzSpace.s48,
        child: FloatingActionButton(
          heroTag: 'pause',
          tooltip: paused ? s.monitorResume : s.monitorPause,
          onPressed: () => model.setPaused(!paused),
          backgroundColor: paused ? hz.accentTint : hz.surface,
          foregroundColor: paused ? hz.accentText : hz.text,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.card,
            side: BorderSide(color: hz.line, width: Lines.hairline),
          ),
          child: Icon(paused ? AppIcons.play : AppIcons.pause, key: ValueKey(paused)),
        ),
      ),
    );
  }
}

/// Status dot that emits a ring on every telegram.
class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulse, required this.icon});

  final Color color;
  final ValueNotifier<int> pulse;

  /// Symbol of the connection state (check mark, triangle, octagon).
  final IconData icon;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  @override
  void initState() {
    super.initState();
    widget.pulse.addListener(_onPulse);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (old.pulse != widget.pulse) {
      old.pulse.removeListener(_onPulse);
      widget.pulse.addListener(_onPulse);
    }
  }

  void _onPulse() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    // Under continuous traffic do not restart all the time; one running ring is enough.
    if (_controller.value > 0.5) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    widget.pulse.removeListener(_onPulse);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every telegram makes the symbol flash briefly: a sign of life without glow.
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) =>
          Opacity(opacity: 0.4 + 0.6 * Motion.curve.transform(_controller.value), child: child),
      child: Icon(widget.icon, size: 14, color: widget.color),
    );
  }
}

/// One tap point dropped while others keep running (issue #8). The overall connection banner
/// stays quiet then; this one names the tap point.
class _TapBanner extends StatelessWidget {
  const _TapBanner({required this.tunnel});

  final KnxTunnel tunnel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: tunnel.tapPoints,
      builder: (context, points, _) {
        final active = points.where((p) => !p.paused).toList();
        final live = active.where((p) => p.connected).length;
        // Not reachable is a gap of that tap point, not a bus fault: the wording says so.
        final down = active.where((p) => !p.connected && p.state == TunnelState.disconnected).toList();
        final silent = active.where((p) => p.connected && p.silent).toList();
        return AnimatedSize(
          duration: Motion.of(context),
          curve: Motion.curve,
          child: live > 0 && down.isNotEmpty
              ? _Banner(
                  status: HorizontStatus.warning,
                  text: [
                    s.tapDown(down.map((p) => p.name).join(', '), live, active.length),
                    ?down.first.error,
                    s.tapDownHint,
                  ].join(' · '),
                )
              : silent.isNotEmpty
              ? _Banner(
                  status: HorizontStatus.info,
                  text: '${s.tapSilent(silent.map((p) => p.name).join(', '))} · ${s.tapSilentHint}',
                )
              : const SizedBox(width: double.infinity),
        );
      },
    );
  }
}

/// Notice row above the list ([HorizontNotice]) within the page margin.
class _Banner extends StatelessWidget {
  const _Banner({required this.status, required this.text, this.actions = const []});

  final HorizontStatus status;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final gutter = Gap.gutterFor(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, HzSpace.s4, gutter, Gap.item),
      child: HorizontNotice(
        status,
        action: actions.isEmpty ? null : Row(mainAxisSize: MainAxisSize.min, children: actions),
        child: Text(text),
      ),
    );
  }
}

/// Notice on connection loss with a countdown to the next automatic attempt.
/// Notice when Data Secure telegrams cannot be read; otherwise they would be
/// missing from the list unnoticed.
/// Sound acknowledgement running: target and counter, tapping opens it, stop ends it.
class _AckBanner extends StatelessWidget {
  const _AckBanner();

  @override
  Widget build(BuildContext context) {
    final ack = SoundAck.instance;
    return ListenableBuilder(
      listenable: ack,
      builder: (context, _) => AnimatedSize(
        duration: Motion.of(context),
        curve: Motion.curve,
        child: switch (ack.target) {
          null => const SizedBox(width: double.infinity),
          final target => _Banner(
            status: HorizontStatus.info,
            text: '${s.ackTitle}: ${target.describe()}$metaSeparator${s.ackCount(ack.count)}',
            actions: [
              TextButton(
                onPressed: () => pushTool<void>(context, (_) => const SoundAckScreen()),
                child: Text(s.commonMore),
              ),
              TextButton(onPressed: ack.stop, child: Text(s.ackStop)),
            ],
          ),
        },
      ),
    );
  }
}

class _SecureBanner extends StatefulWidget {
  const _SecureBanner();

  @override
  State<_SecureBanner> createState() => _SecureBannerState();
}

class _SecureBannerState extends State<_SecureBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final keys = KeyringStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([keys.withoutKey, keys.rejected, keys]),
      builder: (context, _) {
        final missing = keys.withoutKey.value;
        final rejected = keys.rejected.value;
        final show = !_dismissed && (missing > 0 || rejected > 0);
        return AnimatedSize(
          duration: Motion.of(context),
          curve: Motion.curve,
          child: !show
              ? const SizedBox(width: double.infinity)
              : _Banner(
                  status: HorizontStatus.warning,
                  text: [
                    if (missing > 0) s.secureWithoutKeys(missing),
                    if (rejected > 0) s.secureRejected(rejected),
                  ].join(' '),
                  actions: [
                    if (missing > 0) TextButton(onPressed: () => importKeyring(context), child: Text(s.keyringImport)),
                    IconButton(
                      tooltip: s.commonDismiss,
                      onPressed: () => setState(() => _dismissed = true),
                      icon: Icon(AppIcons.close, size: 18, color: context.hz.textMuted),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _ConnectionBanner extends StatefulWidget {
  const _ConnectionBanner({
    required this.tunnel,
    required this.busy,
    required this.onReconnect,
    required this.onReport,
    this.retryAt,
  });

  final KnxTunnel tunnel;
  final bool busy;
  final DateTime? retryAt;
  final VoidCallback onReconnect;

  /// Diagnostics package for the fault report.
  final VoidCallback onReport;

  @override
  State<_ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends State<_ConnectionBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ConnectionBanner old) {
    super.didUpdateWidget(old);
    _syncTicker();
  }

  /// Ticks every second only while an attempt is scheduled.
  void _syncTicker() {
    if (widget.retryAt == null) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tunnel = widget.tunnel;
    return ListenableBuilder(
      listenable: Listenable.merge([tunnel.state, tunnel.error]),
      builder: (context, _) {
        final show = !widget.busy && tunnel.state.value == TunnelState.disconnected;
        final retryAt = widget.retryAt;
        final seconds = retryAt == null ? null : (retryAt.difference(DateTime.now()).inMilliseconds / 1000).ceil();
        return AnimatedSize(
          duration: Motion.of(context),
          curve: Motion.curve,
          child: !show
              ? const SizedBox(width: double.infinity)
              : _Banner(
                  status: HorizontStatus.critical,
                  text: [
                    tunnel.error.value ?? s.monitorConnectionLost,
                    if (seconds != null) s.monitorRetryIn(seconds.clamp(0, 999)),
                  ].join(' · '),
                  actions: [
                    IconButton(
                      tooltip: s.diagTitle,
                      onPressed: widget.onReport,
                      icon: const Icon(AppIcons.supportPackage, size: HzIconSize.row),
                    ),
                    TextButton(onPressed: widget.onReconnect, child: Text(s.monitorReconnect)),
                  ],
                ),
        );
      },
    );
  }
}
