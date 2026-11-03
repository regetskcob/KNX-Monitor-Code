import 'notify_io.dart' if (dart.library.js_interop) 'notify_web.dart' as impl;

/// Show a notification: locally on iOS, in the Home Assistant add-on as an HA notification (and
/// optionally push via the add-on server). [silent]: without system sound – the app plays its own
/// (watcher).
Future<void> sendNotification({required String id, required String title, required String body, bool silent = false}) =>
    impl.sendNotification(id: id, title: title, body: body, silent: silent);

/// Ask for permission once (iOS only).
Future<void> requestNotificationPermission() => impl.requestNotificationPermission();
