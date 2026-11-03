import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/plan_source.dart';
import 'package:knx_monitor/platform/license_plan.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Vektoren aus signLicense() in supabase/functions/_shared/license.ts mit einem
// Wegwerf-Schlüssel: So passt das Format von Server und App nachweislich zusammen.
const _vectorKey =
    'MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAET6G+q1p/it5BYdyOBjFEfN1BiFx+I8dUXsX6dc6/EH1AGkdGsGhjv6Qr9VEVe+GZKJTEGxl5m1LOqAUnHKqjYA==';
const _vectorSub =
    'KNX1.eyJ0eXAiOiJrbngtbGljZW5zZSIsImxpZCI6InN1Yl8wMXRlc3QiLCJwcm9kdWN0IjoicHJvX3llYXJseSIsInRpZXIiOiJwcm8iLCJ1bnRpbCI6MTgyNTExMzYwMCwiaWF0IjoxNzkzNTc3NjAwfQ.KHfKd3ThlO3UxZrrr-GswIpQJD05csD1IbO5-dUubV9ToMUofUu7OcquPSRFzEtJt2_hLPAHXPJTd6F_xbuUMA';
const _vectorOnce =
    'KNX1.eyJ0eXAiOiJrbngtbGljZW5zZSIsImxpZCI6InR4bl8wMXRlc3QiLCJwcm9kdWN0IjoicGx1c19saWZldGltZSIsInRpZXIiOiJwbHVzIiwidW50aWwiOm51bGwsImlhdCI6MTc5MzU3NzYwMH0.jcHV3LN8L11e_t0RBGPC5CF26riIvWp1-fDqpWn-j888dB6J3pJ4wzzjSehS-kpnlc0yozK05EaAvQJKXwVP_Q';

void main() {
  group('Format', () {
    test('Abo vom Server wird gelesen', () {
      final c = LicenseClaims.verify(_vectorSub, _vectorKey)!;
      expect(c.id, 'sub_01test');
      expect(c.product, 'pro_yearly');
      expect(c.tier, Tier.pro);
      expect(c.issuedAt.toUtc(), DateTime.utc(2026, 11, 2));
      expect(c.until?.toUtc(), DateTime.utc(2027, 11, 2));
    });

    test('Einmalkauf vom Server gilt dauerhaft', () {
      final c = LicenseClaims.verify(_vectorOnce, _vectorKey)!;
      expect(c.tier, Tier.plus);
      expect(c.until, isNull);
    });

    test('Verändert, gekürzt oder fremder Schlüssel: abgelehnt', () {
      final p = _vectorSub.split('.');
      final other = _vectorOnce.split('.');
      expect(LicenseClaims.verify('${p[0]}.${other[1]}.${p[2]}', _vectorKey), isNull);
      expect(LicenseClaims.verify('KNX2.${p[1]}.${p[2]}', _vectorKey), isNull);
      expect(LicenseClaims.verify('${p[0]}.${p[1]}', _vectorKey), isNull);
      expect(LicenseClaims.verify('Unsinn', _vectorKey), isNull);
      expect(LicenseClaims.verify(_vectorSub, _testPublicKey), isNull);
    });

    test('Antwort der Kontofunktion gilt nicht als Lizenz, auch mit gleichem Schlüssel', () {
      final data = utf8.encode(jsonEncode({'sub': 'u', 'tier': 'pro', 'iat': 1, 'until': 4102444800}));
      expect(LicenseClaims.verify('KNX1.${_sign(Uint8List.fromList(data))}', _testPublicKey), isNull);
    });
  });

  group('Abgleich', () {
    final issued = DateTime(2026, 11, 2);
    final periodEnd = DateTime(2027, 11, 2);
    var now = issued;
    late Future<String> Function(String) server;
    var asked = 0;

    LicensePlanSource source() => LicensePlanSource(
      publicKey: _testPublicKey,
      clock: () => now,
      fetch: (l) {
        asked++;
        return server(l);
      },
    );
    Future<String> offline(String _) => Future.error(StateError('offline'));
    final mail = _token(id: 'sub_1', iat: issued, until: periodEnd);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = issued;
      asked = 0;
      server = offline;
    });

    test('Ohne Lizenz: Free, kein Kontakt zum Server', () async {
      expect(await source().current(), Tier.free);
      expect(asked, 0);
    });

    test('Falsche Eingabe: abgelehnt, nichts gespeichert', () async {
      await expectLater(source().redeem('KNX1.falsch.falsch'), throwsA(isA<LicenseRejected>()));
      expect(await source().current(), Tier.free);
    });

    test('Eingabe ohne Netz gilt, auch mit Umbrüchen aus der Mail', () async {
      final s = source();
      final wrapped = '  ${mail.substring(0, 40)}\n${mail.substring(40)}\n';
      expect(await s.redeem(wrapped), Tier.pro);
      expect(s.lastAnswerDefinite, isFalse);
    });

    test('Offline gilt das Abo bis zum Ablauf, danach Hinweis statt Pro', () async {
      await source().redeem(mail);
      now = periodEnd.subtract(const Duration(days: 1));
      expect(await source().current(), Tier.pro);
      now = periodEnd.add(const Duration(days: 1));
      final s = source();
      expect(await s.current(), Tier.free);
      expect(s.lapsed, Tier.pro);
      expect(s.lastAnswerDefinite, isFalse, reason: 'Sonst griffe nur die kurze Frist einer Erstattung');
    });

    test('Zurückgedrehte Uhr verlängert das Abo nicht', () async {
      await source().redeem(mail);
      now = periodEnd.add(const Duration(days: 1));
      await source().current();
      now = issued;
      expect(await source().current(), Tier.free);
    });

    test('Kleine Uhrkorrektur schadet nicht', () async {
      await source().redeem(mail);
      now = issued.add(const Duration(days: 1));
      await source().current();
      now = now.subtract(const Duration(minutes: 5));
      expect(await source().current(), Tier.pro);
    });

    test('Einmalkauf gilt offline dauerhaft, auch ohne Server', () async {
      await source().redeem(_token(id: 'txn_1', iat: issued, until: null, tier: 'plus', product: 'plus_lifetime'));
      now = DateTime(2060);
      final s = source();
      expect(await s.current(), Tier.plus);
    });

    test('Einmalkauf mit Frist: offline Ende, ein Abgleich macht ihn dauerhaft', () async {
      final end = issued.add(const Duration(days: 30));
      final first = _token(id: 'txn_1', iat: issued, until: end, tier: 'plus', product: 'plus_lifetime');
      await source().redeem(first);
      now = end.add(const Duration(days: 1));
      expect(await source().current(), Tier.free);
      server = (_) async => _token(id: 'txn_1', iat: now, until: null, tier: 'plus', product: 'plus_lifetime');
      expect(await source().restore(), Tier.plus);
      server = offline;
      now = DateTime(2060);
      expect(await source().current(), Tier.plus);
    });

    test('Verlängerung kommt mit dem Abgleich und ist eindeutig', () async {
      await source().redeem(mail);
      final later = periodEnd.add(const Duration(days: 365));
      now = periodEnd.add(const Duration(days: 2));
      server = (_) async => _token(id: 'sub_1', iat: now, until: later);
      final s = source();
      expect(await s.current(), Tier.pro);
      expect(s.lastAnswerDefinite, isTrue);
      server = offline;
      expect(await source().current(), Tier.pro);
    });

    test('Abgleich höchstens einmal am Tag, Eingabe und Wiederherstellen immer', () async {
      server = (_) async => _token(id: 'sub_1', iat: now, until: periodEnd);
      await source().redeem(mail);
      expect(asked, 1);
      now = issued.add(const Duration(hours: 23));
      await source().current();
      expect(asked, 1);
      await source().restore();
      expect(asked, 2);
      now = now.add(const Duration(hours: 25));
      await source().current();
      expect(asked, 3);
    });

    test('Gescheiterter Abgleich versucht es beim nächsten Start wieder', () async {
      await source().redeem(mail);
      expect(asked, 1);
      await source().current();
      expect(asked, 2);
    });

    test('Erstattet: signierte Free ist eindeutig und bleibt es ohne Netz', () async {
      final once = _token(id: 'txn_1', iat: issued, until: null, tier: 'plus', product: 'plus_lifetime');
      await source().redeem(once);
      now = issued.add(const Duration(days: 2));
      server = (_) async => _token(id: 'txn_1', iat: now, until: now, tier: 'free', product: 'plus_lifetime');
      final s = source();
      expect(await s.current(), Tier.free);
      expect(s.lastAnswerDefinite, isTrue);
      expect(s.lapsed, isNull);
      server = offline;
      final again = source();
      expect(await again.current(), Tier.free);
      expect(again.lastAnswerDefinite, isTrue);
    });

    test('Die alte Mail nach der Erstattung hebt die signierte Free nicht auf', () async {
      await source().redeem(mail);
      now = issued.add(const Duration(days: 2));
      server = (_) async => _token(id: 'sub_1', iat: now, until: now, tier: 'free');
      expect(await source().current(), Tier.free);
      server = offline;
      expect(await source().redeem(mail), Tier.free);
    });

    test('Server antwortet Unsinn oder eine andere Lizenz: Stand bleibt', () async {
      await source().redeem(mail);
      now = issued.add(const Duration(days: 2));
      for (final answer in ['Unsinn', _token(id: 'sub_2', iat: now, until: now, tier: 'free')]) {
        server = (_) async => answer;
        final s = source();
        expect(await s.current(), Tier.pro);
        expect(s.lastAnswerDefinite, isFalse);
      }
    });

    test('Überholte Antwort des Servers gewinnt nicht', () async {
      await source().redeem(mail);
      now = issued.add(const Duration(days: 2));
      server = (_) async =>
          _token(id: 'sub_1', iat: issued.subtract(const Duration(days: 9)), until: now, tier: 'free');
      expect(await source().current(), Tier.pro);
    });

    test('Neue Antwort heilt eine falsch vorgestellte Uhr', () async {
      now = DateTime(2031);
      server = (_) async => _token(id: 'sub_1', iat: issued, until: periodEnd);
      expect(await source().redeem(mail), Tier.pro);
      now = issued.add(const Duration(days: 1));
      server = offline;
      expect(await source().current(), Tier.pro);
    });

    test('Zweite Lizenz ersetzt die erste', () async {
      await source().redeem(_token(id: 'sub_1', iat: issued, until: periodEnd, tier: 'plus', product: 'plus_yearly'));
      expect(await source().redeem(_token(id: 'sub_2', iat: issued, until: periodEnd)), Tier.pro);
    });

    test('Ohne Serverschlüssel im Build verrät eine gespeicherte Lizenz nichts', () async {
      await source().redeem(mail);
      final s = LicensePlanSource(publicKey: _vectorKey, clock: () => now, fetch: offline);
      expect(await s.current(), Tier.free);
    });
  });

  group('Plan', () {
    final issued = DateTime(2026, 11, 2);
    var now = issued;
    final old = Plan.clock;
    tearDownAll(() => Plan.clock = old);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = issued;
      Plan.clock = () => now;
    });

    Future<Plan> loaded(Future<String> Function(String) server) async {
      final plan = Plan.instance;
      await plan.load(
        using: LicensePlanSource(publicKey: _testPublicKey, clock: () => now, fetch: server),
      );
      await plan.refreshing;
      return plan;
    }

    Future<String> offline(String _) => Future.error(StateError('offline'));

    test('Eingabe schaltet frei', () async {
      final plan = await loaded(offline);
      expect(plan.purchasable, isTrue);
      expect(plan.bought, Tier.free);
      await plan.redeem(_token(id: 'sub_1', iat: issued, until: DateTime(2027, 11, 2)));
      expect(plan.bought, Tier.pro);
    });

    test('Erstattung: wie im Store noch 3 Tage, dann Free', () async {
      final plan = await loaded(offline);
      await plan.redeem(_token(id: 'sub_1', iat: issued, until: DateTime(2027, 11, 2)));
      now = issued.add(const Duration(days: 2));
      Future<String> refunded(String _) async => _token(id: 'sub_1', iat: now, until: now, tier: 'free');
      await loaded(refunded);
      expect(plan.bought, Tier.pro);
      now = now.add(const Duration(days: 4));
      await loaded(refunded);
      expect(plan.bought, Tier.free);
    });

    test('Abo offline abgelaufen: noch 30 Tage ab der letzten Bestätigung', () async {
      final plan = await loaded(offline);
      final end = issued.add(const Duration(days: 30));
      await plan.redeem(_token(id: 'sub_1', iat: issued, until: end));
      now = end.subtract(const Duration(days: 1));
      await loaded(offline);
      now = end.add(const Duration(days: 10));
      await loaded(offline);
      expect(plan.bought, Tier.pro);
      now = end.add(const Duration(days: 40));
      await loaded(offline);
      expect(plan.bought, Tier.free);
    });
  });
}

/// Testschlüssel; der echte private liegt nur als Secret beim Server.
final _testKey = ECPrivateKey(
  BigInt.parse('c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721', radix: 16),
  ECDomainParameters('prime256v1'),
);
final _testPublicKey = base64.encode((_testKey.parameters!.G * _testKey.d)!.getEncoded(false));

String _sign(Uint8List data) {
  final signer = Signer('SHA-256/DET-ECDSA')..init(true, PrivateKeyParameter<ECPrivateKey>(_testKey));
  final sig = signer.generateSignature(data) as ECSignature;
  Uint8List bytes(BigInt v) {
    final hex = v.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList([for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);
  }

  String enc(List<int> b) => base64Url.encode(b).replaceAll('=', '');
  return '${enc(data)}.${enc([...bytes(sig.r), ...bytes(sig.s)])}';
}

String _token({
  required String id,
  required DateTime iat,
  required DateTime? until,
  String tier = 'pro',
  String product = 'pro_yearly',
}) {
  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
  final body = {
    'typ': 'knx-license',
    'lid': id,
    'product': product,
    'tier': tier,
    'iat': secs(iat),
    'until': until == null ? null : secs(until),
  };
  return 'KNX1.${_sign(Uint8List.fromList(utf8.encode(jsonEncode(body))))}';
}
