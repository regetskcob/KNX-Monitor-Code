import 'dart:convert';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/knxproj_parser.dart';

/// Großes, gut komprimierbares Applikationsprogramm (viele Rückverweise).
String _bigApplication(int objects) {
  final r = Random(1);
  final b = StringBuffer('<ApplicationProgram Id="M-0008_A-1"><Static><ComObjects>');
  for (var i = 0; i < objects; i++) {
    b.write(
      '<ComObject Id="M-0008_A-1_O-$i" Number="$i" TransmitFlag="${r.nextBool() ? 'Enabled' : 'Disabled'}" '
      'DatapointType="DPST-9-${r.nextInt(30)}" Text="Objekt $i ${'x' * r.nextInt(200)}" />',
    );
    b.write('<ParameterBlock Text="${'Füllung ' * r.nextInt(40)}" />');
  }
  b.write('</ComObjects><ComObjectRefs>');
  for (var i = 0; i < objects; i++) {
    b.write('<ComObjectRef Id="M-0008_A-1_O-${i}_R-1" RefId="M-0008_A-1_O-$i" />');
  }
  b.write('</ComObjectRefs></Static></ApplicationProgram>');
  return b.toString();
}

void main() {
  test('findet beim stückweisen Entpacken dieselben Tags wie im ganzen Text', () {
    final text = _bigApplication(20000); // einige MB
    final bytes = latin1.encode(text);
    final zip = ZipEncoder().encodeBytes(Archive()..add(ArchiveFile.bytes('M-0008/M-0008_A-1.xml', bytes)));
    final file = ZipDecoder().decodeBytes(zip).findFile('M-0008/M-0008_A-1.xml')!;

    final found = <String>[];
    final scanner = TagScanner(['<ComObjectRef ', '<ComObject '], found.add);
    file.writeContent(scanner);
    scanner.finish();

    final expected = RegExp(r'<ComObject(Ref)? [^>]*>').allMatches(text).map((m) => m[0]!).toList();
    expect(found.length, expected.length);
    expect(found, expected);
    expect(scanner.length, bytes.length);
  });

  test('Tags über Blockgrenzen und einzelne Bytes', () {
    final found = <String>[];
    final scanner = TagScanner(['<ComObject '], found.add);
    for (final b in latin1.encode('xx<Com')) {
      scanner.writeByte(b);
    }
    scanner.writeBytes(latin1.encode('Object Id="1" /><ComObjects><ComObject Id="2"'));
    scanner.writeBytes(latin1.encode(' /> <ComObj'));
    scanner.finish();
    expect(found, ['<ComObject Id="1" />', '<ComObject Id="2" />']);
  });
}
