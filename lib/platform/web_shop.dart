import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../l10n/locale_controller.dart';
import '../model/plan.dart';
import '../model/plan_source.dart';

/// Purchase page (Paddle) and its offers on the website (per language).
const _site = 'https://busclear.de/';
String get webShop => LocaleController.instance.locale.languageCode == 'de' ? '${_site}kaufen/' : '${_site}en/buy/';
bool get _german => LocaleController.instance.locale.languageCode == 'de';

/// On a construction site the connection often hangs instead of failing.
const webTimeout = Duration(seconds: 10);

/// Verifies a server signature (ECDSA P-256 / SHA-256, r‖s, base64url) and returns the content;
/// `null` if something is wrong. [publicKey]: SPKI, base64.
Uint8List? verifiedBytes(String payload, String signature, String publicKey) {
  try {
    final data = base64Url.decode(base64Url.normalize(payload));
    final sig = base64Url.decode(base64Url.normalize(signature));
    if (sig.length != 64) return null;
    final spki = base64.decode(publicKey);
    final domain = ECDomainParameters('prime256v1');
    final key = ECPublicKey(domain.curve.decodePoint(spki.sublist(spki.length - 65)), domain);
    final signer = Signer('SHA-256/ECDSA')..init(false, PublicKeyParameter<ECPublicKey>(key));
    BigInt big(Uint8List b) => b.fold(BigInt.zero, (v, e) => (v << 8) | BigInt.from(e));
    return signer.verifySignature(data, ECSignature(big(sig.sublist(0, 32)), big(sig.sublist(32)))) ? data : null;
  } on Object {
    return null;
  }
}

/// Offers from the purchase page (`angebote.json`), prices as in the store. If the page does not
/// exist yet (404 until sales start), that is not an outage: empty list, and the paywall says "not
/// available yet". Other errors remain errors ("unreachable").
Future<List<PlanOffer>> webOffers() async {
  final res = await http.get(Uri.parse('${_site}kaufen/angebote.json')).timeout(webTimeout);
  if (res.statusCode == 404) return const [];
  if (res.statusCode != 200) throw http.ClientException('Angebote: ${res.statusCode}');
  return [
    for (final o in jsonDecode(res.body) as List)
      PlanOffer(
        id: o['id'] as String,
        tier: (o['id'] as String).startsWith('pro') ? Tier.pro : Tier.plus,
        price: (_german ? o['price'] : o['priceEn'] ?? o['price']) as String,
        period: OfferPeriod.values.asNameMap()[o['period']] ?? OfferPeriod.yearly,
        trialDays: o['trialDays'] as int? ?? 0,
      ),
  ];
}
