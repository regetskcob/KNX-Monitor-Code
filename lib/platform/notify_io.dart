import 'native_bridge.dart';

Future<void> sendNotification({required String id, required String title, required String body, bool silent = false}) =>
    NativeBridge.notify(id: id, title: title, body: body, silent: silent);

Future<void> requestNotificationPermission() => NativeBridge.notifyPermission();
