import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/diagnostics_bundle.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/knxproj_parser.dart';
import 'package:knx_monitor/platform/safe_zip.dart';

Uint8List zipOf(Map<String, int> sizes) {
  final archive = Archive();
  sizes.forEach((name, size) {
    archive.addFile(ArchiveFile(name, size, Uint8List(size)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  tearDown(() => defaultZipLimits = const ZipLimits());

  test('harmloses Archiv geht durch', () {
    final a = decodeZipLimited(zipOf({'a': 10, 'b': 20}));
    expect(a.findFile('b')!.content, hasLength(20));
  });

  test('Zahl der Einträge aus dem Endeintrag, ohne das Verzeichnis zu lesen', () {
    expect(zipEntryCount(zipOf({'a': 1, 'b': 2, 'c': 3})), 3);
    expect(zipEntryCount(Uint8List.fromList([0x50, 0x4B, 3, 4, 0, 0])), isNull);
    expect(zipEntryCount(Uint8List(0)), isNull);
    // Stated count above the limit: refused before the directory is parsed.
    final many = zipOf({'a': 1});
    final end = many.length - 22;
    many[end + 10] = 0xFF;
    many[end + 11] = 0xFF;
    expect(() => decodeZipLimited(many, limits: const ZipLimits(maxEntries: 400)), throwsA(isA<ZipLimitException>()));
  });

  test('Grenzen je Datei, gesamt und Zahl der Einträge', () {
    final bomb = zipOf({'a': 2000, 'b': 2000});
    expect(bomb.length, lessThan(1000), reason: 'packt sich auf ein Vielfaches aus');
    expect(
      () => decodeZipLimited(bomb, limits: const ZipLimits(maxFileBytes: 1000)),
      throwsA(isA<ZipLimitException>()),
    );
    expect(
      () => decodeZipLimited(bomb, limits: const ZipLimits(maxTotalBytes: 3000)),
      throwsA(isA<ZipLimitException>()),
    );
    expect(() => decodeZipLimited(bomb, limits: const ZipLimits(maxEntries: 1)), throwsA(isA<ZipLimitException>()));
  });

  test('gibt nicht mehr heraus, als das Verzeichnis nennt', () {
    final bytes = zipOf({'a': 5000});
    // Größe im zentralen Verzeichnis kleinlügen: Sie täuscht die Grenze nicht aus.
    final patched = Uint8List.fromList(bytes);
    for (var i = 0; i < patched.length - 4; i++) {
      if (patched[i] == 0x50 && patched[i + 1] == 0x4b && patched[i + 2] == 1 && patched[i + 3] == 2) {
        patched[i + 24] = 10;
        patched[i + 25] = 0;
      }
    }
    final a = decodeZipLimited(patched);
    expect(() => a.findFile('a')!.content, throwsA(anything));
  });

  group('Aufrufer sagen es klar', () {
    setUp(() => defaultZipLimits = const ZipLimits(maxFileBytes: 1000));
    final bomb = zipOf({'x.xml': 5000});

    test('ETS-Projekt', () {
      expect(() => parseKnxproj(bomb), throwsA(isA<FormatException>()));
    });

    test('Diagnosepaket', () {
      expect(() => DiagnosticsPackage.fromZip(bomb), throwsA(isA<FormatException>()));
    });

    test('Übergabepaket', () {
      expect(
        () => HandoverPackage.open(bomb),
        throwsA(isA<PackageException>().having((e) => e.problem, 'problem', PackageProblem.tooLarge)),
      );
    });
  });
}
