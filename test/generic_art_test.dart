import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/device_art.dart';
import 'package:knx_monitor/model/device_channels.dart';

/// Generischer Aktor in der neutralen Optik „A“: Breite nach Kanalzahl,
/// Beschriftungsfeld je Kanal, Relais-Symbol nur bei Schaltkanälen.
void main() {
  List<String> keys(int n) => [for (var i = 1; i <= n; i++) '$i'];

  test('Breite in TE nach Kanalzahl, Höhe wie Herstellergrafiken', () {
    expect(genericArt(keys(2)).size, const Size(36, 90)); // 2 TE
    expect(genericArt(keys(8)).size, const Size(72, 90)); // 4 TE, zwei Reihen
    expect(genericArt(keys(16)).size.width, 144); // 8 TE
    expect(genericArt(keys(24)).size.width % 18, 0);
  });

  test('bis vier Kanäle eine Reihe, darüber zwei', () {
    expect(genericArt(keys(4)).channels.map((c) => c.area.top).toSet(), {30.0});
    expect(genericArt(keys(8)).channels.map((c) => c.area.top).toSet(), {25.0, 45.0});
  });

  test('Felder für Namen und Adresse, Relais nur beim Schalten', () {
    final art = genericArt(['A', 'B', 'C'], [ChannelKind.switching, ChannelKind.blind, ChannelKind.dimming]);
    expect(art.channels.every((c) => c.label != null && c.led != null), isTrue);
    expect([for (final c in art.channels) c.contact != null], [true, false, false]);
    expect(art.channelKinds, [ChannelKind.switching, ChannelKind.blind, ChannelKind.dimming]);
    expect(art.address, isNotNull);
    expect(art.bus!.right, lessThanOrEqualTo(art.size.width));
    // Kanäle liegen innerhalb des Geräts.
    for (final c in art.channels) {
      expect(c.area.left, greaterThanOrEqualTo(0));
      expect(c.area.right, lessThanOrEqualTo(art.size.width));
    }
  });
}
