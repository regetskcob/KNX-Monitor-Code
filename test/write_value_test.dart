import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/ui/write_value.dart';

void main() {
  late List<({int? small, List<int> data})> written;

  Future<void> pump(WidgetTester tester, {Dpt? dpt, Telegram? initial}) {
    written = [];
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: WriteValueControl(
            dpt: dpt,
            initial: initial,
            onWrite: ({int? small, List<int> data = const []}) async {
              written.add((small: small, data: data));
              return true;
            },
          ),
        ),
      ),
    );
  }

  testWidgets('DPT 9: übernimmt aktuellen Wert und schreibt kodiert', (tester) async {
    await pump(
      tester,
      dpt: const Dpt(9, 1),
      initial: Telegram(
        time: DateTime(2026),
        source: 0,
        destination: 0,
        type: TelegramType.write,
        data: Uint8List.fromList([0x0C, 0x24]),
        isSmall: false,
      ),
    );
    expect(find.text('21,2'), findsOneWidget);
    expect(find.text('°C'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '22,5');
    await tester.tap(find.text('Schreiben'));
    await tester.pumpAndSettle();
    expect(written.single.data, [0x0C, 0x65]);
    expect(find.text('Geschrieben: 22,5 °C · vom Bus bestätigt'), findsOneWidget);
  });

  testWidgets('DPT 1.008: zeigt Auf/Ab-Tasten', (tester) async {
    await pump(tester, dpt: const Dpt(1, 8));
    await tester.tap(find.text('Ab'));
    await tester.pumpAndSettle();
    expect(written.single.small, 1);
  });

  testWidgets('ohne DPT: Format wählbar, ungültige Eingabe wird abgefangen', (tester) async {
    await pump(tester);
    expect(find.text('Prozent · 5.001'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '150');
    await tester.tap(find.text('Schreiben'));
    await tester.pumpAndSettle();
    expect(written, isEmpty);
    expect(find.textContaining('Ungültiger Wert'), findsOneWidget);
  });

  testWidgets('ohne DPT: Format aus der Wertlänge geraten (2 Byte → Kommazahl)', (tester) async {
    await pump(
      tester,
      initial: Telegram(
        time: DateTime(2026),
        source: 0,
        destination: 0,
        type: TelegramType.write,
        data: Uint8List.fromList([0x0C, 0x33]),
        isSmall: false,
      ),
    );
    expect(find.text('Kommazahl · 9.xxx'), findsOneWidget);
    expect(find.text('21,5'), findsOneWidget);
  });
}
