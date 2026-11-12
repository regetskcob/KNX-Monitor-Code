import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/secure/keyring_store.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/company.dart';
import 'package:knx_monitor/model/connection_options.dart';
import 'package:knx_monitor/model/customer.dart';
import 'package:knx_monitor/model/handover.dart';
import 'package:knx_monitor/model/project_states.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/platform/storage_io.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/handover_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A later package for an installation that came by handover: found by key, or for packages from
// before keys by company and installation; never replaced without the question; a failed step
// leaves the installation as it was.

const _key = '0b6a1c1e-7d0e-4f6e-9a55-3f2a9c01be77';
const _secret = 'MTIzNDU2Nzg5MDEyMzQ1Ng==';

GroupCatalog _catalog({bool extended = false}) => GroupCatalog(
  {
    0x0801: GroupInfo(address: 0x0801, name: extended ? 'Licht Küche Insel' : 'Licht Küche', dpt: const Dpt(1, 1)),
    if (!extended) 0x0802: const GroupInfo(address: 0x0802, name: 'Licht Flur'),
    if (extended) 0x0901: const GroupInfo(address: 0x0901, name: 'Markise'),
    if (extended) 0x0902: const GroupInfo(address: 0x0902, name: 'Markise Status'),
  },
  devices: {
    0x1101: const DeviceInfo(address: 0x1101, name: 'Aktor'),
    if (extended) 0x1102: const DeviceInfo(address: 0x1102, name: 'Markisenaktor'),
  },
  projectName: 'Haus Muster',
);

const _keyring = <String, Object?>{
  'project': 'Haus Muster',
  'groupKeys': {'2049': _secret},
  'sequence': {'4353': 5},
  'tunnels': [
    {'address': 0x11F1, 'host': 0x11FF, 'userId': 3, 'password': 'TunnelGeheim'},
  ],
};

HandoverPackage _package(
  String id, {
  String? key = _key,
  bool extended = false,
  String company = 'Elektro Muster',
  String origin = '3f2a9c01be77',
  String name = 'Haus Muster',
  Map<String, Object?>? keyring,
  DateTime? created,
}) => HandoverPackage(
  id: id,
  created: created ?? DateTime(2026, 11, 10),
  installationName: name,
  contact: PackageContact(name: company),
  origin: origin,
  key: key,
  catalog: handoverCatalog(_catalog(extended: extended)),
  gateway: const GatewayRef(host: '192.168.1.22'),
  connection: const {'mode': 'tcp', 'routingAddress': 0x00FE, 'secureUserId': 2},
  keyring: keyring,
);

Future<void> _loadFonts() async {
  const fonts = {
    'Literata': ['Literata-Light.ttf', 'Literata-SemiBold.ttf'],
    'MonaSans': ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf'],
    'MaterialSymbolsSharp': ['MaterialSymbolsSharp-300.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader('packages/horizont/${entry.key}');
    for (final file in entry.value) {
      loader.addFont(rootBundle.load('packages/horizont/fonts/$file'));
    }
    await loader.load();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  final installs = InstallationStore.instance;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('followup');
    AppStorage.instance = IoStorage(dir);
    installs.debugReset();
    CustomerStore.instance.debugReset();
    CompanyStore.instance.debugReset();
    CatalogStore.instance.catalog = GroupCatalog.empty;
    await installs.load();
    await InstallationStore.reloadStores();
    // The customer's device is in use: the first installation is their own.
    await CatalogStore.instance.adopt(_catalog(), name: 'eigen.csv');
  });

  tearDown(() async {
    debugHandoverStep = null;
    CatalogStore.instance.catalog = GroupCatalog.empty;
    HandoverStore.instance.origin = null;
    await dir.delete(recursive: true);
  });

  group('Zuordnung', () {
    test('mit Schlüssel: der Schlüssel entscheidet, auch bei neuem Namen und neuer Firma', () async {
      final first = await applyHandover(_package('a'));
      final later = _package('b', name: 'Haus Muster mit Anbau', company: 'Elektro Muster GmbH');
      final target = await handoverTarget(later);
      expect(target.match, HandoverMatch.followUp);
      expect(target.installation?.id, first.id);
      expect(target.asks, isTrue);
      // Another key is another installation, whatever else is the same.
      final other = await handoverTarget(_package('c', key: '11111111-2222-4333-8444-555555555555'));
      expect(other.match, HandoverMatch.none);
      expect(other.asks, isFalse);
    });

    test('dasselbe Paket noch einmal: dieselbe Anlage, mit Rückfrage', () async {
      final first = await applyHandover(_package('a'));
      final target = await handoverTarget(_package('a'));
      expect(target.match, HandoverMatch.samePackage);
      expect(target.installation?.id, first.id);
      expect(target.asks, isTrue);
    });

    test('ohne Schlüssel: Firma und Anlage beim Elektriker', () async {
      final first = await applyHandover(_package('a', key: null));
      expect((await handoverTarget(_package('b', key: null))).installation?.id, first.id);
      // Firmenname ohne Rücksicht auf Groß- und Kleinschreibung und Leerzeichen.
      expect(
        (await handoverTarget(_package('b', key: null, company: '  elektro  MUSTER '))).installation?.id,
        first.id,
      );
      // Andere Firma mit derselben Anlagen-ID: nicht dieselbe Anlage.
      expect((await handoverTarget(_package('b', key: null, company: 'Andere GmbH'))).match, HandoverMatch.none);
      // Ohne Firmennamen lässt sich nichts zuordnen.
      expect((await handoverTarget(_package('b', key: null, company: ''))).match, HandoverMatch.none);
    });

    test('ohne Schlüssel und mit „default“ als Herkunft: Firma und Anlagenname', () async {
      final first = await applyHandover(_package('a', key: null, origin: 'default'));
      expect((await handoverTarget(_package('b', key: null, origin: 'default'))).installation?.id, first.id);
      expect(
        (await handoverTarget(_package('b', key: null, origin: 'default', name: 'Haus Beispiel'))).match,
        HandoverMatch.none,
        reason: '„default“ heißt jede Box-Anlage',
      );
      // Der Kunde hat die Anlage umbenannt: Der Name aus dem Paket steht in der Herkunft.
      await installs.rename(first.id, 'Unser Haus');
      expect((await handoverTarget(_package('b', key: null, origin: 'default'))).installation?.id, first.id);
    });

    test('altes Paket (ohne Schlüssel), neues mit: gleiche Firma und Anlage genügen', () async {
      final first = await applyHandover(_package('a', key: null));
      final target = await handoverTarget(_package('b'));
      expect(target.match, HandoverMatch.followUp);
      expect(target.installation?.id, first.id);
    });

    test('eine selbst angelegte Anlage ist nie Ziel', () async {
      final mine = installs.active;
      final p = _package('a', key: mine.key, name: mine.name);
      expect((await handoverTarget(p)).match, HandoverMatch.none);
      final copy = await applyHandover(p);
      expect(copy.id, isNot(mine.id));
      expect(CatalogStore.instance.catalog[0x0801]?.name, 'Licht Küche');
    });

    test('Herkunft aus einer älteren App (ohne Anlagenname) bleibt lesbar', () {
      final origin = HandoverOrigin.fromJson({
        'handover': 'a',
        'origin': 'default',
        'contact': {'name': 'Elektro Muster'},
        'created': 0,
      });
      expect(origin.installationName, isNull);
      final i = Installation(id: 'x', name: 'Haus Muster', created: DateTime(2026));
      expect(isFollowUp(_package('b', key: null, origin: 'default'), origin, installation: i), isTrue);
    });
  });

  group('Aktualisieren', () {
    test('was sich ändert', () async {
      final first = await applyHandover(_package('a', keyring: _keyring));
      final changes = await handoverChanges(_package('b', extended: true), first);
      expect(changes.groupsAdded, 2);
      expect(changes.groupsRemoved, 1);
      expect(changes.groupsRenamed, 1);
      expect(changes.devicesAdded, 1);
      expect(changes.devicesRemoved, 0);
      expect(changes.packageHasKeys, isFalse);
      expect(changes.installationHasKeys, isTrue);
      final same = await handoverChanges(_package('c'), first);
      expect(same.groupsChanged, isFalse);
      expect(same.devicesChanged, isFalse);
      // Auch für eine Anlage, die gerade nicht aktiv ist.
      await installs.switchTo(installs.list.firstWhere((i) => i.id != first.id).id);
      final inactive = await handoverChanges(_package('b', extended: true), first);
      expect(inactive.groupsAdded, 2);
      expect(inactive.installationHasKeys, isNull);
    });

    test('Projekt wird ersetzt, die Daten des Kunden bleiben', () async {
      final first = await applyHandover(_package('a'));
      final storage = ScopedStorage(AppStorage.instance, 'installations/${first.id}/');
      await storage.write('history/2026-11.json', '{"verlauf":1}');
      await storage.write('annotations.json', '[{"id":"k1"}]');
      await CustomerStore.instance.saveVisit(
        first.id,
        Visit(id: 'v1', time: DateTime(2026, 11, 11), kind: VisitKind.manual, text: 'eigener Eintrag'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(InstallationStore.scopedKey(first.id, 'chart_last'), 'diagramm');
      await prefs.setStringList(InstallationStore.scopedKey(first.id, 'saved_filters'), ['wächter']);

      final updated = await applyHandover(_package('b', extended: true, name: 'Haus Muster mit Anbau'));
      expect(updated.id, first.id);
      expect(updated.name, 'Haus Muster mit Anbau');
      expect(installs.list.length, 2);
      expect(CatalogStore.instance.catalog[0x0901]?.name, 'Markise');
      expect(CatalogStore.instance.catalog[0x0802], isNull);
      expect(HandoverStore.instance.origin?.handover, 'b');
      expect(await storage.read('history/2026-11.json'), '{"verlauf":1}');
      expect(await storage.read('annotations.json'), '[{"id":"k1"}]');
      expect(CustomerStore.instance.visits(first.id).single.text, 'eigener Eintrag');
      expect(prefs.getString(InstallationStore.scopedKey(first.id, 'chart_last')), 'diagramm');
      expect(prefs.getStringList(InstallationStore.scopedKey(first.id, 'saved_filters')), ['wächter']);
    });

    test('als neue Anlage: die bisherige bleibt, wie sie ist', () async {
      final first = await applyHandover(_package('a'));
      final second = await applyHandover(_package('b', extended: true, created: DateTime(2026, 11, 11)), asNew: true);
      expect(second.id, isNot(first.id));
      expect(installs.list.length, 3);
      expect(installs.byId(first.id)!.key, _key);
      expect(second.key, isNot(_key), reason: 'zwei Anlagen hier teilen keinen Schlüssel');
      expect(CatalogStore.instance.catalog[0x0901]?.name, 'Markise');
      await installs.switchTo(first.id);
      expect(CatalogStore.instance.catalog[0x0802]?.name, 'Licht Flur');
      expect(HandoverStore.instance.origin?.handover, 'a');
      // Ein drittes Paket gehört zu der mit dem jüngeren Paket.
      final target = await handoverTarget(_package('c', created: DateTime(2026, 11, 12)));
      expect(target.match, HandoverMatch.followUp);
      expect(target.installation?.id, second.id);
    });
  });

  group('Fehlgeschlagener Schritt', () {
    for (final step in ['catalog', 'keys', 'connection', 'origin', 'index']) {
      test('Aktualisieren scheitert bei „$step“: Anlage wie vorher', () async {
        final first = await applyHandover(_package('a', keyring: _keyring));
        final mine = installs.list.firstWhere((i) => i.id != first.id);
        await installs.switchTo(mine.id);
        final storage = ScopedStorage(AppStorage.instance, 'installations/${first.id}/');
        final before = {
          // With the project states: a failed update must not leave the state its import added.
          for (final f in [
            'catalog.json',
            projectStatesPath,
            'dpt_overrides.json',
            'name_overrides.json',
            HandoverStore.file,
          ])
            f: await storage.read(f),
        };
        debugHandoverStep = (s) => s == step ? throw StateError('Schritt $s') : null;
        await expectLater(applyHandover(_package('b', extended: true, name: 'Anderer Name')), throwsStateError);
        debugHandoverStep = null;
        expect(installs.active.id, mine.id, reason: 'zurück in der Anlage von vorher');
        expect(installs.list.length, 2);
        expect(installs.byId(first.id)!.name, 'Haus Muster');
        expect(installs.byId(first.id)!.gateway?.host, '192.168.1.22');
        for (final MapEntry(key: file, value: text) in before.entries) {
          expect(await storage.read(file), text, reason: file);
        }
        await installs.switchTo(first.id);
        expect(CatalogStore.instance.catalog[0x0802]?.name, 'Licht Flur');
        expect(CatalogStore.instance.catalog[0x0901], isNull);
        expect(KeyringStore.instance.groupKeyCount, 1);
        expect(KeyringStore.instance.tunnels.single.password, 'TunnelGeheim');
        expect(ConnectionOptions.instance.mode, ConnectionMode.tcp);
        expect(HandoverStore.instance.origin?.handover, 'a');
        // Der nächste Versuch gelingt.
        final updated = await applyHandover(_package('b', extended: true));
        expect(updated.id, first.id);
        expect(CatalogStore.instance.catalog[0x0901]?.name, 'Markise');
        expect(KeyringStore.instance.loaded, isFalse);
      });
    }

    test('neue Anlage scheitert: wieder entfernt, die aktive bleibt', () async {
      final mine = installs.active.id;
      debugHandoverStep = (s) => s == 'origin' ? throw StateError('Schritt $s') : null;
      await expectLater(applyHandover(_package('a', keyring: _keyring)), throwsStateError);
      expect(installs.list.single.id, mine);
      expect(installs.active.id, mine);
      expect(CatalogStore.instance.catalog[0x0801]?.name, 'Licht Küche');
      expect(KeyringStore.instance.loaded, isFalse);
    });
  });

  group('Format bleibt Version 1', () {
    Uint8List zip(Map<String, String> files) {
      final a = Archive();
      for (final MapEntry(:key, :value) in files.entries) {
        final b = utf8.encode(value);
        a.addFile(ArchiveFile(key, b.length, b));
      }
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    test('Paket von vor den Schlüsseln (ohne key, projectNames, connection) öffnet', () async {
      final file = zip({
        'handover.json': jsonEncode({
          'format': handoverFormat,
          'version': 1,
          'id': 'alt1',
          'created': '2026-10-30T12:00:00.000',
          'installation': 'Haus Muster',
          'contact': {'name': 'Elektro Muster'},
          'encrypted': false,
          'hasKeys': false,
          'contents': {'groups': 2, 'devices': 1},
        }),
        'payload.json': jsonEncode({
          'origin': '3f2a9c01be77',
          'catalog': handoverCatalog(_catalog()).toJson(),
          'overrides': <String, Object?>{},
        }),
      });
      final p = await openHandover(file);
      expect(p.key, isNull);
      expect(p.projectNames, isEmpty);
      final first = await applyHandover(p);
      expect(first.name, 'Haus Muster');
      // Das nächste Paket derselben Firma für dieselbe Anlage findet sie.
      expect((await handoverTarget(_package('b'))).installation?.id, first.id);
    });

    test('unbekannte Felder in Kopf und Inhalt stören nicht; die Version bleibt 1', () async {
      final source = ZipDecoder().decodeBytes(_package('a').toFile());
      Map<String, Object?> read(String name) =>
          (jsonDecode(utf8.decode(source.findFile(name)!.content)) as Map).cast<String, Object?>();
      final head = read('handover.json')..['futureField'] = {'x': 1};
      final payload = read('payload.json')..['futureList'] = [1, 2];
      expect(head['version'], 1);
      final p = await openHandover(zip({'handover.json': jsonEncode(head), 'payload.json': jsonEncode(payload)}));
      expect(p.key, _key);
      expect(p.catalog[0x0801]?.name, 'Licht Küche');
    });
  });

  group('Rückfrage', () {
    Widget app(Widget home, {double scale = 1}) => MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

    Widget host(HandoverChanges changes, void Function(HandoverChoice?) result, {bool canSetUpNew = true}) => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => result(
              await showDialog<HandoverChoice>(
                context: context,
                builder: (_) => HandoverUpdateDialog(
                  installation: 'Haus Muster',
                  company: 'Elektro Muster',
                  changes: changes,
                  canSetUpNew: canSetUpNew,
                ),
              ),
            ),
            child: const Text('öffnen'),
          ),
        ),
      ),
    );

    const changes = HandoverChanges(groupsAdded: 2, groupsRemoved: 1, groupsRenamed: 1, devicesAdded: 1);

    testWidgets('nennt Änderungen und was bleibt; beide Wege wählbar', (tester) async {
      HandoverChoice? choice;
      await tester.pumpWidget(app(host(changes, (c) => choice = c)));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('„Haus Muster“ aktualisieren?'), findsOneWidget);
      expect(find.text('Gruppenadressen: 2 neu, 1 entfernt, 1 umbenannt.'), findsOneWidget);
      expect(find.text('Geräte: 1 neu, 0 entfernt, 0 umbenannt.'), findsOneWidget);
      expect(find.textContaining('Dein Verlauf, deine Diagramme, Wächter'), findsOneWidget);
      expect(find.textContaining('keine KNX-Secure-Schlüssel'), findsOneWidget, reason: 'Schlüssel hier unbekannt');
      await tester.tap(find.text('Als neue Anlage einrichten'));
      await tester.pumpAndSettle();
      expect(choice, HandoverChoice.setUpNew);
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diese Anlage aktualisieren'));
      await tester.pumpAndSettle();
      expect(choice, HandoverChoice.update);
    });

    testWidgets('Add-on: keine zweite Anlage; ohne Schlüssel auf beiden Seiten kein Hinweis', (tester) async {
      await tester.pumpWidget(app(host(const HandoverChanges(installationHasKeys: false), (_) {}, canSetUpNew: false)));
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      expect(find.text('Als neue Anlage einrichten'), findsNothing);
      expect(find.text('Adressen und Geräte sind unverändert.'), findsOneWidget);
      expect(find.textContaining('KNX-Secure-Schlüssel'), findsNothing);
    });

    testWidgets('375 pt breit, Textgröße 2.0: kein Überlauf, Knöpfe mindestens 44 pt', (tester) async {
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(host(const HandoverChanges(groupsAdded: 120, devicesRemoved: 12, packageHasKeys: true), (_) {}), scale: 2),
      );
      await tester.tap(find.text('öffnen'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Diese Anlage aktualisieren', 'Als neue Anlage einrichten']) {
        final button = find.ancestor(of: find.text(label), matching: find.bySubtype<ButtonStyleButton>());
        expect(tester.getSize(button).height, greaterThanOrEqualTo(44), reason: label);
      }
    });
  });
}
