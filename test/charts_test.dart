import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/charts_screen.dart';
import 'package:knx_monitor/ui/heatmap.dart';
import 'package:knx_monitor/ui/history_chart.dart';

Telegram _t(DateTime time, int ga) => Telegram(
  time: time,
  source: 0x1105,
  destination: ga,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

void main() {
  test('Ausdünnen behält Spitzen (Minimum und Maximum je Abschnitt)', () {
    final start = DateTime(2026);
    final points = [
      for (var i = 0; i < 1000; i++)
        ChartPoint(start.add(Duration(seconds: i)), i == 500 ? 99 : (i == 700 ? -50 : 1), _t(start, 1)),
    ];
    final thin = downsample(points, 100);
    expect(thin.length, lessThanOrEqualTo(102));
    expect(thin.map((p) => p.value), containsAll([99.0, -50.0]));
    expect(thin.last, same(points.last));
  });

  test('chart periods: today from midnight, 7 and 30 days back, loaded without a start', () {
    final now = DateTime(2026, 11, 4, 11, 30);
    expect(ChartPeriod.loaded.from(now), isNull);
    expect(ChartPeriod.today.from(now), DateTime(2026, 11, 4));
    expect(ChartPeriod.week.from(now), DateTime(2026, 10, 28, 11, 30));
    expect(ChartPeriod.month.from(now), DateTime(2026, 10, 5, 11, 30));
  });

  test('a series from server telegrams and newer ones from the log, in time order', () {
    final start = DateTime(2026, 11, 4, 8);
    final telegrams = [
      _t(start.add(const Duration(hours: 3)), 7),
      _t(start, 7),
      _t(start.add(const Duration(hours: 1)), 7),
    ];
    final series = seriesOf(7, telegrams, const Color(0xFF000000))!;
    expect(series.points.map((p) => p.time.hour), [8, 9, 11]);
    expect(series.kind, ChartKind.step);
  });

  test('Heatmap staffelt die Auflösung nach Zeitspanne', () {
    // Unter einer Stunde: je Minute, Zeilen je Stunde.
    var map = heatmapForTimes([DateTime(2026, 10, 12, 9, 5), DateTime(2026, 10, 12, 9, 50)]);
    expect(map.scale, HeatmapScale.minutes);
    expect(map.rows, ['09:00']);
    expect(map.cells[0][5], 1);
    expect(map.cells[0][50], 1);

    // Ein Nachmittag: je 5 Minuten.
    map = heatmapForTimes([DateTime(2026, 10, 12, 13, 2), DateTime(2026, 10, 12, 17, 59)]);
    expect(map.scale, HeatmapScale.fiveMinutes);
    expect(map.rows.length, 5);
    expect(map.cells[4][11], 1);

    // Drei Tage: Zeilen je Tag, Spalten je Stunde.
    map = heatmapForTimes([DateTime(2026, 10, 12, 9), DateTime(2026, 10, 14, 22)]);
    expect(map.scale, HeatmapScale.days);
    expect(map.rows.length, 3);
    expect(map.cells[2][22], 1);

    // Mehr als eine Woche: Wochentag × Stunde (12.10.2026 ist ein Montag).
    final log = TelegramLog()..addAll([_t(DateTime(2026, 10, 12, 9, 5), 1), _t(DateTime(2026, 10, 26, 9, 50), 2)]);
    map = heatmapOf(log);
    expect(map.scale, HeatmapScale.weekly);
    expect(map.cells[0][9], 2);
  });

  testWidgets('Antippbare Heatmap-Zellen sind für Screenreader Knöpfe', (tester) async {
    final handle = tester.ensureSemantics();
    String? query;
    final map = heatmapForTimes([DateTime(2026, 10, 12, 9, 5), DateTime(2026, 10, 12, 9, 50)]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: ActivityHeatmap(heatmap: map, onQuery: (q) => query = q),
        ),
      ),
    );
    final cell = find.bySemanticsLabel(RegExp(r'^09:05 · 1$'));
    expect(cell, findsOneWidget);
    expect(tester.getSemantics(cell), matchesSemantics(label: '09:05 · 1', isButton: true, hasTapAction: true));
    tester.semantics.tap(find.semantics.byLabel('09:05 · 1'));
    expect(query, isNotNull);
    // Leere Zellen bleiben stumm.
    expect(find.bySemanticsLabel(RegExp(r'^09:06 · 0$')), findsNothing);
    handle.dispose();
  });
}
