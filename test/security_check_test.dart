import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/gateway_info.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knx_tunnel.dart';
import 'package:knx_monitor/knx/routing_tunnel.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/security_check.dart';

int _ga(String s) => parseGroup(s)!;
int _pa(String s) => parseIndividual(s)!;

Telegram _t(String source, String ga) => Telegram(
  time: DateTime(2026, 10, 29),
  source: _pa(source),
  destination: _ga(ga),
  type: TelegramType.write,
  data: Uint8List.fromList([1]),
  isSmall: true,
);

GatewayInfo _gateway({required bool secure}) => GatewayInfo(
  name: 'IP',
  medium: 0x02,
  programmingMode: false,
  address: _pa('1.1.250'),
  serial: '000000000000',
  mac: '00:00:00:00:00:00',
  multicast: '224.0.23.12',
  projectInstallation: 0,
  services: {0x02: 2, 0x04: 2, if (secure) 0x09: 1},
);

final _catalog = GroupCatalog(
  {
    for (final ga in ['1/1/1', '1/1/2', '6/0/0', '6/0/1']) _ga(ga): GroupInfo(address: _ga(ga), name: ga),
  },
  devices: {_pa('1.1.10'): DeviceInfo(address: _pa('1.1.10'), name: 'Aktor')},
);

void main() {
  test('Verbindungsart aus dem Tunnel', () {
    expect(LinkSecurity.of(KnxTunnel('192.0.2.1')), LinkSecurity.plainTunnel);
    expect(LinkSecurity.of(RoutingTunnel(address: _pa('1.1.254'))), LinkSecurity.plainRouting);
    expect(LinkSecurity.of(DemoTunnel()), LinkSecurity.demo);
  });

  test('Demo-Haus: eigener Hinweis statt „Home Assistant bzw. Demo“', () {
    final check = SecurityCheck.of(
      SecurityInput(link: LinkSecurity.demo, catalog: GroupCatalog(const {}), telegrams: const []),
    );
    expect(check.findings.first.title, 'Demo-Haus');
    expect(check.findings.first.text, isNot(contains('Home Assistant')));
  });

  test('Ungesicherter Tunnel, obwohl das Gateway Secure kann: Empfehlung', () {
    final check = SecurityCheck.of(
      SecurityInput(
        link: LinkSecurity.plainTunnel,
        catalog: _catalog,
        telegrams: [_t('1.1.10', '1/1/1'), _t('1.1.10', '6/0/0')],
        gateway: _gateway(secure: true),
        securedGroups: {_ga('6/0/0'), _ga('6/0/1')},
        keyringLoaded: true,
      ),
    );
    expect(check.gatewaySecure, isTrue);
    expect(check.findings.first.level, SecurityLevel.advice);
    expect(check.findings.first.title, contains('Secure'));
    expect((check.projectSecured, check.projectGroups), (2, 4));
    expect((check.seenSecured, check.seenGroups), (1, 2));
    expect(check.foreign, isEmpty);
    expect(check.findings.last.level, SecurityLevel.good); // alle Absender bekannt
  });

  test('Gateway ohne Secure: nur Hinweis, keine Empfehlung', () {
    final check = SecurityCheck.of(
      SecurityInput(
        link: LinkSecurity.plainTunnel,
        catalog: _catalog,
        telegrams: const [],
        gateway: _gateway(secure: false),
      ),
    );
    expect(check.findings.first.level, SecurityLevel.info);
    expect(check.gatewaySecure, isFalse);
  });

  test('IP Secure, fremde Absender und Telegramme ohne Schlüssel', () {
    final check = SecurityCheck.of(
      SecurityInput(
        link: LinkSecurity.ipSecure,
        catalog: _catalog,
        telegrams: [
          _t('1.1.10', '1/1/1'),
          _t('1.1.200', '1/1/1'),
          _t('1.1.200', '1/1/2'),
          _t('1.1.201', '1/1/2'),
          _t('1.1.255', '1/1/2'), // eigener Tunnel
        ],
        ownAddresses: {_pa('1.1.255')},
        keyringLoaded: true,
        securedGroups: {_ga('6/0/0')},
        secureWithoutKey: 3,
        secureRejected: 1,
      ),
    );
    expect(check.findings.first.level, SecurityLevel.good);
    expect(check.foreign.map((f) => (formatIndividual(f.address), f.count)), [('1.1.200', 2), ('1.1.201', 1)]);
    expect(check.foreign.first.groups, {_ga('1/1/1'), _ga('1/1/2')});
    final titles = check.findings.map((f) => f.title).toList();
    expect(titles, contains(contains('ohne Schlüssel')));
    expect(titles, contains(contains('Ungültige')));
    expect(titles.last, '2 Absender nicht im Projekt');
  });

  test('Ohne Keyring und ohne Topologie: ruhige Hinweise', () {
    final check = SecurityCheck.of(
      SecurityInput(
        link: LinkSecurity.unknown,
        catalog: GroupCatalog(const {}),
        telegrams: [_t('1.1.200', '1/1/1')],
        secureWithoutKey: 4,
      ),
    );
    expect(check.findings.every((f) => f.level == SecurityLevel.info), isTrue);
    expect(check.findings[1].text, contains('4 Telegramme'));
    expect(check.foreign, isEmpty);
  });
}
