import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../model/incoming_file.dart';

/// Files the system hands to the app: iOS, macOS and Android via the `knx/native` channel, Windows
/// and Linux as an argument at startup. Nothing in the browser.
///
/// The native side only remembers the address and reads only when the app asks. That way nothing
/// arrives too early on a cold start, and a broken file does not disturb the start: nothing is read
/// before [attach].
class IncomingFiles with WidgetsBindingObserver {
  IncomingFiles._();

  static final instance = IncomingFiles._();
  static const _channel = MethodChannel('knx/native');

  final _gate = IncomingFileGate();
  bool _attached = false;
  String? _startPath;

  static bool get _native => !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid);

  /// Before `runApp`, like [BoxConnection.listen].
  void listen(List<String> args) {
    if (kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows || Platform.isLinux) _startPath = packagePathFromArgs(args);
    if (_native) _channel.setMethodCallHandler(_onNativeCall);
  }

  /// The UI is up: fetch what is waiting and from now on open directly.
  void attach(Future<void> Function(IncomingFile) open) {
    if (kIsWeb) return;
    _attached = true;
    _gate.attach(open);
    unawaited(_fetch());
  }

  Future<Object?> _onNativeCall(MethodCall call) async {
    if (call.method == 'incomingFilesChanged' && _attached) await _fetch();
    return null;
  }

  Future<void> _fetch() async {
    final path = _startPath;
    _startPath = null;
    if (path != null) _gate.add(await readPackagePath(path));
    if (!_native) return;
    try {
      final raw = await _channel.invokeMethod<Object?>('incomingFiles', {'maxBytes': incomingMaxBytes});
      incomingFromNative(raw).forEach(_gate.add);
    } on Object catch (e) {
      debugPrint('Geöffnete Dateien: $e');
    }
  }

  /// On launch via a file, iOS may also send the route. The app knows no routes; the package
  /// arrives via the channel.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async =>
      const {'file', 'content'}.contains(routeInformation.uri.scheme);
}

/// Read a file from Windows or Linux. Never throws.
@visibleForTesting
Future<IncomingFile> readPackagePath(String path, {int maxBytes = incomingMaxBytes}) async {
  try {
    final file = File(path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) return const IncomingRefused(IncomingProblem.unreadable);
    if (stat.size > maxBytes) return const IncomingRefused(IncomingProblem.tooLarge);
    return IncomingBytes(await file.readAsBytes());
  } on Object catch (e) {
    debugPrint('Geöffnete Datei: $e');
    return const IncomingRefused(IncomingProblem.unreadable);
  }
}
