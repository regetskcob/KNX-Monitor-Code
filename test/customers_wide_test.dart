import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/customers_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Customer files on wide layouts: the list on the left, the chosen file on the right. On the
// phone nothing changes: one column, the file opens as a page.

Future<void> _loadFonts() async {
  const fonts = {
    'Literata': ['Literata-Light.ttf', 'Literata-SemiBold.ttf'],
    'MonaSans': ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf'],
    'MonaspaceArgon': ['MonaspaceArgon-Regular.otf', 'MonaspaceArgon-SemiBold.otf'],
    'MaterialSymbolsSharp': ['MaterialSymbolsSharp-300.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader('packages/horizont/${entry.key}');
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('packages/horizont/fonts/$file'));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget app(Widget home, {double scale = 1}) => MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('de'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  late Installation first;
  late Installation second;

  /// Two installations with a file; [first] is the active one.
  Future<void> prepare(WidgetTester tester, Size size, {bool fonts = false}) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.runAsync(() async {
      if (fonts) await _loadFonts();
      final dir = await Directory.systemTemp.createTemp('customers_wide');
      addTearDown(() => dir.delete(recursive: true));
      AppStorage.instance = IoStorage(dir);
      final installs = InstallationStore.instance..debugReset();
      final store = CustomerStore.instance..debugReset();
      await installs.load();
      first = installs.active;
      second = await installs.create('Praxis Beispiel');
      await store.saveRecord(
        first.id,
        const CustomerRecord(customer: 'Familie Muster', site: 'Musterweg 1\n12345 Ort', phone: '0123'),
      );
      await store.saveRecord(
        second.id,
        CustomerRecord(
          customer: 'Zahnarztpraxis Dr. Beispiel',
          email: 'praxis@example.com',
          maintenanceMonths: 1,
          maintenanceSince: DateTime(2020),
        ),
      );
      await store.saveVisit(
        second.id,
        Visit(id: 'v1', time: DateTime(2026, 10, 2), kind: VisitKind.manual, text: 'Präsenzmelder eingestellt'),
      );
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Finder row(Installation i) => find.byKey(ValueKey('customer-${i.id}'));
  bool selected(WidgetTester tester, Installation i) => tester
      .widget<HorizontSelectable>(find.descendant(of: row(i), matching: find.byType(HorizontSelectable)))
      .selected;

  testWidgets('breit: Liste links, gewählte Akte rechts, ohne Seitenwechsel', (tester) async {
    await prepare(tester, const Size(1194, 834));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    // Die aktive Anlage ist gewählt: rechts steht nie nichts.
    expect(find.byType(CustomerDetailView), findsOneWidget);
    expect(find.byType(CustomerDetailScreen), findsNothing);
    expect(find.text('0123'), findsOneWidget);
    expect(selected(tester, first), isTrue);
    expect(selected(tester, second), isFalse);
    // Liste links von der Akte.
    expect(tester.getTopRight(row(second)).dx, lessThan(tester.getTopLeft(find.byType(CustomerDetailView)).dx));

    await tester.tap(row(second));
    await tester.pump();
    expect(find.text('praxis@example.com'), findsOneWidget);
    expect(find.text('0123'), findsNothing);
    expect(find.textContaining('Präsenzmelder eingestellt'), findsOneWidget);
    expect(selected(tester, second), isTrue);
    expect(find.byType(BackButton), findsNothing, reason: 'keine neue Seite');
    // Das Menü der Akte sitzt in der rechten Spalte.
    await tester.tap(
      find.descendant(of: find.byType(CustomerDetailView), matching: find.byType(PopupMenuButton<VoidCallback>)),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<VoidCallback>, 'Akte als PDF'), findsOneWidget);
    expect(find.text('Akte exportieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breit: Suche, die die gewählte Akte ausblendet, zeigt die erste verbleibende', (tester) async {
    await prepare(tester, const Size(1194, 834));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Zahnarzt');
    await tester.pump();
    expect(row(first), findsNothing);
    expect(find.text('praxis@example.com'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'gibtsnicht');
    await tester.pump();
    expect(find.byType(CustomerDetailView), findsNothing);
    expect(find.text('Wähle links eine Anlage.'), findsOneWidget);
  });

  testWidgets('breit: Tastatur wählt, Screenreader hört „ausgewählt“', (tester) async {
    final semantics = tester.ensureSemantics();
    await prepare(tester, const Size(1194, 834));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    expect(tester.getSemantics(row(first)), isSemantics(isButton: true, isSelected: true, hasSelectedState: true));
    expect(tester.getSemantics(row(second)), isSemantics(isButton: true, isSelected: false, hasSelectedState: true));
    expect(find.bySemanticsLabel('Anlagen'), findsOneWidget);

    // Fokus auf die zweite Zeile, Enter wählt sie.
    final focus = Focus.of(tester.element(find.descendant(of: row(second), matching: find.byType(Row)).first));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('praxis@example.com'), findsOneWidget);
    expect(tester.getSemantics(row(second)), isSemantics(isButton: true, isSelected: true, hasSelectedState: true));
    expect(tester.getSemantics(row(first)), isSemantics(isButton: true, isSelected: false, hasSelectedState: true));
    semantics.dispose();
  });

  testWidgets('breit: Zeilen sind mindestens 44 pt hoch', (tester) async {
    await prepare(tester, const Size(1194, 834));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    for (final i in [first, second]) {
      expect(tester.getSize(row(i)).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('Telefon: eine Spalte, die Akte öffnet als Seite', (tester) async {
    await prepare(tester, const Size(375, 812));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    expect(find.byType(CustomerDetailView), findsNothing);
    expect(find.byType(HorizontSelectable), findsNothing);
    expect(find.text('Wartung fällig'), findsOneWidget);
    await tester.tap(find.text('Zahnarztpraxis Dr. Beispiel'));
    await tester.pumpAndSettle();
    expect(find.byType(CustomerDetailScreen), findsOneWidget);
    expect(find.text('praxis@example.com'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schmales Fenster knapp unter der Grenze bleibt einspaltig', (tester) async {
    await prepare(tester, const Size(839, 700));
    await tester.pumpWidget(app(const CustomersScreen()));
    await tester.pump();
    expect(find.byType(CustomerDetailView), findsNothing);
  });

  testWidgets('375 pt breit, Textgröße 2.0: Liste und Akte ohne Überlauf', (tester) async {
    await prepare(tester, const Size(375, 667), fonts: true);
    await tester.pumpWidget(app(const CustomersScreen(), scale: 2));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Zahnarztpraxis Dr. Beispiel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('breit mit Textgröße 2.0 (840 pt): beide Spalten ohne Überlauf', (tester) async {
    await prepare(tester, const Size(840, 700), fonts: true);
    await tester.pumpWidget(app(const CustomersScreen(), scale: 2));
    await tester.pump();
    expect(find.byType(CustomerDetailView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(row(second));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('Akte bearbeiten', () {
    testWidgets('1194 pt: Kunde und Baustelle links, Wartung und Notizen rechts daneben', (tester) async {
      await prepare(tester, const Size(1194, 834));
      await tester.pumpWidget(app(CustomerEditScreen(installationId: first.id)));
      await tester.pump();
      final customer = tester.getTopLeft(find.text('Kunde und Baustelle'));
      final maintenance = tester.getTopLeft(find.text('Wartung und Notizen'));
      expect(customer.dx, lessThan(100));
      expect(maintenance.dx, greaterThan(597));
      expect(maintenance.dy, customer.dy);
      expect(maintenance.dy, lessThan(200));
      expect(tester.getTopLeft(find.text('Notizen')).dx, greaterThan(597));
      // Keyboard order: the left column first; the notes come last.
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, 'Familie Muster');
      expect(tester.takeException(), isNull);
    });

    testWidgets('speichert alle Felder; die Notizen tragen ein sichtbares Etikett', (tester) async {
      await prepare(tester, const Size(1194, 834));
      await tester.pumpWidget(app(CustomerEditScreen(installationId: first.id)));
      await tester.pump();
      expect(find.text('Notizen'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Verteiler im Keller');
      await tester.enterText(find.byType(TextField).at(6), '12');
      await tester.runAsync(() async {
        await tester.tap(find.text('Speichern'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      final record = CustomerStore.instance.record(first.id);
      expect(record.notes, 'Verteiler im Keller');
      expect(record.maintenanceMonths, 12);
      expect(record.customer, 'Familie Muster');
    });

    testWidgets('Telefon: eine Spalte', (tester) async {
      await prepare(tester, const Size(375, 2000));
      await tester.pumpWidget(app(CustomerEditScreen(installationId: first.id)));
      await tester.pump();
      final customer = tester.getTopLeft(find.text('Kunde und Baustelle'));
      final maintenance = tester.getTopLeft(find.text('Wartung und Notizen'));
      expect(maintenance.dx, customer.dx);
      expect(maintenance.dy, greaterThan(customer.dy));
    });

    testWidgets('375 pt breit, Textgröße 2.0: kein Überlauf', (tester) async {
      await prepare(tester, const Size(375, 667), fonts: true);
      await tester.pumpWidget(app(CustomerEditScreen(installationId: first.id), scale: 2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.textContaining('Kundendaten bleiben auf diesem Gerät'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
