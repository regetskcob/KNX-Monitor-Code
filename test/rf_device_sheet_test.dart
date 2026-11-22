import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/device_art.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/device_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(320, 700), Size(393, 852)]) {
    testWidgets('device sheet of the RF smoke detector fits a phone ($size)', (tester) async {
      CatalogStore.instance.catalog = demoCatalog();
      final art = DeviceArtCatalog.instance..debugReset();
      await tester.runAsync(art.load);
      var now = DateTime(2026, 11, 22, 10);
      DemoTunnel.clock = () => now = now.add(const Duration(milliseconds: 900));
      final tunnel = DemoTunnel();
      final log = TelegramLog()..addAll(tunnel.simulate(steps: 4000));
      tunnel.dispose();
      DemoTunnel.clock = DateTime.now;
      expect(log.log.where((t) => t.source == DemoTunnel.rfDevice), isNotEmpty, reason: 'smoke detector sent nothing');
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('de'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DeviceTraffic(address: DemoTunnel.rfDevice, log: log),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('FUNKSIGNAL'), findsOneWidget);
      expect(find.text('BATTERIE'), findsOneWidget);
      expect(find.text('schwach'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    });
  }
}
