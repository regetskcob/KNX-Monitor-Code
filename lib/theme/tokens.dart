import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

/// Spacing of the app, named by purpose, values from Horizont's 4-point grid. Page margin: [gutter]
/// below 600, [gutterWide] from 600.
abstract final class Gap {
  /// Left/right page margin on the phone, also in sheets.
  static const gutter = HzSpace.s16;

  /// Page margin from 600 (sidebar).
  static const gutterWide = HzSpace.s24;

  /// Page margin for the available width.
  static double gutterFor(double width) => width >= HzBreakpoint.medium ? gutterWide : gutter;

  /// Between cards and sections.
  static const section = HzSpace.s16;

  /// Title → content, field → field.
  static const inner = HzSpace.s12;

  /// List entries, chips.
  static const item = HzSpace.s8;

  /// Bottom spacing at the end of scrolling pages.
  static const bottom = HzSpace.s32;

  /// Padding of cards.
  static const card = HzSpace.s16;

  /// Default padding of a page with a list.
  static const page = EdgeInsets.fromLTRB(gutter, item, gutter, bottom);
}

/// Corner radii following Horizont's soft variant: green box 16, cards 14, tiles and notice boxes
/// 12, status and badges 2. Buttons and fields take 8 from the theme (`HzSoft.control`); 12 would
/// turn them into pills at pointer height.
abstract final class Radii {
  static const xl = HzSoft.box;
  static const lg = HzSoft.card;
  static const md = HzSoft.tile;
  static const sm = HzRadius.r2;

  static const box = BorderRadius.all(Radius.circular(xl));
  static const card = BorderRadius.all(Radius.circular(lg));
  static const tile = BorderRadius.all(Radius.circular(md));

  /// A control the app shapes itself (icon button with a ground), like the themed buttons.
  static const control = BorderRadius.all(Radius.circular(HzSoft.control));
  static const row = BorderRadius.all(Radius.circular(sm));
}

/// Line widths: a hairline structures, 2 px marks selection and focus.
abstract final class Lines {
  static const hairline = HzLine.hairline;
  static const selection = HzLine.selection;

  /// Measurement curves and charts.
  static const data = HzLine.data;

  /// Walls in the floor plan.
  static const wall = HzLine.wall;
}

/// Maximum content widths per screen type.
abstract final class Widths {
  /// Forms (connect).
  static const form = HzSize.form;

  /// Reading pages (diagnostics, statistics, tools, recordings …).
  static const reading = HzSize.textColumn;

  /// Two-column form page (connect).
  static const dashboard = HzSize.page;

  /// Tool pages with card columns (topology, statistics, health …): iPad landscape and Mac use the
  /// width; only large Mac windows are framed.
  static const wide = 1600.0;

  /// Minimum width of a card column on tool pages.
  static const column = 440.0;

  /// Search field in the title bar (from 600).
  static const search = HzSize.search;

  /// Sidebar from 600.
  static const sidebar = HzSize.sidebar;

  /// Inspector on the right from 840 or 1200.
  static const inspector = HzSize.inspectorWide;

  /// Device tree on the left in the topology from 1200: address, name and hop.
  static const tree = 400.0;

  /// Maximum width of a line card in the topology.
  static const lineCard = 560.0;

  /// Minimum width of a card in the grid (Mac, large windows).
  static const gridCard = HzSize.gridCard;
}

/// Window sizes following Horizont: layout is built by available width, never by device.
abstract final class Breakpoints {
  /// From here on a sidebar instead of a tab bar.
  static const medium = HzBreakpoint.medium;

  /// From here on an inspector on the right.
  static const expanded = HzBreakpoint.expanded;

  /// From here on a card grid and toolbar.
  static const large = HzBreakpoint.large;
}

/// Animations: four durations, one curve, no springs. Zero with reduced motion.
abstract final class Motion {
  static const fast = HzMotion.fast;
  static const base = HzMotion.base;
  static const slow = HzMotion.slow;

  /// Calm step for motion nobody tapped or that confirms something: changing values, expanding
  /// lists, success. The longest duration of the scale.
  static const calm = HzMotion.calm;

  /// Eases out softly, without overshoot (for [calm]).
  static const settle = HzMotion.settle;

  /// In, or movement.
  static const curve = HzMotion.standard;

  /// Out.
  static const curveOut = HzMotion.exit;

  /// Duration, or zero if motion should be reduced.
  static Duration of(BuildContext context, [Duration d = base]) => resolveMotion(context, d);

  static Duration fastOf(BuildContext context) => of(context, fast);
  static Duration slowOf(BuildContext context) => of(context, slow);
  static Duration calmOf(BuildContext context) => of(context, calm);
}

/// Separator in metadata rows ("1/2/3 · 12:00:01 · 1.1.5").
const metaSeparator = horizontMetaSeparator;
