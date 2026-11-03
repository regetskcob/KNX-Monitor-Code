import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/device_label.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/service_report.dart';
import 'package:knx_monitor/model/site_photos.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

Uint8List _jpegWithGps({int width = 40, int height = 20}) {
  final image = img.Image(width: width, height: height);
  image.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(51, 1);
  image.exif.imageIfd['Make'] = img.IfdValueAscii('Telefon');
  return img.encodeJpg(image);
}

GroupCatalog _catalog() => GroupCatalog(
  const {},
  devices: {
    0x1105: const DeviceInfo(address: 0x1105, name: 'Schaltaktor', location: 'Keller › Verteiler', product: 'AKS'),
    0x1101: const DeviceInfo(address: 0x1101, name: '', product: 'Dimmaktor'),
    0x1100: const DeviceInfo(address: 0x1100, name: 'Linienkoppler'),
    0x11F0: const DeviceInfo(address: 0x11F0, name: 'Tunnel 1', tunnelOf: 0x1102),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Fotos verkleinern', () {
    test('Metadaten fallen weg, lange Kante begrenzt', () {
      final original = _jpegWithGps(width: 3000, height: 1000);
      expect(img.decodeJpg(original)!.exif.isEmpty, isFalse, reason: 'Vorlage hat Metadaten');
      final out = img.decodeJpg(compressSitePhoto(original))!;
      expect(out.width, sitePhotoMaxEdge);
      expect(out.height, closeTo(667, 1));
      expect(out.exif.gpsIfd.isEmpty, isTrue);
      expect(out.exif.imageIfd.isEmpty, isTrue);
    });

    test('Kein Bild oder zu groß: FormatException', () {
      expect(() => compressSitePhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
      expect(() => compressSitePhoto(Uint8List(sitePhotoMaxInput + 1)), throwsFormatException);
    });
  });

  group('Ablage', () {
    late MemoryStorage storage;
    final photos = SitePhotoStore.instance;
    const dir = 'installations/default';

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = MemoryStorage();
      AppStorage.instance = storage;
      InstallationStore.instance.debugReset();
      photos.debugReset();
    });

    test('Speichern, Beschriften, Lesen, Löschen im Ordner der Anlage', () async {
      final a = await photos.add(Uint8List.fromList([1, 2]), caption: ' Keller ', at: DateTime(2026, 10, 1));
      final b = await photos.add(Uint8List.fromList([3]), at: DateTime(2026, 10, 2));
      expect(photos.photos.map((p) => p.id), [b.id, a.id]);
      expect(storage.files.keys, contains('$dir/site_photos/${a.id}.jpg.b64'));
      expect(storage.files.keys, contains('$dir/site_photos.json'));
      expect(await photos.read(a.id), [1, 2]);
      await photos.setCaption(b.id, 'Reihe 2');
      photos.debugReset();
      await photos.load();
      expect(photos.photos.first.caption, 'Reihe 2');
      expect(photos.photos.last.caption, 'Keller');
      await photos.remove(a.id);
      expect(await photos.read(a.id), isNull);
      expect(storage.files.keys, isNot(contains('$dir/site_photos/${a.id}.jpg.b64')));
    });

    test('Kaputte Liste bleibt liegen, kaputte Einträge fallen weg', () async {
      storage.files['$dir/site_photos.json'] = '{kaputt';
      await photos.load();
      expect(photos.photos, isEmpty);
      expect(storage.files.keys.any((f) => f.contains('site_photos.json.corrupt')), isTrue);
      photos.debugReset();
      storage.files['$dir/site_photos.json'] = jsonEncode([
        {'id': '../../evil', 'at': '2026-10-01T00:00:00Z'},
        {'id': 'abc', 'at': 'keinDatum'},
        {'id': 'ok1', 'caption': 'Gut', 'at': '2026-10-01T00:00:00Z'},
      ]);
      await photos.load();
      expect(photos.photos.map((p) => p.id), ['ok1']);
      expect(await photos.read('../../evil'), isNull);
    });

    test('Fotos gehen mit der Anlage', () async {
      final installations = InstallationStore.instance;
      await installations.load();
      final other = await installations.create('Kunde');
      final base = 'installations/${other.id}';
      storage.files['$base/site_photos.json'] = '[]';
      storage.files['$base/site_photos/abc.jpg.b64'] = 'AA==';
      await installations.delete(other.id);
      expect(storage.files.keys.where((k) => k.startsWith(base)), isEmpty);
    });
  });

  test('Nicht im Diagnose- und nicht im Übergabepaket', () {
    for (final file in [
      'lib/export/diagnostics_bundle.dart',
      'lib/export/handover_package.dart',
      'lib/model/handover.dart',
      'lib/ui/support_package_screen.dart',
      'lib/ui/handover_screen.dart',
    ]) {
      final source = File(file).readAsStringSync();
      expect(source.contains('SitePhoto'), isFalse, reason: file);
      expect(source.contains('site_photos'), isFalse, reason: file);
    }
  });

  group('Etiketten', () {
    test('QR-Inhalt: keine URL, keine Geheimnisse, lokal auflösbar', () {
      final code = deviceLabelCode('a1b2c3d4e5f6', 0x1105);
      expect(code, 'knx-monitor-device:1:a1b2c3d4e5f6:1.1.5');
      expect(code, isNot(contains('//')));
      expect(parseDeviceLabel(code), (installation: 'a1b2c3d4e5f6', address: 0x1105));
      // Muss als QR-Code kodierbar sein.
      expect(pw.Barcode.qrCode().make(code, width: 100, height: 100), isNotEmpty);
    });

    test('Fremde Codes werden abgelehnt', () {
      for (final text in [
        '',
        'https://knx-monitor.de/1.1.5',
        'knxmonitor://box?x=1',
        'knx-monitor-device:2:abc:1.1.5',
        'knx-monitor-device:1:abc:1/1/5',
        'knx-monitor-device:1:../..:1.1.5',
        'knx-monitor-device:1:abc:1.1.5:mehr',
      ]) {
        expect(parseDeviceLabel(text), isNull, reason: text);
      }
    });

    test('Auflösen: aktive Anlage öffnet, andere nennt sie', () {
      final code = deviceLabelCode('aaa', 0x1105);
      String? name(String id) => id == 'aaa' ? 'Kunde Müller' : null;
      expect(resolveDeviceLabel(code, activeId: 'aaa', nameOf: name), isA<LabelOpenDevice>());
      final other = resolveDeviceLabel(code, activeId: 'bbb', nameOf: name);
      expect((other as LabelOtherInstallation).installationName, 'Kunde Müller');
      expect(
        resolveDeviceLabel(deviceLabelCode('zzz', 1), activeId: 'bbb', nameOf: name),
        isA<LabelUnknownInstallation>(),
      );
      expect(resolveDeviceLabel('Hallo', activeId: 'bbb', nameOf: name), isA<LabelForeign>());
    });

    test('Daten je Gerät: ohne Tunnel, Funktion ersatzweise das Produkt, Auswahl', () {
      final labels = deviceLabels(_catalog(), 'aaa');
      expect(labels.map((l) => formatIndividual(l.address)), ['1.1.0', '1.1.1', '1.1.5']);
      expect(labels[1].function, 'Dimmaktor');
      expect(labels[2].place, 'Keller › Verteiler');
      expect(deviceLabels(_catalog(), 'aaa', only: {0x1101}).single.address, 0x1101);
    });

    test('PDF: über mehrere Bögen, ohne Fehler', () async {
      final many = [
        for (var i = 1; i <= labelColumns * labelRows + 2; i++)
          DeviceLabel(
            address: 0x1100 + i,
            place: 'Ein sehr langer Einbauort im Keller hinter der Tür links neben dem Zählerschrank',
            function: 'Funktion $i',
            code: deviceLabelCode('aaa', 0x1100 + i),
          ),
      ];
      final bytes = await buildPdf(DeviceLabelsPdf(many));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });

  group('Servicebericht', () {
    ServiceReport report({List<ServicePhoto> photos = const []}) => ServiceReport(
      created: DateTime(2026, 10, 30),
      customer: 'Müller',
      site: '',
      technician: '',
      language: 'de',
      occasion: 'x',
      observed: '',
      done: '',
      recommendation: '',
      photos: photos,
      signature: Signature.empty,
    );

    test('Ohne Fotos bleibt das Format und damit die Prüfsumme', () {
      expect(report().toJson().containsKey('photos'), isFalse);
    });

    test('Mit Fotos: Runde durch JSON, PDF auch ohne Bilddatei', () async {
      final r = report(photos: const [ServicePhoto('abc', 'Keller')]);
      final back = ServiceReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, Object?>);
      expect(back.photos.single.caption, 'Keller');
      expect(back.checksum, r.checksum);
      final jpeg = img.encodeJpg(img.Image(width: 4, height: 4));
      for (final photos in [
        const <String, Uint8List>{},
        {'abc': jpeg},
      ]) {
        final bytes = await buildPdf(ServiceReportPdf(r, photos: photos));
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      }
    });
  });
}
