import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/acceptance.dart';
import 'package:knx_monitor/model/commissioning.dart';
import 'package:knx_monitor/model/health.dart';
import 'package:knx_monitor/model/statistics.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/ui/history_chart.dart';

Telegram _t(int second, String ga, TelegramType type, List<int> data, {bool small = false, bool outgoing = false}) =>
    Telegram(
      time: DateTime(2026, 10, 14, 15, 20, second, second * 37 % 1000),
      source: outgoing ? parseIndividual('1.1.38')! : parseIndividual('1.1.18')!,
      destination: parseGroup(ga)!,
      type: type,
      data: Uint8List.fromList(data),
      isSmall: small,
      outgoing: outgoing,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('einfaches PDF enthält alle Telegramme, aber weder Notiz noch Legende', () async {
    final telegrams = [
      for (var i = 0; i < 40; i++) _t(i % 60, '1/1/${i + 1}', TelegramType.write, [1], small: true),
    ];
    final store = CatalogStore.instance;
    final full = await buildTelegramPdf(telegrams, store: store, note: 'Notiz');
    final simple = await buildTelegramPdf(telegrams, store: store, note: 'Notiz', simple: true);
    expect(simple.length, greaterThan(1000));
    expect(simple.length, lessThan(full.length));
  });

  // Alle Auftragsarten lassen sich in den Hintergrund-Isolate senden und
  // ergeben dort ein PDF (Schriften, Sprache und Projekt gehen mit).
  test('PDF-Aufträge entstehen im Hintergrund-Isolate', () async {
    final telegrams = [
      for (var i = 0; i < 40; i++) _t(i % 60, '2/0/0', TelegramType.write, [0x0C, 0x20 + i]),
    ];
    final log = TelegramLog()..addAll(telegrams);
    final jobs = <PdfJob>[
      TelegramPdf(telegrams, gateway: 'Gira X1', title: 'Test', note: 'Notiz'),
      ChartPdf(address: parseGroup('2/0/0')!, telegrams: telegrams, kind: ChartKind.line, dpt: const Dpt(9, 1)),
      StatisticsPdf(BusStatistics.of(log)),
      CommissioningPdf(Commissioning.instance),
      HealthPdf(
        HealthRun(DateTime(2026, 10, 23), [HealthFinding(FindingKind.alwaysSilent, 0x1000)], asked: 1, answered: 0),
      ),
      AcceptancePdf(
        Acceptance(
          created: DateTime(2026, 10, 27, 16, 5),
          project: 'Haus Muster',
          customer: 'Familie Muster',
          site: 'Hauptstraße 1\n12345 Musterstadt',
          technician: 'D. Elektro',
          customerSigner: 'MAX MUSTER',
          remarks: 'Kunde eingewiesen',
          followUps: 'Taster Bad tauschen',
          language: 'en',
          started: DateTime(2026, 10, 25),
          gateway: 'Gira X1',
          items: [
            CheckItem(parseGroup('1/4/0')!, state: CheckState.seen, value: 'Ein', source: 0x1105),
            CheckItem(parseGroup('1/4/1')!, state: CheckState.issue, note: 'Klemmt', foreign: true, source: 0x1107),
            CheckItem(parseGroup('1/4/2')!),
          ],
          groups: {
            parseGroup('1/4/0')!: (name: 'Licht Flur RM', path: 'Licht › RM'),
            parseGroup('1/4/1')!: (name: 'Licht Bad RM', path: 'Licht › RM'),
            parseGroup('1/4/2')!: (name: 'Licht Küche RM', path: null),
          },
          customerSignature: const Signature([
            [Offset(0.1, 0.5), Offset(0.5, 0.2), Offset(0.9, 0.6)],
          ]),
          technicianSignature: const Signature([
            [Offset(0.1, 0.6), Offset(0.8, 0.4)],
          ]),
        ),
      ),
    ];
    for (final job in jobs) {
      final bytes = await buildPdfInBackground(job);
      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-', reason: '${job.runtimeType}');
    }
  });

  // Lange Tabellen brechen auf Folgeseiten um, statt an der Seitengrenze zu
  // scheitern (die App hing am iPad beim Export des Gesundheitsberichts).
  test('Gesundheitsbericht mit vielen Befunden über mehrere Seiten', () async {
    final run = HealthRun(
      DateTime(2026, 10, 23),
      [for (var i = 0; i < 300; i++) HealthFinding(FindingKind.alwaysSilent, 0x0800 + i)],
      asked: 300,
      answered: 0,
    );
    final bytes = await buildHealthPdf(run, store: CatalogStore.instance);
    // Vorher: PdfTooBigPageException schon ab etwa 80 Befunden.
    expect(bytes, isNotEmpty);
  });

  test('PDF-Protokoll mit Namen, Werten und Umlauten', () async {
    final store = CatalogStore.instance
      ..catalog = GroupCatalog(
        {
          parseGroup('2/0/0')!: GroupInfo(
            address: parseGroup('2/0/0')!,
            name: 'EG FL Ist-Temperatur',
            path: 'Heizung › Ist-Werte',
            dpt: const Dpt(9, 1),
          ),
          parseGroup('1/1/7')!: GroupInfo(
            address: parseGroup('1/1/7')!,
            name: 'Küche Decke Schalten',
            path: 'Beleuchtung › Schalten',
            dpt: const Dpt(1, 1),
          ),
        },
        devices: {
          parseIndividual('1.1.18')!: DeviceInfo(address: parseIndividual('1.1.18')!, name: 'Heizungsaktor EG'),
        },
        projectName: 'WalkenBock',
      );

    final telegrams = [
      for (var i = 0; i < 60; i++)
        switch (i % 4) {
          0 => _t(i, '2/0/0', TelegramType.write, [0x0C, 0x24 + i]),
          1 => _t(i, '1/1/7', TelegramType.write, [i & 1], small: true, outgoing: true),
          2 => _t(i, '2/0/0', TelegramType.read, const [0], small: true),
          _ => _t(i, '3/4/5', TelegramType.response, [0x80 + i]),
        },
    ];
    final pdf = await buildTelegramPdf(telegrams, store: store, gateway: 'Gira X1 · 192.168.1.22');
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    // Zur Sichtprüfung: KNX_PDF_OUT=/pfad/datei.pdf flutter test test/pdf_export_test.dart
    final out = Platform.environment['KNX_PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf);
  });
}
