import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/model/bus_metrics.dart';
import 'package:knx_monitor/model/template_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final c = demoCatalog();
  Dpt? dptOf(int a) => c.groups[a]?.dpt;
  int ga(String name) => c.groups.values.firstWhere((g) => g.name == name).address;

  test('aus einem Raum-Diagramm: Vorlage je Raum, Raum fällt aus dem Namen', () {
    final ids = [ga('EG KÜ Ist-Temperatur'), ga('EG KÜ Soll-Temperatur'), BusMetric.telegrams.id];
    final (:rule, :dropped) = ruleFromChart('Klima EG KÜ', ids, c.groups, c.devices, dptOf: dptOf);
    expect(dropped, 0);
    expect(rule!.name, 'Klima');
    expect(rule.perRoom, isTrue);
    expect(rule.series.map((s) => s.role ?? '${s.metric}'), ['temperature', 'setpoint', '-1']);
  });

  test('JSON hin und zurück, fremde Dateien werden abgelehnt', () {
    const rule = TemplateRule(
      name: 'Klima',
      perRoom: true,
      series: [RuleSeries.role('temperature'), RuleSeries.metric(-2)],
    );
    final back = TemplateRule.fromJson(jsonDecode(jsonEncode(rule.toJson())));
    expect(back.name, 'Klima');
    expect(back.perRoom, isTrue);
    expect(back.series.map((s) => s.role ?? '${s.metric}'), ['temperature', '-2']);
    expect(() => TemplateRule.fromJson({'name': 'x'}), throwsFormatException);
    expect(
      () => TemplateRule.fromJson({'format': TemplateRule.format, 'name': 'x', 'series': <Object?>[]}),
      throwsFormatException,
    );
  });

  test('angewendet: je Raum mit genug Treffern, fürs Haus einmal', () {
    const perRoom = TemplateRule(
      name: 'Klima',
      perRoom: true,
      series: [RuleSeries.role('temperature'), RuleSeries.role('setpoint'), RuleSeries.role('valve')],
    );
    final rooms = applyRule(perRoom, c.groups, c.devices, dptOf: dptOf);
    expect(rooms.map((r) => r.place), containsAll(['EG KÜ', 'OG SZ']));
    final kitchen = rooms.firstWhere((r) => r.place == 'EG KÜ');
    expect(kitchen.ids, [ga('EG KÜ Ist-Temperatur'), ga('EG KÜ Soll-Temperatur'), ga('EG KÜ Stellwert Heizen (%)')]);

    const house = TemplateRule(name: 'Haus', series: [RuleSeries.role('power'), RuleSeries.metric(-1)]);
    final once = applyRule(house, c.groups, c.devices, dptOf: dptOf);
    expect(once.single.place, '');
    expect(once.single.ids.last, BusMetric.telegrams.id);
  });

  test('eigene Vorlagen bleiben gespeichert, gleicher Name ersetzt', () async {
    SharedPreferences.setMockInitialValues({});
    final store = CustomTemplates.instance..reset();
    await store.add(const TemplateRule(name: 'A', series: [RuleSeries.metric(-1)]));
    await store.add(const TemplateRule(name: 'A', series: [RuleSeries.metric(-2)]));
    store.reset();
    await store.load();
    expect(store.rules.single.series.single.metric, -2);
  });

  test('Import während des ersten Ladens geht nicht verloren', () async {
    SharedPreferences.setMockInitialValues({
      'chart_template_rules': jsonEncode([
        const TemplateRule(name: 'Alt', series: [RuleSeries.metric(-1)]).toJson(),
      ]),
    });
    final store = CustomTemplates.instance..reset();
    final loading = store.load();
    final adding = store.add(const TemplateRule(name: 'Neu', series: [RuleSeries.metric(-2)]));
    await Future.wait([loading, adding]);
    expect(store.rules.map((r) => r.name), ['Alt', 'Neu']);
    store.reset();
    await store.load();
    expect(store.rules.map((r) => r.name), ['Alt', 'Neu']);
  });
}
