import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plan_source.dart';

/// Unlock tier.
enum Tier {
  free,
  plus,
  pro;

  /// Whether it is at least as high as [other].
  bool covers(Tier other) => index >= other.index;
}

/// Features that require a tier – with their minimum tier.
enum Feature {
  /// Watcher: sound and notification when a group address is sent.
  watcher(Tier.plus),

  /// Long-term history (whole days on the device).
  longHistory(Tier.plus),
  charts(Tier.plus),
  statistics(Tier.plus),
  alarms(Tier.plus),

  /// Full exports: ETS file, ZIP, charts, PDF with note and legend. Telegrams as
  /// CSV and the simple PDF are free; the data belongs to the user.
  export(Tier.plus),
  diagnostics(Tier.pro),
  commissioning(Tier.pro),

  /// Project comparison with check rules and tasks for the ETS.
  projectCheck(Tier.plus),
  busMonitor(Tier.pro),
  topology(Tier.pro),
  communicationMap(Tier.pro),
  trigger(Tier.pro),

  /// Play a recording back onto the bus.
  busReplay(Tier.pro),

  /// Send cyclically or delayed.
  scheduledSend(Tier.pro),
  box(Tier.pro),

  /// Sound acknowledgement: a tone per telegram, commissioning alone.
  soundAck(Tier.pro),

  /// Acceptance protocol with signature on the device.
  acceptance(Tier.pro),

  /// Fault hunt: catch sporadic faults over days with the KNX box.
  faultHunt(Tier.pro),

  /// Configuration for the Home Assistant KNX integration from the project.
  haConfig(Tier.plus),

  /// Cause chain and response times command → status feedback.
  causeChain(Tier.plus),

  /// Security check: Secure usage and foreign senders.
  securityCheck(Tier.plus),

  /// Device inventory via the bus (manufacturer, serial number, firmware).
  inventory(Tier.pro),

  /// Company letterhead on all PDFs.
  letterhead(Tier.pro),

  /// Service report for the customer.
  serviceReport(Tier.pro),

  /// Installations as customer records with visit history.
  customerRecords(Tier.pro),

  /// Create a handover package for the customer's app.
  handover(Tier.pro),

  /// Open a handover package from the electrician. Reporting back to them is never locked.
  handoverReceive(Tier.plus),

  /// Resident manual as PDF.
  residentManual(Tier.pro),

  /// Current and power values from actuators with current measurement. Plus, like
  /// statistics and charts: a pure evaluation of what was overheard, for anyone
  /// with their own installation, not a tool for customer jobs.
  loadValues(Tier.plus),

  /// Photo documentation of the distribution board and QR labels.
  siteDocs(Tier.pro),

  /// Installation report from the box and add-on for the customer. Pro, like fault
  /// hunt and box pairing; free anyway in the add-on and in the box's browser.
  plantReport(Tier.pro),

  /// Sync between the user's own devices via iCloud or Google Drive.
  cloudSync(Tier.plus),

  /// Home planner: all levels, checks, deadlines, quote check, dimensions and DXF.
  /// Wishes, room book, one level, channel requirements and CSV stay free.
  homePlan(Tier.plus),

  /// Company edition: not announced yet, therefore not on the paywall.
  businessStandard(Tier.pro, listed: false),
  gaAssistant(Tier.pro, listed: false),
  standardCheck(Tier.pro, listed: false),
  siteNotes(Tier.pro, listed: false),
  siteSurvey(Tier.pro, listed: false),

  /// Pro Team: company, storage, send log, four-eyes acceptance, queries.
  /// The separate Pro Team tier does not exist yet; until then it is tied to Pro.
  team(Tier.pro, listed: false),
  askMaster(Tier.pro, listed: false);

  const Feature(this.tier, {this.listed = true});

  final Tier tier;

  /// Whether it appears in the paywall's feature list.
  final bool listed;
}

/// One-time messages for the transition period after the free period.
enum PlanNotice { openStarted, openEnded }

/// The only place that knows the tier. Everything else asks [allows] or reads
/// the limits ([maxInstallations] …).
class Plan extends ValueNotifier<Tier> {
  // Until [load] has run, the highest tier applies: better to show too much than
  // to briefly lock out paying customers.
  Plan._() : super(Tier.pro);

  static final instance = Plan._();
  static const _key = 'plan_tier';
  static const _betaTesterKey = 'plan_beta_tester';
  static const _betaStoreKey = 'plan_beta_store';
  static const _rewardKey = 'plan_beta_reward_until';
  static const _betaLastKey = 'plan_beta_last';
  static const _paidKey = 'plan_paid_tier';
  static const _paidSeenKey = 'plan_paid_seen';

  /// `true` as soon as a real purchase channel has responded. Without this marker,
  /// [_key] and [_paidKey] come from a build without a purchase channel.
  static const _storeConfirmedKey = 'plan_store_confirmed';
  static const _openSeenKey = 'plan_open_seen';
  static const _openUntilKey = 'plan_open_until';
  static const _openStartShownKey = 'plan_open_start_shown';
  static const _openEndShownKey = 'plan_open_end_shown';
  static const _freeSinceKey = 'plan_free_since';

  /// How long a paid tier remains after the store last confirmed it, if the store
  /// is unreachable, only returns cached data or reports a payment problem. On a
  /// construction site a wrong "Free" is an outage; a month too much Pro after a
  /// cancellation costs nothing.
  static const paidGrace = Duration(days: 30);

  /// How long it remains when the store freshly and clearly reports less (refund,
  /// expired, store account changed), counted from that first response.
  static const refundGrace = Duration(days: 3);

  /// Existing users from the time without a purchase channel: Pro for this long
  /// from the first start of the first paid version.
  static const openTransition = Duration(days: 30);

  /// Thank-you for beta testers: Pro for this long after the store launch.
  static const betaReward = Duration(days: 90);

  /// Latest paid launch date. Set to the real date before launch; together with
  /// [betaReward] it limits the thank-you ([rewardHardEnd]), even with edited
  /// settings.
  static final latestLaunch = DateTime.utc(2027, 12, 31);

  /// After this point there is no more thank-you, regardless of what is stored.
  static final rewardHardEnd = latestLaunch.add(betaReward);

  /// Clock for the beta reward (tests).
  static DateTime Function() clock = DateTime.now;

  /// Where the tier comes from; [load] picks it to match the platform.
  PlanSource source = const OpenPlanSource();

  /// Forces a tier outside release builds (debug, profile):
  /// `--dart-define=PLAN=free|plus|pro`.
  static const _forced = String.fromEnvironment('PLAN');

  /// TestFlight beta: everything free, unless the hidden switch [betaStore] is on.
  bool beta = false;

  /// Hidden switch in the beta: paywall and purchases as in the store (sandbox).
  bool betaStore = false;

  /// End of the beta thank-you (Pro), once the app comes from the store.
  DateTime? rewardUntil;

  /// Tier according to the store, without beta and thank-you.
  Tier _bought = Tier.free;

  /// Highest most recently confirmed paid tier and when (for [paidGrace]).
  Tier _paid = Tier.free;
  DateTime? _paidSeen;

  /// First fresh, definitive response with less than [_paid] (for [refundGrace]).
  DateTime? _freeSince;

  /// End of the transition period for existing users ([openTransition]).
  DateTime? _openUntil;

  /// One-time message that has not been shown yet.
  PlanNotice? _notice;

  /// A purchase is awaiting approval ("Ask to Buy", deferred payment).
  bool awaitingApproval = false;

  /// Runs until the store has responded (beta, purchases). [load] does not wait
  /// for it, so startup without a network does not hang.
  Future<void> refreshing = Future.value();

  final _loaded = Completer<void>();

  /// Completes once [load] is done (even after an error): afterwards [source] is
  /// the correct purchase source, no longer the default.
  Future<void> get loaded => _loaded.future;

  /// Shows the last known state immediately and queries the store in the background.
  Future<void> load({PlanSource? using}) async {
    try {
      await _load(using);
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _load(PlanSource? using) async {
    source = using ?? PlanSource.forPlatform();
    final prefs = await SharedPreferences.getInstance();
    await _dropOpenState(prefs);
    _notice = null;
    awaitingApproval = false;
    beta = prefs.getBool(_betaLastKey) ?? false;
    betaStore = beta && (prefs.getBool(_betaStoreKey) ?? false);
    rewardUntil = DateTime.tryParse(prefs.getString(_rewardKey) ?? '');
    _paid = Tier.values.asNameMap()[prefs.getString(_paidKey)] ?? Tier.free;
    _paidSeen = DateTime.tryParse(prefs.getString(_paidSeenKey) ?? '');
    _freeSince = DateTime.tryParse(prefs.getString(_freeSinceKey) ?? '');
    _openUntil = DateTime.tryParse(prefs.getString(_openUntilKey) ?? '');
    if (source.purchasable) {
      _show(Tier.values.asNameMap()[prefs.getString(_key)] ?? Tier.free);
    } else {
      _show(source.open ? Tier.pro : Tier.free);
    }
    refreshing = _refresh(prefs);
  }

  /// Builds without a purchase channel reported Pro and, up to 1.9.1, stored it as
  /// paid. Such states are not a purchase: drop them, and only remember that this
  /// device went through the free period (for [openTransition]).
  Future<void> _dropOpenState(SharedPreferences prefs) async {
    if (!(prefs.getBool(_storeConfirmedKey) ?? false)) {
      final stored = Tier.values.asNameMap()[prefs.getString(_key)] ?? Tier.free;
      if (stored != Tier.free || prefs.containsKey(_paidKey)) {
        await prefs.remove(_key);
        await prefs.remove(_paidKey);
        await prefs.remove(_paidSeenKey);
        await prefs.setBool(_openSeenKey, true);
      }
    }
    if (source.open) await prefs.setBool(_openSeenKey, true);
  }

  Future<void> _refresh(SharedPreferences prefs) async {
    try {
      // `null`: beta currently not determinable; keep the last state.
      final unlock = await source.betaUnlock;
      if (unlock != null) {
        beta = unlock;
        await prefs.setBool(_betaLastKey, beta);
        betaStore = beta && (prefs.getBool(_betaStoreKey) ?? false);
        if (beta) {
          await prefs.setBool(_betaTesterKey, true);
        } else if ((prefs.getBool(_betaTesterKey) ?? false) && !prefs.containsKey(_rewardKey)) {
          // First start after the beta (store version): the thank-you starts now.
          final end = clock().add(betaReward);
          rewardUntil = end.isAfter(rewardHardEnd) ? rewardHardEnd : end;
          await prefs.setString(_rewardKey, rewardUntil!.toIso8601String());
        }
        await _startOpenTransition(prefs);
      }
      source.onChange = _apply;
      await _apply(await source.current());
    } on Object catch (e) {
      // No network, store unreachable: keep the last state.
      debugPrint('Plan: $e');
      _show(_bought);
    }
    _notice = _pendingNotice(prefs);
    notifyListeners();
  }

  /// First start with a purchase channel after the free period: the period starts now.
  Future<void> _startOpenTransition(SharedPreferences prefs) async {
    if (!source.purchasable || beta || _openUntil != null) return;
    if (!(prefs.getBool(_openSeenKey) ?? false)) return;
    _openUntil = clock().add(openTransition);
    await prefs.setString(_openUntilKey, _openUntil!.toIso8601String());
  }

  PlanNotice? _pendingNotice(SharedPreferences prefs) {
    if (_openUntil == null || !source.purchasable || beta || _bought != Tier.free) return null;
    if (openTransitionActive) return (prefs.getBool(_openStartShownKey) ?? false) ? null : PlanNotice.openStarted;
    return (prefs.getBool(_openEndShownKey) ?? false) ? null : PlanNotice.openEnded;
  }

  Future<void> _apply(Tier tier) async {
    // Without a purchase channel there is nothing to remember: only what a store confirms is paid.
    if (!source.purchasable) {
      _show(tier);
      return;
    }
    if (tier != Tier.free) awaitingApproval = false;
    final prefs = await SharedPreferences.getInstance();
    final now = clock();
    var shown = tier;
    if (tier != Tier.free && tier.index >= _paid.index) {
      _paid = tier;
      _paidSeen = now;
      _freeSince = null;
      await prefs.setString(_paidKey, tier.name);
      await prefs.setString(_paidSeenKey, now.toIso8601String());
      await prefs.remove(_freeSinceKey);
    } else if (tier.index < _paid.index) {
      final seen = _paidSeen;
      var until = seen?.add(paidGrace);
      if (source.lastAnswerDefinite) {
        var since = _freeSince;
        if (since == null || now.isBefore(since)) {
          since = _freeSince = now;
          await prefs.setString(_freeSinceKey, now.toIso8601String());
        }
        final short = since.add(refundGrace);
        if (until != null && short.isBefore(until)) until = short;
      }
      if (seen != null && now.isBefore(until!) && !now.isBefore(seen.subtract(paidGrace))) {
        debugPrint('Plan: Store meldet ${tier.name}, ${_paid.name} gilt bis $until weiter');
        shown = _paid;
      } else {
        _paid = tier;
        _paidSeen = null;
        _freeSince = null;
        await prefs.remove(_paidKey);
        await prefs.remove(_paidSeenKey);
        await prefs.remove(_freeSinceKey);
      }
    }
    _show(shown);
    await prefs.setBool(_storeConfirmedKey, true);
    await prefs.setString(_key, shown.name);
  }

  /// Purchased tier plus beta, thank-you and transition period.
  void _show(Tier bought) {
    _bought = bought;
    final gift = (beta && !betaStore) || rewardActive || openTransitionActive;
    final tier = gift ? Tier.pro : bought;
    value = kReleaseMode ? tier : (Tier.values.asNameMap()[_forced] ?? tier);
  }

  /// Whether the beta thank-you is still running. An end beyond [rewardHardEnd] or
  /// further than [betaReward] in the future cannot be genuine (settings edited,
  /// clock turned back) and does not count.
  bool get rewardActive {
    final until = rewardUntil;
    if (until == null) return false;
    final now = clock();
    return now.isBefore(until) && !until.isAfter(rewardHardEnd) && !until.isAfter(now.add(betaReward));
  }

  /// Whether the transition period for existing users is still running. As with
  /// the thank-you, an end further away than the whole period does not count.
  bool get openTransitionActive {
    final until = _openUntil;
    if (until == null) return false;
    final now = clock();
    return now.isBefore(until) && !until.isAfter(now.add(openTransition));
  }

  /// End of the transition period, as long as it affects the user (nothing purchased yet).
  DateTime? get openUntil => openTransitionActive && _bought == Tier.free ? _openUntil : null;

  /// Tier from purchases, without beta, thank-you and transition period: up to
  /// here it is really purchased; above it the paywall shows purchase buttons.
  Tier get bought => _bought;

  /// Whether Pro is only a gift (thank-you, transition period).
  bool get gifted => rewardActive || openTransitionActive;

  /// One-time message for startup, see [acknowledgeNotice].
  PlanNotice? get notice => _notice;

  /// [notice] was shown and does not come back.
  Future<void> acknowledgeNotice() async {
    final shown = _notice;
    if (shown == null) return;
    _notice = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(shown == PlanNotice.openStarted ? _openStartShownKey : _openEndShownKey, true);
  }

  /// Hidden beta switch: test the paywall as in the store.
  Future<void> setBetaStore(bool on) async {
    if (!beta) return;
    betaStore = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_betaStoreKey, on);
    _show(_bought);
    notifyListeners();
  }

  /// Offers for the paywall (empty without a purchase channel).
  Future<List<PlanOffer>> offers() => source.offers();

  /// Buys [offer]; afterwards the new tier applies. If the purchase awaits
  /// approval, [awaitingApproval] remembers that; the tier then arrives via
  /// [PlanSource.onChange].
  Future<void> buy(PlanOffer offer) async {
    try {
      await _apply(await source.buy(offer));
    } on PlanAwaitingApproval {
      awaitingApproval = true;
      notifyListeners();
      rethrow;
    }
  }

  /// Store page for managing and cancelling the subscription.
  Future<Uri?> manageUrl() => source.manageUrl();

  /// Account signed in or out: assign purchases and fetch the tier again.
  Future<void> identify(String? userId) async {
    try {
      await source.identify(userId);
      await _apply(await source.current());
    } on Object catch (e) {
      debugPrint('Plan: $e');
    }
  }

  /// Restores earlier purchases (new device, reinstalled).
  Future<void> restore() async => _apply(await source.restore());

  /// Enter the license from the purchase email, see [PlanSource.redeem].
  Future<void> redeem(String code) async => _apply(await source.redeem(code));

  /// In the demo house everything is free: prospects should be able to try Pro.
  /// [value] stays the purchased tier (paywall, menu). Without notification: set
  /// while the monitor is built; the menus are created only afterwards.
  bool demo = false;

  /// Member of a company with an active subscription: Pro without an own purchase.
  bool _teamMember = false;
  set teamMember(bool on) {
    if (_teamMember == on) return;
    _teamMember = on;
    notifyListeners();
  }

  /// Tier by which features and limits apply.
  Tier get _effective => demo || _teamMember ? Tier.pro : value;

  bool allows(Feature f) => _effective.covers(f.tier);

  /// See [PlanSource.lapsed].
  Tier? get lapsed => source.lapsed;

  /// Deliberately all free: [PlanSource.open] or beta. No offers are missing here.
  bool get free => source.open || (beta && !betaStore);

  /// Whether there is anything to buy here.
  bool get purchasable => source.purchasable && (!beta || betaStore);

  /// Installations side by side.
  /// Platforms without a purchase channel limit via [PlanSource.maxInstallations].
  int get maxInstallations {
    final byTier = switch (_effective) {
      Tier.free => 1,
      Tier.plus => 3,
      Tier.pro => _unlimited,
    };
    final cap = source.maxInstallations;
    return cap == null || demo ? byTier : (cap < byTier ? cap : byTier);
  }

  /// Whether the platform itself limits the installations (add-on, Linux), not the tier.
  bool get installationsCapped {
    final cap = source.maxInstallations;
    return cap != null && !demo && maxInstallations == cap;
  }

  /// Saved recordings.
  int get maxRecordings => _effective == Tier.free ? 1 : _unlimited;

  /// Longest retention of the long-term history in days (0 = none).
  int get maxHistoryDays => allows(Feature.longHistory) ? _unlimited : 0;

  /// How far back the live monitor reaches; `null` = only the entry limit. Free
  /// keeps the last hour.
  Duration? get liveWindow => _effective == Tier.free ? const Duration(minutes: 60) : null;

  static const _unlimited = 1 << 30;
}
