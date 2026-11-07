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
  Future<List<StoredFile>> list(String dir) async {
    if (failing) throw StateError('kaputt');
    return [
      for (final MapEntry(:key, :value) in files.entries)
        if (key.startsWith('$dir/') && !key.substring(dir.length + 1).contains('/'))
          (name: key.substring(dir.length + 1), size: value.length),
    ];
  }

  @override
  Future<void> delete(String path) async {
    if (failing) throw StateError('kaputt');
    files.remove(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryStorage storage;
  final guards = <CrashGuard>[];

  /// Processes that still run; all others have ended.
  late Set<int> running;
  var nextPid = 100;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = _MemoryStorage();
    running = {};
    AppLog.instance.clear();
  });

  tearDown(() async {
    for (final g in guards) {
      await g.stop();
    }
    guards.clear();
  });

  /// A new process starts the app.
  Future<CrashGuard> run({
    Duration flushInterval = const Duration(hours: 1),
    int? pid,
    DateTime Function()? now,
    bool? unknownAlive,
  }) async {
    final guard = CrashGuard(
      storage: storage,
      flushInterval: flushInterval,
      pid: pid ?? nextPid++,
      alive: (id) async => unknownAlive == true ? null : running.contains(id),
      singleProcess: false,
      now: now,
    );
    guards.add(guard);
    await guard.start(force: true);
    return guard;
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('erster Start meldet nichts', () async {
    expect((await run()).unclean, isNull);
  });

  test('ohne Ende im Vordergrund meldet der nächste Start', () async {
    await run();
    final next = await run();
    expect(next.unclean, isNotNull);
    expect(next.consecutive, 1);
  });

  test('Hintergrund und sauberes Ende zählen nicht', () async {
    for (final state in [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.detached]) {
      storage.files.clear();
      final first = await run();
      first.handleState(state);
      await settle();
      expect((await run()).unclean, isNull, reason: '$state');
    }
  });

  test('schneller Wechsel Vordergrund, Hintergrund hinterlässt keine Marke', () async {
    final guard = await run();
    guard.handleState(AppLifecycleState.paused);
    guard.handleState(AppLifecycleState.resumed);
    guard.handleState(AppLifecycleState.paused);
    await settle();
    await settle();
    expect(storage.files.containsKey(guard.markerFile), isFalse);
    guard.handleState(AppLifecycleState.resumed);
    await settle();
    expect(storage.files.containsKey(guard.markerFile), isTrue);
  });

  test('zurück im Vordergrund zählt wieder', () async {
    final first = await run();
    first.handleState(AppLifecycleState.paused);
    await settle();
    first.handleState(AppLifecycleState.resumed);
    await settle();
    expect((await run()).unclean, isNotNull);
  });

  test('die letzten Zeilen des Laufs landen im Log des nächsten', () async {
    final first = await run();
    AppLog.instance.add('Fehler kurz vor dem Ende');
    await first.flush();
    expect(storage.files[first.logFile], contains('Fehler kurz vor dem Ende'));
    AppLog.instance.clear();
    await run();
    expect(AppLog.instance.lines.join('\n'), contains('Fehler kurz vor dem Ende'));
    // Taken over: the file of the ended process is gone.
    expect(storage.files.containsKey(first.logFile), isFalse);
  });

  test('Fehler in Ablage und Einstellungen verhindern den Start nicht', () async {
    await run();
    storage.failing = true;
    final guard = await run();
    expect(guard.unclean, isNull);
    AppLog.instance.add('x');
    await guard.flush();
    guard.handleState(AppLifecycleState.paused);
    await settle();
  });

  test('ohne force bleibt sie im Debug-Betrieb aus', () async {
    final guard = CrashGuard(storage: storage);
    guards.add(guard);
    await guard.start();
    expect(storage.files, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('schreibt nur, wenn neue Zeilen da sind', () async {
    final guard = await run();
    AppLog.instance.add('eins');
    await guard.flush();
    storage.files.remove(guard.logFile);
    await guard.flush();
    expect(storage.files.containsKey(guard.logFile), isFalse);
    AppLog.instance.add('zwei');
    await guard.flush();
    expect(storage.files.containsKey(guard.logFile), isTrue);
  });

  group('mehrere Instanzen', () {
    test('eine laufende zweite Instanz ist kein Absturz', () async {
      final a = await run();
      running.add(a.pid);
      final b = await run();
      expect(b.unclean, isNull);
      expect(storage.files.containsKey(a.markerFile), isTrue, reason: 'Marke von A bleibt');
    });

    test('sauberes Ende der einen löscht die Marke der anderen nicht', () async {
      final a = await run();
      running.add(a.pid);
      final b = await run();
      running.add(b.pid);
      AppLog.instance.add('B kurz vor dem Absturz');
      await b.flush();
      a.handleState(AppLifecycleState.detached);
      await settle();
      expect(storage.files.containsKey(b.markerFile), isTrue);
      // B stürzt ab, A ist sauber beendet.
      running.removeAll({a.pid, b.pid});
      AppLog.instance.clear();
      final c = await run();
      expect(c.unclean, isNotNull);
      expect(AppLog.instance.lines.join('\n'), contains('B kurz vor dem Absturz'));
    });

    test('Marke mit der eigenen Prozess-ID stammt von einem beendeten Lauf', () async {
      final a = await run(pid: 7);
      running.add(7);
      // The id came back: this process cannot have written it.
      final b = await run(pid: a.pid);
      expect(b.unclean, isNotNull);
    });

    test('nicht prüfbar zählt als beendet', () async {
      await run();
      expect((await run(unknownAlive: true)).unclean, isNotNull);
    });

    test('Logs beendeter Prozesse werden aufgeräumt, laufender nicht', () async {
      storage.files['crash/log-5.txt'] = 'alt';
      storage.files['crash/log-6.txt'] = 'läuft';
      running.add(6);
      final guard = await run();
      expect(guard.unclean, isNull);
      expect(storage.files.containsKey('crash/log-5.txt'), isFalse);
      expect(storage.files['crash/log-6.txt'], 'läuft');
    });
  });

  test('alte Marke in den Einstellungen wird übernommen und entfernt', () async {
    final t = DateTime(2026, 11, 6, 14, 32);
    SharedPreferences.setMockInitialValues({CrashGuard.legacyKey: t.millisecondsSinceEpoch});
    storage.files[CrashGuard.legacyLogFile] = 'Zeile vom alten Lauf';
    final guard = await run();
    expect(guard.unclean, t);
    expect(AppLog.instance.lines.join('\n'), contains('Zeile vom alten Lauf'));
    expect((await SharedPreferences.getInstance()).containsKey(CrashGuard.legacyKey), isFalse);
    expect(storage.files.containsKey(CrashGuard.legacyLogFile), isFalse);
  });

  group('mehrmals in Folge', () {
    test('eine zweite Instanz beendet die Folge der laufenden nicht', () async {
      await run();
      await run();
      final a = await run(); // zweiter Absturz in Folge, läuft noch
      expect(a.consecutive, 2);
      running.add(a.pid);
      final b = await run(); // startet daneben, findet keine tote Marke
      expect(b.unclean, isNull);
      running.add(b.pid);
      // A stürzt ab, B läuft weiter: der nächste Start zählt weiter.
      running.remove(a.pid);
      expect((await run()).consecutive, 3);
    });

    test('zählt Abstürze in Folge und hält ab dem dritten das Verbinden an', () async {
      await run();
      expect((await run()).consecutive, 1);
      final second = guards.last;
      expect(second.holdAutoConnect, isFalse);
      await run();
      final third = await run();
      expect(third.consecutive, 3);
      expect(third.holdAutoConnect, isTrue);
      expect(third.afterConnecting, isFalse);
      third.dismiss();
      expect(third.holdAutoConnect, isFalse);
    });

    test('kurz nach dem Verbinden nur, wenn es jedes Mal so war', () async {
      var now = DateTime(2026, 11, 6, 14);
      DateTime clock() => now;
      var guard = await run(now: clock);
      for (var i = 0; i < 3; i++) {
        guard.connected();
        await settle();
        now = now.add(const Duration(minutes: 10));
        guard = await run(now: clock);
      }
      expect(guard.consecutive, 3);
      expect(guard.afterConnecting, isTrue);
      // Länger verbunden, dann Absturz: nicht mehr „kurz nach dem Verbinden“
      // (aber noch kein stabiler Lauf).
      guard.connected();
      await settle();
      now = now.add(const Duration(minutes: 4));
      await guard.flush();
      guard = await run(now: clock);
      expect(guard.consecutive, 4);
      expect(guard.afterConnecting, isFalse);
    });

    test('ein sauberer Start oder ein stabiler Lauf beendet die Folge', () async {
      var now = DateTime(2026, 11, 6, 14);
      DateTime clock() => now;
      await run(now: clock);
      await run(now: clock);
      final stable = await run(now: clock);
      expect(stable.consecutive, 2);
      now = now.add(CrashGuard.stableAfter);
      await stable.flush();
      expect((await run(now: clock)).consecutive, 1);
      final clean = guards.last;
      clean.handleState(AppLifecycleState.paused);
      await settle();
      final after = await run(now: clock);
      expect(after.unclean, isNull);
      expect(after.consecutive, 0);
    });
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
