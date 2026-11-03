import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/gateway_info.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/connect_help.dart';
import 'package:knx_monitor/model/connection_options.dart';

import 'fake_gateway.dart';

void main() {
  group('connectHelp', () {
    test('Jeder bekannte Grund hat Titel und mindestens einen Schritt', () {
      for (final p in ConnectProblem.values) {
        final help = connectHelp(p, mode: ConnectionMode.udp, port: 3671)!;
        expect(help.title, isNotEmpty, reason: p.name);
        expect(help.steps, isNotEmpty, reason: p.name);
      }
      expect(connectHelp(null, mode: ConnectionMode.udp, port: 3671), isNull);
    });

    test('Ungewöhnlicher Port steht bei Zeitüberschreitung zuerst', () {
      final help = connectHelp(ConnectProblem.noResponse, mode: ConnectionMode.udp, port: 3672)!;
      expect(help.steps.first, s.helpOddPort(3672));
      expect(help.actions, [HelpAction.scan]);
      expect(
        connectHelp(ConnectProblem.noResponse, mode: ConnectionMode.udp, port: 3671)!.steps,
        isNot(contains(s.helpOddPort(3671))),
      );
    });

    test('Tunnel belegt verweist auf die Suche, Secure auf Keyring und Projektdatei', () {
      expect(connectHelp(ConnectProblem.noFreeTunnel, mode: ConnectionMode.udp, port: 3671)!.steps, [
        s.helpTunnelsHeld,
        s.helpCloseEts,
        s.helpScanShowsSlots,
        s.helpUseRouting,
      ]);
      expect(connectHelp(ConnectProblem.secureMissing, mode: ConnectionMode.secure, port: 3671)!.actions, [
        HelpAction.keyring,
        HelpAction.projectHelp,
      ]);
      expect(
        connectHelp(ConnectProblem.network, mode: ConnectionMode.tcp, port: 3671)!.steps,
        contains(s.helpTcpPort(3671)),
      );
    });

    test('Keine Suche über die Box ohne „gleiches Netz“', () {
      expect(noGatewayHelp().steps.first, s.helpSameNetwork);
      expect(noGatewayHelp(box: true).steps, isNot(contains(s.helpSameNetwork)));
      expect(noGatewayHelp().actions, [HelpAction.demo]);
    });

    test('Freie Tunnel aus der Gateway-Beschreibung', () {
      const info = GatewayInfo(
        name: 'IP',
        medium: 2,
        programmingMode: false,
        address: 0x11FF,
        serial: '',
        mac: '',
        multicast: '',
        projectInstallation: 0,
        slots: [
          TunnelSlot(0x11F1, free: true, usable: true),
          TunnelSlot(0x11F2, free: false, usable: true),
          TunnelSlot(0x11F3, free: true, usable: false),
        ],
      );
      expect(freeTunnels(info), '1 von 3 Tunneln frei');
      const noSlots = GatewayInfo(
        name: 'Router',
        medium: 2,
        programmingMode: false,
        address: 0x1100,
        serial: '',
        mac: '',
        multicast: '',
        projectInstallation: 0,
      );
      expect(freeTunnels(noSlots), isNull);
    });
  });

  group('Gründe am Tunnel', () {
    late FakeGateway gateway;
    setUp(() async => gateway = await FakeGateway.start());
    tearDown(() => gateway.close());

    test('Keine freien Tunnel', () async {
      gateway.full = true;
      final tunnel = KnxTunnel('127.0.0.1', port: gateway.port);
      await expectLater(
        tunnel.connect(),
        throwsA(isA<KnxException>().having((e) => e.problem, 'problem', ConnectProblem.noFreeTunnel)),
      );
      tunnel.dispose();
    });

    test('Keine Antwort', () async {
      final tunnel = KnxTunnel('127.0.0.1', port: gateway.port + 1);
      await expectLater(
        tunnel.connect(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<KnxException>().having((e) => e.problem, 'problem', ConnectProblem.noResponse)),
      );
      tunnel.dispose();
    });
  });
}
