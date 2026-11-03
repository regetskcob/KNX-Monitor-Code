import 'plan.dart';

/// A purchasable package as shown on the paywall.
class PlanOffer {
  const PlanOffer({
    required this.id,
    required this.tier,
    required this.price,
    required this.period,
    this.trialDays = 0,
    this.handle,
  });

  /// Free trial in days this device is eligible for (0 = none).
  final int trialDays;

  /// Product ID in the stores (`pro_yearly` …).
  final String id;
  final Tier tier;

  /// Formatted price from the store ("99,00 €").
  final String price;
  final OfferPeriod period;

  /// Object of the purchase channel (RevenueCat package), only for [PlanSource.buy].
  final Object? handle;
}

enum OfferPeriod { monthly, yearly, lifetime }

/// The purchase was cancelled in the store dialog – not an error.
class PlanCancelled implements Exception {
  const PlanCancelled();
}

/// The purchase continues in the browser (Windows, Paddle): afterwards use
/// "Käufe wiederherstellen" (restore purchases) in the app or enter the license from the email.
class PlanPending implements Exception {
  const PlanPending();
}

/// The purchase awaits approval (Apple "Ask to Buy", Google deferred payment):
/// not an error, and no tier yet.
class PlanAwaitingApproval implements Exception {
  const PlanAwaitingApproval();
}

/// The entered license text is wrong (typo, truncated, not ours).
class LicenseRejected implements Exception {
  const LicenseRejected();
}

/// Where the tier comes from: store, later an account with web purchase.
abstract class PlanSource {
  const PlanSource();

  /// Purchase channel of the current platform. Without one, everything is free.
  static PlanSource Function() forPlatform = OpenPlanSource.new;

  /// Whether there is anything to buy here.
  bool get purchasable;

  /// Deliberately free (add-on, Linux, build with `PLAN_OPEN`): everything is Pro here.
  bool get open => false;

  /// Whether the last response from [current], [buy] or [restore] was definitive,
  /// i.e. fresh and without a payment problem. Only then does [Plan.refundGrace]
  /// apply instead of [Plan.paidGrace].
  bool get lastAnswerDefinite => false;

  Future<Tier> current();
  Future<List<PlanOffer>> offers();
  Future<Tier> buy(PlanOffer offer);
  Future<Tier> restore();

  /// Enter the license from the purchase email (only [LicensePlanSource]). Throws
  /// [LicenseRejected] if it is wrong.
  Future<Tier> redeem(String code) => throw const LicenseRejected();

  /// Store page where the subscription is managed and cancelled.
  Future<Uri?> manageUrl() async => null;

  /// Assigns purchases to an account (`null` = signed out); see Account.
  Future<void> identify(String? userId) async {}

  /// Paid tier that lapsed for lack of verification (account offline for more
  /// than 30 days); the paywall then explains why Free applies again.
  Tier? get lapsed => null;

  /// Limit on installations independent of the tier (`null` = none).
  int? get maxInstallations => null;

  /// Whether a TestFlight beta build is running. Then everything is free. `null`:
  /// currently not determinable (no network, error); that is not the same as
  /// "no beta" and therefore does not start a thank-you.
  Future<bool?> get betaUnlock async => false;

  /// Reports changes from outside (subscription renewed, expired, refunded).
  set onChange(void Function(Tier tier) listener) {}
}

/// Deliberately without a purchase channel (Linux, add-on, box in the browser,
/// build with `PLAN_OPEN`): everything free. The add-on and Linux additionally
/// get only one installation ([maxInstallations]), otherwise they would be a way
/// around the tiers.
class OpenPlanSource extends PlanSource {
  const OpenPlanSource({this.maxInstallations});

  @override
  final int? maxInstallations;

  @override
  bool get purchasable => false;

  @override
  bool get open => true;

  @override
  Future<Tier> current() async => Tier.pro;

  @override
  Future<List<PlanOffer>> offers() async => const [];

  @override
  Future<Tier> buy(PlanOffer offer) async => Tier.pro;

  @override
  Future<Tier> restore() async => Tier.pro;
}

/// Release without a purchase channel and without `PLAN_OPEN` (forgotten key):
/// Free, so a build mistake does not give everything away. The paywall says
/// "not yet available".
class NoPlanSource extends PlanSource {
  const NoPlanSource();

  @override
  bool get purchasable => false;

  @override
  Future<Tier> current() async => Tier.free;

  @override
  Future<List<PlanOffer>> offers() async => const [];

  @override
  Future<Tier> buy(PlanOffer offer) async => Tier.free;

  @override
  Future<Tier> restore() async => Tier.free;
}
