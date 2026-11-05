import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/app_lock.dart';
import 'package:knx_monitor/platform/key_vault.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements KeyVault {
  final data = <String, String>{};
  bool broken = false;

  @override
  Future<String?> read(String key) async {
    if (broken) throw StateError('kein Schlüsselbund');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (broken) throw StateError('kein Schlüsselbund');
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
}

class _Auth implements LockAuthenticator {
  bool isSupported = true;
  bool answer = true;

  @override
  Future<bool> supported() async => isSupported;

  bool gone = false;

  @override
  Future<bool> surelyGone() async => gone;

  @override
  Future<bool> authenticate(String reason) async => answer;
}

/// Ein gültiger Hash; ihn erzeugt eine eigene Sperre mit eigenem Schlüsselbund.
Future<String> _hashOf(String password) async {
  final vault = _Vault();
  final lock = AppLock(authenticator: _Auth(), vault: vault);
  await lock.enablePassword(password);
  return vault.data['app_lock_password']!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Vault vault;
  late _Auth auth;
  late DateTime now;
  late AppLock lock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLock.iterations = 10;
    AppLock.failDelay = Duration.zero;
    vault = _Vault();
    auth = _Auth();
    now = DateTime(2026, 10, 30, 12);
    lock = AppLock(authenticator: auth, vault: vault, clock: () => now);
  });

  test('ohne Einrichtung bleibt die App offen', () async {
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.locked, isFalse);
  });

  test('eingerichtet ist die App nach dem Start gesperrt', () async {
    await lock.load();
    await lock.enablePassword('geheim1');
    final next = AppLock(authenticator: auth, vault: vault, clock: () => now);
    await next.load();
    expect(next.locked, isTrue);
    expect(next.mode, AppLockMode.password);
  });

  test('das Passwort liegt nur als Hash im Schlüsselbund', () async {
    await lock.enablePassword('geheim1');
    expect(vault.data['app_lock_password'], isNot(contains('geheim1')));
    expect(vault.data['app_lock_password'], startsWith('v1:10:'));
    expect(vault.data.toString(), isNot(contains('geheim1')));
  });

  test('falsches Passwort entsperrt nicht, richtiges schon', () async {
    await lock.enablePassword('geheim1');
    await lock.load();
    expect(await lock.unlockWithPassword('falsch'), isFalse);
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithPassword('geheim1'), isTrue);
    expect(lock.locked, isFalse);
  });

  test('nach vielen Fehlversuchen zählt auch das richtige Passwort erst später', () async {
    await lock.enablePassword('geheim1');
    await lock.load();
    for (var i = 0; i < 5; i++) {
      await lock.unlockWithPassword('falsch');
    }
    expect(lock.waitUntil, now.add(const Duration(seconds: 30)));
    expect(await lock.unlockWithPassword('geheim1'), isFalse);
    now = now.add(const Duration(seconds: 31));
    expect(await lock.unlockWithPassword('geheim1'), isTrue);
    expect(lock.waitUntil, isNull);
  });

  test('Fehlversuche überstehen einen Neustart', () async {
    await lock.enablePassword('geheim1');
    await lock.load();
    for (var i = 0; i < 4; i++) {
      await lock.unlockWithPassword('falsch');
    }
    final next = AppLock(authenticator: auth, vault: vault, clock: () => now);
    await next.load();
    await next.unlockWithPassword('falsch');
    expect(next.waitUntil, isNotNull);
  });

  group('Uhr vorgestellt', () {
    late Duration elapsed;
    AppLock withClocks() => AppLock(authenticator: auth, vault: vault, clock: () => now, elapsed: () => elapsed);

    setUp(() => elapsed = const Duration(minutes: 3));

    test('Wartezeit läuft auf der monotonen Uhr weiter', () async {
      lock = withClocks();
      await lock.enablePassword('geheim1');
      await lock.load();
      for (var i = 0; i < 5; i++) {
        await lock.unlockWithPassword('falsch');
      }
      now = now.add(const Duration(days: 1));
      expect(await lock.unlockWithPassword('geheim1'), isFalse, reason: 'nur die Uhr wurde verstellt');
      expect(lock.waitUntil, now.add(const Duration(seconds: 30)));
      elapsed += const Duration(seconds: 31);
      expect(await lock.unlockWithPassword('geheim1'), isTrue);
      expect(lock.waitUntil, isNull);
    });

    test('nach dem Neustart gilt der Rest der gespeicherten Wartezeit auch monoton', () async {
      lock = withClocks();
      await lock.enablePassword('geheim1');
      await lock.load();
      for (var i = 0; i < 5; i++) {
        await lock.unlockWithPassword('falsch');
      }
      elapsed = Duration.zero; // neuer Prozess
      final next = withClocks();
      await next.load();
      now = now.add(const Duration(hours: 1));
      expect(await next.unlockWithPassword('geheim1'), isFalse);
      elapsed += const Duration(seconds: 31);
      expect(await next.unlockWithPassword('geheim1'), isTrue);
    });

    test('nach zehn Fehlversuchen erst nach einem Neustart weiter', () async {
      lock = withClocks();
      await lock.enablePassword('geheim1');
      await lock.load();
      for (var i = 0; i < AppLock.maxFailsPerRun; i++) {
        expect(lock.restartRequired, isFalse);
        await lock.unlockWithPassword('falsch');
        elapsed += const Duration(hours: 1);
        now = now.add(const Duration(hours: 1));
      }
      expect(lock.restartRequired, isTrue);
      expect(await lock.unlockWithPassword('geheim1'), isFalse);
      expect(await lock.unlockWithRecovery('egal'), isFalse);
      final next = withClocks();
      await next.load();
      expect(next.restartRequired, isFalse);
      expect(await next.unlockWithPassword('geheim1'), isTrue);
    });

    test('jeder Fehlversuch dauert mindestens die feste Pause', () async {
      AppLock.failDelay = const Duration(milliseconds: 200);
      lock = withClocks();
      await lock.enablePassword('geheim1');
      await lock.load();
      final watch = Stopwatch()..start();
      await lock.unlockWithPassword('falsch');
      expect(watch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 200)));
      watch.reset();
      expect(await lock.unlockWithPassword('geheim1'), isTrue);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 200)), reason: 'richtiges Passwort ohne Pause');
    });
  });

  test('Wartezeit wächst und endet bei 15 Minuten', () {
    expect(AppLock.waitAfter(4), Duration.zero);
    expect(AppLock.waitAfter(5), const Duration(seconds: 30));
    expect(AppLock.waitAfter(6), const Duration(minutes: 1));
    expect(AppLock.waitAfter(50), const Duration(minutes: 15));
  });

  test('Gerätesperre muss beim Einschalten einmal klappen', () async {
    auth.answer = false;
    expect(await lock.enableSystem('x'), isFalse);
    expect(lock.enabled, isFalse);
    auth.answer = true;
    expect(await lock.enableSystem('x'), isTrue);
    expect(lock.mode, AppLockMode.system);
  });

  test('gescheiterte Gerätesperre entsperrt nicht', () async {
    await lock.enableSystem('x');
    await lock.load();
    auth.answer = false;
    expect(await lock.unlockWithSystem('x'), isFalse);
    expect(lock.locked, isTrue);
  });

  test('sperrt erst nach Ablauf der Frist im Hintergrund', () async {
    await lock.enableSystem('x');
    await lock.setTimeout(5);
    lock.changedLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4));
    lock.changedLifecycle(AppLifecycleState.resumed);
    expect(lock.locked, isFalse);
    lock.changedLifecycle(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 5));
    lock.changedLifecycle(AppLifecycleState.resumed);
    expect(lock.locked, isTrue);
  });

  test('Frist „sofort“ sperrt bei jedem Verlassen', () async {
    await lock.enableSystem('x');
    await lock.setTimeout(0);
    lock.changedLifecycle(AppLifecycleState.inactive);
    lock.changedLifecycle(AppLifecycleState.resumed);
    expect(lock.locked, isTrue);
  });

  test('Betrieb verlangt die Sperre und hält sie an', () async {
    lock.required = true;
    expect(lock.needsSetup, isTrue);
    await lock.enablePassword('geheim1');
    expect(lock.needsSetup, isFalse);
    await lock.disable();
    expect(lock.enabled, isTrue);
    lock.required = false;
    await lock.disable();
    expect(lock.enabled, isFalse);
    expect(vault.data, isEmpty);
  });

  test('ohne Schlüsselbund geht das Passwort trotzdem und zählt nicht als Fehlversuch', () async {
    vault.broken = true;
    await lock.enablePassword('geheim1');
    await lock.load();
    expect(await lock.unlockWithPassword('geheim1'), isTrue);
  });

  test('gestörter Schlüsselbund beim Prüfen sperrt nicht aus', () async {
    await lock.enablePassword('geheim1');
    await lock.load();
    vault.broken = true;
    for (var i = 0; i < 8; i++) {
      expect(await lock.unlockWithPassword('geheim1'), isFalse);
    }
    expect(lock.waitUntil, isNull);
    vault.broken = false;
    expect(await lock.unlockWithPassword('geheim1'), isTrue);
  });

  group('Schlüsselbund geht vor', () {
    AppLock fresh() => AppLock(authenticator: auth, vault: vault, clock: () => now);

    test('Einstellungen gelöscht: bleibt gesperrt', () async {
      await lock.load();
      await lock.enablePassword('geheim1');
      SharedPreferences.setMockInitialValues({});
      final next = fresh();
      await next.load();
      expect(next.enabled, isTrue);
      expect(next.locked, isTrue);
      expect(next.mode, AppLockMode.password);
    });

    test('Einstellungen sagen aus oder Gerätesperre: ändert nichts', () async {
      await lock.load();
      await lock.enablePassword('geheim1');
      SharedPreferences.setMockInitialValues({'app_lock_enabled': false, 'app_lock_mode': 'system'});
      final next = fresh();
      await next.load();
      expect(next.enabled, isTrue);
      expect(next.mode, AppLockMode.password);
    });

    test('eingeschmuggelter Hash in den Einstellungen zählt nicht', () async {
      await lock.load();
      await lock.enablePassword('geheim1');
      final hash = await _hashOf('angreifer');
      SharedPreferences.setMockInitialValues({'app_lock_password_fallback': hash});
      final next = fresh();
      await next.load();
      expect(await next.unlockWithPassword('angreifer'), isFalse);
      expect(await next.unlockWithPassword('geheim1'), isTrue);
    });

    test('auch wenn der Hash im Schlüsselbund fehlt, aber der Stand dort steht', () async {
      await lock.load();
      await lock.enableSystem('x');
      final hash = await _hashOf('angreifer');
      SharedPreferences.setMockInitialValues({'app_lock_password_fallback': hash});
      final next = fresh();
      await next.load();
      expect(await next.checkPassword('angreifer'), isFalse);
    });

    test('Bestand: Hash im Schlüsselbund, Einstellungen leer: Sperre an und übernommen', () async {
      vault.data['app_lock_password'] = await _hashOf('geheim1');
      final next = fresh();
      await next.load();
      expect(next.enabled, isTrue);
      expect(vault.data, contains('app_lock_state'));
      expect(await next.unlockWithPassword('geheim1'), isTrue);
    });

    test('Fehlversuche und Wartezeit überleben den Neustart', () async {
      await lock.load();
      await lock.enablePassword('geheim1');
      for (var i = 0; i < 5; i++) {
        await lock.unlockWithPassword('falsch');
      }
      expect(lock.waitUntil, isNotNull);
      SharedPreferences.setMockInitialValues({});
      final next = fresh();
      await next.load();
      expect(next.waitUntil, lock.waitUntil);
      expect(await next.unlockWithPassword('geheim1'), isFalse, reason: 'noch in der Wartezeit');
      now = now.add(const Duration(minutes: 1));
      await next.unlockWithPassword('falsch');
      expect(next.waitUntil, now.add(const Duration(seconds: 60)), reason: 'der Zähler lief weiter');
    });

    test('verstellte Uhr: höchstens die längste Wartezeit', () async {
      vault.data['app_lock_state'] =
          '{"enabled":true,"mode":"password","fails":9,"waitUntil":"2099-01-01T00:00:00.000Z"}';
      final next = fresh();
      await next.load();
      expect(next.waitUntil, now.add(const Duration(minutes: 15)));
    });

    test('Schlüsselbund kaputt: nur dann zählen die Einstellungen', () async {
      vault.broken = true;
      SharedPreferences.setMockInitialValues({'app_lock_enabled': true, 'app_lock_mode': 'password'});
      final next = fresh();
      await next.load();
      expect(next.enabled, isTrue);
      expect(next.locked, isTrue);
    });
  });

  group('Ändern nur mit dem bisherigen Zugang', () {
    Future<AppLock> locked() async {
      await lock.load();
      await lock.enablePassword('alt12345');
      final next = AppLock(authenticator: auth, vault: vault, clock: () => now);
      await next.load();
      return next;
    }

    test('Passwort lässt sich nicht einfach ersetzen', () async {
      final next = await locked();
      expect(() => next.enablePassword('neu12345'), throwsStateError);
      expect(await next.enableSystem('x'), isFalse);
      expect(() => next.setRecovery('ABCD'), throwsStateError);
      await next.disable();
      expect(next.enabled, isTrue, reason: 'Abschalten ebenso');
      expect(await next.unlockWithPassword('neu12345'), isFalse);
    });

    test('mit dem alten Passwort geht es, aber nicht ewig', () async {
      final next = await locked();
      expect(await next.checkPassword('alt12345'), isTrue);
      await next.enablePassword('neu12345');
      expect(await next.checkPassword('neu12345'), isTrue);
      now = now.add(const Duration(minutes: 6));
      expect(() => next.enablePassword('dritt1234'), throwsStateError);
    });
  });

  group('App-Umschalter', () {
    test('Vorgabe aus, greift nur mit Sperre, bleibt nach dem Neustart', () async {
      final calls = <bool>[];
      AppLock make() =>
          AppLock(authenticator: auth, vault: vault, clock: () => now, secureScreen: (hide) async => calls.add(hide));
      final a = make();
      await a.load();
      expect(a.hideScreen, isFalse);
      await a.setHideScreen(true);
      expect(calls.last, isFalse, reason: 'ohne Sperre kein Schutz');
      await a.enablePassword('geheim1');
      expect(calls.last, isTrue);
      final b = make();
      await b.load();
      expect(b.hideScreen, isTrue);
      expect(calls.last, isTrue);
      expect(await b.checkPassword('geheim1'), isTrue);
      await b.disable();
      expect(calls.last, isFalse);
    });
  });

  test('Notfallschlüssel öffnet, verlangt ein neues Passwort und gilt nur einmal', () async {
    const code = 'ABCD-EFGH-JKLM-NPQR-STUV-WXYZ';
    await lock.enablePassword('geheim1', recovery: code);
    await lock.load();
    expect(vault.data.values.join(), isNot(contains('ABCD')));
    expect(await lock.unlockWithRecovery('falsch'), isFalse);
    expect(lock.locked, isTrue);
    expect(await lock.unlockWithRecovery('abcd efgh jklm npqr stuv wxyz'), isTrue);
    expect(lock.locked, isFalse);
    expect(lock.needsSetup, isTrue);
    await lock.enablePassword('neu12345', recovery: 'ZZZZ-ZZZZ');
    expect(lock.needsSetup, isFalse);
    await lock.load();
    expect(await lock.unlockWithRecovery(code), isFalse, reason: 'alter Schlüssel verbraucht');
    expect(await lock.unlockWithPassword('geheim1'), isFalse);
    expect(await lock.unlockWithPassword('neu12345'), isTrue);
  });

  test('Fehlversuche beim Notfallschlüssel bremsen wie beim Passwort', () async {
    await lock.enablePassword('geheim1', recovery: 'ABCD');
    await lock.load();
    for (var i = 0; i < 5; i++) {
      await lock.unlockWithRecovery('falsch');
    }
    expect(lock.waitUntil, isNotNull);
    expect(await lock.unlockWithRecovery('ABCD'), isFalse);
  });

  test('Aussetzer beim Nachsehen hebt die Sperre nicht auf, sicheres Fehlen schon', () async {
    SharedPreferences.setMockInitialValues({'app_lock_enabled': true, 'app_lock_mode': 'system'});
    auth
      ..isSupported = false
      ..answer = false;
    await lock.load();
    expect(await lock.unlockWithSystem('test'), isFalse);
    expect(lock.enabled, isTrue);
    auth.gone = true;
    expect(await lock.unlockWithSystem('test'), isTrue);
    expect(lock.enabled, isFalse);
  });
}
