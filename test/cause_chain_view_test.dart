import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/expert_mode.dart';
import 'package:knx_monitor/model/plain_text.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/cause_chain_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _t0 = DateTime(2026, 10, 29, 20);

Telegram _t(int ms, String source, String ga) => Telegram(
  time: _t0.add(Duration(milliseconds: ms)),
  source: parseIndividual(source)!,
  destination: parseGroup(ga)!,
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final command = _t(0, '1.1.60', '1/1/1');
  final feedback = _t(120, '1.1.10', '1/4/1');
  final log = [command, feedback];

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('de'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: CauseChainView(telegram: command, log: log),
      ),
    ),
  );

  testWidgets('ohne Expertenmodus spricht die Kette wie die Live-Liste', (tester) async {
    await ExpertMode.instance.set(false);
    await pump(tester);
    expect(find.text(telegramSentence(command)), findsOneWidget);
    expect(find.text(telegramSentence(feedback)), findsOneWidget);
    // Ohne Projekt nur Zeitnähe: nicht „gleichzeitig“ nennen, der Abstand steht daneben.
    expect(find.text('Zeitnah, ohne Bezug'), findsOneWidget);
    expect(find.text('+120 ms'), findsOneWidget);
  });

  testWidgets('im Expertenmodus Adresse, Wert und Absender', (tester) async {
    await ExpertMode.instance.set(true);
    addTearDown(() => ExpertMode.instance.set(false));
    await pump(tester);
    expect(find.text(telegramSentence(command)), findsNothing);
    expect(find.textContaining('1/1/1'), findsWidgets);
  });
}
