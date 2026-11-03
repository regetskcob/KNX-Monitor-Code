import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/device_inventory.dart';
import 'package:knx_monitor/model/ets_tasks.dart';

int ga(int main, int middle, int sub) => (main << 11) | (middle << 8) | sub;
int pa(int line, int device) => (1 << 12) | (line << 8) | device;

/// Kleines Projekt mit den typischen Funden: Rückmeldung ohne L-Flag, zwei
/// Kanäle eines Aktors auf derselben Rückmeldung, Objekt ohne K-Flag, Gerät
/// ohne Verknüpfung.
GroupCatalog _catalog() {
  const status = ComFlags(transmit: true);
  final actuator = pa(1, 18);
  final button = pa(1, 50);
  return GroupCatalog(
    {
      ga(2, 1, 4): GroupInfo(
        address: ga(2, 1, 4),
        name: 'EG WZ Soll-Temperatur Status',
        links: [
          GroupLink(device: actuator, object: 128, text: 'Kanal D: Wohnzimmer', sends: true, flags: status),
          GroupLink(device: actuator, object: 168, text: 'Kanal E: Esszimmer', sends: true, flags: status),
        ],
      ),
      ga(1, 0, 1): GroupInfo(
        address: ga(1, 0, 1),
        name: 'EG WZ Licht',
        links: [
          GroupLink(device: button, object: 4, text: 'Taste 1', sends: true, flags: const ComFlags(transmit: true)),
          GroupLink(
            device: actuator,
            object: 10,
            text: 'Kanal A',
            flags: const ComFlags(communication: false, write: true),
          ),
        ],
      ),
    },
    devices: {
      actuator: DeviceInfo(address: actuator, name: 'Heizungsaktor'),
      button: DeviceInfo(address: button, name: 'Taster'),
      pa(1, 120): DeviceInfo(address: pa(1, 120), name: 'Binäreingang'),
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Aufgaben je Gerät aus dem Projekt, Datentypen an den Adressen', () {
    final catalog = _catalog();
    final tasks = EtsTasks.of(catalog, {ga(1, 0, 1): const Dpt(1, 1), ga(9, 9, 9): const Dpt(9, 1)});
    expect(tasks.hasFlags, isTrue);
    // Import: nur Adressen aus dem Projekt mit geändertem Typ.
    expect(tasks.importable.map((t) => t.group), [ga(1, 0, 1)]);
    expect(tasks.importable.single.dpt, const Dpt(1, 1));
    expect(tasks.imports.single, (
      address: ga(1, 0, 1),
      name: 'EG WZ Licht',
      dpt: const Dpt(1, 1),
      description: null,
      path: null,
    ));
    // Von Hand: Rückmeldung ohne Datentyp, Licht ohne Empfänger (Aktor ohne K).
    expect([
      for (final t in tasks.manual) (t.group, t.kind),
    ], containsAll([(ga(2, 1, 4), EtsTaskKind.noDpt), (ga(1, 0, 1), EtsTaskKind.withoutReceiver)]));

    final actuator = tasks.devices[pa(1, 18)]!;
    final kinds = actuator.map((t) => t.kind).toList();
    expect(kinds, containsAll([EtsTaskKind.readWithoutReadFlag, EtsTaskKind.objectWithoutCommunication]));
    expect(kinds.where((k) => k == EtsTaskKind.multipleSenders), hasLength(2));
    // Hinweise zuletzt.
    expect(actuator.last.hint, isTrue);
    // Der andere Sender ist ein Kanal desselben Geräts.
    final d = actuator.firstWhere((t) => t.kind == EtsTaskKind.multipleSenders && t.object == 128);
    expect(d.others.single.device, pa(1, 18));
    expect(d.others.single.number, 168);

    expect(tasks.devices[pa(1, 120)]!.single.kind, EtsTaskKind.deviceWithoutLinks);
    expect(tasks.devices.containsKey(pa(1, 50)), isFalse);
    expect(tasks.devices.keys.toList(), [pa(1, 18), pa(1, 120)]);
  });

  test('Angelerntes: Namen für unbenannte Adressen, neue Adressen, Typen – alles im Import', () {
    final project = GroupCatalog({
      ga(1, 0, 1): GroupInfo(address: ga(1, 0, 1), name: 'Neue Gruppenadresse', dpt: const Dpt(1, 1)),
      ga(1, 0, 2): GroupInfo(address: ga(1, 0, 2), name: 'Flur Licht', path: 'Licht › EG'),
    });
    final learned = GroupCatalog({
      // Angelernter Typ überschreibt keinen aus dem Projekt.
      ga(1, 0, 1): GroupInfo(address: ga(1, 0, 1), name: 'Küche Decke', dpt: const Dpt(5, 1)),
      ga(1, 0, 2): GroupInfo(address: ga(1, 0, 2), name: 'Flur', dpt: const Dpt(1, 1)),
      ga(1, 0, 9): GroupInfo(address: ga(1, 0, 9), name: 'Garten', dpt: const Dpt(1, 1)),
    });
    final tasks = EtsTasks.of(project, const {}, learned: learned);
    expect(
      [for (final t in tasks.importable) (t.group, t.kind)],
      [(ga(1, 0, 1), EtsTaskKind.learnedName), (ga(1, 0, 2), EtsTaskKind.dpt), (ga(1, 0, 9), EtsTaskKind.learnedNew)],
    );
    // Ein gepflegter Projektname wird nicht überschrieben, aber der Typ kommt mit.
    final flur = tasks.imports.firstWhere((e) => e.address == ga(1, 0, 2));
    expect((flur.name, flur.dpt, flur.path), ('Flur Licht', const Dpt(1, 1), 'Licht › EG'));
    expect(tasks.imports.firstWhere((e) => e.address == ga(1, 0, 1)).name, 'Küche Decke');
    // Vorher-Stand steht in der Aufgabe (das PDF kennt im Hintergrund nur den
    // zusammengeführten Katalog).
    final name = tasks.importable.firstWhere((t) => t.kind == EtsTaskKind.learnedName);
    expect(name.beforeName, 'Neue Gruppenadresse');
    expect(tasks.importable.firstWhere((t) => t.kind == EtsTaskKind.dpt).beforeDpt, isNull);
    expect(tasks.imports.firstWhere((e) => e.address == ga(1, 0, 9)).dpt, const Dpt(1, 1));
    // Mit angelerntem Namen gibt es keine Aufgabe „ohne Namen“.
    expect(tasks.manual.where((t) => t.kind == EtsTaskKind.noName), isEmpty);
  });

  test('Inventar: fehlt im Projekt, Seriennummer anders, antwortet nicht', () {
    final catalog = _catalog();
    final tasks = EtsTasks.of(
      catalog,
      const {},
      inventory: [
        InventoryEntry(pa(1, 77), InventoryStatus.notInProject),
        InventoryEntry(pa(1, 18), InventoryStatus.serialMismatch, project: catalog.devices[pa(1, 18)]),
        InventoryEntry(pa(1, 50), InventoryStatus.missing, project: catalog.devices[pa(1, 50)]),
        InventoryEntry(pa(1, 120), InventoryStatus.match, project: catalog.devices[pa(1, 120)]),
      ],
    );
    expect(tasks.devices[pa(1, 77)]!.single.kind, EtsTaskKind.notInProject);
    expect(tasks.devices[pa(1, 18)]!.map((t) => t.kind), contains(EtsTaskKind.serialMismatch));
    expect(tasks.devices[pa(1, 50)]!.single.hint, isTrue);
    expect(tasks.devices[pa(1, 120)]!.map((t) => t.kind), [EtsTaskKind.deviceWithoutLinks]);
  });

  test('ohne Funde und ohne geänderte Typen: leer', () {
    final catalog = GroupCatalog({ga(1, 0, 1): GroupInfo(address: ga(1, 0, 1), name: 'Licht', dpt: const Dpt(1, 1))});
    final tasks = EtsTasks.of(catalog, {ga(1, 0, 1): const Dpt(1, 1)});
    expect(tasks.isEmpty, isTrue);
    expect(tasks.count, 0);
  });

  test('PDF mit Übersicht und Geräteseiten entsteht im Hintergrund', () async {
    final catalog = _catalog();
    CatalogStore.instance.catalog = catalog;
    final tasks = EtsTasks.of(catalog, {ga(1, 0, 1): const Dpt(1, 1)});
    final bytes = await buildPdfInBackground(EtsTasksPdf(tasks, drawings: {pa(1, 18): _png}));
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
    // Übersicht plus eine Seite je Gerät mit Aufgaben.
    expect(RegExp(r'/Type\s*/Page\b').allMatches(latin1.decode(bytes)).length, greaterThanOrEqualTo(3));
    // Ein kaputtes Bild kostet nur die Zeichnung, nicht das PDF.
    final broken = await buildPdfInBackground(
      EtsTasksPdf(
        tasks,
        drawings: {
          pa(1, 18): Uint8List.fromList([1, 2, 3]),
        },
      ),
    );
    expect(latin1.decode(broken.sublist(0, 5)), '%PDF-');
  });
}

/// 1 × 1 Pixel, weiß.
final _png = Uint8List.fromList(
  base64.decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII='),
);
