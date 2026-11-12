import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/keys.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/box_claims.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';

/// docs/keys.md: a box that names the key of an installation here is connected only after the
/// user said so. The question comes once per box and installation; the box settings keep it.
void main() {
  final store = InstallationStore.instance;
  late Installation mine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    Addon.box = null;
    store.debugReset();
    await store.load();
    mine = await store.create('Kunde Meier');
    store
      ..boxKey = newKey()
      ..boxClaims = {mine.id: 'default'};
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        home: Scaffold(body: child),
      ),
    );
  }

  Widget offerButton() => Builder(
    builder: (context) => TextButton(onPressed: () => BoxClaims.offer(context), child: const Text('prüfen')),
  );

  testWidgets('„Nicht jetzt“: nichts verbunden, und die Frage kommt für diese Box nicht wieder', (tester) async {
    await pump(tester, offerButton());
    await tester.tap(find.text('prüfen'));
    await tester.pumpAndSettle();
    expect(find.text('Anlage mit dieser Box verbinden?'), findsOneWidget);
    expect(find.textContaining('„Kunde Meier“'), findsOneWidget);
    expect(find.textContaining('Die Kennung allein beweist nichts'), findsOneWidget);
    await tester.tap(find.text('Nicht jetzt'));
    await tester.pumpAndSettle();
    expect(store.boxClaims, {mine.id: 'default'}, reason: 'still only a claim');
    expect(await tester.runAsync(BoxClaims.unanswered), isEmpty);
    await tester.tap(find.text('prüfen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);

    // Another box with a claim on the same installation asks again.
    store.boxKey = newKey();
    expect(await tester.runAsync(BoxClaims.unanswered), [mine.id]);
  });

  testWidgets('Verbinden bestätigt die Anlage; die Box-Einstellungen listen offene', (tester) async {
    await pump(tester, const BoxClaimList());
    expect(find.textContaining('Die Box führt diese Anlagen'), findsOneWidget);
    expect(find.text('Kunde Meier'), findsOneWidget);
    await tester.tap(find.text('Verbinden'));
    await tester.pumpAndSettle();
    expect(find.text('Anlage mit dieser Box verbinden?'), findsOneWidget);
    await tester.tap(find.text('Verbinden').last);
    await tester.pumpAndSettle();
    // Without a reachable box the sync afterwards clears the list; with one, acceptBoxClaim binds
    // the installation first (test/keys_test.dart).
    expect(store.boxClaims, isEmpty);
    expect(find.textContaining('Die Box führt diese Anlagen'), findsNothing);
  });

  testWidgets('keine Ansprüche: keine Frage, kein Abschnitt', (tester) async {
    store.boxClaims = const {};
    await pump(tester, Column(children: [offerButton(), const BoxClaimList()]));
    await tester.tap(find.text('prüfen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Die Box führt diese Anlagen'), findsNothing);
  });
}
