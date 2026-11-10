import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/availability.dart';

void main() {
  test('Ausfall über Mitternacht wird auf beide Tage verteilt', () {
    final byDay = outagesByDay([
      Outage(DateTime(2026, 10, 1, 23, 30), DateTime(2026, 10, 2, 1, 15), OutageKind.offline),
      Outage(DateTime(2026, 10, 2, 8), DateTime(2026, 10, 2, 8, 3), OutageKind.disconnected),
    ]);
    expect(byDay.keys, [DateTime(2026, 10, 1), DateTime(2026, 10, 2)]);
    expect(byDay[DateTime(2026, 10, 1)]!.single.duration, const Duration(minutes: 30));
    expect(outageSummary(byDay[DateTime(2026, 10, 2)]!), 'Add-on lief 1 h 15 min nicht · Bus 3 min getrennt');
  });

  test('Dauer lesbar', () {
    expect(formatDuration(const Duration(seconds: 20)), '< 1 min');
    expect(formatDuration(const Duration(hours: 11, minutes: 45)), '11 h 45 min');
    expect(formatDuration(const Duration(hours: 2)), '2 h');
  });

  test('Lücke eines Messpunkts: eigene Art, mit Namen, über Mitternacht verteilt', () {
    final gap = Outage.fromJson({
      'from': DateTime(2026, 11, 9, 23, 50).millisecondsSinceEpoch,
      'to': DateTime(2026, 11, 10, 0, 10).millisecondsSinceEpoch,
      'kind': 'tap',
      'tap': 'Linie 1.2',
    });
    expect(gap.kind, OutageKind.tap);
    final byDay = outagesByDay([
      gap,
      Outage(DateTime(2026, 11, 10, 8), DateTime(2026, 11, 10, 8, 3), OutageKind.disconnected),
    ]);
    expect(byDay[DateTime(2026, 11, 9)]!.single.tap, 'Linie 1.2');
    expect(
      outageSummary(byDay[DateTime(2026, 11, 10)]!),
      'Bus 3 min getrennt · Messpunkt Linie 1.2 10 min nicht erreichbar',
    );
    // Unknown kinds of newer servers still count as disconnected, as before.
    expect(Outage.fromJson({'from': 0, 'to': 1, 'kind': 'neu'}).kind, OutageKind.disconnected);
  });
}
