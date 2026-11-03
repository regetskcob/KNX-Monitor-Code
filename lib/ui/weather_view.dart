import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../l10n/locale_controller.dart';
import '../knx/telegram.dart';
import '../model/device_channels.dart';
import '../model/device_shapes.dart';
import '../model/telegram_log.dart';
import 'device_drawing.dart';

/// Weather station (drawn neutrally): dome with brightness windows per
/// compass direction and rain sensor, below it the wind wheel that spins at
/// the measured speed, the temperature on the left. Above it the sky arc with
/// the sun position (azimuth/elevation).
class WeatherView extends StatelessWidget {
  const WeatherView({super.key, required this.address, required this.log, this.compact = false});

  /// Only the drawing (distribution board).
  final bool compact;

  final int address;
  final TelegramLog log;

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogStore.instance.catalog;
    final roles = <SensorRole, DeviceObject>{};
    final brightness = <DeviceObject>[];
    for (final o in objectsOf(address, catalog)) {
      final r = roleOf(o, catalog);
      if (r == null || !o.sends) continue;
      if (r == SensorRole.brightness) brightness.add(o);
      roles.putIfAbsent(r, () => o);
    }
    // Directions: named windows; an overall value without direction only if there are none.
    final windows = brightness.where((o) => bearingOf(catalog[o.address]?.name ?? '') != null).toList();
    if (windows.isEmpty) windows.addAll(brightness.take(1));

    String text(DeviceObject? o, Map<int, Telegram> latest) => switch (o == null ? null : latest[o.address]) {
      final t? when t.type != TelegramType.read => CatalogStore.instance.value(t),
      _ => '–',
    };
    return DeviceDrawing(
      address: address,
      log: log,
      compact: compact,
      height: 320,
      animate: roles.containsKey(SensorRole.wind),
      semantics: (latest) =>
          [
                for (final r in [
                  SensorRole.temperature,
                  SensorRole.wind,
                  SensorRole.rain,
                  ...[for (final _ in windows) null],
                ])
                  ?r,
              ]
              .map((r) => roles[r])
              .whereType<DeviceObject>()
              .followedBy(windows)
              .map((o) => '${catalog[o.address]?.name ?? formatGroup(o.address)}: ${text(o, latest)}')
              .join(', '),
      painter: (style, latest, elapsed) => _WeatherPainter(
        style: style,
        elapsed: elapsed,
        temperature: text(roles[SensorRole.temperature], latest),
        wind: numberOf(roles[SensorRole.wind]?.address ?? -1, latest),
        windText: roles.containsKey(SensorRole.wind) ? text(roles[SensorRole.wind], latest) : null,
        rain: switch (roles[SensorRole.rain]) {
          final o? => (numberOf(o.address, latest) ?? 0) > 0,
          null => null,
        },
        windows: [
          for (final o in windows)
            (bearingOf(catalog[o.address]?.name ?? ''), numberOf(o.address, latest), text(o, latest)),
        ],
        azimuth: numberOf(roles[SensorRole.azimuth]?.address ?? -1, latest),
        elevation: numberOf(roles[SensorRole.elevation]?.address ?? -1, latest),
      ),
    );
  }
}

class _WeatherPainter extends CustomPainter {
  _WeatherPainter({
    required this.style,
    required this.elapsed,
    required this.temperature,
    required this.wind,
    required this.windText,
    required this.rain,
    required this.windows,
    required this.azimuth,
    required this.elevation,
  });

  final DrawingStyle style;
  final Duration elapsed;
  final String temperature;
  final double? wind;
  final String? windText;
  final bool? rain;

  /// Richtung (Grad), Lux, Text.
  final List<(double?, double?, String)> windows;
  final double? azimuth;
  final double? elevation;

  static bool get _de => s.localeName.startsWith('de');
  static String get _east => _de ? 'O' : 'E';
  static Map<int, String> get _bearing => {
    0: 'N',
    45: 'N$_east',
    90: _east,
    135: 'S$_east',
    180: 'S',
    225: 'SW',
    270: 'W',
    315: 'NW',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final hz = style.hz;
    final cx = size.width / 2;

    // Sky arc with sun (east left, south top, west right).
    final horizon = 74.0;
    final arcW = math.min(size.width * 0.8, 320.0);
    final sky = Rect.fromCenter(center: Offset(cx, horizon), width: arcW, height: 120);
    canvas.drawArc(sky, math.pi, math.pi, false, style.stroke(hz.line));
    canvas.drawLine(Offset(sky.left - 8, horizon), Offset(sky.right + 8, horizon), style.stroke(hz.line));
    style.label(canvas, _east, Offset(sky.left - 4, horizon + 9), align: TextAlign.center, small: true, muted: true);
    style.label(canvas, 'S', Offset(cx, horizon - 68), align: TextAlign.center, small: true, muted: true);
    style.label(canvas, 'W', Offset(sky.right + 4, horizon + 9), align: TextAlign.center, small: true, muted: true);
    if (azimuth != null && elevation != null && elevation! > -2) {
      final t = ((azimuth! - 90) / 180).clamp(0.0, 1.0);
      final sun = Offset(sky.left + t * arcW, horizon - (elevation! / 90).clamp(0.0, 1.0) * 60 * 1.6);
      for (var a = 0; a < 8; a++) {
        final d = Offset.fromDirection(math.pi / 4 * a, 1);
        canvas.drawLine(sun + d * 10, sun + d * 14, style.stroke(hz.warning, 1.4));
      }
      canvas.drawCircle(sun, 7, style.fill(hz.warning));
      style.label(
        canvas,
        '${azimuth!.round()}° · ${elevation!.round()}°',
        Offset(sun.dx, sun.dy - 22),
        align: TextAlign.center,
        small: true,
        muted: true,
      );
    }

    // Wall bracket on the right with arm.
    final bodyY = 180.0;
    final arm = Rect.fromLTRB(cx + 40, bodyY + 4, cx + 120, bodyY + 12);
    canvas.drawRect(arm, style.fill(hz.sunken));
    canvas.drawRect(arm, style.stroke(hz.lineStrong));
    final bracket = RRect.fromRectAndRadius(Rect.fromLTWH(cx + 120, bodyY - 30, 18, 70), const Radius.circular(3));
    canvas.drawRRect(bracket, style.fill(hz.sunken));
    canvas.drawRRect(bracket, style.stroke(hz.lineStrong));

    // Dome with brightness windows.
    final dome = Rect.fromCenter(center: Offset(cx, bodyY), width: 170, height: 76);
    final domePath = Path()..addArc(dome, math.pi, math.pi);
    domePath.close();
    canvas.drawPath(domePath, style.fill(hz.surface));
    canvas.drawPath(domePath, style.stroke(hz.lineStrong));
    final base = RRect.fromRectAndRadius(
      Rect.fromLTWH(dome.left + 6, bodyY, dome.width - 12, 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(base, style.fill(hz.sunken));
    canvas.drawRRect(base, style.stroke(hz.lineStrong));
    final n = windows.length;
    for (final (i, (bearing, lux, value)) in windows.indexed) {
      final a = math.pi + math.pi * (i + 1) / (n + 1);
      final c = Offset(cx + math.cos(a) * dome.width * 0.36, bodyY + math.sin(a) * dome.height * 0.36);
      final win = Rect.fromCenter(center: c, width: 18, height: 12);
      // Fill by brightness, logarithmic up to 100 klx.
      final level = lux == null ? 0.0 : (math.log(lux + 1) / math.log(100001)).clamp(0.0, 1.0);
      canvas.drawOval(win, style.fill(hz.warning.withValues(alpha: 0.15 + 0.75 * level)));
      canvas.drawOval(win, style.stroke(hz.lineStrong));
      final label = bearing == null ? '' : _bearing[(bearing / 45).round() * 45 % 360] ?? '';
      // Values in a row above the dome, with a line to the window.
      final column = size.width / n;
      final at = Offset(column * (i + 0.5), dome.top - 40);
      canvas.drawLine(at + const Offset(0, 8), c - const Offset(0, 7), style.stroke(hz.line));
      style.label(
        canvas,
        [label, value].where((e) => e.isNotEmpty).join(' '),
        at,
        align: TextAlign.center,
        small: true,
        maxWidth: column - 6,
      );
    }

    // Rain sensor on top of the dome.
    if (rain != null) {
      final plate = Rect.fromCenter(center: Offset(cx, dome.top + 3), width: 26, height: 6);
      canvas.drawRect(plate, style.fill(rain! ? hz.accent : hz.sunken));
      canvas.drawRect(plate, style.stroke(hz.lineStrong));
      if (rain!) {
        for (final dx in [-16.0, -4.0, 9.0, 20.0]) {
          final top = Offset(cx + dx, dome.top - 22 + (dx.abs() % 7));
          canvas.drawLine(top, top + const Offset(-2, 8), style.stroke(hz.accent, 1.6));
        }
      }
    }

    // Wind wheel below the dome.
    if (windText != null) {
      final hub = Offset(cx, bodyY + 62);
      canvas.drawLine(Offset(cx, bodyY + 14), hub, style.stroke(hz.lineStrong, 2));
      final speed = (wind ?? 0) * 0.9; // rad/s
      final angle = elapsed.inMicroseconds / 1e6 * speed;
      for (var k = 0; k < 3; k++) {
        final a = angle + math.pi * 2 * k / 3;
        final tip = hub + Offset(math.cos(a) * 34, math.sin(a) * 9);
        canvas.drawLine(hub, tip, style.stroke(hz.lineStrong, 1.4));
        // Cup: in perspective, larger at the front.
        final front = (math.sin(a) + 1) / 2;
        final cup = Rect.fromCenter(center: tip, width: 12 + 6 * front, height: 14 + 6 * front);
        canvas.drawOval(cup, style.fill(hz.surface));
        canvas.drawOval(cup, style.stroke(hz.lineStrong));
      }
      canvas.drawCircle(hub, 3, style.fill(hz.textMuted));
      style.label(canvas, windText!, Offset(cx, hub.dy + 28), align: TextAlign.center, bold: true);
    }

    // Temperature on the left: thermometer with value.
    final th = Offset(dome.left + 10, bodyY + 58);
    final tube = RRect.fromRectAndRadius(Rect.fromCenter(center: th, width: 8, height: 34), const Radius.circular(4));
    canvas.drawRRect(tube, style.stroke(hz.lineStrong));
    canvas.drawCircle(th + const Offset(0, 19), 6, style.fill(hz.critical));
    canvas.drawLine(th + const Offset(0, 13), th + const Offset(0, -6), style.stroke(hz.critical, 3));
    style.label(canvas, temperature, Offset(th.dx, th.dy + 40), align: TextAlign.center, bold: true);
  }

  @override
  bool shouldRepaint(_WeatherPainter old) => true;
}
