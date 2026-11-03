import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/platform/account_plan.dart';
import 'package:knx_monitor/platform/license_plan.dart';
import 'package:knx_monitor/platform/store_plan.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlanSource _source(
  TargetPlatform platform, {
  bool web = false,
  bool release = true,
  bool planOpen = false,
  bool windowsShop = false,
  String licenseKey = '',
  bool accountConfigured = true,
  String appleKey = '',
  String googleKey = '',
}) => planSourceFor(
  platform: platform,
  web: web,
  release: release,
  planOpen: planOpen,
  windowsShop: windowsShop,
  licenseKey: licenseKey,
  accountConfigured: accountConfigured,
  appleKey: appleKey,
  googleKey: googleKey,
);

EntitlementInfo _entitlement(
  String name,
  String product, {
  Store store = Store.playStore,
  String? expires = '2027-01-01T00:00:00Z',
  String? billingIssue,
}) => EntitlementInfo(
  name,
  true,
  true,
  '2026-01-01T00:00:00Z',
  '2026-01-01T00:00:00Z',
  product,
  false,
  store: store,
  expirationDate: expires,
  billingIssueDetectedAt: billingIssue,
);

CustomerInfo _info(List<EntitlementInfo> active, {String requested = '2026-11-01T12:00:00Z'}) => CustomerInfo(
  EntitlementInfos({for (final e in active) e.identifier: e}, {for (final e in active) e.identifier: e}),
  const {},
  const [],
  const [],
  const [],
  '2026-01-01T00:00:00Z',
  'u1',
  const {},
  requested,
);

Package _package(String id) => Package(
  id,
  PackageType.custom,
  StoreProduct(id, '', '', 99, '99,00 €', 'EUR'),
  const PresentedOfferingContext('default', null, null),
);

void main() {
  group('Kaufweg je Plattform', () {
    test('Release ohne Schlüssel und ohne PLAN_OPEN: Free, nicht Pro', () async {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        final source = _source(platform);
        expect(source, isA<NoPlanSource>(), reason: '$platform');
        expect(await source.current(), Tier.free);
        expect(source.open, isFalse);
      }
    });

    test('Windows ohne Shop oder ohne Konto ist nicht frei', () {
      expect(_source(TargetPlatform.windows, windowsShop: true, accountConfigured: false), isA<NoPlanSource>());
      expect(_source(TargetPlatform.windows, windowsShop: true), isA<AccountPlanSource>());
    });

    test('Windows mit Lizenzschlüssel verkauft ohne Konto', () {
      final source = _source(TargetPlatform.windows, windowsShop: true, licenseKey: 'k', accountConfigured: false);
      expect(source, isA<LicensePlanSource>());
      expect(source.purchasable, isTrue);
      expect(source.open, isFalse);
    });

    test('Lizenzschlüssel allein schaltet nichts ein, und nur unter Windows', () {
      expect(_source(TargetPlatform.windows, licenseKey: 'k', accountConfigured: false), isA<NoPlanSource>());
      expect(_source(TargetPlatform.android, windowsShop: true, licenseKey: 'k'), isA<NoPlanSource>());
      expect(_source(TargetPlatform.linux, windowsShop: true, licenseKey: 'k'), isA<OpenPlanSource>());
    });

    test('PLAN_OPEN gibt bewusst frei und schlägt einen Schlüssel', () {
      final source = _source(TargetPlatform.iOS, planOpen: true, appleKey: 'appl_x');
      expect(source, isA<OpenPlanSource>());
      expect(source.open, isTrue);
      expect(source.maxInstallations, isNull);
    });

    test('Linux, Add-on und Box bleiben frei mit einer Anlage', () {
      for (final source in [_source(TargetPlatform.linux), _source(TargetPlatform.android, web: true)]) {
        expect(source, isA<OpenPlanSource>());
        expect(source.maxInstallations, 1);
      }
    });

    test('Mit Schlüssel der Store, Debug ohne Schlüssel frei', () {
      expect(_source(TargetPlatform.macOS, appleKey: 'appl_x'), isA<StorePlanSource>());
      expect(_source(TargetPlatform.android, googleKey: 'goog_x'), isA<StorePlanSource>());
      expect(_source(TargetPlatform.android, release: false), isA<OpenPlanSource>());
    });
  });

  group('Wechsel des Google-Abos', () {
    test('Plus auf Pro löst das laufende Plus ab', () {
      final info = _info([_entitlement('plus', 'plus_yearly')]);
      final params = StorePlanSource.purchaseParams(_package('pro_yearly'), info);
      expect(params.productChangeInfo?.oldProductIdentifier, 'plus_yearly');
      expect(params.productChangeInfo?.replacementMode, StoreReplacementMode.withTimeProration);
    });

    test('Basis-Abo in der ID stört nicht, Pro geht vor Plus', () {
      final info = _info([_entitlement('plus', 'pro_monthly:monthly'), _entitlement('pro', 'pro_monthly:monthly')]);
      expect(StorePlanSource.googleSubscriptionToReplace(info, 'pro_yearly:yearly'), 'pro_monthly');
    });

    test('Nichts abzulösen: kein Abo, Einmalkauf, anderer Store, gleiches Abo', () {
      String? old(List<EntitlementInfo> active, [String id = 'pro_yearly']) =>
          StorePlanSource.googleSubscriptionToReplace(_info(active), id);
      expect(old([]), isNull);
      expect(old([_entitlement('plus', 'plus_lifetime', expires: null)]), isNull);
      expect(old([_entitlement('plus', 'plus_yearly', store: Store.appStore)]), isNull);
      expect(old([_entitlement('pro', 'pro_yearly')]), isNull);
    });

    test('Ohne Kundendaten (Apple) keine Angabe', () {
      expect(StorePlanSource.purchaseParams(_package('pro_yearly'), null).productChangeInfo, isNull);
    });
  });

  test('Warten auf Freigabe ist kein Kauffehler', () {
    PlatformException error(PurchasesErrorCode code) => PlatformException(code: '${code.index}');
    expect(StorePlanSource.purchaseFailure(error(PurchasesErrorCode.paymentPendingError)), isA<PlanAwaitingApproval>());
    expect(StorePlanSource.purchaseFailure(error(PurchasesErrorCode.purchaseCancelledError)), isA<PlanCancelled>());
    expect(StorePlanSource.purchaseFailure(error(PurchasesErrorCode.networkError)), isA<PlatformException>());
  });

  group('Eindeutige Antwort des Stores', () {
    final now = DateTime.utc(2026, 11, 1, 13);

    test('Frisch und ohne Zahlungsproblem', () {
      expect(StorePlanSource.definiteAnswer(_info([]), now), isTrue);
    });

    test('Zwischengespeichert oder unlesbar: nicht eindeutig', () {
      expect(StorePlanSource.definiteAnswer(_info([], requested: '2026-10-20T12:00:00Z'), now), isFalse);
      expect(StorePlanSource.definiteAnswer(_info([], requested: 'kaputt'), now), isFalse);
    });

    test('Zahlungsproblem: nicht eindeutig', () {
      final info = _info([_entitlement('pro', 'pro_yearly', billingIssue: '2026-10-31T00:00:00Z')]);
      expect(StorePlanSource.definiteAnswer(info, now), isFalse);
    });
  });

  test('Windows ohne Konfiguration bleibt ohne gespeicherte Stufe', () async {
    SharedPreferences.setMockInitialValues({});
    await Plan.instance.load(using: _source(TargetPlatform.windows));
    await Plan.instance.refreshing;
    expect(Plan.instance.value, Tier.free);
    expect(Plan.instance.free, isFalse);
    expect((await SharedPreferences.getInstance()).getString('plan_tier'), isNull);
  });
}
