// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von KNX Monitor (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

import 'package:flutter/foundation.dart';

import '../acceptance.dart';

/// Pro Team: im öffentlichen Quellstand nicht dabei.
class Team extends ChangeNotifier {
  Team._();

  static final instance = Team._();

  List<String> get privateNames => const [];

  Future<void> load() async {}

  Acceptance stampChecked(Acceptance a) => a;

  Future<void> submitReview(Acceptance a) async {}
}
