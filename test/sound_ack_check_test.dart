import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/sound_ack.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/sound_ack_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SoundAck.instance.stop);

  testWidgets('Testton vor der ersten Klangquittung: erst nach „Gehört“ geht es los', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Builder(
            builder: (context) =>
                TextButton(onPressed: () => toggleSoundAck(context, const AckLine(1, 1)), child: const Text('start')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Gehört?'), findsOneWidget);
    expect(SoundAck.instance.active, isFalse);

    await tester.tap(find.text('Nicht gehört'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stummmodus'), findsOneWidget);

    await tester.tap(find.text('Gehört, los'));
    await tester.pumpAndSettle();
    expect(SoundAck.instance.active, isTrue);

    // In derselben Sitzung kein zweites Mal.
    SoundAck.instance.stop();
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Gehört?'), findsNothing);
    expect(SoundAck.instance.active, isTrue);
  });
}
