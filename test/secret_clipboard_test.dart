import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/secret_clipboard.dart';

/// Geheimnisse in der Zwischenablage: nach einer Minute wieder weg, fremder Inhalt bleibt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String? clipboard;
  final native = <Map<Object?, Object?>>[];

  setUp(() {
    clipboard = null;
    native.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          clipboard = (call.arguments as Map)['text'] as String?;
        case 'Clipboard.getData':
          return {'text': clipboard};
      }
      return null;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    messenger.setMockMethodCallHandler(const MethodChannel('knx/native'), null);
  });

  const keep = Duration(milliseconds: 50);

  test('wird nach der Frist geleert', () async {
    await copySecret('geheim', keep: keep);
    expect(clipboard, 'geheim');
    await Future<void>.delayed(keep * 3);
    expect(clipboard, '');
  });

  test('inzwischen etwas anderes kopiert: bleibt', () async {
    await copySecret('geheim', keep: keep);
    clipboard = 'eigener Text';
    await Future<void>.delayed(keep * 3);
    expect(clipboard, 'eigener Text');
  });

  test('mit nativem Teil: dort mit Frist, ohne eigenes Leeren', () async {
    // Explicit, instead of relying on flutter test's default platform.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    messenger.setMockMethodCallHandler(const MethodChannel('knx/native'), (call) async {
      native.add(call.arguments as Map<Object?, Object?>);
      return true;
    });
    await copySecret('geheim');
    expect(native.single, {'text': 'geheim', 'seconds': 60});
    expect(clipboard, isNull);
  });
}
