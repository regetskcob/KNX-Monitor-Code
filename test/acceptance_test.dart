import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';

/// A protocol exactly as the app wrote it before the optional details and the
/// defect photos existed.
const _oldProtocol =
    '{"format":"knx-monitor-acceptance","version":1,"created":1793113200000,"project":"Haus Muster",'
    '"customer":"Familie Muster","site":"Hauptstraße 1","technician":"D. Elektro","customerSigner":"MAX MUSTER",'
    '"remarks":"","followUps":"Taster tauschen","language":"de","started":null,"gateway":null,'
    '"items":[{"a":2304,"s":"ok"},{"a":4096,"s":"issue","n":"klemmt"}],'
    '"groups":{"2304":["Licht Flur RM","Licht › RM"],"4096":["Ist-Temperatur",null]},'
    '"customerSignature":[[[0.1235,0.5],[1.0,0.0]]],"technicianSignature":[[[0.1,0.1],[0.2,0.2]]]}';
const _oldProtocolChecksum = '54dd098ffaeacba74ce64a152d4ef3041df6ae1c60a037badb3dd17d5907b3de';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  group('Freiwillige Angaben und Mangelfotos', () {
    final jpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 30)));

    Acceptance withDetails() {
      c
        ..mark(temp, CheckState.issue)
        ..setNote(temp, 'Fühler defekt');
      return Acceptance.fromCommissioning(
        c,
        customer: 'Familie Muster',
        site: 'Hauptstraße 1',
        technician: 'D. Elektro',
        customerSigner: '',
        remarks: '',
        followUps: '',
        language: 'de',
        customerSignature: Signature.empty,
        technicianSignature: Signature.empty,
        standard: ' DIN VDE 0100-600 ',
        projectNumber: 'P-2026-17',
        warrantyStart: DateTime(2026, 11, 11, 14, 30),
        // Ein Foto zu einem Mangel und eines zu einem Punkt, der keiner ist.
        defectPhotos: {temp: DefectPhoto.of('abc', jpeg), rm: DefectPhoto.of('nein', jpeg)},
        now: DateTime(2026, 10, 27, 16),
      );
    }

    test('altes Protokoll lädt, bleibt Byte für Byte gleich und behält seine Prüfsumme', () {
      final old = Acceptance.fromJson(jsonDecode(_oldProtocol) as Map<String, Object?>);
      expect(old.customer, 'Familie Muster');
      expect(old.standard, isEmpty);
      expect(old.projectNumber, isEmpty);
      expect(old.warrantyStart, isNull);
      expect(old.defectPhotos, isEmpty);
      expect(old.hasDetails, isFalse);
      expect(jsonEncode(old.toJson()), _oldProtocol);
      expect(old.checksum, sha256.convert(utf8.encode(_oldProtocol)).toString());
      expect(old.checksum, _oldProtocolChecksum);
    });

    test('ohne die neuen Angaben stehen auch keine neuen Felder in der Datei', () {
      final json = make().toJson();
      for (final key in ['standard', 'projectNumber', 'warrantyStart', 'defectPhotos']) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(acceptanceDetailCells(make()), isEmpty);
    });

    test('Angaben und Fotos überstehen JSON; Foto nur am Mangel; Prüfsumme deckt das Bild', () {
      final a = withDetails();
      expect(a.standard, 'DIN VDE 0100-600');
      expect(a.warrantyStart, DateTime(2026, 11, 11), reason: 'ein Kalendertag, keine Uhrzeit');
      expect(a.defectPhotos.keys, [temp]);
      final json = jsonDecode(jsonEncode(a.toJson())) as Map<String, Object?>;
      expect(json['warrantyStart'], '2026-11-11');
      final back = Acceptance.fromJson(json);
      expect(back.checksum, a.checksum);
      expect(back.projectNumber, 'P-2026-17');
      expect(back.warrantyStart, DateTime(2026, 11, 11));
      expect(back.defectPhotos[temp]!.id, 'abc');
      expect(back.defectPhotos[temp]!.matches(jpeg), isTrue);
      expect(back.defectPhotos[temp]!.matches(Uint8List.fromList([...jpeg, 0])), isFalse);
      // Ein anderes Bild unter derselben ID ändert die Prüfsumme.
      final other = Acceptance.fromJson({
        ...a.toJson(),
        'defectPhotos': {
          '$temp': DefectPhoto.of('abc', [1, 2, 3]).toJson(),
        },
      });
      expect(other.checksum, isNot(a.checksum));
      // Der Stempel der Gegenprüfung nimmt die Angaben mit.
      final stamped = a.stamped(checkedBy: 'Meisterin');
      expect(stamped.standard, a.standard);
      expect(stamped.defectPhotos.keys, [temp]);
    });

    for (final (language, standard, number, warranty, date) in [
      ('de', 'Bezug auf Norm', 'Projektnummer', 'Beginn der Gewährleistung', '11.11.2026'),
      ('en', 'Standard referred to', 'Project number', 'Start of warranty', '2026-11-11'),
    ]) {
      test('PDF ($language): Zellen mit den Angaben, Bild, fehlendes und fremdes Bild', () async {
        LocaleController.instance.debugSetLocale(Locale(language));
        addTearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));
        final a = withDetails();
        expect(acceptanceDetailCells(a).map((c) => (c.$1, c.$2)), [
          (standard, 'DIN VDE 0100-600'),
          (number, 'P-2026-17'),
          (warranty, date),
        ]);
        final plain = await buildPdf(AcceptancePdf(make()));
        final withPhoto = await buildPdf(AcceptancePdf(a, photos: {'abc': jpeg}));
        final missing = await buildPdf(AcceptancePdf(a));
        final foreign = await buildPdf(
          AcceptancePdf(a, photos: {'abc': Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)))}),
        );
        // Only the image the report was signed with is printed.
        expect(withPhoto.length, greaterThan(missing.length));
        expect(foreign.length, lessThan(withPhoto.length));
        for (final pdf in [plain, withPhoto, missing, foreign]) {
          expect(utf8.decode(pdf.sublist(0, 5)), '%PDF-');
        }
        expect(
          utf8.decode((await buildPdfInBackground(AcceptancePdf(a, photos: {'abc': jpeg}))).sublist(0, 5)),
          '%PDF-',
        );
      });
    }
  });
}
