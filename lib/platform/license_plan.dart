import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../model/plan.dart';
import '../model/plan_source.dart';
import 'web_shop.dart';

/// Function that exchanges a license for the current state at Paddle.
const _refreshUrl = 'https://erruhlqtrnuxgguvbein.supabase.co/functions/v1/license-refresh';

/// Verified content of a license (`KNX1.<content>.<signature>`).
class LicenseClaims {
  const LicenseClaims({
    required this.id,
    required this.product,
    required this.tier,
    required this.issuedAt,
    required this.until,
  });

  /// Purchase at Paddle (`sub_…`, `txn_…`).
  final String id;
  final String product;
  final Tier tier;
  final DateTime issuedAt;

  /// Valid until then (at most 30 days from issue); `null` = permanent (one-time purchase).
  final DateTime? until;

  /// Verifies signature and content; `null` if something is wrong. A signed response of the account
  /// function does not pass here (`typ`, different key).
  static LicenseClaims? verify(String text, String publicKey) {
    final parts = text.split('.');
    if (parts.length != 3 || parts[0] != 'KNX1') return null;
    final data = verifiedBytes(parts[1], parts[2], publicKey);
    if (data == null) return null;
    try {
      final j = jsonDecode(utf8.decode(data)) as Map<String, Object?>;
      if (j['typ'] != 'knx-license') return null;
      final until = j['until'] as int?;
      return LicenseClaims(
        id: j['lid']! as String,
        product: j['product']! as String,
        tier: Tier.values.asNameMap()[j['tier']] ?? Tier.free,
        issuedAt: DateTime.fromMillisecondsSinceEpoch((j['iat']! as int) * 1000),
        until: until == null ? null : DateTime.fromMillisecondsSinceEpoch(until * 1000),
      );
    } on Object {
      return null;
    }
  }
}

/// Windows without an account: purchase in the browser via Paddle; the signed license arrives by
/// e-mail and is entered here. It works offline; with a network the app fetches the state once a
/// day.
class LicensePlanSource extends PlanSource {
  LicensePlanSource({required this.publicKey, DateTime Function()? clock, Future<String> Function(String)? fetch})
    : _clock = clock ?? DateTime.now,
      _fetch = fetch ?? _fetchFromServer;

  final String publicKey;
  final DateTime Function() _clock;
  final Future<String> Function(String license) _fetch;

  static const _licenseKey = 'license_text';

  /// Latest time seen (milliseconds), against a clock that was turned back.
  static const _seenKey = 'license_seen';

  /// Last successful sync (milliseconds).
  static const _checkedKey = 'license_checked';

  /// Small clock corrections are normal and do not count as turning back.
  static const _clockTolerance = Duration(hours: 1);

  /// How often the app asks for the state at startup.
  static const checkEvery = Duration(hours: 24);

  static Future<String> _fetchFromServer(String license) async {
    final res = await http
        .post(
          Uri.parse(_refreshUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'license': license}),
        )
        .timeout(webTimeout);
    if (res.statusCode != 200) throw http.ClientException('Lizenz: ${res.statusCode}');
    return (jsonDecode(res.body) as Map)['license'] as String;
  }

  @override
  bool get purchasable => true;

  @override
  Tier? get lapsed => _lapsed;
  Tier? _lapsed;

  @override
  bool get lastAnswerDefinite => _definite;
  bool _definite = false;

  @override
  Future<Tier> current() => _current(force: false);

  /// A server response always counts. Without a response the last license counts until it expires;
  /// after that [Plan.paidGrace] applies. A one-time purchase becomes permanent after the first
  /// sync beyond the refund period (`until` missing), even without a server. A signed Free is just
  /// as final.
  Future<Tier> _current({required bool force}) async {
    _lapsed = null;
    _definite = false;
    final prefs = await SharedPreferences.getInstance();
    final now = _clock();
    final seen = prefs.getInt(_seenKey) ?? 0;
    if (now.millisecondsSinceEpoch > seen) await prefs.setInt(_seenKey, now.millisecondsSinceEpoch);
    final stored = prefs.getString(_licenseKey);
    final saved = stored == null ? null : LicenseClaims.verify(stored, publicKey);
    if (stored == null || saved == null) return Tier.free;
    var claims = saved;

    final checked = prefs.getInt(_checkedKey);
    final age = checked == null ? null : now.difference(DateTime.fromMillisecondsSinceEpoch(checked));
    if (force || age == null || age.isNegative || age >= checkEvery) {
      try {
        final text = await _fetch(stored).timeout(webTimeout);
        final fresh = LicenseClaims.verify(text, publicKey);
        if (fresh != null && fresh.id == claims.id && !fresh.issuedAt.isBefore(claims.issuedAt)) {
          await prefs.setString(_licenseKey, text);
          // The response just came from the server: its `iat` also heals a clock that is running
          // fast.
          await prefs.setInt(_seenKey, fresh.issuedAt.millisecondsSinceEpoch);
          await prefs.setInt(_checkedKey, now.millisecondsSinceEpoch);
          claims = fresh;
          _definite = true;
          if (fresh.tier == Tier.free || fresh.until == null) return fresh.tier;
          return fresh.issuedAt.isBefore(fresh.until!) ? fresh.tier : Tier.free;
        }
      } on Object catch (e) {
        debugPrint('Lizenz: nicht abgeglichen: $e');
      }
    }
    if (claims.tier == Tier.free) {
      _definite = true;
      return Tier.free;
    }
    final until = claims.until;
    if (until == null) return claims.tier;
    final highest = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_seenKey) ?? now.millisecondsSinceEpoch);
    final wentBack = now.isBefore(highest.subtract(_clockTolerance));
    if (!wentBack && highest.isBefore(until)) return claims.tier;
    _lapsed = claims.tier;
    return Tier.free;
  }

  /// Stores a license and syncs it immediately. Line breaks from the e-mail do not matter. An older
  /// state of the same license (the e-mail after a sync) does not overwrite the newer one.
  @override
  Future<Tier> redeem(String code) async {
    final text = code.replaceAll(RegExp(r'\s'), '');
    final claims = LicenseClaims.verify(text, publicKey);
    if (claims == null) throw const LicenseRejected();
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_licenseKey);
    final old = stored == null ? null : LicenseClaims.verify(stored, publicKey);
    if (old == null || old.id != claims.id || !claims.issuedAt.isBefore(old.issuedAt)) {
      await prefs.setString(_licenseKey, text);
    }
    return _current(force: true);
  }

  /// Offers as for the account, from the purchase page.
  @override
  Future<List<PlanOffer>> offers() => webOffers();

  /// Opens the purchase page in the browser, with only the selected product.
  @override
  Future<Tier> buy(PlanOffer offer) async {
    final params = Uri(queryParameters: {'product': offer.id}).query;
    await launchUrl(Uri.parse(webShop).replace(fragment: params), mode: LaunchMode.externalApplication);
    throw const PlanPending();
  }

  @override
  Future<Tier> restore() => _current(force: true);

  /// Every Paddle buyer lands here; the purchase e-mail also has a direct link.
  @override
  Future<Uri?> manageUrl() async => Uri.parse('https://paddle.net');
}
