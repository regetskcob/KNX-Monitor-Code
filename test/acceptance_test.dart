import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

void main() {
  late Directory dir;
  final c = Commissioning.instance;
  final rm = parseGroup('1/4/0')!;
  final temp = parseGroup('2/0/0')!;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('acceptance');
    AppStorage.instance = IoStorage(dir);
    c.debugReset();
    CatalogStore.instance.catalog = GroupCatalog({
      rm: GroupInfo(address: rm, name: 'Licht Flur RM', path: 'Licht › RM'),
      temp: GroupInfo(address: temp, name: 'Ist-Temperatur', path: 'Heizung'),
    }, projectName: 'Haus Muster');
    c.prepare([rm, temp]);
    c.mark(rm, CheckState.ok);
  });

  tearDown(() async {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    // Das Speichern aus mark() läuft im Hintergrund; erst abwarten, dann löschen.
    await c.flush();
    await dir.delete(recursive: true);
  });

  Acceptance make({String customer = 'Familie Muster'}) => Acceptance.fromCommissioning(
    c,
    customer: customer,
    site: ' Hauptstraße 1 ',
    technician: 'D. Elektro',
    customerSigner: 'MAX MUSTER',
    remarks: '',
    followUps: 'Taster tauschen',
    language: 'de',
    customerSignature: const Signature([
      [Offset(0.123456, 0.5), Offset(1.4, -0.2)],
    ]),
    technicianSignature: const Signature([
      [Offset(0.1, 0.1), Offset(0.2, 0.2)],
    ]),
    now: DateTime(2026, 10, 27, 16),
  );

  test('Friert Stand und Namen ein, übersteht JSON, Prüfsumme bleibt gleich', () {
    final a = make();
    expect(a.site, 'Hauptstraße 1');
    expect(a.project, 'Haus Muster');
    expect(a.groups[rm]?.name, 'Licht Flur RM');
    expect(a.done, 1);
    // Spätere Änderungen an der Checkliste und am Projekt ändern das Protokoll nicht.
    c.mark(temp, CheckState.issue);
    CatalogStore.instance.catalog = GroupCatalog.empty;
    expect(a.count(CheckState.issue), 0);

    final back = Acceptance.fromJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>);
    expect(back.checksum, a.checksum);
    expect(back.groups[rm]?.path, 'Licht › RM');
    expect(back.items.map((i) => i.state), a.items.map((i) => i.state));
    // Gerundet und ins Feld geklemmt.
    expect(back.customerSignature.strokes.first.first, const Offset(0.1235, 0.5));
    expect(back.customerSignature.strokes.first.last, const Offset(1, 0));
  });

  test('Prüfsumme ändert sich mit dem Inhalt', () {
    expect(make().checksum, isNot(make(customer: 'Familie Beispiel').checksum));
    expect(make().checksum, hasLength(64));
  });

  test('Leere Unterschrift', () {
    expect(Signature.empty.isEmpty, isTrue);
    expect(
      const Signature([
        [Offset(0.5, 0.5)],
      ]).isEmpty,
      isTrue,
    );
  });

  test('Ablage je Installation, neueste zuerst', () async {
    final store = AcceptanceStore.instance;
    await store.save(make());
    await store.save(
      Acceptance.fromJson({...make().toJson(), 'created': DateTime(2026, 10, 28).millisecondsSinceEpoch}),
    );
    final list = await store.list();
    expect(list, hasLength(2));
    expect(list.first.created, DateTime(2026, 10, 28));
  });

  test('Demo-Haus: Protokoll nur im Speicher, nichts in der Installation', () async {
    final store = AcceptanceStore.instance;
    final before = (await store.list()).length;
    DemoTunnel.active = true;
    try {
      await store.save(make());
      expect(await store.list(), hasLength(1));
    } finally {
      DemoTunnel.active = false;
    }
    expect(await store.list(), hasLength(before), reason: 'nichts gespeichert, Demo-Protokoll verfällt');
  });
}
