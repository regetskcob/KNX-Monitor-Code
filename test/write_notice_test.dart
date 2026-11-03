import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/write_notice.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/write_confirm.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final notice = WriteNotice.instance;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    notice.debugReset();
    DemoTunnel.active = false;
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });

  Future<List<bool?>> pump(WidgetTester tester, Future<bool> Function(BuildContext) ask) async {
    final results = <bool?>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) =>
              TextButton(onPressed: () async => results.add(await ask(context)), child: const Text('los')),
        ),
      ),
    );
    return results;
  }

  for (final (name, ask) in <(String, Future<bool> Function(BuildContext))>[
    ('Schreiben', (c) => confirmWrite(c, 1, small: 1)),
    ('Wiedergabe', confirmReplay),
  ]) {
    testWidgets('$name: Abbrechen schreibt nicht und blendet nichts aus', (tester) async {
      final results = await pump(tester, ask);
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      expect(find.text(s.writeNoticeTitle), findsOneWidget);
      await tester.tap(find.text(s.writeNoticeHide));
      await tester.pump();
      await tester.tap(find.text(s.commonCancel));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(notice.dismissed, isFalse);
    });

    testWidgets('$name: Ausblenden gilt beim nächsten Mal', (tester) async {
      final results = await pump(tester, ask);
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(s.writeNoticeHide));
      await tester.pump();
      await tester.tap(find.text(s.writeNoticeConfirm));
      await tester.pumpAndSettle();
      expect(results, [true]);
      expect(notice.dismissed, isTrue);
      await tester.tap(find.text('los'));
      await tester.pumpAndSettle();
      expect(find.text(s.writeNoticeTitle), findsNothing);
      expect(results, [true, true]);
    });
  }

  testWidgets('Ohne Haken erscheint der Hinweis wieder, im Demo-Haus gar nicht', (tester) async {
    final results = await pump(tester, (c) => confirmWrite(c, 1, small: 1));
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.writeNoticeConfirm));
    await tester.pumpAndSettle();
    expect(results, [true]);
    expect(notice.dismissed, isFalse);
    DemoTunnel.active = true;
    await tester.tap(find.text('los'));
    await tester.pumpAndSettle();
    expect(find.text(s.writeNoticeTitle), findsNothing);
    expect(results, [true, true]);
  });

  test('Bericht enthält nur ob und wann, Ausblenden überlebt den Neustart', () async {
    await notice.load();
    expect(notice.toReport(), {'dismissed': false});
    await notice.dismiss(DateTime.utc(2026, 10, 31, 12));
    notice.debugReset();
    await notice.load();
    expect(notice.toReport(), {'dismissed': true, 'dismissedAt': '2026-10-31T12:00:00.000Z'});
    await notice.restore();
    notice.debugReset();
    await notice.load();
    expect(notice.dismissed, isFalse);
  });
}
