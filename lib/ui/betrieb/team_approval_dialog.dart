// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von Busclear (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

import 'package:flutter/widgets.dart';

import '../../model/betrieb/team_model.dart';

/// Ohne Team ist alles erlaubt.
Future<bool> ensureTeamRight(BuildContext context, TeamAction action) async => true;
