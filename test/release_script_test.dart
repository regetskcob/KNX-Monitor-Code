@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// tool/release.sh mit Ersatz für flutter, xcodebuild und gh, in einem leeren HOME.
void main() {
  late Directory home;
  late Directory bin;
  late File calls;

  void fake(String name, String body) {
    final file = File('${bin.path}/$name')..writeAsStringSync('#!/usr/bin/env bash\n$body\n');
    Process.runSync('chmod', ['+x', file.path]);
  }

  setUp(() {
    home = Directory.systemTemp.createTempSync('release_test');
    bin = Directory('${home.path}/bin')..createSync();
    calls = File('${home.path}/calls')..writeAsStringSync('');
    Directory('${home.path}/.config/knx-monitor').createSync(recursive: true);
    File('${home.path}/.config/knx-monitor/supabase.env').writeAsStringSync('SUPABASE_URL=u\nSUPABASE_KEY=k\n');
  });
  tearDown(() => home.deleteSync(recursive: true));

  ProcessResult run(List<String> args, [Map<String, String> env = const {}]) => Process.runSync(
    'bash',
    ['tool/release.sh', ...args],
    // Build switches of the caller (e.g. RC_NONE=1 tool/release.sh app) must
    // not leak into the cases; each test sets what it needs.
    environment: {
      'HOME': home.path,
      'PATH': '${bin.path}:${Platform.environment['PATH']}',
      for (final k in [
        'RC_NONE',
        'PAID',
        'BETA',
        'BETRIEB',
        'RC_GOOGLE_KEY',
        'RC_APPLE_KEY',
        'UPLOAD',
        'ASC_KEY_ID',
        'ASC_ISSUER_ID',
        'ASC_KEY_PATH',
      ])
        k: '',
      ...env,
    },
  );

  group('Kaufweg im Build', () {
    test('Mit Schlüssel: der Schlüssel', () {
      final r = run(['rc-define', 'RC_APPLE_KEY'], {'RC_APPLE_KEY': 'appl_x'});
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}'.trim(), '--dart-define=RC_APPLE_KEY=appl_x');
    });

    test('Ohne Schlüssel: Abbruch', () {
      final r = run(['rc-define', 'RC_APPLE_KEY']);
      expect(r.exitCode, isNot(0));
      expect('${r.stdout}', isNot(contains('PLAN_OPEN')));
    });

    test('RC_NONE=1 setzt PLAN_OPEN und baut auch mit vorhandenem Schlüssel keinen ein', () {
      final r = run(['rc-define', 'RC_GOOGLE_KEY'], {'RC_NONE': '1', 'RC_GOOGLE_KEY': 'goog_x'});
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}'.trim(), '--dart-define=PLAN_OPEN=true');
    });

    test('PAID=1 verweigert RC_NONE=1', () {
      final r = run(['rc-define', 'RC_APPLE_KEY'], {'RC_NONE': '1', 'PAID': '1'});
      expect(r.exitCode, isNot(0));
      expect('${r.stderr}${r.stdout}', contains('PAID=1'));
    });

    test('PAID=1 mit Schlüssel läuft', () {
      expect(run(['rc-define', 'RC_APPLE_KEY'], {'PAID': '1', 'RC_APPLE_KEY': 'appl_x'}).exitCode, 0);
    });
  });

  group('macOS', () {
    setUp(() {
      fake('flutter', '''
echo "flutter \$*" >> "${calls.path}"
mkdir -p build/symbols/macos && touch build/symbols/macos/app.symbols
''');
      fake('xcodebuild', '''
echo "xcodebuild \$*" >> "${calls.path}"
while [ \$# -gt 0 ]; do
  if [ "\$1" = -archivePath ]; then mkdir -p "\$2"; fi
  shift
done
''');
    });

    test('Baut mit den Angaben von iOS, archiviert in den Organizer, behält die Symbole', () {
      final r = run(['macos'], {'RC_APPLE_KEY': 'appl_x'});
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final log = calls.readAsLinesSync();
      expect(log[0], contains('build macos --release --obfuscate --split-debug-info=build/symbols/macos'));
      expect(log[0], contains('RC_APPLE_KEY=appl_x'));
      expect(log[0], isNot(contains('SUPABASE')));
      expect(log[0], isNot(contains('BETRIEB')));
      expect(log[1], contains('-workspace macos/Runner.xcworkspace -scheme Runner -configuration Release'));
      expect(log[1], contains('${home.path}/Library/Developer/Xcode/Archives/'));
      final version = RegExp(r'^version: (.+)$', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!;
      expect(
        File('${home.path}/keys/symbols/knx-monitor/${version[1]}/macos/app.symbols').existsSync(),
        isTrue,
        reason: '${r.stdout}',
      );
    });

    test('BETRIEB=1 baut das Konto ein und verlangt die Supabase-Werte', () {
      final r = run(['macos'], {'RC_APPLE_KEY': 'appl_x', 'BETRIEB': '1'});
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final log = calls.readAsLinesSync();
      expect(log[0], contains('BETRIEB=true'));
      expect(log[0], contains('SUPABASE_URL=u'));
      calls.writeAsStringSync('');
      File('${home.path}/.config/knx-monitor/supabase.env').deleteSync();
      expect(run(['macos'], {'RC_APPLE_KEY': 'appl_x', 'BETRIEB': '1'}).exitCode, isNot(0));
      expect(calls.readAsStringSync(), isEmpty);
    });

    test('Ohne Schlüssel wird nichts gebaut, ohne Supabase-Werte aber schon', () {
      expect(run(['macos']).exitCode, isNot(0));
      expect(calls.readAsStringSync(), isEmpty);
      File('${home.path}/.config/knx-monitor/supabase.env').deleteSync();
      expect(run(['macos'], {'RC_APPLE_KEY': 'appl_x'}).exitCode, 0);
    });
  });

  test('iOS: Archiv landet auch im Organizer', () {
    fake('flutter', '''
mkdir -p build/ios/ipa build/ios/archive/Runner.xcarchive
touch build/ios/ipa/app.ipa build/ios/archive/Runner.xcarchive/Info.plist
''');
    final r = run(['ios'], {'RC_APPLE_KEY': 'appl_x'});
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final archives = Directory('${home.path}/Library/Developer/Xcode/Archives')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path);
    // The archive's own Info.plist, whatever else lies in it: in a checkout that has built a
    // real release, build/ios/archive holds the whole archive and all of it is copied.
    expect(archives.where((p) => p.endsWith('.xcarchive/Info.plist')), hasLength(1));
  });

  group('Desktop-Release', () {
    void runs(String list, Map<String, String> linuxJob) {
      final cases = [for (final e in linuxJob.entries) '*" ${e.key} "*) echo ${e.value} ;;'].join('\n    ');
      fake('gh', '''
case " \$* " in
  *"run list"*) echo "$list" ;;
  *"run view"*) case " \$* " in
    $cases
  esac ;;
esac
''');
    }

    test('Fehlgeschlagener Windows-Job blockiert nicht, es zählt der Linux-Job', () {
      runs('101', {'101': 'success'});
      final r = run(['desktop-run', 'app-v1.0.0+1']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect('${r.stdout}'.trim(), '101');
    });

    test('Neuester Lauf mit erfolgreichem Linux-Job', () {
      runs('103\n102\n101', {'103': 'failure', '102': 'success', '101': 'success'});
      expect('${run(['desktop-run', 'app-v1.0.0+1']).stdout}'.trim(), '102');
    });

    test('Ohne erfolgreichen Linux-Job kein Lauf', () {
      runs('103', {'103': 'failure'});
      expect('${run(['desktop-run', 'app-v1.0.0+1']).stdout}'.trim(), isEmpty);
    });
  });

  test('CI baut Windows fürs Tag mit Kaufweg', () {
    final ci = File('.github/workflows/ci.yml').readAsStringSync();
    expect(ci, contains('--dart-define=WINDOWS_SHOP=true'));
    expect(ci, isNot(contains('PLAN_OPEN')));
  });
}
