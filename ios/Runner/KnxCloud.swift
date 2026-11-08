// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von Busclear (Konto,
// Betriebslösung, Bauherren-Paket oder Abgleich). Hier ist alles aus.

import Foundation

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// Abgleich über iCloud: im öffentlichen Quellstand nicht dabei. Der Kanal
/// „knx/cloud“ bleibt unbeantwortet; die Dart-Seite ist ebenfalls aus.
final class KnxCloud {
  static func register(messenger: FlutterBinaryMessenger) {}
}
