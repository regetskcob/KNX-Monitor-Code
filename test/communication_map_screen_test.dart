import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/ui/communication_map_screen.dart';

void main() {
  testWidgets('Werkzeug startet mit der Übersicht; Zurück führt zur Übersicht', (tester) async {
    final wind = parseGroup('8/1/1')!;
    CatalogStore.instance.catalog = GroupCatalog({
      wind: GroupInfo(address: wind, name: 'Windgeschwindigkeit'),
      parseGroup('1/1/0')!: GroupInfo(address: parseGroup('1/1/0')!, name: 'Licht Flur'),
    });
    addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
    final log = TelegramLog()
      ..add(
        Telegram(
          time: DateTime(2026),
          source: parseIndividual('1.2.20')!,
          destination: wind,
          type: TelegramType.write,
          data: Uint8List.fromList([0, 0]),
          isSmall: false,
        ),
      );

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CommunicationMapScreen(log: log))),
            child: const Text('öffnen'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('öffnen'));
    await tester.pumpAndSettle();
    // Ab 600 startet die Gerätekarte; die Adressen liegen im Umschalter.
    await tester.tap(find.textContaining('Gruppenadressen ·'));
    await tester.pumpAndSettle();

    // Übersicht: nichts vorausgewählt, beide Listen, aktivste zuerst.
    expect(find.text('Gruppenadressen'), findsOneWidget);
    expect(find.text('2'), findsWidgets); // Zähler im Abschnittstitel
    expect(find.textContaining('Licht Flur'), findsOneWidget);
    expect(find.text('1×'), findsWidgets);

    await tester.tap(find.textContaining('Windgeschwindigkeit').first);
    await tester.pumpAndSettle();
    expect(find.text('Übersicht'), findsOneWidget); // Chip zurück zur Übersicht

    // Zurück wie die Systemgeste (respektiert PopScope).
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pumpAndSettle();
    expect(find.text('Gruppenadressen'), findsOneWidget); // wieder Übersicht, nicht geschlossen
  });
}
