import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/write_notice.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/send_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_gateway.dart';

// Schreiben von Anfang bis Ende, ohne Bus: das Schreib-Blatt der App über
// einen echten KNXnet/IP-Tunnel an ein Gateway auf localhost, das jedes
// Telegramm abfängt (FakeGateway.requests) statt es auf eine Linie zu legen.
void main() {
  setUp(() => WriteNotice.instance.debugDismiss());
  testWidgets('Schreib-Blatt sendet GroupValueWrite an das Gateway', (tester) async {
    SharedPreferences.setMockInitialValues({});
    CatalogStore.instance.catalog = GroupCatalog.empty;
    final gateway = (await tester.runAsync(FakeGateway.start))!;
    final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
    await tester.runAsync(tunnel.connect);
    addTearDown(() async {
      await tester.runAsync(tunnel.disconnect);
      gateway.close();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(onPressed: () => showSendSheet(context, tunnel), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Gruppenadresse 1/2/3, Wert 1 (ohne Projekt wählt das Blatt Prozent, 5.001).
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '1/2/3');
    await tester.pump();
    await tester.enterText(find.byType(TextField).last, '01');
    await tester.pump();
    // „Schreiben“ steht auch auf dem Umschalter Schreiben/Lesen: der Knopf ist der letzte.
    final button = find.text(s.writeButton).last;
    await tester.ensureVisible(button);
    await tester.tap(button);
    // Echte Sockets und Zeitgeber der App abwechselnd laufen lassen.
    for (var i = 0; i < 40 && find.textContaining(s.confirmAcknowledged).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    }

    final writes = [
      for (final c in gateway.requests)
        if (c[3] & 0x80 != 0 && ((c[9] & 0x03) << 8 | c[10]) & 0x3C0 == 0x080) c,
    ];
    expect(writes, hasLength(1), reason: 'genau ein GroupValueWrite');
    final c = writes.single;
    expect((c[6] << 8) | c[7], 0x0A03, reason: 'Ziel 1/2/3');
    expect(c.sublist(11), [0x03], reason: '1 % = 3/255 als ein Datenbyte');
    expect(find.textContaining(s.confirmAcknowledged), findsOneWidget, reason: 'Quittung vom Gateway angezeigt');
  });
}
