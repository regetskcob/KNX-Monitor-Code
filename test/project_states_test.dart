import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/telegram_files.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/project_states.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

GroupCatalog _project(Map<int, (String, Dpt?)> groups, {String? name, Map<int, String> devices = const {}}) =>
    GroupCatalog(
      {
        for (final MapEntry(:key, :value) in groups.entries)
          key: GroupInfo(address: key, name: value.$1, dpt: value.$2, path: 'Licht'),
      },
      devices: {for (final MapEntry(:key, :value) in devices.entries) key: DeviceInfo(address: key, name: value)},
      projectName: name,
    );

Telegram _telegram(DateTime time, {int destination = 0x0801, List<int> data = const [1], bool small = true}) =>
    Telegram(
      time: time,
      source: 0x1101,
      destination: destination,
      type: TelegramType.write,
      data: Uint8List.fromList(data),
      isSmall: small,
    );

final _old = _project(
  {0x0801: ('Licht Küche', const Dpt(1, 1)), 0x0802: ('Licht Flur', const Dpt(1, 1)), 0x0803: ('Alt', null)},
  name: 'Haus 2024',
  devices: {0x1101: 'Aktor alt'},
);
final _new = _project(
  {
    0x0801: ('Temperatur Küche', const Dpt(9, 1)),
    0x0802: ('Licht Flur', const Dpt(1, 1)),
    0x0804: ('Neu', const Dpt(1, 1)),
  },
  name: 'Haus 2026',
  devices: {0x1101: 'Aktor neu'},
);

void main() {
  group('ProjectStates', () {
    test('first project counts from the beginning, no second state', () {
      final states = ProjectStates();
      expect(states.push(GroupCatalog.empty, _old, at: DateTime(2026, 3), name: 'a.knxproj'), isTrue);
      expect(states.states, hasLength(1));
      expect(states.hasPast, isFalse);
      expect(states.states.single.from, isNull);
      expect(states.indexAt(DateTime(2000)), 0);
    });

    test('an installation from before states keeps its project from the beginning', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6), name: 'b.knxproj');
      expect(states.states, hasLength(2));
      expect(states.states.first.from, isNull);
      expect(states.states.last.from, DateTime(2026, 6));
      final back = states.catalogOf(0, _new);
      expect(jsonEncode(back.toJson()['groups']), jsonEncode(_old.toJson()['groups']));
      expect(back.devices[0x1101]!.name, 'Aktor alt');
      expect(back.projectName, 'Haus 2024');
    });

    test('lookup by time: before the first, at the boundary, after the last', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6));
      final third = _project({0x0801: ('Dritter', null)});
      states.push(_new, third, at: DateTime(2026, 9));
      expect(states.indexAt(DateTime(1999)), 0);
      expect(states.indexAt(DateTime(2026, 6).subtract(const Duration(microseconds: 1))), 0);
      expect(states.indexAt(DateTime(2026, 6)), 1, reason: 'a state is valid from its start, inclusive');
      expect(states.indexAt(DateTime(2026, 8, 31)), 1);
      expect(states.indexAt(DateTime(2026, 9)), 2);
      expect(states.indexAt(DateTime(2040)), 2);
      expect(states.catalogOf(1, third)[0x0801]!.name, 'Temperatur Küche');
      expect(states.catalogOf(0, third)[0x0801]!.name, 'Licht Küche');
    });

    test('changes against the state before: added, removed, renamed, retyped', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6));
      final c = states.changesOf(1, _new);
      expect([for (final g in c.added) g.address], [0x0804]);
      expect([for (final g in c.removed) g.address], [0x0803]);
      expect(c.renamed.single.before.name, 'Licht Küche');
      expect(c.renamed.single.after.name, 'Temperatur Küche');
      expect(c.retyped.single.after.dpt, const Dpt(9, 1));
      expect(states.changesOf(0, _new).isEmpty, isTrue);
    });

    test('the same project again adds no state', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6));
      expect(states.push(_new, _new, at: DateTime(2026, 7), name: 'again.knxproj'), isFalse);
      expect(states.states, hasLength(2));
      expect(states.states.last.name, 'again.knxproj');
      expect(states.states.last.from, DateTime(2026, 6));
    });

    test('bounded: older states are merged into the oldest', () {
      final states = ProjectStates();
      var current = _project({1: ('v0', null)});
      for (var i = 1; i <= 30; i++) {
        final next = _project({1: ('v$i', null), 100 + i: ('nur $i', null)});
        states.push(current, next, at: DateTime(2026, 1, i));
        current = next;
      }
      expect(states.states, hasLength(maxProjectStates));
      expect(states.states.first.from, isNull, reason: 'the oldest kept state counts from the beginning');
      // 30 states were pushed after v0: the 12 newest stay, v19 … v30.
      expect(states.catalogOf(0, current)[1]!.name, 'v19');
      expect(states.indexAt(DateTime(2026, 1, 5)), 0);
      expect(states.catalogOf(states.indexAt(DateTime(2026, 1, 25, 12)), current)[1]!.name, 'v25');
      expect(states.catalogOf(maxProjectStates - 1, current)[1]!.name, 'v30');
    });

    test('json round trip keeps states and deltas', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6), name: 'b.knxproj');
      final read = ProjectStates.fromJson(jsonDecode(jsonEncode(states.toJson())) as Map<String, Object?>);
      expect(read.states, hasLength(2));
      expect(read.states.last.name, 'b.knxproj');
      expect(read.catalogOf(0, _new)[0x0803]!.name, 'Alt');
      expect(read.catalogOf(0, _new)[0x0804], isNull);
      expect(read.catalogOf(0, _new)[0x0801]!.dpt, const Dpt(1, 1));
    });

    test('states out of order are refused', () {
      expect(
        () => ProjectStates.fromJson({
          'states': [
            {'from': 20, 'g': <String, Object?>{}, 'd': <String, Object?>{}},
            {'from': 10},
          ],
        }),
        throwsFormatException,
      );
    });

    test('date only between the neighbours', () {
      final states = ProjectStates();
      states.push(_old, _new, at: DateTime(2026, 6));
      final third = _project({0x0801: ('Dritter', null)});
      states.push(_new, third, at: DateTime(2026, 9));
      expect(states.setFrom(0, DateTime(2020)), isFalse, reason: 'the oldest counts from the beginning');
      expect(states.setFrom(1, DateTime(2026, 9)), isFalse);
      expect(states.setFrom(1, DateTime(2026, 10)), isFalse);
      expect(states.setFrom(1, DateTime(2026, 5, 20)), isTrue);
      expect(states.setFrom(2, DateTime(2026, 5, 20)), isFalse);
      expect(states.setFrom(2, DateTime(2026, 8)), isTrue);
      expect(states.indexAt(DateTime(2026, 5, 25)), 1);
    });

    test('removing a state: oldest, middle, current', () {
      ProjectStates three() => ProjectStates()
        ..push(_old, _new, at: DateTime(2026, 6))
        ..push(_new, _project({0x0801: ('Dritter', null)}), at: DateTime(2026, 9));
      final third = _project({0x0801: ('Dritter', null)});

      final a = three();
      expect(a.remove(0, third), isNull);
      expect(a.states, hasLength(2));
      expect(a.states.first.from, isNull);
      expect(a.catalogOf(0, third)[0x0801]!.name, 'Temperatur Küche');

      final b = three();
      expect(b.remove(1, third), isNull);
      expect(b.states, hasLength(2));
      expect(b.states.last.from, DateTime(2026, 9));
      expect(b.catalogOf(0, third)[0x0801]!.name, 'Licht Küche', reason: 'the state before stays valid until the next');
      expect(b.catalogOf(0, third)[0x0803]!.name, 'Alt');
      expect(b.catalogOf(0, third)[0x0804], isNull);

      final c = three();
      final back = c.remove(2, third)!;
      expect(back[0x0801]!.name, 'Temperatur Küche');
      expect(c.states, hasLength(2));
      expect(c.states.last.groups, isNull);
      expect(c.catalogOf(0, back)[0x0801]!.name, 'Licht Küche');
    });

    // The numbers behind the storage decision (reverse deltas instead of copies).
    test('real size: 8000 addresses, 12 states with 2 % changed each', () {
      GroupCatalog big(int version) => GroupCatalog(
        {
          for (var i = 0; i < 8000; i++)
            i + 1: GroupInfo(
              address: i + 1,
              // Every state renames another 2 % of the addresses.
              name: 'Raum ${i ~/ 20} Leuchte ${i % 20} Schalten${i % 50 == version % 50 ? ' v$version' : ''}',
              path: 'Beleuchtung › Raum ${i ~/ 20}',
              dpt: const Dpt(1, 1),
              description: 'Kanal ${i % 12} des Aktors',
              links: [
                GroupLink(device: 0x1100 + i % 200, object: i % 60, text: 'Schalten', sends: true, ref: 'M-0083_O-$i'),
                GroupLink(device: 0x1200 + i % 200, object: i % 60, text: 'Status'),
              ],
            ),
        },
        devices: {for (var i = 0; i < 400; i++) 0x1100 + i: DeviceInfo(address: 0x1100 + i, name: 'Gerät $i')},
      );
      final states = ProjectStates();
      var current = big(0);
      final watch = Stopwatch()..start();
      for (var v = 1; v < maxProjectStates; v++) {
        final next = big(v);
        states.push(current, next, at: DateTime(2026, v));
        current = next;
      }
      final pushMs = watch.elapsedMilliseconds;
      final catalogBytes = utf8.encode(jsonEncode(current.toJson())).length;
      final statesBytes = utf8.encode(jsonEncode(states.toJson())).length;
      watch.reset();
      final oldest = states.catalogOf(0, current);
      final rebuildMs = watch.elapsedMilliseconds;
      // ignore: avoid_print
      print(
        'catalog ${catalogBytes ~/ 1024} KB, 12 states as deltas ${statesBytes ~/ 1024} KB '
        '(copies: ${11 * catalogBytes ~/ 1024} KB); 11 imports $pushMs ms, oldest state rebuilt in $rebuildMs ms',
      );
      expect(states.states, hasLength(maxProjectStates));
      expect(oldest[1]!.name, big(0)[1]!.name);
      expect(statesBytes, lessThan(catalogBytes), reason: 'eleven older states cost less than one copy');
    });
  });

  group('CatalogStore with states', () {
    late MemoryStorage storage;
    final store = CatalogStore.instance;
    const path = 'installations/default/$projectStatesPath';

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      AppStorage.instance = storage = MemoryStorage();
      CatalogStore.now = () => DateTime(2026, 6);
      await store.reload();
    });

    tearDown(() => CatalogStore.now = DateTime.now);

    test('an old installation without states: one state, no file, names as always', () async {
      storage.files['installations/default/catalog.json'] = jsonEncode(_old.toJson());
      await store.reload();
      expect(store.projectStates, hasLength(1));
      expect(store.projectStates.single.from, isNull);
      expect(store.currentStateFrom, isNull);
      final t = _telegram(DateTime(2019));
      expect(store.title(t), 'Licht Küche');
      expect(store.pastStateOf(t), isNull);
      expect(storage.files.containsKey(path), isFalse);
    });

    test('a renamed and retyped address keeps name and type in old telegrams', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      expect(storage.files.containsKey(path), isFalse, reason: 'one state needs no file');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      expect(storage.files.containsKey(path), isTrue);
      expect(store.projectStates, hasLength(2));

      final before = _telegram(DateTime(2026, 8, 31, 23, 59), data: [1]);
      final at = _telegram(DateTime(2026, 9), data: [0x0C, 0x24], small: false);
      final today = _telegram(DateTime(2026, 11), data: [0x0C, 0x24], small: false);
      expect(store.title(before), 'Licht Küche');
      expect(store.dptFor(before), const Dpt(1, 1));
      expect(store.value(before), isNot(contains('°C')));
      expect(store.sender(before), contains('Aktor alt'));
      expect(store.pastStateOf(before)!.name, 'alt.knxproj');
      for (final t in [at, today]) {
        expect(store.title(t), 'Temperatur Küche');
        expect(store.value(t), contains('°C'));
        expect(store.sender(t), contains('Aktor neu'));
        expect(store.pastStateOf(t), isNull);
      }
      // An address that no longer exists keeps its old name; one that did not exist yet has none.
      expect(store.title(_telegram(DateTime(2026, 7), destination: 0x0803)), 'Alt');
      expect(store.infoOf(_telegram(DateTime(2026, 7), destination: 0x0804)), isNull);
      // Lookups without a time stay with today's project.
      expect(store.info(0x0801)!.name, 'Temperatur Küche');

      // The CSV of a past period names it with the state of its time.
      final csv = buildCsv([before, today]);
      expect(csv, contains('"Licht Küche","1.001"'));
      expect(csv, contains('"Temperatur Küche","9.001"'));
    });

    test('states survive a restart', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      await store.reload();
      expect(store.projectStates, hasLength(2));
      expect(store.title(_telegram(DateTime(2026, 7))), 'Licht Küche');
      expect(store.title(_telegram(DateTime(2026, 10))), 'Temperatur Küche');
    });

    test('date corrected: the boundary moves, not into the future', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      final t = _telegram(DateTime(2026, 8, 20));
      expect(store.title(t), 'Licht Küche');
      expect(await store.setProjectStateFrom(1, DateTime(2026, 12)), isFalse);
      expect(await store.setProjectStateFrom(1, DateTime(2026, 8, 15)), isTrue);
      expect(store.title(t), 'Temperatur Küche');
      await store.reload();
      expect(store.projectStates.last.from, DateTime(2026, 8, 15));
    });

    test('removing the current state returns to the project before', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      await store.removeProjectState(1);
      expect(store.projectStates, hasLength(1));
      expect(store.project[0x0801]!.name, 'Licht Küche');
      expect(store.fileName, 'alt.knxproj');
      expect(storage.files.containsKey(path), isFalse);
      expect(jsonDecode(storage.files['installations/default/catalog.json']!), containsPair('project', 'Haus 2024'));
    });

    test('removing the project removes its states', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      await store.clear();
      expect(storage.files.containsKey(path), isFalse);
      expect(store.projectStates, isEmpty);
      expect(store.title(_telegram(DateTime(2026, 7))), '1/0/1');
    });

    test('a name correction applies to the old state only where it corrects the same name', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      await store.setNames({0x0801: 'Temp. Küche', 0x0802: 'Licht Diele'});
      expect(store.title(_telegram(DateTime(2026, 7))), 'Licht Küche');
      expect(store.title(_telegram(DateTime(2026, 7), destination: 0x0802)), 'Licht Diele');
      expect(store.title(_telegram(DateTime(2026, 10))), 'Temp. Küche');
    });

    test('the demo house has one state and keeps the own ones', () async {
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      store.beginDemo(_project({0x0801: ('Demo', null)}));
      expect(store.projectStates, isEmpty);
      expect(store.title(_telegram(DateTime(2026, 7))), 'Demo');
      store.endDemo();
      expect(store.title(_telegram(DateTime(2026, 7))), 'Licht Küche');
    });

    test('a file the storage refuses (older add-on) does not stop the import', () async {
      AppStorage.instance = storage = _Refusing();
      await store.reload();
      await store.adopt(_old, name: 'alt.knxproj');
      CatalogStore.now = () => DateTime(2026, 9);
      await store.adopt(_new, name: 'neu.knxproj');
      expect(store.project[0x0801]!.name, 'Temperatur Küche');
      expect(store.title(_telegram(DateTime(2026, 7))), 'Licht Küche', reason: 'kept until the app closes');
    });
  });
}

class _Refusing extends MemoryStorage {
  @override
  Future<void> write(String path, String text) async {
    if (path.endsWith(projectStatesPath)) throw StateError('403');
    await super.write(path, text);
  }
}
