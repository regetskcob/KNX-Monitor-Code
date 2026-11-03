import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/resident_manual.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/resident_manual_screen.dart';

GroupInfo _g(int a, String name, {String? path, Dpt? dpt, List<GroupLink> links = const []}) =>
    GroupInfo(address: a, name: name, path: path, dpt: dpt, links: links);

final _catalog = GroupCatalog(
  {
    1: _g(1, 'Licht Küche', dpt: const Dpt(1, 1), links: const [GroupLink(device: 0x1101)]),
    2: _g(2, 'Licht Küche RM', dpt: const Dpt(1, 1), links: const [GroupLink(device: 0x1101)]),
    3: _g(3, 'Licht Küche dimmen', dpt: const Dpt(3, 7), links: const [GroupLink(device: 0x1101)]),
    4: _g(4, 'Rollo Bad', path: 'OG › Bad', dpt: const Dpt(1, 8)),
    5: _g(5, 'Ist-Temperatur Bad', path: 'OG › Bad', dpt: const Dpt(9, 1)),
    6: _g(6, 'Solltemperatur Bad', path: 'OG › Bad', dpt: const Dpt(9, 1)),
    7: _g(7, 'Status Heizung', path: 'OG › Bad', dpt: const Dpt(1, 11)),
    8: _g(8, 'Sperre Fenster', path: 'OG › Bad', dpt: const Dpt(1, 1)),
    9: _g(9, 'Unbekannt ohne Typ'),
    10: _g(10, formatGroup(10)),
    11: _g(11, 'Rollo Status', path: 'Rückmeldung › Rollo'),
    12: _g(12, 'Status RM', path: 'OG'),
  },
  devices: {0x1101: const DeviceInfo(address: 0x1101, name: 'Aktor', location: 'EG › Küche')},
  projectName: 'Haus Muster',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Räume aus Gerätestandort oder Pfad, ohne Technisches', () {
    final rooms = buildManualRooms(_catalog);
    expect(rooms.map((r) => r.title), ['EG › Küche', 'OG › Bad', '']);
    final kitchen = rooms.first.entries.map((e) => e.name);
    expect(kitchen, ['Licht Küche', 'Licht Küche dimmen']);
    final bath = {for (final e in rooms[1].entries) e.name: e.kind};
    expect(bath['Rollo Bad'], ManualKind.blinds);
    expect(bath['Ist-Temperatur Bad'], ManualKind.temperature);
    expect(bath['Solltemperatur Bad'], ManualKind.setpoint);
    expect(bath.containsKey('Status Heizung'), isFalse);
    expect(bath.containsKey('Sperre Fenster'), isFalse);
    expect(rooms.last.entries.single.kind, ManualKind.other);
  });

  test('Bedienung aus dem Datentyp', () {
    expect(manualKindOf(const Dpt(1, 1)), ManualKind.onOff);
    expect(manualKindOf(const Dpt(1, 8)), ManualKind.blinds);
    expect(manualKindOf(const Dpt(3, 7)), ManualKind.dim);
    expect(manualKindOf(const Dpt(5, 1)), ManualKind.percent);
    expect(manualKindOf(const Dpt(17, 1)), ManualKind.scene);
    expect(manualKindOf(const Dpt(14, 56)), ManualKind.measure);
    expect(manualKindOf(null), ManualKind.other);
    expect(manualKindOf(const Dpt(232, 600)), ManualKind.other);
  });

  test('angelernte Namen ohne Pfad zählen; leeres Projekt ergibt nichts', () {
    expect(buildManualRooms(GroupCatalog.empty), isEmpty);
    final learned = buildManualRooms(GroupCatalog({1: _g(1, 'Gelerntes Licht', dpt: const Dpt(1, 1))}));
    expect(learned.single.title, '');
    expect(learned.single.entries.single.name, 'Gelerntes Licht');
  });

  test('gleicher Name im selben Raum nur einmal, groß/klein egal', () {
    final rooms = buildManualRooms(
      GroupCatalog({
        1: _g(1, 'Licht', path: 'Flur', dpt: const Dpt(1, 1)),
        2: _g(2, 'LICHT', path: 'Flur', dpt: const Dpt(1, 1)),
      }),
    );
    expect(rooms.single.entries.length, 1);
  });

  test('PDF entsteht, auch im Hintergrund und ohne Kontakt', () async {
    final manual = buildResidentManual(
      catalog: _catalog,
      language: 'en',
      customer: const CustomerRecord(customer: 'Familie Muster'),
      note: 'Hauptschalter im Keller',
      contactName: 'Elektro Muster',
      contactPhone: '0123',
    );
    expect(manual.customer, 'Familie Muster');
    final pdf = await buildPdf(ResidentManualPdf(manual));
    expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(utf8.decode((await buildPdfInBackground(ResidentManualPdf(manual))).sublist(0, 5)), '%PDF-');
    final empty = await buildPdf(ResidentManualPdf(buildResidentManual(catalog: GroupCatalog.empty, language: 'de')));
    expect(utf8.decode(empty.sublist(0, 5)), '%PDF-');
  });

  testWidgets('Seite: ohne Projekt gesperrt, mit Projekt Zusammenfassung', (tester) async {
    Widget app() => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: const ResidentManualScreen(),
    );
    CatalogStore.instance.catalog = GroupCatalog.empty;
    addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
    await tester.pumpWidget(app());
    expect(find.textContaining('braucht es ein Projekt'), findsOneWidget);
    CatalogStore.instance.catalog = _catalog;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    expect(find.text('3 Bereiche, 6 Funktionen'), findsOneWidget);
    expect(find.textContaining('braucht es ein Projekt'), findsNothing);
  });
}
