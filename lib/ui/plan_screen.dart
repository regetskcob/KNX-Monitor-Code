import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/locale_controller.dart';
import '../model/betrieb_mode.dart';
import '../model/plan.dart';
import '../model/plan_source.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate;
import '../model/account.dart';
import '../platform/account_plan.dart';
import '../platform/addon.dart';
import '../platform/license_plan.dart';
import 'account_screen.dart';

/// Name of the tier as stores and website write it (not translated).
String tierName(Tier t) => switch (t) {
  Tier.free => 'Free',
  Tier.plus => 'Plus',
  Tier.pro => 'Pro',
};

/// Name of a feature as it is called in the menu.
String featureName(Feature f) => switch (f) {
  Feature.longHistory => s.historyTitle,
  Feature.charts => s.chartsTitle,
  Feature.watcher => s.watchTitle,
  Feature.statistics => s.statsTitle,
  Feature.alarms => s.notifyMenu,
  Feature.export => s.planFeatureFullExport,
  Feature.diagnostics => s.diagnosticsTitle,
  Feature.commissioning => s.commTitle,
  Feature.projectCheck => s.checkTitle,
  Feature.busMonitor => s.busmonTitle,
  Feature.topology => s.topoTitle,
  Feature.communicationMap => s.mapTitle,
  Feature.trigger => s.triggerTitle,
  Feature.busReplay => s.planFeatureReplay,
  Feature.scheduledSend => s.planFeatureScheduled,
  Feature.box => s.boxAdd,
  Feature.soundAck => s.ackTitle,
  Feature.acceptance => s.acceptTitle,
  Feature.faultHunt => s.huntTitle,
  Feature.haConfig => s.haTitle,
  Feature.causeChain => s.chainTitle,
  Feature.securityCheck => s.secTitle,
  Feature.inventory => s.invTitle,
  Feature.siteDocs => s.siteDocsTitle,
  Feature.homePlan => s.hpTitle,
  Feature.plantReport => s.plantTitle,
  Feature.loadValues => s.loadTitle,
  Feature.letterhead => s.companyFeature,
  Feature.serviceReport => s.srFeature,
  Feature.customerRecords => s.customerFeature,
  Feature.handover => s.handoverFeature,
  Feature.handoverReceive => s.handoverReceiveFeature,
  Feature.residentManual => s.manualFeature,
  Feature.cloudSync => s.cloudSyncFeature,
  // Behind the switch so the texts are not in the shipped app.
  Feature.team => Betrieb.enabled ? s.teamTitle : '',
  Feature.askMaster => Betrieb.enabled ? s.teamAskTitle : '',
  Feature.businessStandard => Betrieb.enabled ? s.bizStandardTitle : '',
  Feature.gaAssistant => Betrieb.enabled ? s.bizAssistantTitle : '',
  Feature.standardCheck => Betrieb.enabled ? s.bizCheckTitle : '',
  Feature.siteNotes => Betrieb.enabled ? s.bizNotesTitle : '',
  Feature.siteSurvey => Betrieb.enabled ? s.bizSurveyTitle : '',
};

/// Whether [feature] is unlocked. Otherwise the paywall opens; afterwards it
/// counts whether a purchase was made.
Future<bool> unlock(BuildContext context, Feature feature) async {
  final plan = Plan.instance;
  if (plan.allows(feature)) return true;
  await showPlanScreen(
    context,
    reason: s.planFeatureLocked(featureName(feature), tierName(feature.tier)),
    need: feature.tier,
  );
  return plan.allows(feature);
}

/// [need]: the tier that resolves the occasion. For Pro the page shows only
/// Pro, so nobody buys Plus and then faces the same lock.
Future<void> showPlanScreen(BuildContext context, {String? reason, Tier need = Tier.plus}) => Navigator.of(context)
    .push(
      MaterialPageRoute<void>(
        builder: (_) => PlanScreen(reason: reason, need: need),
      ),
    );

/// Beta notice from the menu. Hidden: a long press on the title toggles between
/// the beta unlock and the paywall as in the store (sandbox).
Future<void> showBetaInfo(BuildContext context) => showAdaptiveDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog.adaptive(
    title: GestureDetector(
      onLongPress: () async {
        final messenger = ScaffoldMessenger.of(context);
        final plan = Plan.instance;
        await plan.setBetaStore(!plan.betaStore);
        if (dialog.mounted) Navigator.of(dialog).pop();
        messenger.showSnackBar(SnackBar(content: Text(plan.betaStore ? s.planBetaStoreOn : s.planBetaStoreOff)));
      },
      child: Text(s.planBetaTitle),
    ),
    content: Text(s.planBetaBody(Plan.betaReward.inDays ~/ 30)),
    actions: [
      horizontDialogAction(dialog, label: s.commonClose, primary: true, onPressed: () => Navigator.of(dialog).pop()),
    ],
  ),
);

/// Shows one-time messages of [Plan.notice] as a dialog, even without anyone
/// opening the paywall: start and end of the transition period for existing users.
class PlanNoticeGate extends StatefulWidget {
  const PlanNoticeGate({super.key, required this.child});

  final Widget child;

  @override
  State<PlanNoticeGate> createState() => _PlanNoticeGateState();
}

class _PlanNoticeGateState extends State<PlanNoticeGate> {
  @override
  void initState() {
    super.initState();
    Plan.instance.addListener(_check);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    Plan.instance.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted) return;
    final plan = Plan.instance;
    final until = plan.openUntil;
    final body = switch (plan.notice) {
      PlanNotice.openStarted => until == null ? null : s.planOpenNotice(formatDate(until)),
      PlanNotice.openEnded => s.planOpenEnded,
      null => null,
    };
    if (body == null) return;
    // Remembers immediately that it was shown, so it does not appear twice.
    unawaited(plan.acknowledgeNotice());
    unawaited(_show(body));
  }

  Future<void> _show(String body) async {
    final open = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.planTitle),
        content: Text(body),
        actions: [
          horizontDialogAction(dialog, label: s.commonClose, onPressed: () => Navigator.of(dialog).pop(false)),
          horizontDialogAction(
            dialog,
            label: s.planTitle,
            primary: true,
            onPressed: () => Navigator.of(dialog).pop(true),
          ),
        ],
      ),
    );
    if (open == true && mounted) await showPlanScreen(context);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Small badge of the required tier ("PRO") on locked entries.
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key});

  final Tier tier;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.row,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4, vertical: HzSpace.s2),
        child: Kennung(tierName(tier)),
      ),
    );
  }
}

/// Paywall: what Plus and Pro offer, prices from the store, purchase and
/// restore. Built in-house following Horizont, no store paywall.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, this.reason, this.need = Tier.plus});

  /// Why the page opened ("„Diagnose“ gehört zu Pro.", diagnostics is part of Pro).
  final String? reason;

  /// Minimum tier for the occasion; lower tiers do not appear.
  final Tier need;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final Future<List<PlanOffer>> _offers = Plan.instance.offers();
  bool _busy = false;

  static final _terms = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
  static Uri get _privacy => Uri.parse(
    LocaleController.instance.locale.languageCode == 'de'
        ? 'https://knx-monitor.de/datenschutz/'
        : 'https://knx-monitor.de/en/privacy/',
  );

  Future<void> _run(Future<void> Function() action, String Function() done) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done())));
    } on PlanCancelled {
      // Abgebrochen: keine Meldung.
    } on PlanPending {
      messenger.showSnackBar(
        SnackBar(
          content: Text(Plan.instance.source is LicensePlanSource ? s.planLicenseCheckoutOpened : s.planCheckoutOpened),
        ),
      );
    } on LicenseRejected {
      messenger.showSnackBar(SnackBar(content: Text(s.planLicenseInvalid)));
    } on PlanAwaitingApproval {
      messenger.showSnackBar(SnackBar(content: Text(s.planPendingApproval)));
    } on PlatformException catch (e) {
      // The store's own reason (e.g. payment declined) helps the user.
      messenger.showSnackBar(
        horizontMessageSnackBar(colors, s.planBuyFailed(e.message ?? e.code), status: HorizontStatus.critical),
      );
    } on Object catch (e) {
      debugPrint('Kauf: $e');
      messenger.showSnackBar(horizontMessageSnackBar(colors, s.actionFailed, status: HorizontStatus.critical));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(PlanOffer offer) async {
    // Windows purchases via the account: sign in first, then to the purchase page.
    if (Plan.instance.source is AccountPlanSource && !Account.instance.signedIn) {
      await showAccountScreen(context);
      if (!mounted || !Account.instance.signedIn) return;
    }
    await _run(() => Plan.instance.buy(offer), () => s.planThanks(tierName(offer.tier)));
  }

  void _restore() => _run(
    Plan.instance.restore,
    () => Plan.instance.value == Tier.free ? s.planNothingRestored : s.planRestored(tierName(Plan.instance.value)),
  );

  Future<void> _enterLicense() async {
    final code = await showDialog<String>(context: context, builder: (_) => const _LicenseDialog());
    if (code == null || !mounted) return;
    await _run(
      () => Plan.instance.redeem(code),
      () =>
          Plan.instance.bought == Tier.free ? s.planLicenseEnded : s.planLicenseActive(tierName(Plan.instance.bought)),
    );
  }

  Future<void> _manage() async {
    if (await Plan.instance.manageUrl() case final url?) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(title: Text(s.planTitle)),
      body: ValueListenableBuilder<Tier>(
        valueListenable: Plan.instance,
        builder: (context, tier, _) => FutureBuilder<List<PlanOffer>>(
          future: _offers,
          builder: (context, snapshot) {
            final offers = snapshot.data ?? const <PlanOffer>[];
            final loading = snapshot.connectionState != ConnectionState.done;
            final plan = Plan.instance;
            // A gifted Pro does not hide the purchase buttons: it should be
            // possible to buy before it ends.
            final owned = plan.gifted ? plan.bought : tier;
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.reading),
                child: ListView(
                  padding: Gap.page,
                  children: [
                    if (widget.reason case final reason?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.inner),
                        child: Text(reason, style: theme.textTheme.titleMedium),
                      ),
                    // Current tier in the green box.
                    SectionCard(
                      soft: true,
                      child: Text(
                        s.planCurrent(tierName(tier)),
                        style: theme.textTheme.titleMedium?.copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: Gap.item),
                    if (Plan.instance.lapsed case final lapsed?)
                      Text(
                        s.planLapsed(tierName(lapsed)),
                        style: theme.textTheme.bodyMedium?.copyWith(color: hz.critical),
                      ),
                    if (Plan.instance.rewardActive)
                      Text(
                        s.planBetaReward(formatDate(Plan.instance.rewardUntil!)),
                        style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                      ),
                    if (plan.openUntil case final until?)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.inner),
                        child: HorizontNotice(HorizontStatus.warning, child: Text(s.planOpenNotice(formatDate(until)))),
                      ),
                    if (plan.awaitingApproval)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.inner),
                        child: HorizontNotice(HorizontStatus.warning, child: Text(s.planPendingApproval)),
                      ),
                    // Above the tiers, otherwise it would sit below two long cards
                    // without buttons. `free`: nothing is missing there.
                    if (!loading && offers.isEmpty && !plan.free)
                      Padding(
                        padding: const EdgeInsets.only(top: Gap.inner),
                        child: HorizontNotice(
                          HorizontStatus.warning,
                          child: Text(snapshot.hasError ? s.planNoOffers : s.planNotYetAvailable),
                        ),
                      ),
                    const SizedBox(height: Gap.section),
                    // From the menu (without an occasion) Pro first, Plus below. If Plus
                    // resolves an occasion ("Home Assistant gehört zu Plus"), Plus is on top.
                    // If the occasion requires Pro, only Pro.
                    for (final t in switch ((widget.need, widget.reason)) {
                      (Tier.plus, null) => [Tier.pro, Tier.plus],
                      (Tier.plus, _) => [Tier.plus, Tier.pro],
                      _ => [Tier.pro],
                    }) ...[
                      _TierCard(
                        tier: t,
                        // Without Plus next to it, Pro lists everything, not just the extra.
                        complete: widget.need == Tier.pro,
                        active: owned.covers(t),
                        offers: [
                          for (final o in offers)
                            if (o.tier == t) o,
                        ],
                        loading: loading,
                        busy: _busy,
                        onBuy: _buy,
                      ),
                      const SizedBox(height: Gap.section),
                    ],
                    if (Plan.instance.purchasable) ...[
                      // A license syncs itself; restoring would only mean "enter it again" here.
                      if (plan.source is LicensePlanSource)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(onPressed: _busy ? null : _enterLicense, child: Text(s.planLicenseEnter)),
                        )
                      else
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(onPressed: _busy ? null : _restore, child: Text(s.planRestore)),
                        ),
                      // Windows manages on the purchase page; without offers there is none.
                      if (owned != Tier.free && (offers.isNotEmpty || plan.source is! AccountPlanSource))
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(onPressed: _manage, child: Text(s.planManage)),
                        ),
                      // Account: one purchase on all devices (iPad, Windows, Mac).
                      if (Account.instance.configured)
                        ListenableBuilder(
                          listenable: Account.instance,
                          builder: (context, _) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: () => showAccountScreen(context),
                              icon: const Icon(AppIcons.account, size: 18),
                              label: Text(
                                Account.instance.signedIn
                                    ? s.accountSignedInAs(Account.instance.email ?? '')
                                    : s.accountUseEverywhere,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: Gap.item),
                      Text(s.planLegal, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                      Wrap(
                        spacing: Gap.item,
                        children: [
                          // Apple requires terms of use and privacy policy on the purchase page.
                          if (defaultTargetPlatform == TargetPlatform.iOS ||
                              defaultTargetPlatform == TargetPlatform.macOS)
                            TextButton(onPressed: () => launchUrl(_terms), child: Text(s.planTerms)),
                          TextButton(onPressed: () => launchUrl(_privacy), child: Text(s.planPrivacy)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A tier: label, sentence, what is added, purchase buttons.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.tier,
    required this.complete,
    required this.active,
    required this.offers,
    required this.loading,
    required this.busy,
    required this.onBuy,
  });

  final Tier tier;

  /// Whether to list everything, including what the tier below already offers.
  final bool complete;
  final bool active;
  final List<PlanOffer> offers;
  final bool loading;
  final bool busy;
  final ValueChanged<PlanOffer> onBuy;

  /// What this tier offers: Pro tools first, then (with [complete] or for Plus)
  /// the Plus features.
  List<String> get _points => [
    if (tier == Tier.pro) ...[
      for (final f in Feature.values)
        if (f.tier == Tier.pro && f.listed && (f != Feature.haConfig || Addon.embedded)) featureName(f),
      s.planUnlimitedInstallations,
      if (!complete) s.planAllOfPlus,
    ],
    if (tier == Tier.plus || complete) ...[
      for (final f in Feature.values)
        if (f.tier == Tier.plus && f.listed && (f != Feature.haConfig || Addon.embedded)) featureName(f),
      s.planUnlimitedRecordings,
      if (tier == Tier.plus) s.planInstallations(3),
    ],
  ];

  String _label(PlanOffer o) {
    final price = switch (o.period) {
      OfferPeriod.yearly => s.planPerYear(o.price),
      OfferPeriod.monthly => s.planPerMonth(o.price),
      OfferPeriod.lifetime => s.planOnce(o.price),
    };
    return o.trialDays > 0 ? s.planTrial(o.trialDays, price) : price;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return SectionCard(
      title: tierName(tier),
      trailing: active ? Kennung(s.planActive, color: hz.accentText) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tier == Tier.plus ? s.planPlusPitch : s.planProPitch, style: theme.textTheme.bodyMedium),
          const SizedBox(height: Gap.inner),
          for (final p in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(AppIcons.success, size: 18, color: hz.textMuted),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(p, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          if (!active && (loading || offers.isNotEmpty)) ...[
            const SizedBox(height: Gap.inner),
            if (loading)
              const Center(child: CircularProgressIndicator.adaptive())
            else
              for (final (i, o) in offers.indexed)
                Padding(
                  padding: const EdgeInsets.only(top: HzSpace.s8),
                  // First offer as the primary action, the others quieter.
                  child: i == 0
                      ? FilledButton(onPressed: busy ? null : () => onBuy(o), child: Text(_label(o)))
                      : OutlinedButton(onPressed: busy ? null : () => onBuy(o), child: Text(_label(o))),
                ),
          ],
        ],
      ),
    );
  }
}

/// Entry of the license from the purchase email; usually pasted, line breaks do not matter.
class _LicenseDialog extends StatefulWidget {
  const _LicenseDialog();

  @override
  State<_LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends State<_LicenseDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(s.planLicenseEnter),
      content: TextField(
        controller: _code,
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: s.planLicenseField, helperText: s.planLicenseHelp, helperMaxLines: 3),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _code.text), child: Text(s.planLicenseApply)),
      ],
    );
  }
}
