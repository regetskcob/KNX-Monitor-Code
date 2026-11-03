import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knx_monitor/main.dart';
import 'package:knx_monitor/model/box_connection.dart';
import 'package:knx_monitor/model/history_store.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/box_link.dart';

/// App gegen eine echte Box im Netz: koppeln, Anlagen, Verlauf, Tod der Box. Sendet
/// nichts auf den Bus, entfernt Gerätezugang und übernommene Anlagen am Ende wieder.
///   flutter drive --keep-app-running --driver=test_driver/integration_test.dart \
///     --target=integration_test/box_session_test.dart -d macos \
///     --dart-define=BOX_URL=http://192.168.1.83/ --dart-define=BOX_PW=…
const _url = String.fromEnvironment('BOX_URL');
const _password = String.fromEnvironment('BOX_PW');

/// Echte Geräte ohne Verbindung zu flutter drive: Verlauf im Dokumente-Ordner.
Future<void> _logWrites = Future<void>.value();
void _toFile(String line) {
  _logWrites = _logWrites.then((_) async {
    final dir = await getApplicationDocumentsDirectory();
    await File('${dir.path}/testlauf.log').writeAsString('$line\n', mode: FileMode.append, flush: true);
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final originalReport = reportTestException;
  reportTestException = (details, description) {
    _toFile('FAIL $description: ${details.exception}');
    originalReport(details, description);
  };
  tearDownAll(() async {
    _toFile('ENDE');
    await _logWrites;
  });

  void say(String line) {
    // ignore: avoid_print
    print('SESSION $line');
    _toFile('SESSION $line');
  }

  testWidgets('Box', (tester) async {
    runApp(const KnxMonitorApp());
    await tester.pump(const Duration(seconds: 25)); // Laden darf die Kopplung nicht überschreiben.
    final store = InstallationStore.instance;
    // Rest eines abgebrochenen Laufs aufräumen, eine echte Kopplung nicht anfassen.
    if (BoxConnection.instance.saved?.name.startsWith('knx-testsitzung-') ?? false) {
      await BoxConnection.instance.forget();
    }
    expect(BoxConnection.instance.saved, isNull, reason: 'Echte Kopplung vorhanden: nicht anfassen');
    final before = {for (final i in store.list) i.id};
    final activeBefore = store.active.id;
    final deviceName = 'knx-testsitzung-${DateTime.now().millisecondsSinceEpoch}';
    final watch = Stopwatch()..start();
    final link = BoxLink(url: Uri.parse(_url), name: deviceName, password: _password);
    final key = await Addon.pairBox(link, _password, deviceName);
    say('Gekoppelt in ${watch.elapsedMilliseconds} ms');
    final paired = link.paired(key);
    try {
      await BoxConnection.instance.use(paired);
      final info = await Addon.boxInfo();
      say('Box: ${info['version']}, Uhr ${info['clock'] is Map ? (info['clock'] as Map)['source'] : info['clock']}');
      final bus = await Addon.status();
      say('Bus: ${bus['state']} ${bus['mode']}');
      say('Neustarts: ${(await Addon.restarts()).length}');
      await store.syncBox(adopt: true);
      say('Anlagen auf der Box: ${store.boxList.length}, aktiv ${store.boxActive}');
      expect(store.boxList, isNotEmpty);

      final days = await HistoryStore.instance.days(installation: store.boxActive);
      final orphan = await HistoryStore.instance.withoutTime(installation: store.boxActive);
      say('Verlauf: ${days.length} Tage, ohne Uhrzeit ${orphan.length}');
      expect(orphan, isNotEmpty, reason: 'unsynced-Datei aus dem Test');
      expect(days, isNotEmpty);
      final socket = await Addon.openBus();
      say('Busverbindung geöffnet');
      socket.close();

      // Box tot (Adresse nach RFC 5737, gehört nie einem Gerät): Die App darf nicht hängen und die Anlage nicht verlieren.
      await BoxConnection.instance.use(BoxLink(url: Uri.parse('http://192.0.2.1/'), key: key, name: 'tot'));
      watch.reset();
      Object? error;
      try {
        await Addon.status().timeout(const Duration(seconds: 30));
      } on Object catch (e) {
        error = e;
      }
      say('Tote Box: ${watch.elapsedMilliseconds} ms, Fehler ${error.runtimeType}');
      expect(error, isNotNull);
      watch.reset();
      await store.useOnBox(activeBefore).timeout(const Duration(seconds: 60));
      say('Anlage wechseln bei toter Box: ${watch.elapsedMilliseconds} ms, aktiv ${store.active.id == activeBefore}');
      expect(store.active.id, activeBefore);
      await BoxConnection.instance.use(paired);
      await store.syncBox(adopt: false);
      say('Wieder da: ${store.boxList.length} Anlagen');
    } finally {
      try {
        // Falls der Test bei der toten Box abbrach: Der Zugang liegt auf der echten.
        await BoxConnection.instance.use(paired);
        final devices = await Addon.boxDevices();
        for (final d in devices.cast<Map<String, Object?>>()) {
          if (d['name'] == deviceName) await Addon.revokeDevice(d['id']! as String);
        }
      } on Object catch (e) {
        say('Gerätezugang nicht entfernt: $e');
      }
      // Erst abkoppeln: Dann löscht delete nur lokal, nie die Anlagen auf der Box.
      await BoxConnection.instance.forget();
      for (final i in [...store.list]) {
        if (!before.contains(i.id)) await store.delete(i.id);
      }
      if (store.active.id != activeBefore) await store.switchTo(activeBefore);
      await tester.pump(const Duration(seconds: 1));
      say('Aufgeräumt: ${store.list.length} Anlagen');
    }
  });
}
