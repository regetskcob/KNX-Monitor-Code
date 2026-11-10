import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knxproj_parser.dart';
import 'package:knx_monitor/knx/sqlite_reader.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/knx/xknx_parser.dart';
import 'package:knx_monitor/model/project_check.dart';

// Fixtures from tool/xknx_fixture.py: synthetic, no real installation.
Uint8List _fixture(String name) => File('test/fixtures/xknx/$name').readAsBytesSync();

void main() {
  group('SqliteReader', () {
    test('liest Tabellen, Spalten und Zeilen mit rowid-Alias', () {
      final db = SqliteReader(_fixture('testhaus.xknx'));
      expect(db.tables, containsAll(['projects', 'group_addresses', 'com_object_links']));
      expect(db.columns('areas'), ['id', 'installation_id', 'address', 'name']);
      final areas = db.rows('areas');
      expect(areas.single, {'id': 1, 'installation_id': 1, 'address': 1, 'name': 'Bereich 1'});
    });

    test('mehrstufiger B-Baum und Überlaufseiten', () {
      final rows = SqliteReader(_fixture('testhaus.xknx')).rows('group_addresses');
      expect(rows, hasLength(259));
      expect(rows.map((r) => r['id']), orderedEquals([...rows.map((r) => r['id'] as int)]..sort()));
      final long = rows.firstWhere((r) => r['id'] == 1)['description']! as String;
      expect(long.length, 'Sehr lange Beschreibung. '.length * 300);
      expect(rows.last['name'], startsWith('Adresse 255'));
    });

    test('Blob-Spalten und NULL', () {
      final p = SqliteReader(_fixture('testhaus.xknx')).rows('projects').single;
      expect(p['knx_master_xml'], isA<Uint8List>());
      expect((p['knx_master_xml']! as Uint8List).length, 2000);
      expect(p['password_salt'], isNull);
    });

    test('keine SQLite-Datei', () {
      expect(() => SqliteReader(Uint8List.fromList(List.filled(200, 1))), throwsFormatException);
      expect(isXknx(Uint8List.fromList('a;b;c'.codeUnits)), isFalse);
      expect(isXknx(_fixture('testhaus.xknx')), isTrue);
    });
  });

  group('parseXknx', () {
    // KNX RF: the editor keeps the medium per segment. Fixture: testhaus.xknx with its one
    // segment set to RF (sqlite3 … "update segments set medium_type='RF'").
    test('radio line: devices on an RF segment are marked', () {
      expect(parseXknx(_fixture('testhaus.xknx')).rfLines, isEmpty);
      final rf = parseXknx(_fixture('testhaus_rf.xknx'));
      expect(rf.rfLines, isNotEmpty);
      expect(rf.devices.values.where((d) => !d.isTunnel).every((d) => d.rf), isTrue);
    });

    test('Gruppenadressen, Bereiche und Datentypen', () {
      final c = parseXknx(_fixture('testhaus.xknx'));
      expect(c.projectName, 'Testhaus');
      expect(c.style, GroupStyle.threeLevel);
      expect(c.length, 259);
      final schalten = c[parseGroup('1/1/0')!]!;
      expect(schalten.name, 'Küche Licht Schalten');
      expect(schalten.path, 'Licht › Schalten');
      expect(schalten.dpt, const Dpt(1, 1));
      // Ohne DPT an der Adresse: Typ aus dem Objekt (Override im Projekt).
      expect(c[parseGroup('1/4/0')!]!.dpt, const Dpt(1, 1));
      expect(c[parseGroup('8/1/255')!]!.path, 'Diverses › Viele');
    });

    test('Geräte, Orte, Hersteller, Tunnel, nie programmiert', () {
      final c = parseXknx(_fixture('testhaus.xknx'));
      final aktor = c.devices[parseIndividual('1.1.10')]!;
      expect(aktor.name, 'Schaltaktor 4-fach');
      expect(aktor.product, 'Schaltaktor 4-fach');
      expect(aktor.manufacturer, 'MDT technologies');
      expect(aktor.location, 'EG › Küche');
      expect(aktor.description, 'Schrank');
      expect(aktor.serial, '0083AABBCCDD');
      expect(aktor.neverProgrammed, isFalse);
      expect(c.devices[parseIndividual('1.1.20')]!.name, 'Taster Küche');
      expect(c.devices[parseIndividual('1.1.30')]!.neverProgrammed, isTrue);
      // Ohne physikalische Adresse: nicht im Katalog.
      expect(c.devices, hasLength(6));
      expect(c.devices[parseIndividual('1.1.200')]!.name, 'IP-Router · Tunnel A');
      expect(c.devices[parseIndividual('1.1.201')]!.name, 'IP-Router · Tunnel 2');
      expect(c.devices[parseIndividual('1.1.200')]!.tunnelOf, parseIndividual('1.1.40'));
      expect(c.manufacturers, {0x83: 'MDT technologies', 0x08: 'GIRA Giersiepen'});
    });

    test('Verknüpfungen mit Flags, Overrides und Senden wie beim .knxproj', () {
      final c = parseXknx(_fixture('testhaus.xknx'));
      final schalten = c[parseGroup('1/1/0')!]!.links;
      expect(schalten.map((l) => (formatIndividual(l.device), l.sends)), [('1.1.10', false), ('1.1.20', true)]);
      final taste = schalten.last;
      expect(taste.text, 'Taste 1 – Licht');
      // Objekt aus einem Modul: Nummer nur in der Applikation.
      expect(taste.object, isNull);
      expect(taste.ref, 'M-0083_A-0002-10-BBBB_MD-1_M-1_MI-1_O-3-0_R-5');
      expect(schalten.first.object, 0);
      expect(schalten.first.flags.toString(), 'CW');

      final status = c[parseGroup('1/4/0')!]!.links;
      // Aktor-Status sendet; Anzeige mit S+Ü+A hört nur; Ü per Override aus.
      expect(status.where((l) => l.sends).map((l) => l.ref), ['M-0083_A-0001-10-AAAA_O-1_R-2']);
      expect(status.firstWhere((l) => l.ref!.endsWith('_O-2_R-3')).flags.toString(), 'CR');
    });

    test('Projektprüfung: Gerät nie programmiert, Download ausstehend', () {
      final c = parseXknx(_fixture('testhaus.xknx'));
      expect(c.devices[parseIndividual('1.1.20')]!.pendingDownload, [DownloadPart.parameters, DownloadPart.groups]);
      expect(c.devices[parseIndividual('1.1.10')]!.pendingDownload, isEmpty);
      // Nie programmiert: alles fehlt, das meldet der eigene Befund.
      expect(c.devices[parseIndividual('1.1.30')]!.pendingDownload, isEmpty);
      final back = GroupCatalog.fromJson(c.toJson());
      expect(back.devices[parseIndividual('1.1.20')]!.pendingDownload, [DownloadPart.parameters, DownloadPart.groups]);
      final lint = ProjectLint.of(c);
      expect(lint.devicesPendingDownload.map((d) => formatIndividual(d.address)), ['1.1.20']);
      expect(lint.devicesNeverProgrammed.map((d) => formatIndividual(d.address)), ['1.1.30']);
      expect(lint.devicesWithoutLinks.map((d) => formatIndividual(d.address)), containsAll(['1.1.30', '1.1.40']));
    });

    test('Katalog übersteht JSON', () {
      final c = parseXknx(_fixture('testhaus.xknx'));
      final back = GroupCatalog.fromJson(c.toJson());
      expect(back.length, c.length);
      expect(back[parseGroup('1/1/0')!]!.links.last.ref, c[parseGroup('1/1/0')!]!.links.last.ref);
      expect(back.devices[parseIndividual('1.1.30')]!.neverProgrammed, isTrue);
    });

    test('Passwort: fehlt, falsch, richtig, vorab abgeleiteter Schlüssel', () {
      final bytes = _fixture('testhaus_passwort.xknx');
      expect(() => parseXknx(bytes), throwsA(isA<KnxprojPasswordException>().having((e) => e.wrong, 'wrong', isFalse)));
      expect(
        () => parseXknx(bytes, password: 'falsch'),
        throwsA(isA<KnxprojPasswordException>().having((e) => e.wrong, 'wrong', isTrue)),
      );
      expect(parseXknx(bytes, password: 'geheim').length, 259);
      final kdf = xknxKeyDerivation(bytes)!;
      expect(kdf.iterations, 1000);
      expect(xknxKeyDerivation(_fixture('testhaus.xknx')), isNull);
    });

    test('kaputte Datei', () {
      final bytes = Uint8List.fromList(_fixture('testhaus.xknx'));
      // Seite 2 (Wurzel einer Tabelle) zerstören.
      bytes.fillRange(4096, 4096 + 16, 0xEE);
      expect(() => parseXknx(bytes), throwsFormatException);
      expect(() => parseXknx(Uint8List(10)), throwsFormatException);
    });
  });
}
