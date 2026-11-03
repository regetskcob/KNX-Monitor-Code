import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../model/plan.dart';
import '../model/plan_source.dart';
import '../model/account.dart';
import 'account_plan.dart';
import 'license_plan.dart';

/// Public RevenueCat SDK keys, set at build time via `--dart-define=RC_APPLE_KEY=appl_…` or
/// `RC_GOOGLE_KEY=goog_…`.
const _appleKey = String.fromEnvironment('RC_APPLE_KEY');
const _googleKey = String.fromEnvironment('RC_GOOGLE_KEY');

/// Only beta builds (`--dart-define=BETA=true`) for TestFlight and the Google Play test tracks.
/// Apple reviews apps in the same sandbox as TestFlight, and Google can promote a test build
/// unchanged to production: builds for review and production are made without BETA.
const _betaBuild = bool.fromEnvironment('BETA');

/// Windows sells via the account (Paddle): `--dart-define=WINDOWS_SHOP=true`. Only effective with a
/// license key ([_licenseKey]) or with an account, i.e. the `BETRIEB` switch; otherwise there is
/// nothing to buy on Windows ([NoPlanSource]).
const _windowsShop = bool.fromEnvironment('WINDOWS_SHOP');

/// Switch for selling without an account: public license key (SPKI, base64) via
/// `--dart-define=LICENSE_PUBLIC_KEY=…`.
const _licenseKey = String.fromEnvironment('LICENSE_PUBLIC_KEY');

/// Deliberately everything free, only from `RC_NONE=1 tool/release.sh …`: store builds while there
/// are no sales yet.
const _planOpen = bool.fromEnvironment('PLAN_OPEN');

/// Purchase path of the current platform.
PlanSource storePlanSource() => planSourceFor(
  platform: defaultTargetPlatform,
  web: kIsWeb,
  release: kReleaseMode,
  planOpen: _planOpen,
  windowsShop: _windowsShop,
  licenseKey: _licenseKey,
  accountConfigured: Account.instance.configured,
  appleKey: _appleKey,
  googleKey: _googleKey,
);

/// Deliberately free are the add-on and box in the browser as well as Linux (one installation each)
/// and builds with `PLAN_OPEN`. Otherwise stores via RevenueCat, Windows via license or account. If
/// the purchase path is missing in a release, Free applies: a forgotten key must not give anything
/// away. Debug and profile stay free.
PlanSource planSourceFor({
  required TargetPlatform platform,
  required bool web,
  required bool release,
  required bool planOpen,
  required bool windowsShop,
  required String licenseKey,
  required bool accountConfigured,
  required String appleKey,
  required String googleKey,
}) {
  if (web || platform == TargetPlatform.linux) return const OpenPlanSource(maxInstallations: 1);
  if (planOpen) return const OpenPlanSource();
  if (platform == TargetPlatform.windows && windowsShop) {
    if (licenseKey.isNotEmpty) return LicensePlanSource(publicKey: licenseKey);
    if (accountConfigured) return AccountPlanSource();
  }
  final key = switch (platform) {
    TargetPlatform.iOS || TargetPlatform.macOS => appleKey,
    TargetPlatform.android => googleKey,
    _ => '',
  };
  if (key.isNotEmpty) return StorePlanSource(key);
  return release ? const NoPlanSource() : const OpenPlanSource();
}

/// App Store and Google Play via RevenueCat.
class StorePlanSource extends PlanSource {
  StorePlanSource(this._key);

  final String _key;
  Future<void>? _configured;

  /// Set up once, on first access. If that fails, the next access tries again instead of being
  /// stuck on the error until restart.
  Future<void> _ready() => _configured ??= Purchases.configure(PurchasesConfiguration(_key)).catchError((Object e) {
    _configured = null;
    throw e;
  });

  @override
  bool get purchasable => true;

  /// Beta build and remote switch: metadata `beta_unlock` on the offering in RevenueCat. Android
  /// does not detect test tracks by itself and needs the switch (`true`); on Apple devices
  /// TestFlight is enough, and `false` turns the beta off there. Without a network the SDK returns
  /// the last loaded offerings. Errors and a missing offering yield `null`: undeterminable.
  @override
  Future<bool?> get betaUnlock async {
    if (!_betaBuild) return false;
    try {
      await _ready();
      final current = (await Purchases.getOfferings()).current;
      if (current == null) return null;
      final remote = current.metadata['beta_unlock'];
      if (defaultTargetPlatform == TargetPlatform.android) return remote == true;
      if (remote == false) return false;
      // "sandbox" = TestFlight; "production" in the App Store.
      return await const MethodChannel('knx/native').invokeMethod<String>('storeEnvironment') == 'sandbox';
    } on Object {
      return null;
    }
  }

  /// Tier from the active entitlements `pro` and `plus`.
  static Tier _tierOf(CustomerInfo info) {
    final active = info.entitlements.active;
    if (active.containsKey('pro')) return Tier.pro;
    if (active.containsKey('plus')) return Tier.plus;
    return Tier.free;
  }

  /// How recent a response must be to count as fresh; otherwise the SDK also returns cached data
  /// from days ago.
  static const freshFor = Duration(hours: 24);

  /// A fresh response without a payment problem is unambiguous: then the store really decided so
  /// (refund, expired). The SDK does not provide a separate field for refunds; it removes the
  /// entitlement.
  static bool definiteAnswer(CustomerInfo info, DateTime now) {
    final asked = DateTime.tryParse(info.requestDate);
    if (asked == null || now.difference(asked).abs() > freshFor) return false;
    return info.entitlements.all.values.every((e) => e.billingIssueDetectedAt == null);
  }

  @override
  bool get lastAnswerDefinite => _definite;
  bool _definite = false;

  Tier _answer(CustomerInfo info) {
    _definite = definiteAnswer(info, DateTime.now());
    return _tierOf(info);
  }

  @override
  Future<Tier> current() async {
    await _ready();
    return _answer(await Purchases.getCustomerInfo());
  }

  @override
  set onChange(void Function(Tier tier) listener) {
    _ready().then((_) => Purchases.addCustomerInfoUpdateListener((info) => listener(_answer(info))));
  }

  @override
  Future<List<PlanOffer>> offers() async {
    await _ready();
    final packages = (await Purchases.getOfferings()).current?.availablePackages ?? const <Package>[];
    final eligible = await _trialEligibility(packages);
    final offers = [for (final p in packages) _offerOf(p, eligible)];
    // Per tier the yearly subscription first: the paywall highlights the first one.
    int rank(PlanOffer o) => switch (o.period) {
      OfferPeriod.yearly => 0,
      OfferPeriod.lifetime => 1,
      OfferPeriod.monthly => 2,
    };
    return offers..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  /// Tier and period from the product ID (`pro_yearly`; on Google with the base plan appended,
  /// `pro_yearly:yearly`).
  static PlanOffer _offerOf(Package p, Set<String> eligible) {
    final id = p.storeProduct.identifier;
    final intro = p.storeProduct.introductoryPrice;
    return PlanOffer(
      id: id,
      tier: id.startsWith('pro') ? Tier.pro : Tier.plus,
      price: p.storeProduct.priceString,
      period: id.contains('monthly')
          ? OfferPeriod.monthly
          : id.contains('lifetime')
          ? OfferPeriod.lifetime
          : OfferPeriod.yearly,
      trialDays: intro != null && intro.price == 0 && eligible.contains(id)
          ? intro.periodNumberOfUnits *
                switch (intro.periodUnit) {
                  PeriodUnit.week => 7,
                  PeriodUnit.month => 30,
                  PeriodUnit.year => 365,
                  _ => 1,
                }
          : 0,
      handle: p,
    );
  }

  /// Products whose trial this account may still use. Apple checks this explicitly; Google only
  /// offers them to eligible users anyway.
  static Future<Set<String>> _trialEligibility(List<Package> packages) async {
    final ids = [for (final p in packages) p.storeProduct.identifier];
    if (defaultTargetPlatform == TargetPlatform.android) return ids.toSet();
    try {
      final result = await Purchases.checkTrialOrIntroductoryPriceEligibility(ids);
      return {
        for (final MapEntry(:key, :value) in result.entries)
          if (value.status == IntroEligibilityStatus.introEligibilityStatusEligible) key,
      };
    } on Object {
      return const {};
    }
  }

  /// Running Google subscription that a purchase of [offerId] must replace. Without this, it keeps
  /// running on Google and is charged twice; on Apple the subscription group takes care of it.
  /// One-time purchases and subscriptions from other stores cannot be replaced.
  static String? googleSubscriptionToReplace(CustomerInfo info, String offerId) {
    String base(String id) => id.split(':').first;
    for (final name in const ['pro', 'plus']) {
      final e = info.entitlements.active[name];
      if (e == null || e.store != Store.playStore || e.expirationDate == null) continue;
      final old = base(e.productIdentifier);
      return old == base(offerId) ? null : old;
    }
    return null;
  }

  /// Purchase parameters; [info] only needed on Android.
  static PurchaseParams purchaseParams(Package package, CustomerInfo? info) {
    final old = info == null ? null : googleSubscriptionToReplace(info, package.storeProduct.identifier);
    return PurchaseParams.package(
      package,
      productChangeInfo: old == null
          ? null
          : StoreProductChangeInfo(old, replacementMode: StoreReplacementMode.withTimeProration),
    );
  }

  /// Translates errors of the purchase dialog: cancelling and waiting for approval are not errors.
  static Exception purchaseFailure(PlatformException e) => switch (PurchasesErrorHelper.getErrorCode(e)) {
    PurchasesErrorCode.purchaseCancelledError => const PlanCancelled(),
    PurchasesErrorCode.paymentPendingError => const PlanAwaitingApproval(),
    _ => e,
  };

  @override
  Future<Tier> buy(PlanOffer offer) async {
    await _ready();
    final package = offer.handle! as Package;
    final info = defaultTargetPlatform == TargetPlatform.android ? await Purchases.getCustomerInfo() : null;
    try {
      final result = await Purchases.purchase(purchaseParams(package, info));
      return _answer(result.customerInfo);
    } on PlatformException catch (e) {
      throw purchaseFailure(e);
    }
  }

  /// Link purchases to the account: RevenueCat merges the anonymous user with the account ID, and
  /// purchases from the web (Paddle) are added.
  @override
  Future<void> identify(String? userId) async {
    await _ready();
    if (userId != null) {
      await Purchases.logIn(userId);
    } else if (!(await Purchases.isAnonymous)) {
      await Purchases.logOut();
    }
  }

  @override
  Future<Uri?> manageUrl() async {
    await _ready();
    final url = (await Purchases.getCustomerInfo()).managementURL;
    if (url != null) return Uri.tryParse(url);
    // Without a subscription (e.g. only a one-time purchase) the store's general subscription page.
    return Uri.parse(
      defaultTargetPlatform == TargetPlatform.android
          ? 'https://play.google.com/store/account/subscriptions'
          : 'https://apps.apple.com/account/subscriptions',
    );
  }

  @override
  Future<Tier> restore() async {
    await _ready();
    return _answer(await Purchases.restorePurchases());
  }
}
