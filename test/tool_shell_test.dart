import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/more_menu.dart';
import 'package:knx_monitor/ui/tool_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late BuildContext home;

  MoreMenu menu() => MoreMenu(
    tools: [
      for (final name in ['Gesundheit', 'Topologie'])
        ToolEntry(
          icon: Icons.circle,
          title: name,
          subtitle: '',
          group: ToolGroup.check,
          open: (_) => pushTool<void>(home, (_) => Scaffold(appBar: AppBar(title: Text('Seite $name')))),
        ),
    ],
  );

  Future<void> start(WidgetTester tester, Size size) async {
    SharedPreferences.setMockInitialValues({});
    await ToolShell.instance.load();
    ToolShell.instance.menu = menu;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) {
            home = context;
            return const Scaffold(body: Text('Monitor'));
          },
        ),
      ),
    );
  }

  tearDown(() => ToolShell.instance.menu = null);

  testWidgets('Werkzeugseite mit Leiste; Wechsel ersetzt, Zurück führt zum Monitor', (tester) async {
    await start(tester, const Size(1400, 900));
    menu().tools.first.open(home);
    await tester.pumpAndSettle();
    expect(find.text('Seite Gesundheit'), findsOneWidget);
    expect(find.byType(MoreSidebar), findsOneWidget);
    // Leiste auf eigenem Material-Grund (sonst gelbe Doppellinie unter Text); HorizontSidebar bringt ihn mit.
    expect(find.descendant(of: find.byType(HorizontSidebar), matching: find.byType(Material)), findsWidgets);

    // Wechsel in der Leiste ersetzt die Gesundheit; die Leiste bleibt.
    await tester.tap(find.text('Topologie'));
    await tester.pumpAndSettle();
    expect(find.text('Seite Topologie'), findsOneWidget);
    expect(find.text('Seite Gesundheit'), findsNothing);
    expect(find.byType(MoreSidebar), findsOneWidget);

    Navigator.of(tester.element(find.text('Seite Topologie'))).pop();
    await tester.pumpAndSettle();
    expect(find.text('Monitor'), findsOneWidget);
  });

  testWidgets('Die Breite entscheidet: schmal ohne Leiste', (tester) async {
    await start(tester, const Size(700, 900));
    menu().tools.first.open(home);
    await tester.pumpAndSettle();
    expect(find.byType(MoreSidebar), findsNothing);
  });
}
