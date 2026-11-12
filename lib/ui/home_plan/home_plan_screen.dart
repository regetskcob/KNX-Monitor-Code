// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von Busclear (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

import 'package:flutter/widgets.dart';

import '../../knx/knx_tunnel.dart';
import '../../model/telegram_log.dart';

/// Ohne Bauherren-Paket entfällt der Einstieg auf dem Startbildschirm.
const homePlanAvailable = false;

class HomePlanScreen extends StatelessWidget {
  const HomePlanScreen({super.key, this.log, this.tunnel, this.initialTab = 0});

  final TelegramLog? log;
  final KnxTunnel? tunnel;
  final int initialTab;

  static const afterMoveInTab = 6;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
