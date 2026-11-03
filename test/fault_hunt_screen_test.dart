import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/fault_hunt.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/fault_hunt_screen.dart';
import 'package:knx_monitor/ui/watch_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server ohne Jagd.
class _Client extends FaultHuntClient {
  @override
  Future<FaultHuntDef?> current() async => null;
}

void main() {
  testWidgets('Neuer Wächter steht sofort zur Auswahl, ohne Aktualisieren', (tester) async {
    final address = parseGroup('8/0/1')!;
    CatalogStore.instance.catalog = GroupCatalog({
      address: GroupInfo(address: address, name: 'Störung Heizung', dpt: const Dpt(1, 1)),
    });
    Addon.box = BoxLink(url: Uri.parse('http://127.0.0.1:1'), key: 'k');
    addTearDown(() {
      Addon.box = null;
      WatchRules.instance.value = const [];
      CatalogStore.instance.catalog = GroupCatalog.empty;
    });
    final client = _Client();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: FaultHuntScreen(client: client),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Lege zuerst einen an'), findsOneWidget);

    // Wie nach „Neuer Wächter“ im Wächter-Bildschirm.
    WatchRules.instance.value = [WatchRule(id: 'a', address: address)];
    await tester.pump();
    expect(find.textContaining('Lege zuerst einen an'), findsNothing);
    expect(find.text('Störung Heizung'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wächter-Dialog: Wertfeld erst mit Vergleich', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const WatchScreen(),
      ),
    );
    await tester.tap(find.byTooltip('Neuer Wächter'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    final before = tester.widgetList(fields).length;
    await tester.tap(find.text('beliebiger Wert'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('=').last);
    await tester.pumpAndSettle();
    expect(tester.widgetList(fields).length, before + 1, reason: 'Wertfeld erst mit Vergleich');
  });
}
