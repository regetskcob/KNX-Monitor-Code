// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von KNX Monitor (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

/// Hausplan des Bauherren-Pakets: Dateinamen, damit Löschen und Sicherung sie
/// kennen, falls sie aus einer anderen Fassung stammen.
class HomePlanStore {
  HomePlanStore._();

  static final instance = HomePlanStore._();

  static const path = 'home_plan.json';
  static const imageDir = 'home_plan_images';

  Future<void> load() async {}
}
