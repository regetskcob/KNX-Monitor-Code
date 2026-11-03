import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/secure/keyring_store.dart';
import '../knx/secure/package_crypto.dart';
import '../platform/key_vault.dart';

/// What unlocks the app: the device lock (Face ID, Touch ID, fingerprint,
/// device passcode, Windows Hello) or a separate app password where none of
/// those exist (Linux, Windows without Hello).
enum AppLockMode { system, password }

/// The system's device lock; an interface so tests can run without it.
abstract interface class LockAuthenticator {
  Future<bool> supported();

  /// There is definitely no device lock anymore. An error while checking does not
  /// count: otherwise a glitch would lift the lock.
  Future<bool> surelyGone();
  Future<bool> authenticate(String reason);
}

class SystemLockAuthenticator implements LockAuthenticator {
  final _auth = LocalAuthentication();

  @override
  Future<bool> supported() async {
    // The plugin does not exist for Linux.
    if (Platform.isLinux) return false;
    try {
      return await _auth.isDeviceSupported();
    } on Object catch (e) {
      debugPrint('App-Sperre: Gerätesperre unbekannt: $e');
      return false;
    }
  }

  @override
  Future<bool> surelyGone() async {
    // Windows also reports "device busy" or "disabled by policy" only as "not available".
    if (Platform.isLinux || Platform.isWindows) return false;
    try {
      return !await _auth.isDeviceSupported();
    } on Object catch (e) {
      debugPrint('App-Sperre: Gerätesperre unbekannt: $e');
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // With fallback to the device passcode; otherwise a failed Face ID (gloves on
      // the construction site) locks the user out permanently.
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } on LocalAuthException catch (e) {
      debugPrint('App-Sperre: ${e.code}');
      return false;
    }
  }
}

/// Locks the UI when the app starts or after it has been in the background for a
/// while. The bus keeps running, alarms keep ringing.
///
/// This protects against someone holding the device and does not replace disk
/// encryption: the files in the app directory are protected by the system
/// (iOS, Android) or by FileVault and BitLocker (Mac, Windows).
class AppLock extends ChangeNotifier with WidgetsBindingObserver {
  AppLock({
    LockAuthenticator? authenticator,
    KeyVault? vault,
    DateTime Function()? clock,
    Future<void> Function(bool hide)? secureScreen,
  }) : _authenticator = authenticator ?? SystemLockAuthenticator(),
       _vault = vault ?? SecureKeyVault(),
       _clock = clock ?? DateTime.now,
       _secureScreen = secureScreen ?? _androidSecureScreen;

  static final instance = AppLock();

  /// Lock state in the keychain: on/off, kind, timeout, failed attempts, wait time.
  /// The settings only keep a copy in case the keychain is missing: deleting or
  /// changing something there does not turn the lock off.
  static const _stateKey = 'app_lock_state';
  static const _enabledKey = 'app_lock_enabled';
  static const _modeKey = 'app_lock_mode';
  static const _timeoutKey = 'app_lock_timeout_min';
  static const _failsKey = 'app_lock_fails';
  static const _waitKey = 'app_lock_wait_until';
  static const _hideKey = 'app_lock_hide_screen';
  static const _hashKey = 'app_lock_password';
  static const _hashFallbackKey = 'app_lock_password_fallback';
  static const _recoveryKey = 'app_lock_recovery';
  static const _recoveryFallbackKey = 'app_lock_recovery_fallback';

  /// Minimum length of the app password.
  static const minPasswordLength = 6;

  /// Selectable timeouts in minutes; 0 = immediately on leaving.
  static const timeouts = [0, 1, 5, 15];

  /// Fixed rounds for tests; otherwise [_calibrate] measures the device.
  @visibleForTesting
  static int? iterations;

  /// How long checking the password may take. 600,000 rounds in Dart took 26
  /// seconds on a Galaxy A14. The hash lives in the keychain and failed attempts
  /// slow things down, so fewer suffice; the backup file leaves the device and stays high.
  static const _target = Duration(milliseconds: 800);
  static const _minRounds = 20000;
  static const _maxRounds = 600000;

  /// The emergency key is random (a good 110 bits); guessing is out of the question.
  static const _recoveryRounds = 2000;

  /// How long a confirmed password stays valid for changes to the lock.
  static const _confirmValid = Duration(minutes: 5);

  /// Longest wait time; anything above that would come from a misset clock.
  static const _maxWait = Duration(minutes: 15);

  static Future<void> _androidSecureScreen(bool hide) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await const MethodChannel('knx/native').invokeMethod<void>('secureScreen', {'enabled': hide});
    } on Object catch (e) {
      debugPrint('App-Sperre: Schutz im App-Umschalter nicht gesetzt: $e');
    }
  }

  static Future<int> _calibrate() async {
    final fixed = iterations;
    if (fixed != null) return fixed;
    const probe = 5000;
    final watch = Stopwatch()..start();
    await compute(_derive, (password: 'probe', salt: Uint8List(16), rounds: probe));
    final rounds = probe * _target.inMicroseconds ~/ max(watch.elapsedMicroseconds, 1);
    return rounds.clamp(_minRounds, _maxRounds);
  }

  final LockAuthenticator _authenticator;
  final KeyVault _vault;
  final DateTime Function() _clock;
  final Future<void> Function(bool hide) _secureScreen;

  bool _enabled = false;
  AppLockMode _mode = AppLockMode.system;
  int _timeout = 5;
  bool _locked = false;
  bool _required = false;
  bool _mustReset = false;
  bool _covered = false;
  bool _prompting = false;
  DateTime? _leftAt;
  DateTime? _waitUntil;
  int _fails = 0;
  bool _observing = false;
  bool _hideScreen = false;

  /// The state is in the keychain; then nothing from the settings counts.
  bool _vaultHolds = false;

  /// Hash is exceptionally stored in the settings (the keychain failed when it was set).
  bool _usesFallback = false;
  DateTime? _confirmedAt;

  /// On the web (add-on, box) there is no lock: access to Home Assistant or the box
  /// decides there.
  bool get available => !kIsWeb;
  bool get enabled => _enabled;
  AppLockMode get mode => _mode;
  int get timeoutMinutes => _timeout;
  bool get locked => _locked;

  /// Whether a company requires the lock. If so, it cannot be turned off.
  bool get required => _required;

  /// Company without a configured lock: set it up first, then continue.
  bool get needsSetup => available && (_required || _mustReset) && !_enabled;

  /// Just opened with the emergency key: new password first, then continue.
  bool get mustReset => _mustReset;

  /// Show nothing in the app switcher (iOS, Android).
  bool get covered => _covered && _enabled;

  /// Show nothing in the Android app switcher and prevent screenshots.
  bool get hideScreen => _hideScreen;

  /// Until when nothing may be tried after too many failed attempts.
  DateTime? get waitUntil => _waitUntil;

  Future<bool> systemSupported() => _authenticator.supported();

  Future<void> load() async {
    if (!available) return;
    final prefs = await SharedPreferences.getInstance();
    // The copy first: if the keychain does not answer within the startup deadline,
    // the lock still holds and the app does not open unlocked.
    _fromPrefs(prefs);
    _locked = _enabled;
    notifyListeners();
    await _loadState(prefs);
    final wait = _waitUntil;
    final latest = _clock().add(_maxWait);
    if (wait != null && wait.isAfter(latest)) _waitUntil = latest;
    _locked = _enabled;
    unawaited(_applySecureScreen());
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    notifyListeners();
  }

  /// Keychain first. Only if it really fails, the settings.
  Future<void> _loadState(SharedPreferences prefs) async {
    try {
      final text = await _vault.read(_stateKey);
      if (text != null && _readState(text)) {
        _vaultHolds = true;
        return;
      }
      // First start with this version or unreadable state: a hash in the keychain
      // means the lock is on, even if the settings no longer know about it.
      if (await _vault.read(_hashKey) != null) {
        _enabled = true;
        _mode = AppLockMode.password;
      }
      if (_enabled) await _persist(prefs);
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht lesbar, Einstellungen genommen: $e');
      _vaultHolds = false;
      _fromPrefs(prefs);
    }
  }

  void _fromPrefs(SharedPreferences prefs) {
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _mode = AppLockMode.values.asNameMap()[prefs.getString(_modeKey)] ?? AppLockMode.system;
    _timeout = prefs.getInt(_timeoutKey) ?? _timeout;
    _fails = prefs.getInt(_failsKey) ?? 0;
    _waitUntil = DateTime.tryParse(prefs.getString(_waitKey) ?? '')?.toLocal();
    _hideScreen = prefs.getBool(_hideKey) ?? false;
  }

  bool _readState(String text) {
    try {
      final j = jsonDecode(text) as Map<String, Object?>;
      _enabled = j['enabled']! as bool;
      _mode = AppLockMode.values.asNameMap()[j['mode']] ?? AppLockMode.system;
      _timeout = j['timeout'] as int? ?? _timeout;
      _fails = j['fails'] as int? ?? 0;
      _waitUntil = DateTime.tryParse(j['waitUntil'] as String? ?? '')?.toLocal();
      _hideScreen = j['hide'] == true;
      _usesFallback = j['fallback'] == true;
      return true;
    } on Object catch (e) {
      debugPrint('App-Sperre: Stand nicht lesbar: $e');
      return false;
    }
  }

  /// Writes the state to the keychain and a copy to the settings.
  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setBool(_enabledKey, _enabled);
    await prefs.setString(_modeKey, _mode.name);
    await prefs.setInt(_timeoutKey, _timeout);
    await prefs.setInt(_failsKey, _fails);
    await prefs.setBool(_hideKey, _hideScreen);
    final wait = _waitUntil;
    if (wait == null) {
      await prefs.remove(_waitKey);
    } else {
      await prefs.setString(_waitKey, wait.toUtc().toIso8601String());
    }
    try {
      // Fully off: nothing remains in the keychain.
      if (!_enabled && !_hideScreen && _fails == 0) {
        await _vault.delete(_stateKey);
        _vaultHolds = false;
        return;
      }
      await _vault.write(
        _stateKey,
        jsonEncode({
          'enabled': _enabled,
          'mode': _mode.name,
          'timeout': _timeout,
          'fails': _fails,
          'waitUntil': wait?.toUtc().toIso8601String(),
          'hide': _hideScreen,
          'fallback': _usesFallback,
        }),
      );
      _vaultHolds = true;
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht nutzbar: $e');
    }
  }

  Future<void> _applySecureScreen() => _secureScreen(_enabled && _hideScreen);

  /// Changes to an active lock only with the existing credentials: otherwise anyone
  /// holding the unlocked device could replace a company's password.
  bool get _mayChange {
    if (!_enabled) return true;
    final at = _confirmedAt;
    return at != null && _clock().difference(at) < _confirmValid;
  }

  void _confirmed() => _confirmedAt = _clock();

  /// Show nothing in the Android app switcher; off by default.
  Future<void> setHideScreen(bool value) async {
    _hideScreen = value;
    await _persist(await SharedPreferences.getInstance());
    await _applySecureScreen();
    notifyListeners();
  }

  set required(bool value) {
    if (_required == value) return;
    _required = value;
    notifyListeners();
  }

  /// Turns on the device lock; it has to succeed once, otherwise the user locks
  /// themselves out.
  Future<bool> enableSystem(String reason) async {
    if (!_mayChange || !await _authenticator.supported() || !await _prompt(reason)) return false;
    await _forgetHash();
    await _store(AppLockMode.system);
    return true;
  }

  /// New emergency key: strong enough that the user does not choose it.
  static String newRecoveryCode() => generatePackagePassword();

  Future<void> enablePassword(String password, {String? recovery}) async {
    if (!_mayChange) throw StateError('App-Sperre: erst mit dem bisherigen Zugang bestätigen');
    await _saveSecret(_hashKey, _hashFallbackKey, await _hash(password));
    if (recovery != null) await setRecovery(recovery);
    await _store(AppLockMode.password);
  }

  /// Only the hash stays on the device; the key itself is in the user's PDF.
  Future<void> setRecovery(String code) async {
    if (!_mayChange) throw StateError('App-Sperre: erst mit dem bisherigen Zugang bestätigen');
    await _saveSecret(
      _recoveryKey,
      _recoveryFallbackKey,
      await _hash(normalizePackagePassword(code), rounds: iterations ?? _recoveryRounds),
    );
  }

  Future<void> _saveSecret(String key, String fallback, String value) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _vault.write(key, value);
      await prefs.remove(fallback);
    } on Object catch (e) {
      // Linux without libsecret: better in the settings than no lock at all.
      // Anyone who can read them can reach the files anyway.
      debugPrint('App-Sperre: Schlüsselbund nicht nutzbar: $e');
      await prefs.setString(fallback, value);
      _usesFallback = true;
    }
  }

  Future<void> _store(AppLockMode mode) async {
    _enabled = true;
    _mustReset = false;
    _mode = mode;
    _locked = false;
    _confirmed();
    await _resetFails(await SharedPreferences.getInstance());
    await _applySecureScreen();
    notifyListeners();
  }

  Future<void> disable() async {
    if (_required || !_mayChange) return;
    await _turnOff();
  }

  Future<void> _turnOff() async {
    await _forgetHash();
    _enabled = false;
    _locked = false;
    _usesFallback = false;
    await _resetFails(await SharedPreferences.getInstance());
    await _applySecureScreen();
    notifyListeners();
  }

  Future<void> _forgetHash() async {
    try {
      await _vault.delete(_hashKey);
      await _vault.delete(_recoveryKey);
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht nutzbar: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashFallbackKey);
    await prefs.remove(_recoveryFallbackKey);
  }

  Future<void> setTimeout(int minutes) async {
    _timeout = minutes;
    await _persist(await SharedPreferences.getInstance());
    notifyListeners();
  }

  /// Unlocks with the device lock.
  Future<bool> unlockWithSystem(String reason) async {
    // Device passcode removed in the meantime: whoever can do that knows it.
    // Otherwise nobody could get into the app and their data anymore.
    if (await _authenticator.surelyGone()) {
      debugPrint('App-Sperre: keine Gerätesperre mehr, Sperre aufgehoben');
      await _turnOff();
      // If the company requires the lock, set up a new one right away.
      _mustReset = _required;
      notifyListeners();
      return true;
    }
    if (!await _prompt(reason)) return false;
    _confirmed();
    _locked = false;
    notifyListeners();
    return true;
  }

  /// Checks the device lock without changing the state (before turning it off).
  Future<bool> confirmSystem(String reason) async {
    final ok = await _prompt(reason);
    if (ok) _confirmed();
    return ok;
  }

  /// Whether the app password is correct. Failed attempts extend the wait time.
  Future<bool> checkPassword(String password) async {
    return _check(password, _hashKey, _hashFallbackKey);
  }

  Future<bool> _check(String secret, String key, String fallback) async {
    final wait = _waitUntil;
    if (wait != null && _clock().isBefore(wait)) return false;
    final prefs = await SharedPreferences.getInstance();
    String? stored;
    try {
      // Keychain first. Nothing from the settings replaces a hash from there,
      // otherwise anyone could set their own password there.
      stored = await _vault.read(key);
      if (stored == null && (!_vaultHolds || _usesFallback)) stored = prefs.getString(fallback);
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht lesbar: $e');
      stored = prefs.getString(fallback);
      // Keychain currently unreachable: not a failed attempt by the user.
      if (stored == null) return false;
    }
    final ok = stored != null && await verifyHash(secret, stored);
    if (ok) {
      _confirmed();
      await _resetFails(prefs);
    } else {
      _fails++;
      final delay = waitAfter(_fails);
      _waitUntil = delay == Duration.zero ? null : _clock().add(delay);
      await _persist(prefs);
    }
    notifyListeners();
    return ok;
  }

  Future<bool> unlockWithPassword(String password) async {
    if (!await checkPassword(password)) return false;
    _locked = false;
    notifyListeners();
    return true;
  }

  /// Password forgotten, emergency key at hand: opens the app and requires a new
  /// password. The old key is no longer valid afterwards.
  Future<bool> unlockWithRecovery(String code) async {
    if (!await _check(normalizePackagePassword(code), _recoveryKey, _recoveryFallbackKey)) return false;
    await _turnOff();
    _mustReset = true;
    notifyListeners();
    return true;
  }

  Future<void> _resetFails(SharedPreferences prefs) async {
    _fails = 0;
    _waitUntil = null;
    await _persist(prefs);
  }

  /// Four free attempts, then 30 s, doubling up to 15 minutes.
  @visibleForTesting
  static Duration waitAfter(int fails) {
    if (fails < 5) return Duration.zero;
    final seconds = 30 * pow(2, min(fails - 5, 5)).toInt();
    return Duration(seconds: min(seconds, 900));
  }

  Future<bool> _prompt(String reason) async {
    _prompting = true;
    try {
      return await _authenticator.authenticate(reason);
    } finally {
      _prompting = false;
      // The system dialog counts as "leaving": do not lock again right away.
      _leftAt = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => changedLifecycle(state);

  @visibleForTesting
  void changedLifecycle(AppLifecycleState state) {
    if (!_enabled || _prompting) return;
    if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      final expired = left != null && _clock().difference(left) >= Duration(minutes: _timeout);
      if (expired) _locked = true;
      _covered = false;
      notifyListeners();
      return;
    }
    // On a phone, "inactive" only means notification center or a system dialog.
    final phone = !kIsWeb && (Platform.isIOS || Platform.isAndroid);
    if (!phone || state != AppLifecycleState.inactive) _leftAt ??= _clock();
    // On desktop the window stays visible (monitor on the second screen).
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      _covered = true;
      notifyListeners();
    }
  }

  /// Password forgotten: there is no way back, otherwise the lock could be
  /// bypassed. Deletes all local data and quits the app; whatever is stored in the
  /// account or company comes back after signing in.
  Future<void> wipeAndExit() async {
    // Like the other entries: on the Mac without the data protection keychain.
    const vault = FlutterSecureStorage(
      aOptions: AndroidOptions(resetOnError: false),
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    );
    try {
      await vault.deleteAll();
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht geleert: $e');
    }
    // deleteAll fails on the Mac (-50): delete what we know one by one. The file key
    // would otherwise remain; without the files it is worthless anyway.
    final stored = <String>{};
    try {
      stored.addAll((await vault.readAll()).keys);
    } on Object catch (e) {
      debugPrint('App-Sperre: Schlüsselbund nicht auflistbar: $e');
    }
    for (final key in {...stored, 'knx_file_key', 'supabase_session', 'box_link', _stateKey, _hashKey, _recoveryKey}) {
      try {
        await vault.delete(key: key);
      } on Object catch (e) {
        debugPrint('App-Sperre: $key nicht gelöscht: $e');
      }
    }
    try {
      await KeyringStore.deleteAllStored();
    } on Object catch (e) {
      debugPrint('App-Sperre: Keyrings nicht gelöscht: $e');
    }
    await (await SharedPreferences.getInstance()).clear();
    final dir = await getApplicationSupportDirectory();
    if (await dir.exists()) {
      await for (final entry in dir.list()) {
        await entry.delete(recursive: true);
      }
    }
    exit(0);
  }

  Future<String> _hash(String password, {int? rounds}) async {
    final r = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
    final used = rounds ?? await _calibrate();
    final hash = await compute(_derive, (password: password, salt: salt, rounds: used));
    return 'v1:$used:${base64Encode(salt)}:${base64Encode(hash)}';
  }

  /// Compares without returning early.
  @visibleForTesting
  static Future<bool> verifyHash(String password, String stored) async {
    final parts = stored.split(':');
    if (parts.length != 4 || parts[0] != 'v1') return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null) return false;
    final expected = base64Decode(parts[3]);
    final actual = await compute(_derive, (password: password, salt: base64Decode(parts[2]), rounds: rounds));
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }
}

Uint8List _derive(({String password, Uint8List salt, int rounds}) a) {
  final kdf = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(a.salt, a.rounds, 32));
  return kdf.process(Uint8List.fromList(utf8.encode(a.password)));
}
