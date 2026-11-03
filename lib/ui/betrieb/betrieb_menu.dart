// Platzhalter im öffentlichen Quellstand (tool/public_source/private.txt): Das
// Original gehört zu einem kommerziellen Teil von KNX Monitor (Konto,
// Betriebslösung oder Bauherren-Paket). Hier ist alles aus.

import 'package:flutter/widgets.dart';

import '../../knx/knx_tunnel.dart';
import '../../knx/telegram.dart';
import '../more_menu.dart';

List<MenuToggle> betriebToggles() => const [];

List<ToolEntry> betriebTools(BuildContext context, {KnxTunnel? tunnel, List<Telegram> history = const []}) => const [];
