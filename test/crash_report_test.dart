import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/crash_guard.dart';
import 'package:knx_monitor/model/crash_issue.dart';
import 'package:knx_monitor/model/system_crash_report.dart';
import 'package:knx_monitor/platform/os_info.dart';
import 'package:knx_monitor/platform/process_info_io.dart' show commandMatches, tasklistMatches;
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart' show CrashNotice;
import 'package:knx_monitor/ui/crash_banner.dart';
import 'package:knx_monitor/ui/server_restarts.dart';
import 'package:knx_monitor/ui/support_package_screen.dart' show CrashIssueCard, SystemCrashCard;

/// Shortened from a real macOS 15 report: header line, then the body.
String ips({String proc = 'Busclear', String capture = '2026-11-06 14:32:07.4410 +0100'}) =>
    '${jsonEncode({'app_name': proc, 'timestamp': '2026-11-06 14:32:08.00 +0100', 'app_version': '1.9.9', 'slice_uuid': '1c3a1b0e-0000-4000-8000-000000000000', 'build_version': '42', 'platform': 1, 'bundleID': 'de.regetskcob.knx-monitor', 'share_with_app_devs': 0, 'is_first_party': 0, 'bug_type': '309', 'os_version': 'macOS 15.1 (24B83)', 'roots_installed': 0, 'name': proc, 'incident_id': 'D2A1C5E4-0000-4000-8000-000000000000'})}\n${const JsonEncoder.withIndent('  ').convert({
      'uptime': 86000,
      'procRole': 'Foreground',
      'version': 2,
      'userID': 501,
      'deployVersion': 210,
      'modelCode': 'Mac15,6',
      'coalitionID': 1234,
      'osVersion': {'train': 'macOS 15.1', 'build': '24B83', 'releaseType': 'User'},
      'captureTime': capture,
      'codeSigningMonitor': 1,
      'incident': 'D2A1C5E4-0000-4000-8000-000000000000',
      'pid': 4188,
      'procLaunch': '2026-11-06 14:20:01.0000 +0100',
      'procStartAbsTime': 2000000000,
      'procExitAbsTime': 2100000000,
      'procName': proc,
      'procPath': '/Applications/Busclear.app/Contents/MacOS/Busclear',
      'bundleInfo': {'CFBundleShortVersionString': '1.9.9', 'CFBundleVersion': '42'},
      'parentProc': 'launchd',
      'parentPid': 1,
      'exception': {
        'codes': '0x0000000000000001, 0x0000000000000000',
        'rawCodes': [1, 0],
        'type': 'EXC_BAD_ACCESS',
        'signal': 'SIGSEGV',
        'subtype': 'KERN_INVALID_ADDRESS at 0x0000000000000000',
      },
      'termination': {'flags': 0, 'code': 11, 'namespace': 'SIGNAL', 'indicator': 'Segmentation fault: 11'},
      'vmregioninfo': '0 is not in any region.',
      'faultingThread': 0,
      'threads': [
        {
          'triggered': true,
          'id': 123456,
          'queue': 'com.apple.main-thread',
          'frames': [
            {'imageOffset': 123456, 'symbol': 'flutter::Shell::OnPlatformViewDispatchPointerDataPacket', 'imageIndex': 1},
            {'imageOffset': 2345, 'imageIndex': 0},
          ],
        },
      ],
      'usedImages': [
        {'source': 'P', 'arch': 'arm64', 'base': 4295000000, 'size': 16384, 'uuid': '00000000-0000-4000-8000-000000000001', 'path': '/Applications/Busclear.app/Contents/MacOS/Busclear', 'name': 'Busclear'},
        {'source': 'P', 'arch': 'arm64', 'base': 4300000000, 'size': 40000000, 'uuid': '00000000-0000-4000-8000-000000000002', 'path': '/Users/daniel/Applications/Busclear.app/Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS', 'name': 'FlutterMacOS'},
      ],
    })}';

/// `wevtutil qe Application /f:xml` prints events one after the other.
const windowsXml = '''
<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Application Error' Guid='{a0e9b465-b939-57d7-b27d-95d8e925ff57}'/><EventID>1000</EventID><Version>0</Version><Level>2</Level><Task>100</Task><TimeCreated SystemTime='2026-11-06T13:32:09.1234567Z'/><Computer>BUERO-PC</Computer></System><EventData><Data Name='AppName'>knx_monitor.exe</Data><Data Name='AppVersion'>1.9.9.0</Data><Data Name='AppTimeStamp'>6543a1b2</Data><Data Name='ModuleName'>flutter_windows.dll</Data><Data Name='ModuleVersion'>0.0.0.0</Data><Data Name='ModuleTimeStamp'>65000000</Data><Data Name='ExceptionCode'>c0000005</Data><Data Name='FaultingOffset'>00000000001a2b3c</Data><Data Name='ProcessId'>0x105c</Data><Data Name='ProcessCreationTime'>0x1db30</Data><Data Name='AppPath'>C:\\Users\\daniel\\AppData\\Local\\Busclear\\knx_monitor.exe</Data><Data Name='ModulePath'>C:\\Users\\daniel\\AppData\\Local\\Busclear\\flutter_windows.dll</Data><Data Name='IntegratorReportId'>x</Data><Data Name='PackageFullName'></Data><Data Name='PackageRelativeAppId'></Data></EventData></Event>
<Event xmlns='http://schemas.microsoft.com/win/2004/08/events/event'><System><Provider Name='Application Error'/><EventID>1000</EventID><TimeCreated SystemTime='2026-11-06T13:30:00.0000000Z'/></System><EventData><Data>explorer.exe</Data><Data>10.0</Data><Data>0</Data><Data>ntdll.dll</Data><Data>10.0</Data><Data>0</Data><Data>c0000374</Data></EventData></Event>
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Absturzbericht macOS', () {
    test('liest Art und Modul, keinen Pfad', () {
      final r = SystemCrashReport.parseIps(ips(), executable: 'Busclear')!;
      expect(r.system, 'macOS');
      expect(r.kind, 'EXC_BAD_ACCESS (SIGSEGV)');
      expect(r.module, 'FlutterMacOS');
      expect(r.time, DateTime.utc(2026, 11, 6, 13, 32, 7, 441));
      final json = jsonEncode(r.toJson());
      expect(json, isNot(contains('daniel')));
      expect(json, isNot(contains('/')));
    });

    test('fremde App und kaputte Datei geben nichts', () {
      expect(SystemCrashReport.parseIps(ips(proc: 'Safari'), executable: 'Busclear'), isNull);
      expect(SystemCrashReport.parseIps('kein json'), isNull);
      expect(SystemCrashReport.parseIps('{}\n{}'), isNull);
    });

    test('nimmt den Bericht nahe der letzten Zeit, nicht einen alten', () async {
      final lastSeen = DateTime.utc(2026, 11, 6, 13, 31, 30);
      final finder = SystemCrashFinder(
        platform: TargetPlatform.macOS,
        executable: 'Busclear',
        macFiles: (exe) async => [
          (name: '$exe-2026-11-06-143207.ips', modified: DateTime.utc(2026, 11, 6, 13, 32, 8), read: () async => ips()),
          (
            name: '$exe-2026-11-01-090000.ips',
            modified: DateTime.utc(2026, 11, 1, 8),
            read: () async => ips(capture: '2026-11-01 09:00:00.0000 +0100'),
          ),
        ],
      );
      expect((await finder.find(lastSeen))?.kind, 'EXC_BAD_ACCESS (SIGSEGV)');
      // Am 1.11. gab es keinen passenden Bericht mehr in der Nähe.
      expect(await finder.find(DateTime.utc(2026, 11, 3)), isNull);
    });

    test('ohne Zugriff (Sandbox) und auf Linux kein Bericht', () async {
      final sandboxed = SystemCrashFinder(
        platform: TargetPlatform.macOS,
        executable: 'Busclear',
        macFiles: (_) async => throw const FileSystemExceptionStub(),
      );
      expect(await sandboxed.find(DateTime.now()), isNull);
      expect(
        await SystemCrashFinder(platform: TargetPlatform.linux, executable: 'knx_monitor').find(DateTime.now()),
        isNull,
      );
    });
  });

  group('Absturzbericht Windows', () {
    test('liest Ausnahmecode und Modul der eigenen exe', () {
      final list = SystemCrashReport.parseWindowsEvents(windowsXml, executable: 'KNX_MONITOR.exe');
      expect(list, hasLength(1));
      expect(list.single.kind, 'EXCEPTION_ACCESS_VIOLATION (0xc0000005)');
      expect(list.single.module, 'flutter_windows.dll');
      expect(list.single.time, DateTime.utc(2026, 11, 6, 13, 32, 9, 123, 456));
      expect(jsonEncode(list.single.toJson()), isNot(contains('daniel')));
    });

    test('Finder nimmt den passenden Eintrag', () async {
      final finder = SystemCrashFinder(
        platform: TargetPlatform.windows,
        executable: 'knx_monitor.exe',
        windowsEvents: () async => windowsXml,
      );
      expect((await finder.find(DateTime.utc(2026, 11, 6, 13, 31)))?.module, 'flutter_windows.dll');
      expect(SystemCrashReport.windowsExceptionName('0xE0000001'), '0xe0000001');
      expect(SystemCrashReport.windowsExceptionName('kein code'), isNull);
    });
  });

  group('Prozess läuft noch', () {
    test('ps: macOS mit Pfad, Linux auf 15 Zeichen gekürzt', () {
      expect(commandMatches('/Applications/Busclear.app/Contents/MacOS/Busclear', 'Busclear'), isTrue);
      expect(commandMatches('/usr/bin/vim', 'Busclear'), isFalse);
      expect(commandMatches('knx_monitor', 'knx_monitor'), isTrue);
      expect(commandMatches('knx_monitor_lon', 'knx_monitor_longer_name'), isTrue);
    });

    test('tasklist: gleiche ID, aber andere exe zählt nicht', () {
      expect(
        tasklistMatches('"knx_monitor.exe","4188","Console","1","120.000 K"\r\n', 4188, 'knx_monitor.exe'),
        isTrue,
      );
      expect(tasklistMatches('"notepad.exe","4188","Console","1","12.000 K"\r\n', 4188, 'knx_monitor.exe'), isFalse);
      expect(tasklistMatches('INFO: No tasks are running which match the specified criteria.\r\n', 4188, 'x'), isFalse);
    });
  });

  group('Issue', () {
    test('Adresse enthält nur Version, Plattform, Zeit und Grund', () {
      final uri = crashIssueUrl((
        version: '1.9.9',
        platform: 'macOS 15.1',
        time: '06.11.2026 14:32',
        reason: 'EXC_BAD_ACCESS (SIGSEGV)',
      ));
      expect(uri.host, 'github.com');
      expect(uri.path, '/regetskcob/KNX-Monitor/issues/new');
      expect(uri.queryParameters.keys.toSet(), {'template', 'title', 'version', 'platform', 'time', 'reason'});
      expect(uri.queryParameters['template'], 'crash_report.yml');
      expect(uri.queryParameters['title'], 'Unerwartet beendet: 1.9.9 auf macOS 15.1');
    });

    test('Formular hat Felder mit denselben IDs', () {
      final form = File('tool/public-repo/.github/ISSUE_TEMPLATE/crash_report.yml').readAsStringSync();
      for (final id in ['version', 'platform', 'time', 'reason']) {
        expect(form, contains('id: $id'), reason: id);
      }
    });

    test('Plattform kurz und ohne Kernel-Text', () {
      expect(shortPlatform('macos', 'Version 15.1 (Build 24B83)'), 'macOS 15.1');
      expect(shortPlatform('ios', 'Version 18.1 (Build 22B83)'), 'iOS 18.1');
      expect(shortPlatform('windows', '"Windows 11 Pro" 10.0 (Build 26100)'), 'Windows 11 Pro (Build 26100)');
      expect(shortPlatform('linux', '#1 SMP PREEMPT_DYNAMIC Debian 6.1.115-1'), 'Linux');
      expect(shortPlatform('android', 'Linux 5.10.43 #1 SMP PREEMPT'), 'Android');
    });
  });

  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: Scaffold(body: child),
  );

  group('Gründe', () {
    testWidgets('neue Gründe, Signal und unbekannte Werte', (tester) async {
      await tester.pumpWidget(app(const SizedBox()));
      expect(restartReasonText('oom'), 'Speicher voll');
      expect(restartReasonText('signal', signal: 'SEGV'), 'vom System beendet (SIGSEGV)');
      expect(restartReasonText('signal', signal: 'SIGKILL'), 'vom System beendet (SIGKILL)');
      expect(restartReasonText('signal'), 'vom System beendet');
      expect(restartReasonText('watchdog'), 'Watchdog');
      expect(restartReasonText('etwas-neues'), 'Grund unbekannt');
      expect(restartReasonText(null), 'Grund unbekannt');
    });
  });

  group('Liste der Neustarts', () {
    final t = DateTime(2026, 11, 6, 3, 12);
    testWidgets('Einträge mit Lücke, Version, Grund; Fehlertext nur für Admins', (tester) async {
      await tester.pumpWidget(
        app(
          ServerRestartsPanel(
            box: true,
            load: () async => [
              {
                't': t.subtract(const Duration(days: 8)).millisecondsSinceEpoch,
                'lastSeen': t.subtract(const Duration(days: 8, minutes: 7)).millisecondsSinceEpoch,
                'reason': 'error',
                'version': '1.9.8',
              },
              // Box without RTC: written with the boot clock, before its last sign of life.
              {
                't': DateTime(2026, 1, 1).millisecondsSinceEpoch,
                'lastSeen': t.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
                'reason': 'host',
              },
              {
                't': t.millisecondsSinceEpoch,
                'lastSeen': t.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
                'reason': 'signal',
                'signal': 'KILL',
                'version': '1.9.9',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Neustarts des Servers'), findsOneWidget);
      expect(find.textContaining('systemd startet den Server nach 3 s neu'), findsOneWidget);
      expect(find.text('vom System beendet (SIGKILL)'), findsOneWidget);
      expect(find.textContaining('Lücke 1 min'), findsOneWidget);
      expect(find.textContaining('Lücke 7 min'), findsOneWidget);
      expect(find.textContaining('Lücke unbekannt'), findsOneWidget);
      expect(find.textContaining('Lücke -'), findsNothing, reason: 'keine negative Lücke');
      expect(find.text('Fehlertext nur für Admins sichtbar'), findsOneWidget);
      expect(find.textContaining('Die Gründe kommen von systemd'), findsOneWidget);
    });

    testWidgets('Fehlertext für Admins, Ladefehler ohne Absturz', (tester) async {
      await tester.pumpWidget(
        app(
          ServerRestartsPanel(
            load: () async => [
              {
                't': t.millisecondsSinceEpoch,
                'lastSeen': t.millisecondsSinceEpoch,
                'reason': 'error',
                'error': 'Bad state: kaputt\n#0 main',
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bad state: kaputt'), findsOneWidget);
      expect(find.text('Fehlertext nur für Admins sichtbar'), findsNothing);
      expect(find.textContaining('sobald der Server wieder gestartet ist'), findsOneWidget);

      await tester.pumpWidget(
        app(ServerRestartsPanel(key: UniqueKey(), load: () async => throw StateError('offline'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Die Liste ist gerade nicht abrufbar.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Tipp auf die Statuszeile öffnet die Liste', (tester) async {
      await tester.pumpWidget(
        app(
          ServerRestartsLine({
            'count': 1,
            'last': {'t': t.millisecondsSinceEpoch, 'reason': 'watchdog'},
          }, box: true),
        ),
      );
      expect(find.textContaining('Watchdog'), findsOneWidget);
      await tester.tap(find.byType(ServerRestartsLine));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Neustarts des Servers'), findsOneWidget);
    });
  });

  testWidgets('dritter Absturz in Folge bietet „Ohne Verbinden“', (tester) async {
    var without = 0;
    await tester.pumpWidget(
      app(
        CrashNotice(
          time: DateTime(2026, 11, 6, 14, 32),
          consecutive: 3,
          afterConnecting: true,
          onReport: () {},
          onDismiss: () {},
          onWithoutConnect: () => without++,
        ),
      ),
    );
    expect(find.text('3. unerwartetes Ende in Folge, jedes Mal kurz nach dem Verbinden'), findsOneWidget);
    await tester.tap(find.text('Ohne Verbinden'));
    expect(without, 1);

    await tester.pumpWidget(
      app(CrashNotice(time: DateTime(2026, 11, 6), consecutive: 2, onReport: () {}, onDismiss: () {})),
    );
    expect(find.textContaining('in Folge'), findsNothing);
    expect(find.text('Ohne Verbinden'), findsNothing);
  });

  testWidgets('Banner erscheint nur über der Startseite und schließt sich', (tester) async {
    final guard = _FakeGuard()..crashed = DateTime(2026, 11, 6, 14, 32);
    final routes = PageRouteTracker();
    final navigator = GlobalKey<NavigatorState>();
    DateTime? reported;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        navigatorKey: navigator,
        navigatorObservers: [routes],
        builder: (context, child) =>
            CrashBannerHost(routes: routes, guard: guard, onReport: (t) => reported = t, child: child!),
        home: const Scaffold(body: Text('Start')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CrashBanner), findsNothing);
    unawaited(
      navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Live')))),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Unerwartet beendet am 06.11.2026 14:32'), findsOneWidget);
    await tester.tap(find.text('Ansehen'));
    expect(reported, guard.crashed);
    await tester.tap(find.byType(IconButton));
    await tester.pumpAndSettle();
    expect(find.byType(CrashBanner), findsNothing);
    expect(find.text('Live'), findsOneWidget);
  });

  testWidgets('Öffentlich melden zeigt genau die Felder der Adresse', (tester) async {
    CrashIssue? sent;
    const issue = (version: '1.9.9', platform: 'Android', time: '06.11.2026 14:32', reason: 'unerwartet beendet');
    await tester.pumpWidget(app(CrashIssueCard(issue: issue, onReport: (i) => sent = i)));
    expect(find.text('Öffentlich melden'), findsOneWidget);
    for (final v in ['1.9.9', 'Android', '06.11.2026 14:32', 'unerwartet beendet']) {
      expect(find.text(v), findsOneWidget);
    }
    expect(find.text('Öffnet GitHub im Browser. Das Paket hängst du selbst an.'), findsOneWidget);
    await tester.tap(find.text('Als Issue melden'));
    expect(sent, issue);
  });

  testWidgets('Absturzbericht des Systems mit Häkchen', (tester) async {
    var included = true;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) => SystemCrashCard(
            report: SystemCrashReport(
              system: 'macOS',
              time: DateTime.utc(2026, 11, 6, 13, 32, 7),
              kind: 'EXC_BAD_ACCESS (SIGSEGV)',
              module: 'FlutterMacOS',
            ),
            included: included,
            onChanged: (v) => setState(() => included = v),
          ),
        ),
      ),
    );
    expect(find.text('Absturzbericht von macOS gefunden'), findsOneWidget);
    expect(find.text('FlutterMacOS'), findsOneWidget);
    await tester.tap(find.text('Ins Paket übernehmen'));
    await tester.pump();
    expect(included, isFalse);
  });

  test('Texte gibt es auch auf Englisch', () {
    final en = lookupAppLocalizations(const Locale('en'));
    expect(en.restartReasonOom, 'out of memory');
    expect(en.restartReasonSignalNamed('SIGSEGV'), 'ended by the system (SIGSEGV)');
    expect(en.diagIssueButton, 'Report as issue');
  });
}

class FileSystemExceptionStub implements Exception {
  const FileSystemExceptionStub();
}

class _FakeGuard extends CrashGuard {
  _FakeGuard() : super(singleProcess: true, pid: 1);

  DateTime? crashed;

  @override
  DateTime? get unclean => crashed;

  @override
  void dismiss() {
    crashed = null;
    notifyListeners();
  }
}
