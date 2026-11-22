import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/ui/ai_access_screen.dart';
import 'package:knx_monitor/ui/figure_box.dart';

import 'window.dart';

class _FakeClient extends AiAccessClient {
  _FakeClient({required this.enabled});
  bool enabled;
  int renewed = 0;

  Map<String, Object?> get _settings => {
    'enabled': enabled,
    'token': 'bc_0123456789abcdef$renewed',
    'path': '/api/mcp',
  };

  @override
  Future<Map<String, Object?>> settings() async => _settings;

  @override
  Future<Map<String, Object?>> configure({bool? enabled, bool renew = false}) async {
    this.enabled = enabled ?? this.enabled;
    if (renew) renewed++;
    return _settings;
  }

  @override
  Future<String?> endpoint(String path) async => '$scheme://192.168.1.20:8765$path';

  String scheme = 'http';
}

class _FailingClient extends AiAccessClient {
  _FailingClient(this.error);
  final Object error;

  @override
  Future<Map<String, Object?>> settings() => Future.error(error);
}

void main() {
  const address = 'http://192.168.1.20:8765/api/mcp';
  // Phone width, tall enough that the list builds every row.
  const tallPhone = Size(390, 2400);

  testWidgets('1400 pt: Schalter links, Hinweis, Verbindung und Befehl rechts daneben', (tester) async {
    final client = _FakeClient(enabled: false);
    await pumpWindow(tester, AiAccessScreen(client: client), wideWindow);
    await tester.pumpAndSettle();
    final toggle = tester.getTopLeft(find.byType(SwitchRow));
    final notice = tester.getTopLeft(find.textContaining('Wer den Token hat'));
    expect(toggle.dx, lessThan(wideWindow.width / 2));
    expect(notice.dx, greaterThan(wideWindow.width / 2), reason: 'schon vor dem Einschalten zu lesen');
    expect(find.text('Verbindung'), findsNothing);
    // The explaining text stays a reading column.
    expect(tester.getSize(find.textContaining('Model Context Protocol')).width, lessThan(wideWindow.width * 0.6));

    await tester.tap(find.byType(SwitchRow));
    await tester.pumpAndSettle();
    expect(client.enabled, isTrue);
    for (final head in ['Verbindung', 'Für Claude Code']) {
      expect(tester.getTopLeft(find.text(head)).dx, greaterThan(wideWindow.width / 2));
    }
    expect(find.text(address), findsOneWidget);
    expect(find.textContaining('claude mcp add --transport http busclear $address'), findsOneWidget);
    expect(find.text('bc_012…'), findsOneWidget, reason: 'der Token steht nicht ausgeschrieben in der Zeile');

    await tester.tap(find.text('Neuen Token erzeugen'));
    await tester.pumpAndSettle();
    expect(client.renewed, 1);
    expect(find.textContaining('bc_0123456789abcdef1'), findsOneWidget);
  });

  testWidgets('Token und Befehl gehen als Geheimnis in die Zwischenablage, die Adresse normal', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final secrets = <Object?>[];
    final plain = <Object?>[];
    messenger.setMockMethodCallHandler(const MethodChannel('knx/native'), (call) async {
      if (call.method == 'copySecret') secrets.add((call.arguments as Map)['text']);
      return true;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') plain.add((call.arguments as Map)['text']);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(const MethodChannel('knx/native'), null);
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    for (final window in [tallPhone, wideWindow]) {
      secrets.clear();
      plain.clear();
      await pumpWindow(tester, AiAccessScreen(client: _FakeClient(enabled: true)), window);
      await tester.pumpAndSettle();
      // Every copy button has a name for screen readers and on hover.
      final buttons = find.byTooltip('Kopieren');
      expect(buttons, findsNWidgets(2));
      await tester.tap(buttons.first);
      await tester.pump();
      expect(plain, [address]);
      expect(secrets, isEmpty);
      await tester.ensureVisible(buttons.last);
      await tester.tap(buttons.last);
      await tester.pump();
      await tester.ensureVisible(find.text('Befehl kopieren'));
      await tester.tap(find.text('Befehl kopieren'));
      await tester.pump();
      expect(secrets, ['bc_0123456789abcdef0', contains('Bearer bc_0123456789abcdef0')]);
      expect(plain, [address], reason: 'der Token landet nie in der gewöhnlichen Zwischenablage');
      await tester.pumpAndSettle(const Duration(seconds: 5));
    }
  });

  testWidgets('HTTP-Adresse: Hinweis auf Klartext, bei HTTPS nicht', (tester) async {
    await pumpWindow(tester, AiAccessScreen(client: _FakeClient(enabled: true)), tallPhone);
    await tester.pumpAndSettle();
    expect(find.textContaining('Diese Adresse ist unverschlüsselt'), findsOneWidget);
    await pumpWindow(tester, AiAccessScreen(client: _FakeClient(enabled: true)..scheme = 'https'), wideWindow);
    await tester.pumpAndSettle();
    expect(find.textContaining('Diese Adresse ist unverschlüsselt'), findsNothing);
  });

  testWidgets('Fehler: keine rohe Exception, die Meldung des Servers bleibt', (tester) async {
    await pumpWindow(tester, AiAccessScreen(client: _FailingClient(StateError('Bad state: null check'))), phoneWindow);
    await tester.pumpAndSettle();
    expect(find.textContaining('Bad state'), findsNothing);
    expect(find.text('Das hat nicht geklappt. Versuch es noch einmal.'), findsOneWidget);

    await pumpWindow(
      tester,
      AiAccessScreen(client: _FailingClient(const AddonException('Box: HTTP 500', status: 500))),
      wideWindow,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('HTTP 500'), findsNothing);

    await pumpWindow(
      tester,
      AiAccessScreen(client: _FailingClient(const AddonException('Nur mit Admin-Rechten.'))),
      phoneWindow,
    );
    await tester.pumpAndSettle();
    expect(find.text('Nur mit Admin-Rechten.'), findsOneWidget);
  });

  testWidgets('Telefon: eine Liste wie bisher, auch bei doppelter Schrift ohne Überlauf', (tester) async {
    for (final scale in [1.0, 2.0]) {
      await pumpWindow(tester, AiAccessScreen(client: _FakeClient(enabled: true)), phoneWindow, textScale: scale);
      await tester.pumpAndSettle();
      expect(find.byType(SectionHead), findsNothing);
      expect(find.byType(SwitchRow), findsNothing);
      // Doubled text only has to fit; the list builds its lower rows as they scroll in.
      if (scale > 1) continue;
      expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == address), findsOneWidget);
      final toggle = tester.getTopLeft(find.text('KI-Zugriff erlauben'));
      expect(tester.getTopLeft(find.text('Adresse')).dx, toggle.dx);
      expect(tester.getTopLeft(find.text('Adresse')).dy, greaterThan(toggle.dy));
    }
  });
}
