import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/incoming_file.dart';
import 'package:knx_monitor/platform/incoming_files.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/handover_screen.dart';

void main() {
  group('Startargumente', () {
    test('nur unsere Endungen, erste gewinnt', () {
      expect(packagePathFromArgs(const []), isNull);
      expect(packagePathFromArgs(const ['--flag', '/tmp/x.pdf']), isNull);
      expect(packagePathFromArgs(const ['--flag', '/tmp/a.knxhandover', '/tmp/b.knxreport']), '/tmp/a.knxhandover');
      expect(packagePathFromArgs(const ['/tmp/A.KNXREPORT']), '/tmp/A.KNXREPORT');
      expect(packagePathFromArgs(const [r'C:\Kunden\a.knxhandover']), r'C:\Kunden\a.knxhandover');
    });

    test('file-URI wird zum Pfad, andere Schemata zählen nicht', () {
      expect(packagePathFromArgs(const ['file:///tmp/a%20b.knxhandover']), '/tmp/a b.knxhandover');
      expect(packagePathFromArgs(const ['https://example.com/a.knxhandover']), isNull);
      expect(packagePathFromArgs(const ['knxmonitor://box/a.knxreport']), isNull);
      expect(packagePathFromArgs(const ['file://[kaputt.knxreport']), isNull);
    });
  });

  group('Antwort des nativen Teils', () {
    test('Inhalt, Ablehnung und Unsinn', () {
      final files = incomingFromNative([
        {
          'bytes': Uint8List.fromList([1, 2]),
        },
        {'problem': 'tooLarge'},
        {'problem': 'unreadable'},
        {'bytes': 'kein Inhalt'},
        17,
      ]);
      expect((files[0] as IncomingBytes).bytes, [1, 2]);
      expect((files[1] as IncomingRefused).problem, IncomingProblem.tooLarge);
      for (final f in files.skip(2)) {
        expect((f as IncomingRefused).problem, IncomingProblem.unreadable);
      }
    });

    test('kein Listenwert ist leer', () {
      expect(incomingFromNative(null), isEmpty);
      expect(incomingFromNative('x'), isEmpty);
    });
  });

  group('Weiche', () {
    const a = IncomingRefused(IncomingProblem.tooLarge);
    const b = IncomingRefused(IncomingProblem.unreadable);

    test('wartet, bis die Oberfläche steht', () async {
      final gate = IncomingFileGate()..add(a);
      expect(gate.waiting, 1);
      final opened = <IncomingFile>[];
      gate.attach((f) async => opened.add(f));
      await pumpEventQueue();
      expect(opened, [a]);
      expect(gate.waiting, 0);
    });

    test('nacheinander: die zweite Datei wartet auf die Dialoge der ersten', () async {
      final first = Completer<void>();
      final opened = <IncomingFile>[];
      IncomingFileGate()
        ..attach((f) {
          opened.add(f);
          return f == a ? first.future : Future.value();
        })
        ..add(a)
        ..add(b);
      await pumpEventQueue();
      expect(opened, [a]);
      first.complete();
      await pumpEventQueue();
      expect(opened, [a, b]);
    });

    test('ein Fehler hält die nächste nicht auf', () async {
      final opened = <IncomingFile>[];
      final gate = IncomingFileGate()
        ..add(a)
        ..add(b);
      gate.attach((f) async {
        opened.add(f);
        if (f == a) throw StateError('kaputt');
      });
      await pumpEventQueue();
      expect(opened, [a, b]);
    });

    test('begrenzt, was im Speicher wartet', () {
      final gate = IncomingFileGate();
      for (var i = 0; i < IncomingFileGate.maxWaiting + 3; i++) {
        gate.add(a);
      }
      expect(gate.waiting, IncomingFileGate.maxWaiting);
    });
  });

  group('Datei lesen', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('incoming'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('Inhalt', () async {
      final f = File('${dir.path}/a.knxhandover')..writeAsBytesSync([1, 2, 3]);
      expect(((await readPackagePath(f.path)) as IncomingBytes).bytes, [1, 2, 3]);
    });

    test('zu groß, fehlt, Ordner', () async {
      final f = File('${dir.path}/a.knxhandover')..writeAsBytesSync([1, 2, 3]);
      expect(((await readPackagePath(f.path, maxBytes: 2)) as IncomingRefused).problem, IncomingProblem.tooLarge);
      expect(
        ((await readPackagePath('${dir.path}/fehlt.knxreport')) as IncomingRefused).problem,
        IncomingProblem.unreadable,
      );
      expect(((await readPackagePath(dir.path)) as IncomingRefused).problem, IncomingProblem.unreadable);
    });
  });

  group('Öffnen', () {
    Future<void> open(WidgetTester tester, IncomingFile file) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  TextButton(onPressed: () => unawaited(openIncomingFile(context, file)), child: const Text('los')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
    }

    testWidgets('fremder Inhalt endet als Meldung', (tester) async {
      await open(tester, IncomingBytes(Uint8List.fromList([1, 2, 3, 4])));
      expect(find.text(s.packageCorrupt), findsOneWidget);
    });

    testWidgets('kaputtes ZIP endet als Meldung', (tester) async {
      await open(tester, IncomingBytes(Uint8List.fromList([0x50, 0x4B, 3, 4, 9, 9, 9])));
      expect(find.text(s.packageCorrupt), findsOneWidget);
    });

    testWidgets('zu groß hat eine eigene Meldung', (tester) async {
      await open(tester, const IncomingRefused(IncomingProblem.tooLarge));
      expect(find.text(s.packageTooLarge), findsOneWidget);
    });

    testWidgets('nicht lesbar hat eine eigene Meldung', (tester) async {
      await open(tester, const IncomingRefused(IncomingProblem.unreadable));
      expect(find.text(s.packageUnreadable), findsOneWidget);
    });
  });
}
