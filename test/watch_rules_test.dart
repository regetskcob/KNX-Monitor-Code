import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/model/trigger.dart';
import 'package:knx_monitor/model/watch_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 21, 8);
  Telegram write(int ga, int value, {int sec = 0, TelegramType type = TelegramType.write}) => Telegram(
    time: start.add(Duration(seconds: sec)),
    source: 0x1105,
    destination: ga,
    type: type,
    data: Uint8List.fromList([value]),
    isSmall: true,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = GroupCatalog.empty;
    for (final r in [...WatchRules.instance.value]) {
      await WatchRules.instance.remove(r.id);
    }
  });

  test('Trifft die Adresse, nicht Lesen, mit Sperrzeit gegen Prellen', () async {
    final rules = WatchRules.instance;
    await rules.add(const WatchRule(id: 'a', address: 0x0A03));
    final hits = <WatchHit>[];
    final sub = rules.hits.listen(hits.add);
    final log = TelegramLog();

    rules.check(write(0x0A03, 1), log, now: start);
    rules.check(write(0x0A03, 0, sec: 1), log, now: start.add(const Duration(seconds: 1)));
    rules.check(write(0x0A04, 1), log, now: start.add(const Duration(seconds: 5)));
    rules.check(write(0x0A03, 0, type: TelegramType.read), log, now: start.add(const Duration(seconds: 6)));
    rules.check(write(0x0A03, 1, sec: 7), log, now: start.add(const Duration(seconds: 7)));
    await pumpEventQueue();
    await sub.cancel();

    expect(hits, hasLength(2), reason: 'erstes Telegramm und nach Ablauf der Sperrzeit');
    expect(rules.armed, isTrue);
  });

  test('Aus geschaltete Regeln schweigen; JSON bleibt gleich (für Box und Add-on)', () async {
    const rule = WatchRule(id: 'b', address: 0x0A03, value: 'Ein', sound: false, enabled: false);
    expect(WatchRule.fromJson(rule.toJson()).toJson(), rule.toJson());
    await WatchRules.instance.add(rule);
    expect(WatchRules.instance.armed, isFalse);
    final hits = <WatchHit>[];
    final sub = WatchRules.instance.hits.listen(hits.add);
    WatchRules.instance.check(write(0x0A03, 1), TelegramLog(), now: start);
    await pumpEventQueue();
    await sub.cancel();
    expect(hits, isEmpty);
  });

  group('Prüfung im Add-on bzw. auf der Box', () {
    final light = parseGroup('1/0/4')!;
    final wind = parseGroup('8/1/1')!;
    final text = parseGroup('8/1/2')!;
    setUp(() {
      CatalogStore.instance.catalog = GroupCatalog({
        light: GroupInfo(address: light, name: 'Außenleuchten', dpt: const Dpt(1, 1)),
        wind: GroupInfo(address: wind, name: 'Wind', dpt: const Dpt(9, 5)),
        text: GroupInfo(address: text, name: 'Anzeige', dpt: const Dpt(16, 0)),
      });
    });

    test('ohne Wert jedes Telegramm, Zahlen als Vergleich, kleine Typen als Rohwerte', () {
      expect(WatchRule(id: 'a', address: light).serverCheck(), {'any': true});
      expect(WatchRule(id: 'b', address: wind, value: '10,5', compare: ValueCompare.greater).serverCheck(), {
        'num': [9, 5],
        'op': 'greater',
        'n': 10.5,
      });
      // Gleiche Prüfung wie in der App: „Ein“ trifft 1, nicht 0 (DPT 1 liest
      // nur das unterste Bit – ungerade Rohwerte zählen also mit).
      final on = WatchRule(id: 'c', address: light, value: 'Ein', compare: ValueCompare.equals).serverCheck()!;
      expect(on['small'], isTrue);
      expect(on['values'], allOf(contains(1), isNot(contains(0))));
      // Text (DPT 16) lässt sich nicht aufzählen: das prüft nur die App.
      expect(WatchRule(id: 'd', address: text, value: 'Alarm').serverCheck(), isNull);
    });

    test('Server-Treffer kommen an, Regeln des Servers prüft die App nicht doppelt', () async {
      final rules = WatchRules.instance;
      await rules.load();
      await rules.add(WatchRule(id: 'srv', address: light));
      await rules.add(WatchRule(id: 'app', address: text, value: 'Alarm'));
      final hits = <WatchHit>[];
      final sub = rules.hits.listen(hits.add);

      // Am gemeinsamen Tunnel: nur die Regel, die der Server nicht kann.
      rules.check(write(light, 1), TelegramLog(), now: start, server: true);
      await pumpEventQueue();
      expect(hits, isEmpty);

      rules.report(['srv'], write(light, 1), now: start);
      rules.report(['srv'], write(light, 1), now: start.add(const Duration(seconds: 1)));
      rules.report(['weg'], write(light, 1), now: start.add(const Duration(seconds: 9)));
      await pumpEventQueue();
      await sub.cancel();
      expect(hits.single.rule.id, 'srv');
      expect(hits.single.fromServer, isTrue);
    });
  });

  test('Drossel: Ton höchstens alle 5 s, Vibration nur mit der Mitteilung alle 30 s', () {
    final throttle = WatchAlertThrottle();
    final t0 = DateTime(2026, 10, 29, 18);
    ({bool sound, bool notify, bool vibrate}) at(int seconds, {String id = 'a', bool canNotify = true}) =>
        throttle.hit(id, t0.add(Duration(seconds: seconds)), wantsSound: true, canNotify: canNotify);

    expect(at(0), (sound: true, notify: true, vibrate: true));
    // Außenhelligkeit alle ~2 s: still bis 5 s, dann Ton ohne Vibration.
    expect(at(2), (sound: false, notify: false, vibrate: false));
    expect(at(6), (sound: true, notify: false, vibrate: false));
    expect(at(10), (sound: false, notify: false, vibrate: false));
    expect(at(12), (sound: true, notify: false, vibrate: false));
    expect(at(31), (sound: true, notify: true, vibrate: true));
    // Je Wächter getrennt; im Add-on keine eigene Mitteilung, also nie Vibration.
    expect(at(31, id: 'b', canNotify: false), (sound: true, notify: false, vibrate: false));
    // Ohne Ton: Mitteilung weiter gedrosselt, keine Vibration.
    expect(throttle.hit('c', t0, wantsSound: false, canNotify: true), (sound: false, notify: true, vibrate: false));
  });
}
