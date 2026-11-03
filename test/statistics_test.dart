import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/export/pdf_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/statistics.dart';
import 'package:knx_monitor/model/telegram_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final start = DateTime(2026, 10, 14, 12);

  Telegram t(int sec, String ga, String src, {bool repeated = false}) => Telegram(
    time: start.add(Duration(seconds: sec)),
    source: parseIndividual(src)!,
    destination: parseGroup(ga)!,
    type: TelegramType.write,
    data: Uint8List.fromList([1]),
    isSmall: true,
    repeated: repeated,
  );

  test('Top-Sender, Flatterer, Lastspitzen und PDF', () async {
    CatalogStore.instance.catalog = GroupCatalog.empty;
    final log = TelegramLog()
      ..addAll([
        // 8/2/2 alle 2 s → Flatterer
        for (var i = 0; i < 30; i++) t(i * 2, '8/2/2', '1.1.62', repeated: i % 10 == 0),
        // 1/1/1 selten
        t(5, '1/1/1', '1.1.5'),
        t(50, '1/1/1', '1.1.5'),
        // Spitze: 5 Telegramme in Sekunde 20
        for (var i = 0; i < 4; i++) t(20, '2/0/0', '1.1.50'),
      ]);
    final stats = BusStatistics.of(log);
    expect(stats.total, 36);
    expect(stats.senders.first.address, parseIndividual('1.1.62'));
    expect(stats.senders.first.repeated, 3);
    expect(stats.flappers.map((g) => formatGroup(g.address)), ['8/2/2']);
    expect(stats.flappers.single.medianInterval, const Duration(seconds: 2));
    expect(stats.peaks.first.count, 5); // 4× 2/0/0 + 8/2/2 in Sekunde 20
    expect(stats.span, const Duration(seconds: 58));

    final pdf = await buildStatisticsPdf(stats, store: CatalogStore.instance, gateway: 'Gira X1');
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });
}
