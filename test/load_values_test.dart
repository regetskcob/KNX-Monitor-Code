import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/load_values.dart';
import 'package:knx_monitor/model/plan.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/load_values_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

final _ga = parseGroup('6/0/1')!;
final _t0 = DateTime(2026, 10, 30, 8);

GroupInfo _g(String name, {String address = '6/0/1'}) => GroupInfo(address: parseGroup(address)!, name: name);

Telegram _float(double v, {int minutes = 0, int? ga, bool outgoing = false, TelegramType type = TelegramType.write}) {
  final data = ByteData(4)..setFloat32(0, v);
  return Telegram(
    time: _t0.add(Duration(minutes: minutes)),
    source: 0x1105,
    destination: ga ?? _ga,
    type: type,
    data: data.buffer.asUint8List(),
    isSmall: false,
    outgoing: outgoing,
  );
}

List<LoadSample> _series(List<double> values, {int everyMinutes = 15}) => [
  for (final (i, v) in values.indexed) (time: _t0.add(Duration(minutes: i * everyMinutes)), value: v),
];

DateTime _after(List<LoadSample> s, [Duration d = const Duration(minutes: 1)]) => s.last.time.add(d);

void main() {
  group('Erkennen', () {
    test('Der Datentyp entscheidet', () {
      for (final (dpt, kind) in const [
        (Dpt(7, 12), LoadKind.current),
        (Dpt(9, 21), LoadKind.current),
        (Dpt(14, 19), LoadKind.current),
        (Dpt(14, 56), LoadKind.power),
        (Dpt(9, 24), LoadKind.power),
      ]) {
        expect(loadKindOf(_g('Kanal A'), dpt), kind, reason: '$dpt');
      }
    });

    test('Allgemeiner oder fehlender Typ: nur mit passendem Namen', () {
      expect(loadKindOf(_g('Strom Kanal A'), const Dpt(9)), LoadKind.current);
      expect(loadKindOf(_g('Leistung Küche'), const Dpt(14)), LoadKind.power);
      expect(loadKindOf(_g('Strom Kanal A'), const Dpt(7, 1)), LoadKind.current);
      expect(loadKindOf(_g('Strom Kanal A'), null), LoadKind.current);
      expect(loadKindOf(_g('Kanal A'), const Dpt(9)), isNull);
    });

    test('Falsche Treffer bleiben draußen', () {
      expect(loadKindOf(_g('Strom Kanal A'), const Dpt(9, 1)), isNull, reason: 'Temperatur');
      expect(loadKindOf(_g('Strom Kanal A'), const Dpt(1, 1)), isNull);
      for (final name in [
        'Stromzähler',
        'Stromausfall',
        'Überlast Küche',
        'Lastabwurf',
        'Stromkreis 4',
        'Energie Strom',
      ]) {
        expect(loadKindOf(_g(name), const Dpt(14)), isNull, reason: name);
      }
    });
  });

  group('Werte', () {
    Telegram two(List<int> d) => Telegram(
      time: _t0,
      source: 1,
      destination: _ga,
      type: TelegramType.write,
      data: Uint8List.fromList(d),
      isSmall: false,
    );

    test('Einheiten werden auf A und W gebracht', () {
      expect(loadValueOf(LoadKind.current, const Dpt(7, 12), two([0x03, 0xE8])), closeTo(1, 1e-9));
      expect(loadValueOf(LoadKind.current, const Dpt(14, 19), _float(2.5)), closeTo(2.5, 1e-6));
      expect(loadValueOf(LoadKind.power, const Dpt(14, 56), _float(1200)), closeTo(1200, 1e-3));
      // 9.024: Wert in kW wird zu Watt.
      expect(loadValueOf(LoadKind.power, const Dpt(9, 24), two([0x0C, 0x1A])), greaterThan(1000));
      expect(loadValueOf(LoadKind.power, null, _float(100)), closeTo(100, 1e-3));
    });

    test('Leseanfragen und eigene Telegramme sind keine Messwerte', () {
      expect(loadValueOf(LoadKind.power, const Dpt(14, 56), _float(1, type: TelegramType.read)), isNull);
      expect(loadValueOf(LoadKind.power, const Dpt(14, 56), _float(1, outgoing: true)), isNull);
    });

    test('Kanal: aktuell, Maximum, sortiert, auch ohne Werte auffindbar', () {
      final other = parseGroup('6/0/2')!;
      final groups = [_g('Strom A'), _g('Strom B', address: '6/0/2'), _g('Licht', address: '1/0/0')];
      final out = loadChannels(
        groups,
        [_float(3, minutes: 2), _float(1, minutes: 1), _float(2, minutes: 3)],
        dptOf: (a) => a == parseGroup('1/0/0') ? const Dpt(1, 1) : const Dpt(14, 19),
        now: _t0.add(const Duration(minutes: 4)),
      );
      expect(out.map((c) => c.address), [_ga, other]);
      expect(out.first.latest!.value, closeTo(2, 1e-6));
      expect(out.first.peak!.value, closeTo(3, 1e-6));
      expect(out.last.latest, isNull);
    });
  });

  group('Hinweise sind vorsichtig', () {
    final steady = List.filled(30, 2.0);

    test('Zu wenig Grundlage: nichts', () {
      final few = _series([...List.filled(10, 2.0), 9, 9, 9]);
      expect(loadHint(LoadKind.current, few, _after(few)), isNull);
      // Viele Werte, aber in kurzer Zeit.
      final quick = _series([...steady, 9, 9, 9], everyMinutes: 1);
      expect(loadHint(LoadKind.current, quick, _after(quick)), isNull);
    });

    test('Dauerhafte Abweichung meldet, ein Ausreißer nicht', () {
      final moved = _series([...steady, 4, 4, 4]);
      final hint = loadHint(LoadKind.current, moved, _after(moved))!;
      expect(hint.kind, LoadHintKind.deviation);
      expect(hint.typical, 2);
      expect(hint.percent, 100);
      final outlier = _series([...steady, 2, 2, 9]);
      expect(loadHint(LoadKind.current, outlier, _after(outlier)), isNull);
      final near = _series([...steady, 2.5, 2.5, 2.5]);
      expect(loadHint(LoadKind.current, near, _after(near)), isNull, reason: 'unter 50 %');
    });

    test('Streuung und Mindestbetrag heben die Schwelle', () {
      final noisy = _series([for (var i = 0; i < 30; i++) i.isEven ? 1.0 : 3.0, 3.5, 3.5, 3.5]);
      expect(loadHint(LoadKind.current, noisy, _after(noisy)), isNull);
      final tiny = _series([...List.filled(30, 0.02), 0.06, 0.06, 0.06]);
      expect(loadHint(LoadKind.current, tiny, _after(tiny)), isNull, reason: 'unter 0,1 A');
    });

    test('Null nach Dauerlauf meldet, bei geschalteten Verbrauchern nicht', () {
      final dropped = _series([...steady, 0, 0, 0]);
      expect(loadHint(LoadKind.current, dropped, _after(dropped))!.kind, LoadHintKind.dropped);
      final switched = _series([for (var i = 0; i < 40; i++) i % 3 == 0 ? 0.0 : 2.0, 0, 0, 0]);
      expect(loadHint(LoadKind.current, switched, _after(switched)), isNull);
    });

    test('Stille nur bei regelmäßigem Senden', () {
      final cyclic = _series(steady);
      final late = _after(cyclic, const Duration(hours: 2));
      final hint = loadHint(LoadKind.current, cyclic, late)!;
      expect(hint.kind, LoadHintKind.silent);
      expect(hint.cycle, const Duration(minutes: 15));
      expect(loadHint(LoadKind.current, cyclic, _after(cyclic, const Duration(minutes: 20))), isNull);
      // Unregelmäßig (nur bei Änderung): Stille sagt nichts.
      final irregular = <LoadSample>[
        for (var i = 0; i < 30; i++) (time: _t0.add(Duration(minutes: i * i)), value: 2.0),
      ];
      expect(loadHint(LoadKind.current, irregular, _after(irregular, const Duration(days: 2))), isNull);
    });
  });

  test('Plus, wie Statistik und Diagramme', () {
    expect(Feature.loadValues.tier, Feature.statistics.tier);
    expect(Feature.loadValues.tier, Tier.plus);
  });

  test('Die Ansicht kann nichts anfragen: kein Tunnel, kein Senden', () {
    final source = File('lib/ui/load_values_screen.dart').readAsStringSync();
    for (final banned in ['knx_tunnel', 'KnxTunnel', 'sendRead', 'groupRead', 'send_scheduler']) {
      expect(source.contains(banned), isFalse, reason: banned);
    }
    final model = File('lib/model/load_values.dart').readAsStringSync();
    expect(model.contains('Timer'), isFalse);
  });

  testWidgets('Zeigt Kanal, Wert, Maximum und Hinweis mit Zahlen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    await CatalogStore.instance.reload();
    await CatalogStore.instance.learn([GroupInfo(address: _ga, name: 'Strom Pumpe', dpt: const Dpt(14, 19))]);
    addTearDown(CatalogStore.instance.clearLearned);
    LoadValuesScreen.clock = () => _t0.add(const Duration(minutes: 15 * 33 + 1));
    addTearDown(() => LoadValuesScreen.clock = DateTime.now);
    final log = TelegramLog();
    addTearDown(log.dispose);
    for (var i = 0; i < 30; i++) {
      log.add(_float(2, minutes: i * 15));
    }
    for (var i = 30; i < 33; i++) {
      log.add(_float(4, minutes: i * 15));
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: LoadValuesScreen(log: log),
      ),
    );
    await tester.pump();
    expect(find.text('Strom Pumpe'), findsOneWidget);
    expect(find.text('4,00 A'), findsNWidgets(2), reason: 'Kennzahl und Kanal');
    expect(find.textContaining('Maximum 4,00 A'), findsOneWidget);
    expect(find.textContaining('üblich 2,00 A, zuletzt 4,00 A (+100 %)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
