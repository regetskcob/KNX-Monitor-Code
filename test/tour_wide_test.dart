import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/common.dart';
import 'package:knx_monitor/ui/communication_map_screen.dart';
import 'package:knx_monitor/ui/topology_screen.dart';

/// What the tour (`integration_test/tour_test.dart`) taps on a Mac (1512 × 982) in the demo house:
/// the topology shows the devices in its tree without a fold and opens one beside the lines, the
/// map starts as a graph whose device nodes open their connections. Both by design; the tour looks
/// for these when the phone's fold and arrows are missing.
void main() {
  TelegramLog demoLog() {
    final log = TelegramLog();
    for (final g in demoCatalog().groups.values.take(60)) {
      log.add(
        Telegram(
          time: DateTime(2026),
          source: g.links.where((l) => l.sends).firstOrNull?.device ?? 0x1101,
          destination: g.address,
          type: TelegramType.write,
          data: Uint8List.fromList([1]),
          isSmall: true,
        ),
      );
    }
    return log;
  }

  Widget app(Widget home) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Set<String> texts() => find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().toSet();

  setUp(() => CatalogStore.instance.catalog = demoCatalog());
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  testWidgets('topology at Mac size: devices in the tree, no fold; a device opens beside the lines', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(TopologyScreen(log: demoLog(), onFilter: (_) {})));
    await tester.pump(const Duration(seconds: 1));
    expect(find.descendant(of: find.byType(SectionTitle), matching: find.textContaining('Geräte')), findsNothing);
    final device = find.textContaining('1.1.1').hitTestable();
    expect(device, findsWidgets);
    await tester.tap(device.first);
    await tester.pumpAndSettle();
    expect(find.text('Kommunikationskarte'), findsOneWidget, reason: 'the device details opened');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('map at Mac size: a graph without arrows; a device node opens its connections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1512, 982));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(CommunicationMapScreen(log: demoLog())));
    await tester.pump(const Duration(seconds: 1));
    final map = find.byType(CommunicationMapScreen);
    expect(find.descendant(of: map, matching: find.byIcon(AppIcons.next)), findsNothing);
    final node = find.descendant(of: map, matching: find.textContaining(RegExp(r'^\d+\.\d+\.\d+$'))).hitTestable();
    expect(node, findsWidgets);
    final before = texts();
    await tester.tap(node.first);
    await tester.pumpAndSettle();
    expect(texts().difference(before), contains('Verbindungen'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
