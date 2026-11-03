import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/weekly_report.dart';
import 'package:shared_preferences/shared_preferences.dart';

int ga(String s) => parseGroup(s)!;

void main() {
  final now = DateTime(2026, 10, 29, 20);
  final window = ga('3/0/1');
  const partial = ReportBasis(continuous: false, listened: Duration(hours: 3, minutes: 20), days: 2);

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog({
      window: GroupInfo(address: window, name: 'Fensterkontakt Bad', dpt: const Dpt(1, 19)),
    });
  });
  tearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);

  HealthRun run(Duration ago, List<HealthFinding> findings) =>
      HealthRun(now.subtract(ago), findings, asked: 10, answered: 9);

  test('Ampel: ohne Lauf grau, Hinweise grün, Warnung gelb, Fehler rot, alt grau', () {
    expect(lightOf(null, now), HealthLight.unknown);
    expect(lightOf(run(Duration.zero, [HealthFinding(FindingKind.alwaysSilent, window)]), now), HealthLight.green);
    expect(lightOf(run(Duration.zero, [HealthFinding(FindingKind.overdue, window)]), now), HealthLight.yellow);
    expect(lightOf(run(Duration.zero, [HealthFinding(FindingKind.newSilent, window)]), now), HealthLight.red);
    expect(lightOf(run(const Duration(days: 8), const []), now), HealthLight.unknown);
  });

  test('Alles in Ordnung bis auf den Fensterkontakt, ehrliche Grundlage', () {
    final report = weeklyReport(
      [
        run(const Duration(hours: 1), [HealthFinding(FindingKind.newSilent, window)]),
        run(const Duration(days: 3), const []),
      ],
      now,
      basis: partial,
    );
    expect(report.light, HealthLight.red);
    expect(report.summary, 'Diese Woche alles in Ordnung bis auf eins: „Fensterkontakt Bad“ meldet sich nicht mehr.');
    expect(
      report.basisText,
      startsWith('Grundlage: Die App hat diese Woche etwa 3 h 20 min an 2 Tagen mitgehört (2 Prüfungen).'),
    );
  });

  test('Erledigtes zählt, Läufe älter als eine Woche nicht', () {
    final report = weeklyReport(
      [
        run(const Duration(hours: 1), const []),
        run(const Duration(days: 2), [HealthFinding(FindingKind.stuck, window)]),
        run(const Duration(days: 10), [HealthFinding(FindingKind.repeats, 0x1105)]),
      ],
      now,
      basis: partial,
    );
    expect(report.runs, hasLength(2));
    expect(report.light, HealthLight.green);
    expect(report.open, isEmpty);
    expect(report.resolved.single.kind, FindingKind.stuck);
    expect(report.summary, 'Diese Woche alles in Ordnung. Eine hat sich inzwischen erledigt.');
  });

  test('Passiver Lauf behebt keine Lese-Befunde und macht die Ampel nicht grün', () {
    HealthRun passive(Duration ago) => HealthRun(now.subtract(ago), const [], asked: 0, answered: 0, passive: true);
    final full = run(const Duration(days: 2), [HealthFinding(FindingKind.newSilent, window)]);
    final report = weeklyReport([passive(const Duration(hours: 1)), full], now, basis: partial);
    expect(report.light, HealthLight.red);
    expect(report.open.single.kind, FindingKind.newSilent);
    expect(report.resolved, isEmpty);
    expect(report.lastFull, full.time);

    // Erst ein voller Lauf ohne den Befund behebt ihn.
    final fixed = weeklyReport(
      [passive(const Duration(hours: 1)), run(const Duration(hours: 5), const []), full],
      now,
      basis: partial,
    );
    expect(fixed.light, HealthLight.green);
    expect(fixed.resolved.single.kind, FindingKind.newSilent);
    expect(fixed.lastFull, isNotNull);

    // Andere Befunde (z. B. Zyklen) zählen auch im passiven Lauf.
    final overdue = HealthRun(now, [HealthFinding(FindingKind.overdue, window)], asked: 0, answered: 0, passive: true);
    expect(currentFindings([overdue, full]).map((f) => f.kind), [FindingKind.overdue, FindingKind.newSilent]);
  });

  test('Art des Laufs bleibt gespeichert', () {
    final p = HealthRun(now, const [], asked: 0, answered: 0, passive: true);
    expect(HealthRun.fromJson(p.toJson()).passive, isTrue);
    expect(HealthRun.fromJson(run(Duration.zero, const []).toJson()).passive, isFalse);
  });

  test('Dauerbetrieb und ganz ohne Prüfung', () {
    final box = weeklyReport(
      [run(Duration.zero, const [])],
      now,
      basis: const ReportBasis(continuous: true, listened: Duration.zero, days: 0, server: 'KNX-Box'),
    );
    expect(box.basisText, 'Grundlage: Die KNX-Box hört rund um die Uhr mit; dazu 1 Prüfung diese Woche.');
    final none = weeklyReport(const [], now, basis: partial);
    expect(none.light, HealthLight.unknown);
    expect(none.summary, 'Diese Woche wurde noch nicht geprüft.');
  });

  test('Befunde in Alltagssprache, unbekannte Adresse mit Nummer', () {
    expect(
      plainFinding(HealthFinding(FindingKind.outOfRange, window)),
      '„Fensterkontakt Bad“ zeigt einen unmöglichen Wert',
    );
    expect(
      plainFinding(HealthFinding(FindingKind.overdue, ga('9/7/9'))),
      '„Adresse 9/7/9“ ist ungewöhnlich lange still',
    );
    expect(
      plainFinding(const HealthFinding(FindingKind.repeats, 0x1105)),
      '„Gerät 1.1.5“ muss oft wiederholen – Leitung oder Gerät prüfen lassen',
    );
  });

  test('Mithörzeit je Tag, gespeichert und nach 7 Tagen nicht mehr in der Woche', () async {
    SharedPreferences.setMockInitialValues({});
    final log = ListeningLog.instance..debugReset();
    await log.load();
    for (var i = 0; i < 90; i++) {
      log.addMinute(now);
    }
    log.addMinute(now.subtract(const Duration(days: 1)));
    log.addMinute(now.subtract(const Duration(days: 9)));
    await log.flush();
    expect(log.week(now), (const Duration(minutes: 91), 2));
    log.debugReset();
    await log.load();
    expect(log.week(now).$1, const Duration(minutes: 91));
  });
}
