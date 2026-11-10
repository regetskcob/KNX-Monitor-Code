import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/busmon.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/shared_tunnel.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/busmonitor_screen.dart';

/// Box with the KNX HAT in bus monitor mode: the server delivers the raw frames.
class _HatTunnel extends SharedTunnel {
  _HatTunnel() {
    status.value = {
      'config': {'mode': 'hat', 'hatBusmonitor': true},
    };
  }

  // Not closed on purpose: lives as long as the fake.
  // ignore: close_sinks
  final controller = StreamController<BusmonFrame>.broadcast();

  @override
  Stream<BusmonFrame> get busmon => controller.stream;
}

/// Standard frame 1.1.5 → 1/2/3 with a correct checksum.
BusmonFrame _data() {
  final body = [0xBC, 0x11, 0x05, 0x0A, 0x03, 0xE1, 0x00, 0x81];
  return BusmonFrame.fromRaw(
    Uint8List.fromList([...body, ~body.fold<int>(0, (a, b) => a ^ b) & 0xFF]),
    time: DateTime(2026, 11, 7),
  );
}

BusmonFrame _ack() => BusmonFrame.fromRaw(Uint8List.fromList([0xCC]), time: DateTime(2026, 11, 7));

void main() {
  testWidgets('ACK ohne Datenrahmen davor: Hinweis auf den kBerry und den Link Layer (Issue #1)', (tester) async {
    final tunnel = _HatTunnel();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BusMonitorScreen(monitor: tunnel),
      ),
    );
    await tester.pump();

    // Data frame with its ACK: no hint.
    tunnel.controller
      ..add(_data())
      ..add(_ack());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('ohne Datenrahmen davor'), findsNothing);

    // Two ACKs whose data frames the module left out.
    tunnel.controller
      ..add(_ack())
      ..add(_ack());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('2 Quittungen ohne Datenrahmen davor'), findsOneWidget);
    expect(find.textContaining('Link Layer'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tunnel.controller.close();
  });

  testWidgets('nach dem Neuverbinden gehört die erste Quittung nicht zum alten Datenrahmen', (tester) async {
    final tunnel = _HatTunnel()..state.value = TunnelState.connected;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: BusMonitorScreen(monitor: tunnel),
      ),
    );
    await tester.pump();
    tunnel.controller.add(_data());
    await tester.pump(const Duration(milliseconds: 100));
    // The server loses the module and connects again (as after M_Reset.ind).
    tunnel.state.value = TunnelState.disconnected;
    tunnel.state.value = TunnelState.connected;
    tunnel.controller.add(_ack());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('1 Quittung ohne Datenrahmen davor'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tunnel.controller.close();
  });
}
