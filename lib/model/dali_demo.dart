import '../knx/dali.dart';
import '../knx/demo_tunnel.dart';
import '../l10n/locale_controller.dart';

/// What somebody would have entered for the demo house's DALI gateway: names, rooms and groups of
/// the luminaires (the gateway does not report them on KNX), and names of the groups.
typedef DemoLuminaire = ({int address, String name, String room, int group});

List<DemoLuminaire> demoLuminaires() {
  final de = s.localeName.startsWith('de');
  String t(String d, String e) => de ? d : e;
  final office = t('Büro 2.14', 'Office 2.14');
  final hall = t('Flur EG', 'Hall GF');
  return [
    for (var i = 0; i < 8; i++)
      (address: i, name: '$office ${t('Leuchte', 'luminaire')} ${i + 1}', room: office, group: 0),
    for (var i = 8; i < 16; i++)
      // Short address 12 is the one whose lamp fails in the demo.
      (address: i, name: '$hall ${t('Leuchte', 'luminaire')} ${i - 10 > 0 ? i - 10 : i - 2}', room: hall, group: 1),
    (address: 16, name: t('Ausgang Halle', 'Exit hall'), room: t('Halle', 'Hall'), group: 3),
    (address: 17, name: t('Flur EG Notleuchte 1', 'Hall GF emergency 1'), room: hall, group: 3),
    (
      address: 18,
      name: t('Notleuchte Treppenhaus', 'Emergency staircase'),
      room: t('Treppenhaus', 'Staircase'),
      group: 3,
    ),
  ];
}

/// Names of the demo gateway's groups, by number.
List<String> demoGroupNames() {
  final de = s.localeName.startsWith('de');
  return de
      ? const ['Büro 2.14', 'Flur EG', 'Flur OG', 'Notlicht']
      : const ['Office 2.14', 'Hall GF', 'Hall FF', 'Emergency'];
}

/// The emergency lighting log of the demo house as it would have grown over the last months, so
/// the log shows an overdue and a failed luminaire right away. The raw values are the ones the
/// demo gateway sends ([DemoDali.resultOf]): its live telegrams add nothing new.
List<EmergencyTest> demoEmergencyLog(DateTime now) {
  String raw(int address) =>
      [for (final b in DemoDali.resultOf(address)) b.toRadixString(16).padLeft(2, '0')].join().toUpperCase();
  EmergencyTest entry(int address, EmergencyTestKind kind, int daysAgo, {bool passed = true, int? minutes}) =>
      EmergencyTest(
        // Self-tests run at night.
        time: DateTime(now.year, now.month, now.day - daysAgo, 2, 10 + address),
        group: DemoDali.result(address),
        gateway: DemoDali.gateway,
        address: address,
        kind: kind,
        result: passed ? EmergencyResult.passed : EmergencyResult.failed,
        start: ConverterTestStart.automatic,
        minutes: minutes,
        raw: raw(address),
      );
  return [
    entry(16, EmergencyTestKind.duration, 120, minutes: 95),
    entry(17, EmergencyTestKind.duration, 120, minutes: 92),
    entry(18, EmergencyTestKind.duration, 120, minutes: 61),
    // The function test of the exit luminaire is overdue: its last result is 41 days old.
    entry(16, EmergencyTestKind.function, 41),
    entry(17, EmergencyTestKind.function, 36),
    entry(18, EmergencyTestKind.function, 36),
    entry(18, EmergencyTestKind.duration, 9, passed: false),
    entry(17, EmergencyTestKind.function, 6),
    entry(18, EmergencyTestKind.function, 6),
  ];
}
