import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../knx/knx_tunnel.dart';
import '../model/sound_ack.dart';
import '../monitor_model.dart';

/// Channel to ios/Runner/KnxNative.swift (Android: MainActivity.kt, only the methods that say so
/// explicitly). Otherwise without effect.
abstract final class NativeBridge {
  static const _channel = MethodChannel('knx/native');

  static bool get available => !kIsWeb && Platform.isIOS;

  static Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    if (!available) return null;
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      debugPrint('KnxNative.$method: ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<int?> beginBackgroundTask() => _call<int>('beginBackgroundTask');
  static Future<void> endBackgroundTask(int id) => _call<void>('endBackgroundTask', {'id': id});

  /// Notifications (watchers, alarms): iOS and Android.
  static Future<void> notifyPermission() => _notifyCall('notifyPermission');
  static Future<void> notify({required String id, required String title, required String body, bool silent = false}) =>
      _notifyCall('notify', {'id': id, 'title': title, 'body': body, 'silent': silent});

  static Future<void> _notifyCall(String method, [Map<String, Object?>? args]) async {
    if (kIsWeb) return;
    if (Platform.isIOS) return _call<void>(method, args);
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<Object?>(method, args);
    } on Object catch (e) {
      debugPrint('KnxNative.$method: $e');
    }
  }

  /// Join the KNX box's Wi-Fi (iOS and Android 10+): `joined`, `denied`, `unsupported` (other
  /// platforms; then by hand) or `error: …`.
  static Future<String> joinWifi(String ssid, String password) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('joinWifi', {'ssid': ssid, 'password': password}) ?? 'error';
    } on PlatformException catch (e) {
      return 'error: ${e.message}';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  /// Short beep for the watcher, with vibration ([vibrate], where available) via `alertSound`,
  /// without via `alertSoundQuiet`. Native on iOS, Android and macOS; otherwise (or without the
  /// method in the native part) Flutter's system sound.
  static Future<void> alertSound({bool vibrate = true}) async {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      try {
        await _channel.invokeMethod<void>(vibrate ? 'alertSound' : 'alertSoundQuiet');
        return;
      } on Object {
        // Old build without the method: system sound.
      }
    }
    await SystemSound.play(SystemSoundType.alert);
  }

  /// Short acknowledgement tone of the sound feedback, different depending on [sound]. Native on
  /// iOS, Android and macOS (without vibration, which would be too much for every push button –
  /// only for a foreign source); otherwise Flutter's system sound.
  static void ackSound(AckSound sound) {
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      _channel.invokeMethod<void>('ackSound', {'kind': sound.name}).catchError((Object _) {
        unawaited(SystemSound.play(SystemSoundType.click));
      });
      return;
    }
    unawaited(SystemSound.play(sound == AckSound.foreign ? SystemSoundType.alert : SystemSoundType.click));
  }

  /// Android 13+: ask for notifications once before the foreground service starts (otherwise its
  /// notification would stay invisible). Other platforms: nothing.
  static Future<void> androidNotifyPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('notifyPermission');
    } on Object catch (e) {
      debugPrint('Mitteilungen: $e');
    }
  }

  /// Android: foreground service with a notification so the app keeps listening while the screen is
  /// locked (sound feedback). Other platforms: nothing.
  static Future<void> listenInBackground(bool on, {String title = '', String text = ''}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('listenInBackground', {'on': on, 'title': title, 'text': text});
    } on Object catch (e) {
      debugPrint('Vordergrunddienst: $e');
    }
  }

  /// Keep the screen awake while a watcher is armed and the monitor is open (iPhone, iPad,
  /// Android). No silent audio – display on only.
  static Future<void> keepAwake(bool on) async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) return;
    try {
      await _channel.invokeMethod<void>('keepAwake', {'on': on});
    } on Object {
      // not supported
    }
  }

  /// Release the binding to the box Wi-Fi (Android), e.g. when leaving the box.
  static Future<void> leaveWifi() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('leaveWifi');
    } on Object {
      // nothing bound
    }
  }
}

/// Background behaviour of the monitor on iOS: when moving to the background the tunnel stays up
/// for ~25 s and is then cleanly disconnected so no tunnel stays blocked on the gateway. On return
/// the monitor reconnects.
class BackgroundController {
  BackgroundController(this.model);

  static const _grace = Duration(seconds: 25);

  final MonitorModel model;

  int? _task;
  Timer? _graceTimer;

  KnxTunnel get _tunnel => model.tunnel;

  /// The app goes to the background.
  Future<void> onBackground() async {
    // In the browser (add-on) and on the desktop the tunnel simply keeps running; a minimised
    // window should keep recording.
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid) || _task != null) return;
    // Sound feedback on Android: the foreground service holds the connection.
    if (Platform.isAndroid && SoundAck.instance.active) return;
    _task = await NativeBridge.beginBackgroundTask();
    _graceTimer = Timer(_grace, () async {
      await _tunnel.disconnect(); // release the tunnel on the gateway
      _endTask();
    });
  }

  /// The app is back in the foreground.
  void onForeground() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _endTask();
  }

  void _endTask() {
    final id = _task;
    _task = null;
    if (id != null) NativeBridge.endBackgroundTask(id);
  }

  void dispose() => onForeground();
}
