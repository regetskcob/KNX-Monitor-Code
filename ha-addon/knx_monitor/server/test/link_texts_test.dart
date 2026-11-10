import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  test('knx_io-Meldungen auf Deutsch, Unbekanntes bleibt', () {
    expect(linkText(const LinkException('Gateway has no free tunnel')), 'Gateway meldet: keine freien Tunnel');
    expect(linkText('Host gw.local not found'), 'Host gw.local nicht gefunden');
    expect(linkText('etwas anderes'), 'etwas anderes');
    expect(linkLabel('FT1.2 bus monitor 15.15.255'), 'KNX-HAT Busmonitor 15.15.255');
  });

  test('Bericht der HAT-Prüfung: alle error-Texte übersetzt', () {
    final report = linkReport({
      'steps': [
        {'step': 'linkLayer', 'error': 'M_PropWrite PID 52 = 0x00 rejected'},
        {
          'step': 'reset',
          'tried': [19200],
          'error': 'FT1.2 module stopped responding',
        },
      ],
    });
    expect(report, {
      'steps': [
        {'step': 'linkLayer', 'error': 'M_PropWrite PID 52 = 0x00 abgelehnt'},
        {
          'step': 'reset',
          'tried': [19200],
          'error': 'KNX-HAT antwortet nicht mehr',
        },
      ],
    });
  });
}
