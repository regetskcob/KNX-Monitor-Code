import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/addon_io.dart';

/// Eine abgebrochene Sicherung der Box darf nicht als fertige Datei gelten.
void main() {
  test('zipComplete erkennt eine vollständige und eine abgeschnittene Sicherung', () async {
    final dir = await Directory.systemTemp.createTemp('box-download');
    addTearDown(() => dir.delete(recursive: true));
    final archive = Archive()..addFile(ArchiveFile.string('manifest.json', '{"format":"busclear-box-backup"}'));
    final bytes = ZipEncoder().encode(archive);
    final whole = File('${dir.path}/ganz.zip')..writeAsBytesSync(bytes);
    final cut = File('${dir.path}/halb.zip')..writeAsBytesSync(bytes.sublist(0, bytes.length - 10));
    final empty = File('${dir.path}/leer.zip')..writeAsBytesSync(const []);
    expect(await zipComplete(whole), isTrue);
    expect(await zipComplete(cut), isFalse);
    expect(await zipComplete(empty), isFalse);
  });
}
