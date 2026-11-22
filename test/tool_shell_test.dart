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

  group('Sammelseiten', () {
    MoreMenu hubMenu() => MoreMenu(
      tools: [
        for (final (name, hub) in [
          ('Gesundheit', null),
          ('Räume', ToolHub.checks),
          ('Sperren', ToolHub.checks),
          ('Anlernen', ToolHub.setup),
        ])
          ToolEntry(
            icon: Icons.circle,
            title: name,
            subtitle: 'Hinweis $name',
            group: ToolGroup.check,
            hub: hub,
            open: (_) => pushTool<void>(home, (_) => Scaffold(appBar: AppBar(title: Text('Seite $name')))),
          ),
      ],
    );

    testWidgets('ab zwei Einträgen eine Zeile im Menü, ein einzelner bleibt stehen', (tester) async {
      await start(tester, const Size(1400, 900));
      final titles = [for (final t in hubMenu().menuTools(home)) t.title];
      expect(titles, containsAll(['Gesundheit', 'Prüfungen', 'Anlernen']));
      expect(titles, isNot(contains('Räume')));
      expect(titles, isNot(contains('Einrichtung')));
    });

    testWidgets('Seite listet ihre Werkzeuge; eins öffnet darüber, Zurück führt zur Seite', (tester) async {
      await start(tester, const Size(1400, 900));
      ToolShell.instance.menu = hubMenu;
      hubMenu().menuTools(home).firstWhere((t) => t.title == 'Prüfungen').open(home);
      await tester.pumpAndSettle();
      expect(find.text('Hinweis Räume'), findsOneWidget);
      expect(find.text('Hinweis Sperren'), findsOneWidget);

      await tester.tap(find.text('Hinweis Räume'));
      await tester.pumpAndSettle();
      expect(find.text('Seite Räume'), findsOneWidget);

      Navigator.of(home).pop();
      await tester.pumpAndSettle();
      expect(find.text('Hinweis Sperren'), findsOneWidget);

      // A tool from the bar replaces the hub: "Back" leads to the monitor again.
      await tester.tap(find.text('Gesundheit'));
      await tester.pumpAndSettle();
      expect(find.text('Seite Gesundheit'), findsOneWidget);
      Navigator.of(home).pop();
      await tester.pumpAndSettle();
      expect(find.text('Monitor'), findsOneWidget);
      expect(find.text('Hinweis Sperren'), findsNothing);
    });
  });
}
