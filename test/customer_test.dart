import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/customers_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Visit _visit(DateTime t, VisitKind k, {String id = ''}) =>
    Visit(id: id.isEmpty ? '${t.millisecondsSinceEpoch}' : id, time: t, kind: k);

CustomerEntry _entry(String name, {CustomerRecord record = CustomerRecord.empty, List<Visit> visits = const []}) =>
    CustomerEntry(
      installation: Installation(id: name, name: name, created: DateTime(2026)),
      record: record,
      visits: visits,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wartung', () {
    test('ohne Intervall nie fällig', () {
      expect(const CustomerRecord(customer: 'x').nextMaintenance([]), isNull);
      expect(const CustomerRecord(maintenanceMonths: 0).nextMaintenance([]), isNull);
    });

    test('ab Beginn, dann ab dem letzten wartungsrelevanten Besuch', () {
      final r = CustomerRecord(maintenanceMonths: 12, maintenanceSince: DateTime(2025, 3, 1));
      expect(r.nextMaintenance([]), DateTime(2026, 3, 1));
      // Eine reine Verbindung zählt nicht.
      expect(r.nextMaintenance([_visit(DateTime(2025, 9, 1), VisitKind.connection)]), DateTime(2026, 3, 1));
      expect(r.nextMaintenance([_visit(DateTime(2025, 9, 1), VisitKind.serviceReport)]), DateTime(2026, 9, 1));
    });

    test('Monatsende und Jahreswechsel', () {
      final r = CustomerRecord(maintenanceMonths: 1, maintenanceSince: DateTime(2027, 1, 31));
      expect(r.nextMaintenance([]), DateTime(2027, 2, 28));
      final y = CustomerRecord(maintenanceMonths: 3, maintenanceSince: DateTime(2026, 11, 15));
      expect(y.nextMaintenance([]), DateTime(2027, 2, 15));
    });

    test('fällig am Tag selbst', () {
      final e = _entry('a', record: CustomerRecord(maintenanceMonths: 1, maintenanceSince: DateTime(2026, 9, 30)));
      expect(e.maintenanceDue(DateTime(2026, 10, 29)), isFalse);
      expect(e.maintenanceDue(DateTime(2026, 10, 30)), isTrue);
    });
  });

  group('Liste', () {
    final due = _entry(
      'Zebra',
      record: CustomerRecord(maintenanceMonths: 1, maintenanceSince: DateTime(2020), site: 'Kirchweg 2\nKalkar'),
    );
    final visited = _entry('Bär', visits: [_visit(DateTime(2026, 10, 1), VisitKind.manual)]);
    final plain = _entry(
      'adler',
      record: const CustomerRecord(customer: 'Familie Adler', phone: '0123'),
    );

    test('Suche über Felder, mehrere Wörter, ohne Groß-/Kleinschreibung', () {
      expect(filterCustomers([due, visited, plain], query: 'KALKAR').single, due);
      expect(filterCustomers([due, visited, plain], query: 'familie adler').single, plain);
      expect(filterCustomers([due, visited, plain], query: '0123').single, plain);
      expect(filterCustomers([due, visited, plain], query: 'xyz'), isEmpty);
      expect(filterCustomers([due, visited, plain]).length, 3);
    });

    test('Sortierung: Name, letzter Besuch, Wartung', () {
      final names = filterCustomers([due, visited, plain]).map((e) => e.title);
      expect(names, ['Bär', 'Familie Adler', 'Zebra']);
      expect(filterCustomers([due, plain, visited], sort: CustomerSort.lastVisit).first, visited);
      expect(filterCustomers([plain, visited, due], sort: CustomerSort.maintenance).first, due);
    });
  });

  test('Links zum Anrufen, Mailen, Karte; nichts ohne Angabe', () {
    expect(phoneUri('+49 (0) 123-456').toString(), 'tel:+490123456');
    expect(phoneUri('keine'), isNull);
    expect(mailUri(' a@b.de ').toString(), 'mailto:a@b.de');
    expect(mailUri('keine Adresse'), isNull);
    expect(mapsUri('', TargetPlatform.iOS), isNull);
    expect(mapsUri('Weg 1\nKalkar', TargetPlatform.iOS)!.host, 'maps.apple.com');
    expect(mapsUri('Weg 1\nKalkar', TargetPlatform.android)!.scheme, 'geo');
    expect(mapsUri('Weg 1', TargetPlatform.linux)!.host, 'www.openstreetmap.org');
    expect(mapsUri('Weg 1', TargetPlatform.iOS, web: true)!.host, 'www.openstreetmap.org');
  });

  group('Ablage', () {
    late Directory dir;
    final installs = InstallationStore.instance;
    final store = CustomerStore.instance;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      dir = await Directory.systemTemp.createTemp('customer');
      AppStorage.instance = IoStorage(dir);
      installs.debugReset();
      store.debugReset();
      await installs.load();
    });

    tearDown(() async {
      DemoTunnel.active = false;
      await dir.delete(recursive: true);
    });

    test('Migration: alte Installation ohne Dateien lädt leer; alte Indexdatei bleibt unverändert', () async {
      final index = await AppStorage.instance.read('installations.json');
      await store.load();
      expect(store.record(installs.active.id).isEmpty, isTrue);
      expect(store.visits(installs.active.id), isEmpty);
      expect(await AppStorage.instance.read('installations.json'), index);
      // Die Datei einer älteren Version kennt die Kundenfelder nicht; sie gehen darüber nicht verloren.
      await store.saveRecord(installs.active.id, const CustomerRecord(customer: 'K'));
      final back = jsonDecode((await AppStorage.instance.read('installations.json'))!) as Map<String, Object?>;
      expect((back['list']! as List).single as Map, isNot(contains('customer')));
    });

    test('speichern und neu laden', () async {
      final id = installs.active.id;
      await store.saveRecord(
        id,
        CustomerRecord(customer: 'Familie Test', site: 'Weg 1', maintenanceMonths: 6, maintenanceSince: DateTime(2026)),
      );
      await store.saveVisit(id, _visit(DateTime(2026, 5), VisitKind.manual, id: 'a'));
      await store.saveVisit(id, _visit(DateTime(2026, 6), VisitKind.acceptance, id: 'b'));
      store.debugReset();
      await store.load();
      expect(store.record(id).customer, 'Familie Test');
      expect(store.record(id).maintenanceMonths, 6);
      expect(store.visits(id).map((v) => v.id), ['b', 'a']);
      await store.deleteVisit(id, 'b');
      expect(store.visits(id).single.id, 'a');
    });

    test('kaputte Dateien verhindern nichts und werden beiseitegelegt', () async {
      final id = installs.active.id;
      final s = ScopedStorage(AppStorage.instance, 'installations/$id/');
      await s.write(CustomerStore.customerFile, '{kaputt');
      await s.write(CustomerStore.visitsFile, '[{"t": "falsch"}, {"t": 1000, "k": "zukunft"}]');
      await store.load();
      expect(store.record(id).isEmpty, isTrue);
      // Einzelner kaputter Eintrag fällt weg, unbekannte Art bleibt lesbar.
      expect(store.visits(id).single.kind, VisitKind.manual);
      expect((await s.list('')).any((f) => f.name.contains('.corrupt-')), isFalse, reason: 'zählt nicht als Datei');
      expect(
        Directory('${dir.path}/installations/$id').listSync().any((f) => f.path.contains('customer.json.corrupt')),
        isTrue,
      );
    });

    test('Verbindung höchstens einmal je Tag', () async {
      await store.note(VisitKind.connection, now: DateTime(2026, 10, 30, 8));
      await store.note(VisitKind.connection, now: DateTime(2026, 10, 30, 18));
      await store.note(VisitKind.connection, now: DateTime(2026, 10, 31, 8));
      expect(store.visits(installs.active.id).length, 2);
    });

    test('Demo-Haus schreibt nichts', () async {
      DemoTunnel.active = true;
      await store.saveRecord(installs.active.id, const CustomerRecord(customer: 'Demo'));
      await store.note(VisitKind.manual);
      final s = ScopedStorage(AppStorage.instance, 'installations/${installs.active.id}/');
      expect(await s.read(CustomerStore.customerFile), isNull);
      expect(await s.read(CustomerStore.visitsFile), isNull);
    });

    test('Löschen der Installation nimmt die Akte mit', () async {
      final other = await installs.create('Andere');
      await store.saveRecord(other.id, const CustomerRecord(customer: 'Weg'));
      final s = ScopedStorage(AppStorage.instance, 'installations/${other.id}/');
      expect(await s.read(CustomerStore.customerFile), isNotNull);
      await installs.delete(other.id);
      expect(await s.read(CustomerStore.customerFile), isNull);
      await store.load();
      expect(store.record(other.id).isEmpty, isTrue);
    });

    test('Kundendaten sind nie im Diagnosepaket', () async {
      await store.saveRecord(
        installs.active.id,
        const CustomerRecord(
          customer: 'Familie Geheim',
          site: 'Geheimweg 7',
          phone: '0171-999888',
          email: 'geheim@example.org',
          contact: 'Frau Vertraulich',
          notes: 'Verteiler im Keller',
        ),
      );
      final package = buildDiagnosticsPackage(
        telegrams: const [],
        catalog: GroupCatalog({0x0801: const GroupInfo(address: 0x0801, name: 'Licht')}),
        occurred: DateTime(2026, 10, 30),
        problem: 'Bei Familie Geheim am Geheimweg 7, Frau Vertraulich unter 0171-999888 anrufen',
        knownNames: knownPrivateNames(),
      );
      final all = package.files.values.join('\n');
      for (final secret in ['Familie Geheim', 'Geheimweg 7', '0171-999888', 'geheim@', 'Vertraulich', 'Keller']) {
        expect(all, isNot(contains(secret)), reason: secret);
      }
    });
  });

  group('Oberfläche', () {
    Widget app(Widget home) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: home,
    );

    Future<void> prepare(WidgetTester tester, Future<void> Function() fill) async {
      SharedPreferences.setMockInitialValues({});
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('customer_ui');
        addTearDown(() => dir.delete(recursive: true));
        AppStorage.instance = IoStorage(dir);
        InstallationStore.instance.debugReset();
        CustomerStore.instance.debugReset();
        await InstallationStore.instance.load();
        await fill();
      });
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
    }

    testWidgets('Liste zeigt fällige Wartung; Suche grenzt ein', (tester) async {
      await prepare(tester, () async {
        final id = InstallationStore.instance.active.id;
        await CustomerStore.instance.saveRecord(
          id,
          CustomerRecord(customer: 'Familie Muster', maintenanceMonths: 1, maintenanceSince: DateTime(2020)),
        );
      });
      await tester.pumpWidget(app(const CustomersScreen()));
      await tester.pump();
      expect(find.text('Familie Muster'), findsOneWidget);
      expect(find.text('Wartung fällig'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'gibtsnicht');
      await tester.pump();
      expect(find.text('Familie Muster'), findsNothing);
      expect(find.byType(HorizontEmptyHint), findsOneWidget);
    });

    testWidgets('Akte: Aktionen nur mit Angaben, Verlauf sichtbar', (tester) async {
      late Installation i;
      await prepare(tester, () async {
        i = InstallationStore.instance.active;
        await CustomerStore.instance.saveRecord(i.id, const CustomerRecord(customer: 'Kunde', phone: '0123'));
        await CustomerStore.instance.saveVisit(i.id, _visit(DateTime(2026, 10), VisitKind.faultReport));
      });
      await tester.pumpWidget(app(CustomerDetailScreen(installation: i)));
      await tester.pump();
      expect(find.widgetWithText(ListTile, 'Telefon'), findsOneWidget);
      expect(find.text('0123'), findsOneWidget);
      expect(find.text('E-Mail'), findsNothing);
      expect(find.text('In Karten öffnen'), findsNothing);
      expect(find.text('Störungsmeldung'), findsOneWidget);
    });
  });
}
