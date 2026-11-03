import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/app_log.dart';
import 'package:knx_monitor/model/crash_guard.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/connect_screen.dart' show CrashNotice;
import 'package:knx_monitor/ui/server_restarts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryStorage implements AppStorage {
  final files = <String, String>{};
  bool failing = false;

  @override
  Future<String?> read(String path) async {
    if (failing) throw StateError('kaputt');
    return files[path];
  }

  @override
  Future<void> write(String path, String text) async {
    if (failing) throw StateError('kaputt');
    files[path] = text;
  }

  @override
  Future<void> append(String path, String text) async => files[path] = '${files[path] ?? ''}$text';

  @override
  Future<List<StoredFile>> list(String dir) async => const [];

  @override
  Future<void> delete(String path) async => files.remove(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStorage storage;
  final guards = <CrashGuard>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = _MemoryStorage();
    AppLog.instance.clear();
  });

  tearDown(() async {
    for (final g in guards) {
      await g.stop();
    }
    guards.clear();
  });

  Future<CrashGuard> run({Duration flushInterval = const Duration(hours: 1)}) async {
    final guard = CrashGuard(storage: storage, flushInterval: flushInterval);
    guards.add(guard);
    await guard.start(force: true);
    return guard;
  }

  test('erster Start meldet nichts', () async {
    expect((await run()).unclean, isNull);
  });

  test('ohne Ende im Vordergrund meldet der nächste Start', () async {
    await run();
    expect((await run()).unclean, isNotNull);
  });

  test('Hintergrund und sauberes Ende zählen nicht', () async {
    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.detached]) {
      SharedPreferences.setMockInitialValues({});
      final first = await run();
      first.handleState(state);
      await Future<void>.delayed(Duration.zero);
      expect((await run()).unclean, isNull, reason: '$state');
    }
  });

  test('zurück im Vordergrund zählt wieder', () async {
    final first = await run();
    first.handleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    first.handleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect((await run()).unclean, isNotNull);
  });

  test('die letzten Zeilen des Laufs landen im Log des nächsten', () async {
    final first = await run();
    AppLog.instance.add('Fehler kurz vor dem Ende');
    await first.flush();
    expect(storage.files[CrashGuard.logFile], contains('Fehler kurz vor dem Ende'));
    AppLog.instance.clear();
    await run();
    expect(AppLog.instance.lines.join('\n'), contains('Fehler kurz vor dem Ende'));
  });

  test('Fehler in Ablage und Einstellungen verhindern den Start nicht', () async {
    await run();
    storage.failing = true;
    final guard = await run();
    expect(guard.unclean, isNotNull);
    AppLog.instance.add('x');
    await guard.flush();
  });

  test('ohne force bleibt sie im Debug-Betrieb aus', () async {
    final guard = CrashGuard(storage: storage);
    guards.add(guard);
    await guard.start();
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('schreibt nur, wenn neue Zeilen da sind', () async {
    final guard = await run();
    AppLog.instance.add('eins');
    await guard.flush();
    storage.files.remove(CrashGuard.logFile);
    await guard.flush();
    expect(storage.files, isEmpty);
    AppLog.instance.add('zwei');
    await guard.flush();
    expect(storage.files, isNotEmpty);
  });

  Widget app(Widget child) => MaterialApp(
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('de'),
    home: Scaffold(body: child),
  );

  testWidgets('Hinweis führt zum Bericht und sagt, dass nichts gesendet wird', (tester) async {
    var reported = 0;
    var dismissed = 0;
    await tester.pumpWidget(
      app(CrashNotice(time: DateTime(2026, 10, 30, 12), onReport: () => reported++, onDismiss: () => dismissed++)),
    );
    expect(find.text('KNX Monitor wurde unerwartet beendet'), findsOneWidget);
    expect(find.textContaining('Nichts wird automatisch gesendet'), findsOneWidget);
    await tester.tap(find.text('Bericht erstellen'));
    await tester.tap(find.text('Ausblenden'));
    expect((reported, dismissed), (1, 1));
  });

  testWidgets('Neustart des Servers mit Grund und Warnzeichen', (tester) async {
    await tester.pumpWidget(
      app(
        ServerRestartsLine({
          'count': 2,
          'last': {'t': DateTime(2026, 10, 30, 12).millisecondsSinceEpoch, 'reason': 'host'},
        }),
      ),
    );
    expect(find.textContaining('2 unerwartete Neustarts'), findsOneWidget);
    expect(find.textContaining('Stromausfall'), findsOneWidget);
    expect(find.byType(HorizontStatusLine), findsOneWidget);
  });
}
