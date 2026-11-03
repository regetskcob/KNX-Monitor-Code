import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'app_icons.dart';
import 'brand.dart';

/// Shared colours for the app and PDF export, from Horizont.
///
/// In widgets use `context.hz` (the slots of the current theme). The constants here are the light
/// values for places without a theme: PDF export, images and tests.
abstract final class Palette {
  static final _light = HorizontColors.resolve(Brand.product, Brightness.light);
  static final _dark = HorizontColors.resolve(Brand.product, Brightness.dark);

  static HorizontColors of(bool dark) => dark ? _dark : _light;

  /// Accent "Bus": main action, selection, write telegrams.
  static final write = _light.accent;

  /// Selection background (summaries, legend, focus).
  static final soft = _light.accentTint;
  static final ink = _light.text;
  static final muted = _light.textMuted;
  static final line = _light.line;

  /// Sunken surface, e.g. every second table row in the PDF.
  static final zebra = _light.sunken;

  /// Data colours for chart series and filter groups, per brightness.
  ///
  /// Series 1 is the accent "Bus", like the histories on the objects; then muted tones (dove blue,
  /// old rose, midnight blue, ochre, fir, lilac, moss, plum, petrol). The order is chosen so that
  /// neighbouring series stay distinguishable even with red-green colour blindness (OKLab ΔE ≥ 8);
  /// every colour has at least 3:1 contrast to the surface. In the dark the same tones are lighter,
  /// matching the dark accent.
  static const _seriesLight = [
    Color(0xFF3D75AC), // dove blue
    Color(0xFFB96462), // old rose
    Color(0xFF31518C), // midnight blue
    Color(0xFFB18334), // ochre
    Color(0xFF006640), // fir
    Color(0xFF7A5B9C), // lilac
    Color(0xFF7C9B53), // moss
    Color(0xFF873F5E), // plum
    Color(0xFF008C99), // petrol
  ];

  static const _seriesDark = [
    Color(0xFF73A9E1),
    Color(0xFFE3918E),
    Color(0xFF5779B8),
    Color(0xFFD3A65D),
    Color(0xFF3D936A),
    Color(0xFFA788CA),
    Color(0xFFA2C17B),
    Color(0xFFB76A89),
    Color(0xFF38B1BD),
  ];

  /// Number of data colours; from the eleventh series on they repeat.
  static const seriesCount = 10;

  /// Colour of series [i] (from 0). Always with a legend, never as colour alone.
  static Color series(int i, {bool dark = false}) {
    final n = i % seriesCount;
    if (n == 0) return of(dark).accent;
    return (dark ? _seriesDark : _seriesLight)[n - 1];
  }

  /// Background of the launch screens (native and Flutter splash): system white or black, so the
  /// launch image and surface are identical in every colour space; afterwards Horizont's paper
  /// takes over.
  static Color launchBackground(bool dark) => dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);

  /// Screw terminals and status LED in device drawings (illustration).
  static const terminal = Color(0xFF43A047);
  static const ledOn = Color(0xFF2EBD3A);

  /// Text on label fields of a manufacturer graphic: the field is part of the device (light), hence
  /// dark in both themes.
  static const labelInk = Color(0xFF22221F);

  /// Generic actuator (illustration), colours like the redrawn DIN-rail devices: housing, step,
  /// front plate, edge, terminals.
  static const deviceHousing = Color(0xFFE2E2DC);
  static const deviceStep = Color(0xFFD7D7D0);
  static const deviceFront = Color(0xFFEFEFEA);
  static const deviceEdge = Color(0xFFABABA4);
  static const deviceSlot = Color(0xFF2A2B28);
  static const deviceScrew = Color(0xFFB9BDBF);
  static const deviceLedOff = Color(0xFFBDB8AC);

  /// Neutral look "A" of the generic actuator: print (numbers, pictograms), decorative lines,
  /// buttons, label fields and their border, LED ring, programming LED off.
  static const deviceInk = Color(0xFF55554F);
  static const deviceRule = Color(0xFF9C9C96);
  static const deviceKey = Color(0xFFDCDCD7);
  static const deviceKeyEdge = Color(0xFFA9A9A3);
  static const deviceLabel = Color(0xFFFFFFFF);
  static const deviceLabelEdge = Color(0xFFC4C4BE);
  static const deviceLedRing = Color(0xFF9A9E9A);
  static const deviceLedOffA = Color(0xFFC8CCC8);
  static const deviceProgOff = Color(0xFFD6C9C9);
  static const deviceScrewSlot = Color(0xFF5F656A);

  /// Print on manufacturer graphics (relay symbol), as printed.
  static const printInk = Color(0xFF2E4A8E);

  /// KNX bus cable on manufacturer graphics: green sheath, red (+) and black (−) wire like the real
  /// cable.
  static const busSheath = Color(0xFF4F9A3C);
  static const busPlus = Color(0xFFC8312B);
  static const busMinus = Color(0xFF2A2A28);

  /// Light pulse on the bus cable for telegrams.
  static const busPulse = Color(0xFFFFFFFF);

  /// Display of a glass push button and its text (illustration).
  static const display = Color(0xFF15181B);
  static const displayText = Color(0xFFE6EAED);

  /// Warning colour for anomalies (always with symbol and word).
  static Color warning(ColorScheme s) => of(s.isDark).warning;
  static Color warningSoft(ColorScheme s) => of(s.isDark).warningTint;

  /// Colour of the telegram type: W = accent, R = warning, A = info. Always with the letter
  /// ([letter]), never as colour alone.
  static Color forType(TelegramType type, {bool dark = false}) {
    final c = of(dark);
    return switch (type) {
      TelegramType.write => c.accentText,
      TelegramType.read => c.warning,
      TelegramType.response => c.info,
    };
  }

  /// Background for the telegram type's letter.
  static Color tintForType(TelegramType type, {bool dark = false}) {
    final c = of(dark);
    return switch (type) {
      TelegramType.write => c.accentTint,
      TelegramType.read => c.warningTint,
      TelegramType.response => c.infoTint,
    };
  }

  /// House scene as on the website (`teaser.css`, `--bh-night`, `--bh-glow`).
  static const sceneNightLight = Color(0xFF27324A);
  static const sceneNightDark = Color(0xFF0C1220);
  static const sceneGlow = Color(0xFFEBBE6A);

  /// Order as in the PDF: write, read, response.
  static const order = [TelegramType.write, TelegramType.read, TelegramType.response];

  static IconData icon(TelegramType type) => switch (type) {
    TelegramType.write => AppIcons.write,
    TelegramType.read => AppIcons.read,
    TelegramType.response => AppIcons.reply,
  };

  static String label(TelegramType type) => switch (type) {
    TelegramType.write => s.typeWrite,
    TelegramType.read => s.typeRead,
    TelegramType.response => s.typeResponse,
  };
}

/// Surfaces that adapt in dark mode.
extension PaletteScheme on ColorScheme {
  bool get isDark => brightness == Brightness.dark;

  /// Selection background (accent-tint).
  Color get soft => primaryContainer;

  /// Sunken surface for every second row of dense tables.
  Color get zebra => surfaceContainer;
}

/// Short access to Horizont in the widget tree.
extension HorizontContext on BuildContext {
  /// The colour slots of the current theme (neutrals, accent, status).
  HorizontColors get hz => HorizontTheme.of(this).colors;

  /// The whole Horizont theme (text styles `data`, `kennung`, density).
  HorizontTheme get hzTheme => HorizontTheme.of(this);

  /// Slots for device drawings: in the dark, lighter housing and stronger outlines so the device
  /// stands out from the paper; unchanged in light mode.
  HorizontColors get hzDevice {
    final c = hz;
    if (Theme.of(this).brightness == Brightness.light) return c;
    Color up(Color x, double t) => Color.lerp(x, c.text, t)!;
    return HorizontColors(
      bg: c.bg,
      surface: up(c.surface, 0.10),
      sunken: up(c.bg, 0.04),
      line: up(c.line, 0.25),
      lineStrong: up(c.lineStrong, 0.5),
      text: c.text,
      textMuted: c.textMuted,
      textFaint: c.textFaint,
      accent: c.accent,
      onAccent: c.onAccent,
      accentTint: c.accentTint,
      accentText: c.accentText,
      positive: c.positive,
      positiveTint: c.positiveTint,
      warning: c.warning,
      warningTint: c.warningTint,
      critical: c.critical,
      criticalTint: c.criticalTint,
      onCritical: c.onCritical,
      dataRamp: c.dataRamp,
      info: c.info,
      infoTint: c.infoTint,
    );
  }

  /// Text font for large values (without tabular figures: those have a slashed zero), in the size
  /// and colour of a style from the type scale.
  TextStyle figures(TextStyle? size) => size ?? Theme.of(this).textTheme.bodyMedium!;

  /// Monaspace (values, addresses, times) in the size and colour of a style from the type scale,
  /// e.g. `context.mono(textTheme.titleLarge)`.
  TextStyle mono([TextStyle? size]) {
    final data = hzTheme.data;
    // Set the family via the package: `data.fontFamily` already carries the prefix
    // "packages/horizont/", copyWith would set it twice.
    return (size ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      letterSpacing: data.letterSpacing,
    );
  }
}
