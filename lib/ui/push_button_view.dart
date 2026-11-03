import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/device_channels.dart';
import '../model/push_buttons.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'actuator_view.dart';
import 'telegram_row.dart';

/// Push button as a front view: frame 55 with rockers or a glass push button
/// with sensor areas and display, to scale, so the glass push button is larger.
/// A button press (telegram from the push button itself) lights the button for
/// [pressGlow]; if the feedback then reports "on", the LED goes off briefly and
/// then lights until the feedback reports "off".
/// Tapping a button shows its objects with the current values.
class PushButtonView extends StatefulWidget {
  const PushButtonView({super.key, required this.button, required this.log, this.compact = false});

  final PushButton button;
  final TelegramLog log;

  /// Only the drawing, without type, last press and objects (distribution board).
  final bool compact;

  @override
  State<PushButtonView> createState() => _PushButtonViewState();
}

/// Last pressed: function, button (0 = whole function) and telegram.
typedef _Press = (ButtonFunction, int, Telegram);

class _PushButtonViewState extends State<PushButtonView> with SingleTickerProviderStateMixin {
  /// Last seen telegram per address; detects new presses and provides the
  /// previous value (setpoint ±).
  final _seen = <int, Telegram>{};

  /// Time of the last press per button.
  final _pressedAt = <int, DateTime>{};
  _Press? _last;
  int? _selected;
  int _page = 0;
  late final Ticker _ticker = createTicker((_) {
    final now = DateTime.now();
    if (_pressedAt.values.every((t) => now.difference(t) > pressGlow + pressGap)) _ticker.stop();
    setState(() {});
  });

  PushButton get _button => widget.button;

  @override
  void initState() {
    super.initState();
    for (final f in _button.functions) {
      for (final o in f.channel.objects) {
        if (widget.log.latest[o.address] case final t?) _seen[o.address] = t;
      }
    }
    widget.log.addListener(_onLog);
  }

  @override
  void dispose() {
    widget.log.removeListener(_onLog);
    _ticker.dispose();
    super.dispose();
  }

  void _onLog() {
    final now = DateTime.now();
    var pressed = false;
    for (final f in _button.functions) {
      for (final o in f.channel.objects) {
        final t = widget.log.latest[o.address];
        final before = _seen[o.address];
        if (t == null || identical(t, before)) continue;
        _seen[o.address] = t;
        final key = pressedKey(f, _button.address, t, previous: before);
        if (key == null) continue;
        for (final k in key == 0 ? f.keys : [key]) {
          _pressedAt[k] = now;
        }
        _last = (f, key, t);
        _page = _button.slotOf(key == 0 ? f.first : key).$1;
        pressed = true;
      }
    }
    if (!mounted) return;
    if (pressed && !_ticker.isActive) _ticker.start();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final label = (theme.textTheme.labelSmall ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: hz.text,
    );
    final store = CatalogStore.instance;
    final latest = widget.log.latest;
    final device = store.device(_button.address);
    final now = DateTime.now();
    final fade = !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    final status = {for (final f in _button.functions) f.first: statusOf(f, latest)};
    // Room temperature with one decimal place, as on the display.
    final temperature = switch (_button.temperature) {
      final a? => switch (latest[a]) {
        final t? => numericValue(store.dptOf(a), t)?.toStringAsFixed(1).replaceAll('.', decimalSeparator),
        null => null,
      },
      null => null,
    };

    final keys = <int, _KeyState>{};
    for (final f in _button.functions) {
      for (final k in f.keys) {
        final at = _pressedAt[k];
        final since = at == null ? null : now.difference(at);
        final on = status[f.first] == true;
        keys[k] = _KeyState(
          led: ledLevel(sincePress: since, status: on, fade: fade),
          pressed: since == null || since >= pressGlow + pressGap
              ? 0
              : ledLevel(sincePress: since, status: false, fade: fade),
        );
      }
    }
    final selected = _selected == null ? null : _button.functions[_selected!];
    final meta = (theme.textTheme.bodySmall ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: hz.textMuted,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final panel = _Panel(_button, constraints.maxWidth);
            return SizedBox(
              height: panel.outer.height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _PanelPainter(
                        panel: panel,
                        button: _button,
                        page: _page,
                        keys: keys,
                        selected: selected,
                        temperature: temperature,
                        hz: context.hzDevice,
                        text: label,
                      ),
                    ),
                  ),
                  for (var slot = 0; slot < _button.keysPerPage; slot++)
                    if (_button.functionOf(_page * _button.keysPerPage + slot + 1) case final f?)
                      Positioned.fromRect(
                        rect: panel.key(slot),
                        child: _keyTarget(f, _page * _button.keysPerPage + slot + 1, status[f.first]),
                      ),
                  if (panel.display case final d? when _button.pages > 1)
                    Positioned.fromRect(
                      rect: d,
                      child: Semantics(
                        button: true,
                        label: s.buttonPage('${_page + 1}', '${_button.pages}'),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _page = (_page + 1) % _button.pages),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        if (!widget.compact) ...[
          const SizedBox(height: HzSpace.s8),
          Text(
            [
              device?.product ?? device?.name ?? '',
              formatIndividual(_button.address),
              if (_button.style == PanelStyle.frame55 && temperature != null) '$temperature °C',
            ].where((e) => e.isNotEmpty).join(metaSeparator),
            textAlign: TextAlign.center,
            style: meta,
          ),
          Text(
            switch (_last) {
              (final f, final key, final t) => s.buttonLastPress(
                [key == 0 ? f.label : 'T$key', ?f.channel.title].join(' '),
                store.value(t),
                formatTime(t.time, millis: false),
              ),
              null => s.buttonNoPress,
            },
            textAlign: TextAlign.center,
            style: meta,
          ),
          AnimatedSize(
            duration: Motion.of(context),
            curve: Motion.curve,
            child: selected == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: HzSpace.s8),
                    child: ChannelObjects(channel: selected.channel, latest: latest),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _keyTarget(ButtonFunction f, int key, bool? on) {
    final index = _button.functions.indexOf(f);
    final title = f.channel.title;
    return Semantics(
      button: true,
      selected: _selected == index,
      label: s.buttonKeySemantics(
        [key == f.first && f.second == null ? f.label : 'T$key', ?title].join(' '),
        on == null ? '–' : (on ? s.deviceOn : s.deviceOff),
      ),
      excludeSemantics: true,
      child: Tooltip(
        message: [f.label, ?title].join(' · '),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = _selected == index ? null : index),
        ),
      ),
    );
  }
}

/// State of a button for the drawing.
class _KeyState {
  const _KeyState({required this.led, required this.pressed});

  /// Brightness of the LED (0 … 1).
  final double led;

  /// Highlight of the surface after a press (0 … 1).
  final double pressed;
}

/// Dimensions of the front view in millimeters, scaled to the width; shared by
/// painting and tapping. Both designs at the same scale.
class _Panel {
  _Panel(this.button, double width) {
    scale = math.min(3.0, width / 92);
    final side = (glass ? 92.0 : 80.0) * scale;
    outer = Rect.fromLTWH((width - side) / 2, 0, side, side);
  }

  final PushButton button;
  late final double scale;
  late final Rect outer;

  bool get glass => button.style == PanelStyle.glass;
  int get rows => button.keysPerPage ~/ 2;

  Rect mm(double x, double y, double w, double h) =>
      Rect.fromLTWH(outer.left + x * scale, outer.top + y * scale, w * scale, h * scale);

  /// Insert 55 × 55 in the frame.
  Rect get insert => mm(12.5, 12.5, 55, 55);

  /// Display in the middle of the glass push button.
  Rect? get display => glass ? mm(37, 31, 18, 30) : null;

  /// Area of a button (slot 0 … top left, row by row).
  Rect key(int slot) {
    final col = slot % 2, row = slot ~/ 2;
    if (glass) {
      final h = 72.0 / rows;
      return mm(col == 0 ? 5 : 58, 10 + row * h, 29, h - 3);
    }
    final h = (52.0 - (rows - 1)) / rows;
    return mm(14 + col * 26.5, 14 + row * (h + 1), 25.5, h);
  }

  /// LED of a button: on the outer edge for the glass push button, otherwise top center.
  Offset led(int slot) {
    final r = key(slot);
    if (!glass) return Offset(r.center.dx, r.top + 3 * scale);
    return Offset(slot.isEven ? r.left + 3 * scale : r.right - 3 * scale, r.center.dy);
  }
}

/// Drawing of the push button (illustration) in the theme's surfaces and lines;
/// LED and display in device colors, without glow or gradient.
class _PanelPainter extends CustomPainter {
  _PanelPainter({
    required this.panel,
    required this.button,
    required this.page,
    required this.keys,
    required this.selected,
    required this.temperature,
    required this.hz,
    required this.text,
  });

  final _Panel panel;
  final PushButton button;
  final int page;
  final Map<int, _KeyState> keys;
  final ButtonFunction? selected;
  final String? temperature;
  final HorizontColors hz;
  final TextStyle text;

  Paint _stroke(Color c, [double w = Lines.hairline]) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w;

  @override
  void paint(Canvas canvas, Size size) {
    final sc = panel.scale;
    final outer = RRect.fromRectAndRadius(panel.outer, Radius.circular((panel.glass ? 3 : 4) * sc));
    canvas.drawRRect(outer, Paint()..color = hz.surface);
    canvas.drawRRect(outer, _stroke(hz.lineStrong));
    if (panel.glass) {
      // Glaskante
      canvas.drawRRect(outer.deflate(1.5 * sc), _stroke(hz.line));
      _display(canvas);
    } else {
      final insert = RRect.fromRectAndRadius(panel.insert, Radius.circular(1.5 * sc));
      canvas.drawRRect(insert, Paint()..color = hz.sunken);
      canvas.drawRRect(insert, _stroke(hz.line));
    }

    for (var slot = 0; slot < button.keysPerPage; slot++) {
      final key = page * button.keysPerPage + slot + 1;
      final f = button.functionOf(key);
      final r = panel.key(slot);
      final shape = RRect.fromRectAndRadius(r, Radius.circular((panel.glass ? 2 : 1.5) * sc));
      final state = keys[key];
      if (panel.glass) {
        // Sensor areas only hinted at, like the print under the glass.
        canvas.drawRRect(shape, _stroke(hz.line.withValues(alpha: 0.7)));
      } else {
        canvas.drawRRect(shape, Paint()..color = hz.surface);
        canvas.drawRRect(shape, _stroke(hz.lineStrong));
      }
      if (f != null && identical(f, selected)) {
        canvas.drawRRect(shape, Paint()..color = hz.accentTint);
        canvas.drawRRect(shape.deflate(Lines.selection / 2), _stroke(hz.accent, Lines.selection));
      }
      if (state != null && state.pressed > 0) {
        canvas.drawRRect(shape, Paint()..color = hz.accent.withValues(alpha: 0.22 * state.pressed));
      }
      // LED: off = ring, on = filled (not just color).
      final led = panel.led(slot);
      final radius = math.max(3.0, 1.0 * sc);
      if (f != null) {
        canvas.drawCircle(led, radius, Paint()..color = hz.line);
        if (state != null && state.led > 0) {
          canvas.drawCircle(led, radius, Paint()..color = Palette.ledOn.withValues(alpha: state.led));
        }
        canvas.drawCircle(led, radius, _stroke(hz.lineStrong));
      } else if (panel.glass) {
        canvas.drawCircle(led, radius * 0.6, Paint()..color = hz.line);
      }
      if (f != null) _labels(canvas, slot, key, f);
    }
  }

  void _labels(Canvas canvas, int slot, int key, ButtonFunction f) {
    final sc = panel.scale;
    final r = panel.key(slot);
    final glyph = switch (f.second) {
      null => '',
      final second => switch (f.channel.kind) {
        ChannelKind.blind => key == second ? ' ▼' : ' ▲',
        _ => key == second ? ' −' : ' +',
      },
    };
    final head = 'T$key$glyph';
    final title = f.channel.title ?? '';
    if (panel.glass) {
      // Label from the outer edge inwards, next to the LED.
      final left = slot.isEven;
      final width = r.width - 7 * sc;
      final x = left ? r.left + 6 * sc : r.right - 6 * sc;
      final align = left ? TextAlign.left : TextAlign.right;
      _text(canvas, head, Offset(x, r.center.dy - 13), align: align, bold: true, maxWidth: width);
      _text(canvas, title, Offset(x, r.center.dy + 1), align: align, small: true, maxWidth: width, lines: 2);
    } else {
      final width = r.width - 3 * sc;
      _text(canvas, head, Offset(r.center.dx, r.top + 5.5 * sc), align: TextAlign.center, bold: true, maxWidth: width);
      _text(
        canvas,
        title,
        Offset(r.center.dx, r.top + 5.5 * sc + 14),
        align: TextAlign.center,
        small: true,
        maxWidth: width,
        lines: r.height > 20 * sc ? 2 : 1,
      );
    }
  }

  void _display(Canvas canvas) {
    final d = panel.display!;
    final shape = RRect.fromRectAndRadius(d, Radius.circular(1 * panel.scale));
    canvas.drawRRect(shape, Paint()..color = Palette.display);
    canvas.drawRRect(shape, _stroke(hz.line));
    final value = text.copyWith(color: Palette.displayText);
    _text(
      canvas,
      temperature ?? '–',
      Offset(d.center.dx, d.center.dy - 16),
      align: TextAlign.center,
      bold: true,
      maxWidth: d.width - 4,
      style: value.apply(fontSizeFactor: 1.15),
    );
    if (temperature != null) {
      _text(canvas, '°C', Offset(d.center.dx, d.center.dy + 2), align: TextAlign.center, style: value);
    }
    final pages = button.pages;
    if (pages > 1) {
      const gap = 9.0;
      final y = d.bottom - 9;
      final x0 = d.center.dx - (pages - 1) * gap / 2;
      for (var i = 0; i < pages; i++) {
        final c = Offset(x0 + i * gap, y);
        i == page
            ? canvas.drawCircle(c, 2.5, Paint()..color = Palette.displayText)
            : canvas.drawCircle(c, 2.5, _stroke(Palette.displayText));
      }
    }
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    bool small = false,
    double maxWidth = 120,
    int lines = 1,
    TextStyle? style,
  }) {
    if (value.isEmpty || maxWidth <= 0) return;
    final base = (style ?? text).copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: small ? base.apply(fontSizeFactor: 0.82, color: hz.textMuted) : base,
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: lines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    final dx = switch (align) {
      TextAlign.center => at.dx - tp.width / 2,
      TextAlign.right => at.dx - tp.width,
      _ => at.dx,
    };
    tp.paint(canvas, Offset(dx, at.dy));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_PanelPainter old) => true;
}
