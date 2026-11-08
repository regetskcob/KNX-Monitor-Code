// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von Busclear (Konto,
// Betriebslösung, Bauherren-Paket oder Abgleich). Hier ist alles aus.

/// Abgleich zwischen den eigenen Geräten: im öffentlichen Quellstand nicht dabei.
class CloudSync {
  CloudSync._();

  static final instance = CloudSync._();

  bool get supported => false;

  Future<void> applyPending() async {}

  Future<void> start() async {}
}
