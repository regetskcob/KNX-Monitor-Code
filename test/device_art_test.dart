import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/device_art.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/device_sheet.dart';
import 'package:vector_graphics/vector_graphics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Mitgelieferte Grafik passt zum Demo-Schaltaktor, Kanäle über ihren Kurznamen', () async {
    final art = DeviceArtCatalog.instance..debugReset();
    await art.load();
    final cat = demoCatalog();
    final sa8 = art.of(cat.devices[0x110A]);
    expect(sa8, isNotNull);
    expect(sa8!.size, const Size(72, 90));
    expect(sa8.asset, 'assets/device_art/demo-sa-8.vec');
    expect(sa8.channels.map((c) => c.key), ['1', '2', '3', '4', '5', '6', '7', '8']);
    expect(sa8.channel('3')!.area, const Rect.fromLTWH(34, 25, 14, 17));
    expect(sa8.channel('9'), isNull);
    // Andere Geräte haben keine Grafik und bleiben bei der Zeichnung.
    expect(art.of(cat.devices[0x110C]), isNull);
  });

  testWidgets('Gerätedetail zeigt die Herstellergrafik statt der Zeichnung', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    final art = DeviceArtCatalog.instance..debugReset();
    await tester.runAsync(art.load);
    var now = DateTime(2026, 10, 14, 21, 50);
    DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
    final tunnel = DemoTunnel();
    final log = TelegramLog()..addAll(tunnel.simulate());
    tunnel.dispose();
    DemoTunnel.clock = DateTime.now;
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('de'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: DeviceTraffic(address: 0x110A, log: log)),
      ),
    );
    await tester.pump();
    expect(find.byType(VectorGraphic), findsOneWidget);
    // Kanal antippen: nur noch seine Objekte in der Kanalspalte.
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Kanal 3 ')).first);
    await tester.pump();
    expect(find.textContaining('OG BZ L01'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
