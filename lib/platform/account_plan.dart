// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von Busclear (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

import '../model/plan.dart';
import '../model/plan_source.dart';

/// Freischaltung über das Konto; wird ohne Konto nie gewählt.
class AccountPlanSource extends PlanSource {
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
