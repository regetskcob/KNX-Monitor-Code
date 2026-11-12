// The app's tunnel decrypts KNX Data Secure itself; the emergency lighting log notes `sec` for a
// result that arrived that way, as the add-on and the box do (issue #6).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx/secure.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/dali_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/dali.dart';
import 'package:knx_monitor/model/dali_log.dart';
import 'package:knx_monitor/model/server_features.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/dali_log_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dali_fakes.dart';
import 'memory_storage.dart';

/// Feeds frames in as an interface would.
class _Rx extends KnxTunnel {
  _Rx() : super('rx');

  void rx(Uint8List cemi) => receiveCemi(cemi);
}

/// L_Data.ind from [source] to [destination] with a 6-byte DPT 245.600 payload.
Uint8List _ind(int source, int destination, String hex) {
  final data = hexBytes(hex);
  return Uint8List.fromList([
    0x29, 0x00, 0xBC, 0xE0, //
    source >> 8, source & 0xFF, destination >> 8, destination & 0xFF,
    1 + data.length, 0x00, 0x80, ...data,
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DaliStore.instance;
  final log = DaliTestLog.instance;
  final result = ga('5/2/16');
  final key = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));
  late _Rx tunnel;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    DaliProfiles.debugSet(const []);
    store.debugReset();
    log.debugReset();
    Commissioning.instance.debugReset();
    ServerFeatures.instance.update(null);
    CatalogStore.instance
      ..overrides = {}
      ..catalog = daliCatalog();
    KeyringStore.instance.dataSecure = DataSecure(groupKeys: {result: key}, sequenceNumbers: {gatewayPa: 0});
    tunnel = _Rx();
  });

  tearDown(() async {
    KeyringStore.instance.dataSecure = null;
    tunnel.dispose();
    await store.flush();
    CatalogStore.instance
      ..overrides = {}
      ..catalog = GroupCatalog.empty;
  });

  /// What the gateway sends: [hex] at [result], secured with the group key or in plain.
  Future<Telegram> receive(String hex, {required bool secured}) async {
    final plain = _ind(gatewayPa, result, hex);
    final sender = DataSecure(groupKeys: {result: key}, sequenceNumbers: const {});
    final frame = secured ? (sender.send(plain, source: gatewayPa)..[0] = 0x29) : plain;
    expect(DataSecure.isSecure(frame), secured);
    final next = tunnel.telegrams.first;
    tunnel.rx(frame);
    return next;
  }

  test('a result decrypted by the tunnel is marked, a plain one is not', () async {
    final secured = await receive('100050005CFF', secured: true);
    expect(secured.data, hexBytes('100050005CFF'));
    expect(arrivedSecure(secured), isTrue);
    // The mark goes with the frame through merging at tap points.
    expect(arrivedSecure(secured.atTap(1, sightings: const [Sighting(0, Duration(milliseconds: 40), 5)])), isTrue);
    // A copy from a file or the history has its own frame: it does not claim to be secure.
    expect(arrivedSecure(Telegram.fromJson(secured.toJson())), isFalse);
    final plain = await receive('100050005CFF', secured: false);
    expect(arrivedSecure(plain), isFalse);
    // Telegrams without a frame share the empty one: never marked.
    expect(arrivedSecure(secured.withValue(data: [1])), isFalse);
  });

  test('the emergency lighting log notes sec; view, CSV and PDF data say "KNX Data Secure"', () async {
    final now = DateTime.now();
    store.observe(await receive('100050005CFF', secured: true));
    final entry = log.entries.single;
    expect(entry.secure, isTrue);
    expect(entry.toJson()['sec'], isTrue);
    expect(EmergencyTest.fromJson(entry.toJson())!.secure, isTrue);
    expect(daliEntryNotes(entry), contains('verschlüsselt empfangen (KNX Data Secure)'));
    final data = EmergencyLogData.collect(
      from: now.subtract(const Duration(days: 1)),
      to: now.add(const Duration(days: 1)),
    );
    // The PDF prints the same row, note included.
    expect(data.rows.single.note, contains('verschlüsselt empfangen (KNX Data Secure)'));
    expect(buildEmergencyCsv(data).trim().split('\r\n').last, contains('verschlüsselt empfangen (KNX Data Secure)'));
  });

  test('a plain result is not marked', () async {
    store.observe(await receive('100050005CFF', secured: false));
    expect(log.entries.single.secure, isFalse);
    expect(log.entries.single.toJson().containsKey('sec'), isFalse);
    expect(daliEntryNotes(log.entries.single), isNot(contains('verschlüsselt empfangen (KNX Data Secure)')));
  });

  for (final (scale, stacked) in [(1.0, false), (2.0, true)]) {
    testWidgets('the view says it in words at the entry; text × $scale: raw value ${stacked ? 'below' : 'beside'}', (
      tester,
    ) async {
      final t = (await tester.runAsync(() => receive('100050005CFF', secured: true)))!;
      store.observe(t);
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: DaliLogScreen(now: () => t.time),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Notlicht 16'));
      await tester.pumpAndSettle();
      final note = find.textContaining('verschlüsselt empfangen (KNX Data Secure)');
      expect(note, findsOneWidget);
      final raw = find.text('100050005CFF');
      expect(raw, findsOneWidget);
      if (stacked) {
        // Under the notes, not a narrow column beside them.
        expect(tester.getTopLeft(raw).dy, greaterThanOrEqualTo(tester.getBottomLeft(note).dy - 1));
        expect(tester.getTopLeft(raw).dx, closeTo(tester.getTopLeft(note).dx, 1));
      } else {
        expect(tester.getTopLeft(raw).dy, lessThan(tester.getTopLeft(note).dy));
        expect(tester.getTopLeft(raw).dx, greaterThan(tester.getTopRight(note).dx - 1));
      }
      // The entry stays inside the sheet, and nothing on the screen behind it overflows.
      expect(tester.getTopRight(raw).dx, lessThanOrEqualTo(400 - 16 + 0.5));
      expect(tester.getTopRight(note).dx, lessThanOrEqualTo(400 - 16 + 0.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(store.flush);
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
