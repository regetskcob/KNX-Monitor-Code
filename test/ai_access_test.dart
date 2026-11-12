import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<String?> endpoint(String path) async => 'http://192.168.1.20:8765$path';
}

void main() {
  const address = 'http://192.168.1.20:8765/api/mcp';

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
