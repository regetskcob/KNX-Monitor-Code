import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import 'write_confirm.dart';

import 'package:vector_graphics/vector_graphics_compat.dart';

import '../catalog_store.dart';
import '../knx/active_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart' show isStatusGroup;
import '../model/device_art.dart';
import '../model/device_channels.dart';
import '../model/plain_text.dart';
import '../model/telegram_log.dart';
import '../model/topology.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'live_updates.dart';
import 'operate_mode.dart';
import 'telegram_row.dart' show formatTime;

/// Device drawn as a technical drawing of a DIN-rail device: terminal strips at
/// the top and bottom (one terminal pair per channel), front plate with channel
/// label and status LED, programming LED/button and bus terminal, showing live
/// values from the monitor. Tapping a channel shows its group objects with
/// their current values.
class ActuatorView extends StatefulWidget {
  const ActuatorView({
    super.key,
    required this.address,
    required this.log,
    this.selected,
    this.onSelected,
    this.compact = false,
    this.cableReach,
  });

  final int address;
  final TelegramLog log;

  /// Selected channel when the caller shows the objects itself (wide device
  /// detail); they then do not appear below the drawing.
  final int? selected;
  final ValueChanged<int?>? onSelected;

  /// Graphic only (coupler between the lines of the topology): no channel
  /// cards, chips or source note.
  final bool compact;

  /// Main line and sub-line cables leave sideways, this far (logical pixels)
  /// beyond the edge of the graphic, up to the line boxes of the topology.
  final double? cableReach;

  @override
  State<ActuatorView> createState() => _ActuatorViewState();
}

/// State of a channel for the drawing.
class _ChannelState {
  const _ChannelState(this.channel, this.on, this.fraction, this.text, this.address, [this.others = const []]);

  final DeviceChannel channel;

  /// `null` = unbekannt.
  final bool? on;

  /// 0…1 for percentage values (dimming, position, valve).
  final double? fraction;
  final String text;

  /// Group address the value comes from; without a value the first sending one
  /// (status feedback), otherwise the channel's first one.
  final int? address;

  /// Further objects of the channel with a known value: name and value, at most
  /// [maxOthers]: control value, valve, status, operating mode …
  final List<(String, String)> others;

  static const maxOthers = 4;

  static _ChannelState of(DeviceChannel c, Map<int, Telegram> latest) {
    final t = primaryValue(c, latest);
    final address = t?.destination ?? (c.objects.where((o) => o.sends).firstOrNull ?? c.objects.firstOrNull)?.address;
    final store = CatalogStore.instance;
    final others = <(String, String)>[];
    final seen = <int>{?address};
    for (final o in c.objects) {
      if (others.length >= maxOthers || !seen.add(o.address)) continue;
      final v = latest[o.address];
      if (v == null || v.type == TelegramType.read) continue;
      final name = store.info(o.address)?.name ?? o.text ?? formatGroup(o.address);
      // Drop leading words shared with the channel: channel "EG WC F01", object
      // "EG WC Ist-Temperatur" → "Ist-Temperatur".
      final head = (c.title ?? store.info(address ?? -1)?.name ?? '').split(' ');
      final words = name.split(' ');
      var same = 0;
      while (same < head.length && same < words.length - 1 && head[same] == words[same]) {
        same++;
      }
      others.add((words.skip(same).join(' '), store.value(v)));
    }
    if (t == null || t.type == TelegramType.read) return _ChannelState(c, null, null, '', address, others);
    final dpt = CatalogStore.instance.dptOf(t.destination);
    double? fraction;
    if (dpt?.main == 5 && dpt?.sub == 1 && t.data.isNotEmpty && !t.isSmall) fraction = t.data[0] / 255;
    if (t.isSmall && (dpt == null || dpt.main == 1)) fraction = t.data[0] & 1 == 1 ? 1 : 0;
    final text = switch (fraction) {
      final f? when !t.isSmall => '${(f * 100).round()} %',
      _ => t.isSmall ? '' : CatalogStore.instance.value(t),
    };
    return _ChannelState(c, fraction == null ? null : fraction > 0, fraction, text, address, others);
  }
}

/// Dimensions of the drawing, shared by painting and hit testing.
class _Layout {
  _Layout(this.size, int count) {
    columns = columnsFor(count, size.width);
    rows = (count / columns).ceil();
    final w = size.width;
    housing = Rect.fromLTWH(0, 0, w, size.height);
    top = Rect.fromLTWH(w * 0.04, 0, w * 0.92, terminal);
    front = Rect.fromLTWH(0, terminal, w, header + rows * cell);
    // Single row: only bus terminal and rating plate at the bottom.
    bottom = Rect.fromLTWH(w * 0.04, front.bottom, w * 0.92, rows > 1 ? terminal : busStrip);
    side = Rect.fromLTWH(w - sideWidth, front.top + header, sideWidth, front.height - header);
    grid = Rect.fromLTWH(10, front.top + header, w - sideWidth - 14, rows * cell);
  }

  static const terminal = 34.0;
  static const header = 24.0;
  static const cell = 58.0;
  static const sideWidth = 46.0;
  static const busStrip = 24.0;

  /// Minimum width of a channel: terminal pair with label.
  static const minCell = 44.0;

  /// All channels in one row as long as they fit, otherwise split over two
  /// rows; as on the device, there are only top and bottom terminals.
  static int columnsFor(int count, double width) {
    final fit = ((width - sideWidth - 14) / minCell).floor();
    return math.max(1, count <= fit ? count : (count / 2).ceil());
  }

  static double heightFor(int count, double width) {
    final columns = columnsFor(count, width);
    final rows = (count / columns).ceil();
    return terminal + (rows > 1 ? terminal : busStrip) + header + rows * cell;
  }

  final Size size;
  late final int columns, rows;
  late final Rect housing, top, front, bottom, side, grid;

  Rect cellOf(int i) {
    final cw = grid.width / columns;
    return Rect.fromLTWH(grid.left + (i % columns) * cw, grid.top + (i ~/ columns) * cell, cw, cell);
  }
}

class _ActuatorViewState extends State<ActuatorView> with TickerProviderStateMixin {
  late List<DeviceChannel> _channels = deviceChannels(widget.address);
  int? _own;

  /// Group addresses the device is linked to according to the project.
  late final _linked = {
    for (final g in CatalogStore.instance.catalog.groups.values)
      if (g.links.any((l) => l.device == widget.address)) g.address,
  };

  /// Pulse on the bus cable for every telegram from or to the device.
  late final _pulse = AnimationController(vsync: this, duration: _pulseDuration);

  /// Flash of the traffic LEDs on every telegram on the bus; [_trafficLine] =
  /// from the device's line.
  late final _traffic = AnimationController(vsync: this, duration: Motion.base);
  bool _trafficLine = false;
  bool _pulseOut = true;

  /// Channel whose object the telegram concerns; its pulse also runs along the
  /// leader line to the card.
  int? _pulseChannel;
  Telegram? _seen;

  /// What [_onTelegram] listens to: throttled in the add-on (see
  /// [liveUpdates]).
  late final Listenable _updates;

  /// Ruhige Stufe: Den Puls hat niemand angetippt.
  static const _pulseDuration = Motion.calm;

  bool get _external => widget.onSelected != null;
  int? get _selected => _external ? widget.selected : _own;

  @override
  void initState() {
    super.initState();
    _seen = widget.log.log.lastOrNull;
    _updates = liveUpdates(widget.log)..addListener(_onTelegram);
    // Load the manufacturer graphics once; show the drawing until then.
    final art = DeviceArtCatalog.instance;
    art.load().then((_) {
      if (mounted && art.of(CatalogStore.instance.device(widget.address)) != null) {
        setState(() => _channels = deviceChannels(widget.address));
      }
    });
  }

  @override
  void dispose() {
    _updates.removeListener(_onTelegram);
    _pulse.dispose();
    _traffic.dispose();
    super.dispose();
  }

  /// New telegrams since the last call: if the device sends, the pulse runs
  /// into the cable and from the LED to the card; if it receives (linked
  /// address), it runs into the device and from the card to the LED.
  /// With reduced motion the cable stays still.
  void _onTelegram() {
    final log = widget.log.log;
    // Without motion (also in the add-on) there is nothing to show, so don't
    // search.
    if (!mounted || MediaQuery.disableAnimationsOf(context)) {
      _seen = log.lastOrNull;
      return;
    }
    final fresh = log.isNotEmpty && !identical(log.last, _seen) ? log.last : null;
    if (fresh != null) {
      _trafficLine = lineOf(fresh.source) == lineOf(widget.address);
      _traffic.forward(from: 0);
    }
    Telegram? hit;
    for (var k = log.length - 1, n = 0; k >= 0 && n < 64 && !identical(log[k], _seen); k--, n++) {
      final t = log[k];
      if (t.source == widget.address || _linked.contains(t.destination)) {
        hit = t;
        break;
      }
    }
    _seen = log.lastOrNull;
    if (hit == null) return;
    final destination = hit.destination;
    final channel = _channels.indexWhere((c) => c.objects.any((o) => o.address == destination));
    setState(() {
      _pulseOut = hit!.source == widget.address;
      _pulseChannel = channel < 0 ? null : channel;
    });
    _pulse.forward(from: 0);
  }

  /// Tappable channel (also for screen readers).
  Widget _target(int i, _ChannelState st) => Semantics(
    button: true,
    selected: _selected == i,
    label: s.deviceChannelSemantics(
      [st.channel.label.isEmpty ? s.deviceGeneral : st.channel.label, ?st.channel.title].join(' '),
      st.on == null ? (st.text.isEmpty ? '–' : st.text) : (st.on! ? s.deviceOn : s.deviceOff),
    ),
    child: Tooltip(
      message: [?st.channel.title, if (st.text.isNotEmpty) st.text].join(' · '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Armed: the tap sends like a push button would; otherwise it selects.
        // Only the full drawing has the switch above it: a compact one never sends.
        onTap: () => operateMode.value && !widget.compact ? _operate(st.channel) : _select(i),
      ),
    ),
  );

  void _operate(DeviceChannel channel) => unawaited(
    operateChannel(
      context,
      channel,
      widget.log,
      name: channel.title ?? (channel.label.isEmpty ? s.deviceGeneral : channel.label),
    ),
  );

  /// Channels as cards to the left and right of the graphic, in pairs in
  /// channel order: odd on the left, even on the right (1 | 2, 3 | 4 …). Leader
  /// lines run around the channels: horizontally in the gap above the channel
  /// row (for LEDs below the button, below the row across the terminal strip),
  /// then vertically to the LED. Each line gets its own track in its gap; lines
  /// from the same side lie on top, away from the edge, so they don't cross.
  /// Where lines from both sides have to pass each other, one crossing per row
  /// remains.
  Widget _callouts(
    BuildContext context,
    double maxWidth,
    Widget front,
    Size artSize,
    double scale,
    Map<int, ArtChannel> placed,
    List<_ChannelState> states,
  ) {
    const w = _Callouts.width, h = _Callouts.height, gap = _Callouts.gap, reach = _Callouts.reach;
    final artLeft = (maxWidth - artSize.width) / 2;
    final widthMm = artSize.width / scale;
    Offset led(ArtChannel c) => c.led?.$1 ?? c.area.center;
    final order = placed.keys.toList()..sort();
    // Up to eight channels in pairs (1 | 2, 3 | 4 …); with more, by position on
    // the device, otherwise too many long lines run across the front.
    final paired = order.length <= 8;
    final left = [
      for (final (k, i) in order.indexed)
        if (paired ? k.isEven : led(placed[i]!).dx < widthMm / 2) i,
    ];
    final right = [
      for (final (k, i) in order.indexed)
        if (paired ? k.isOdd : led(placed[i]!).dx >= widthMm / 2) i,
    ];
    final isLeft = {for (final i in left) i: true, for (final i in right) i: false};

    // Tracks per gap (top edge of the channel row): longer lines first and as
    // high as possible; lines from the same side always below the longer ones.
    double reachOf(int i) => isLeft[i]! ? led(placed[i]!).dx : widthMm - led(placed[i]!).dx;
    (double, double) span(int i) => isLeft[i]! ? (0, led(placed[i]!).dx) : (led(placed[i]!).dx, widthMm);
    final laneOf = <int, double>{};
    final rows = <int, List<int>>{};
    for (final i in order) {
      rows.putIfAbsent(placed[i]!.area.top.round(), () => []).add(i);
    }
    for (final row in rows.values) {
      row.sort((a, b) => reachOf(b).compareTo(reachOf(a)));
      final level = <int, int>{};
      for (final i in row) {
        final floor = [
          for (final j in level.keys)
            if (isLeft[j] == isLeft[i]) level[j]! + 1,
        ].fold(0, math.max);
        var l = floor;
        bool clash(int l) => level.entries.any((e) {
          if (e.value != l) return false;
          final (a0, a1) = span(i);
          final (b0, b1) = span(e.key);
          return a0 < b1 && b0 < a1;
        });
        while (clash(l)) {
          l++;
        }
        level[i] = l;
      }
      final levels = level.values.fold(0, math.max) + 1;
      for (final MapEntry(key: i, value: l) in level.entries) {
        // LED below the button (bottom row): tracks below the row, across the
        // bottom terminal strip, rising from below to the LED.
        final c = placed[i]!;
        laneOf[i] = led(c).dy > c.area.center.dy
            ? c.area.bottom + _Callouts.laneBelow * (levels - l)
            : c.area.top - _Callouts.lane * (levels - l);
      }
    }

    // By position: cards follow the tracks from top to bottom.
    if (!paired) {
      for (final side in [left, right]) {
        side.sort((a, b) => laneOf[a]!.compareTo(laneOf[b]!));
      }
    }

    // Cards as pairs of rows, centred on the height of the channels; a row is
    // as tall as its taller card (further objects make it taller).
    final pairs = math.max(left.length, right.length);
    double cardHeight(int i) => _Callouts.heightFor(states[i].others.length);
    final rowHeight = [
      for (var k = 0; k < pairs; k++)
        math.max(k < left.length ? cardHeight(left[k]) : 0.0, k < right.length ? cardHeight(right[k]) : 0.0),
    ];
    final rowTop = <double>[];
    var y = 0.0;
    for (final r in rowHeight) {
      rowTop.add(y);
      y += r + gap;
    }
    final block = math.max(0.0, y - gap);
    final height = math.max(artSize.height, block);
    final artTop = (height - artSize.height) / 2;
    Offset px(Offset mm) => Offset(artLeft + mm.dx * scale, artTop + mm.dy * scale);
    final ledYs = [for (final i in order) px(led(placed[i]!)).dy];
    final middle = (ledYs.reduce(math.min) + ledYs.reduce(math.max)) / 2;
    final first = (middle - block / 2).clamp(0.0, height - block);

    final lines = <(List<Offset>, bool, int)>[];
    final cards = <Widget>[];
    for (final side in [left, right]) {
      final onLeft = identical(side, left);
      final x = onLeft ? artLeft - reach - w : artLeft + artSize.width + reach;
      final cardEdge = onLeft ? x + w : x;
      final ys = [for (final (k, _) in side.indexed) (first + rowTop[k] + h / 2, px(Offset(0, laneOf[side[k]]!)).dy)];
      // Vertical segments between card and device: upward lines further down
      // closer to the device, downward lines further up.
      final ups = [
        for (final (k, (c, l)) in ys.indexed)
          if (c > l) k,
      ];
      final downs = [
        for (final (k, (c, l)) in ys.indexed)
          if (c <= l) k,
      ].reversed.toList();
      final offset = <int, double>{
        for (final group in [ups, downs])
          for (final (r, k) in group.indexed) k: reach * (r + 1) / (group.length + 1),
      };
      for (final (k, i) in side.indexed) {
        final (cy, ly) = ys[k];
        final bend = cardEdge + (onLeft ? offset[k]! : -offset[k]!);
        final target = px(led(placed[i]!));
        lines.add((
          [Offset(cardEdge, cy), Offset(bend, cy), Offset(bend, ly), Offset(target.dx, ly), target],
          _selected == i,
          i,
        ));
        cards.add(
          Positioned(
            left: x,
            top: first + rowTop[k],
            width: w,
            height: cardHeight(i),
            child: _CalloutCard(state: states[i], selected: _selected == i, onTap: () => _select(i)),
          ),
        );
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned(left: artLeft, top: artTop, child: front),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LeaderPainter(
                  lines: lines,
                  hz: context.hz,
                  pulse: _pulse,
                  pulseChannel: _pulseChannel,
                  pulseOut: _pulseOut,
                ),
              ),
            ),
          ),
          ...cards,
        ],
      ),
    );
  }

  /// Cards for a device without channels on its front: alternating left and
  /// right, centred on the graphic. The lines end evenly spaced at the edge of
  /// the front plate, with a bend for offset cards.
  Widget _objectCallouts(
    BuildContext context,
    double maxWidth,
    Widget front,
    Size artSize,
    double scale,
    List<_ChannelState> states,
  ) {
    const w = _Callouts.width, gap = _Callouts.gap, reach = _Callouts.reach;
    final artLeft = (maxWidth - artSize.width) / 2;
    double cardHeight(int i) => _Callouts.heightFor(states[i].others.length);
    final left = [for (var i = 0; i < states.length; i += 2) i];
    final right = [for (var i = 1; i < states.length; i += 2) i];
    double column(List<int> side) => side.fold(0.0, (sum, i) => sum + cardHeight(i) + gap) - gap;
    final block = math.max(column(left), column(right));
    final height = math.max(artSize.height, block);
    final artTop = (height - artSize.height) / 2;
    // Front plate of a DIN-rail device (82 mm tall): 20 … 65 mm from the top,
    // with the narrower terminal steps above and below.
    final plateTop = artTop + _plateTop * scale, plateBottom = artTop + _plateBottom * scale;
    final lines = <(List<Offset>, bool, int)>[];
    final cards = <Widget>[];
    for (final side in [left, right]) {
      final onLeft = identical(side, left);
      final x = onLeft ? artLeft - reach - w : artLeft + artSize.width + reach;
      final cardEdge = onLeft ? x + w : x;
      final deviceEdge = onLeft ? artLeft : artLeft + artSize.width;
      final tops = <double>[];
      var y = (height - column(side)) / 2;
      for (final i in side) {
        tops.add(y);
        y += cardHeight(i) + gap;
      }
      final ys = [
        for (final (k, i) in side.indexed)
          (tops[k] + cardHeight(i) / 2, plateTop + (plateBottom - plateTop) * (k + 1) / (side.length + 1)),
      ];
      // Bends staggered as for the channel cards so the vertical segments don't
      // overlap.
      final ups = [
        for (final (k, (c, t)) in ys.indexed)
          if (c > t) k,
      ];
      final downs = [
        for (final (k, (c, t)) in ys.indexed)
          if (c <= t) k,
      ].reversed.toList();
      final offset = <int, double>{
        for (final group in [ups, downs])
          for (final (r, k) in group.indexed) k: reach * (r + 1) / (group.length + 1),
      };
      for (final (k, i) in side.indexed) {
        final (cy, ty) = ys[k];
        final y = tops[k];
        final bend = cardEdge + (onLeft ? offset[k]! : -offset[k]!);
        lines.add((
          [Offset(cardEdge, cy), Offset(bend, cy), Offset(bend, ty), Offset(deviceEdge, ty)],
          _selected == i,
          i,
        ));
        cards.add(
          Positioned(
            left: x,
            top: y,
            width: w,
            height: cardHeight(i),
            child: _CalloutCard(state: states[i], selected: _selected == i, onTap: () => _select(i)),
          ),
        );
      }
    }
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned(left: artLeft, top: artTop, child: front),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _LeaderPainter(
                  lines: lines,
                  hz: context.hz,
                  pulse: _pulse,
                  pulseChannel: _pulseChannel,
                  pulseOut: _pulseOut,
                ),
              ),
            ),
          ),
          ...cards,
        ],
      ),
    );
  }

  void _select(int i) {
    final next = _selected == i ? null : i;
    if (_external) {
      widget.onSelected!(next);
    } else {
      setState(() => _own = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_channels.isEmpty && artFor(widget.address) == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    // Labels of the drawing as on the device: Monaspace, small.
    final label = (theme.textTheme.labelSmall ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: hz.text,
    );
    final device = CatalogStore.instance.device(widget.address);
    return ListenableBuilder(
      listenable: liveUpdates(widget.log),
      builder: (context, _) {
        final states = [for (final c in _channels) _ChannelState.of(c, widget.log.latest)];
        final selected = _selected == null ? null : _channels[_selected!];
        final art = artFor(widget.address);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (art != null)
              _artFront(context, art, states)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, _Layout.heightFor(states.length, constraints.maxWidth));
                  final layout = _Layout(size, states.length);
                  return SizedBox.fromSize(
                    size: size,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _DevicePainter(
                              layout: layout,
                              states: states,
                              selected: _selected,
                              title: device?.product ?? device?.name ?? '',
                              address: formatIndividual(widget.address),
                              hz: context.hzDevice,
                              text: label,
                            ),
                          ),
                        ),
                        for (final (i, st) in states.indexed)
                          Positioned.fromRect(rect: layout.cellOf(i), child: _target(i, st)),
                      ],
                    ),
                  );
                },
              ),
            if (!_external)
              AnimatedSize(
                duration: Motion.of(context),
                curve: Motion.curve,
                child: selected == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: HzSpace.s8),
                        child: ChannelObjects(channel: selected, latest: widget.log.latest, log: widget.log),
                      ),
              ),
          ],
        );
      },
    );
  }

  /// Manufacturer graphic to scale, at most a quarter of the detail area tall;
  /// on top of it LEDs, channel names in the label fields, and the selection.
  /// Channels without an area on the device (central objects) appear as chips;
  /// if the device has no channels at all (power supply), its objects are shown
  /// as cards around the graphic.
  Widget _artFront(BuildContext context, DeviceArt art, List<_ChannelState> states) {
    final hz = context.hz;
    final placed = <int, ArtChannel>{for (final (i, st) in states.indexed) i: ?art.channel(st.channel.label)};
    final loose = [
      for (var i = 0; i < states.length; i++)
        if (!placed.containsKey(i)) i,
    ];
    Widget chips() => Padding(
      padding: const EdgeInsets.only(top: HzSpace.s8),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: HzSpace.s8,
        children: [
          for (final i in loose)
            ChoiceChip(
              // Objects without a channel (central, lock, diagnostics): spelled
              // out with a count, otherwise it is unclear what the chip opens.
              label: Text(
                states[i].channel.label.isEmpty
                    ? s.deviceGeneralObjects(states[i].channel.objects.length)
                    : [states[i].channel.label, ?states[i].channel.title].join(metaSeparator),
              ),
              selected: _selected == i,
              onSelected: (_) => _select(i),
            ),
        ],
      ),
    );
    final showChips = loose.isNotEmpty && !widget.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final maxHeight = _artMaxHeight(constraints.maxWidth);
            final aspect = art.size.width / art.size.height;
            final callouts = !widget.compact && artCalloutsFit(art, constraints.maxWidth) && states.isNotEmpty;
            final side = callouts ? _Callouts.width + _Callouts.reach : 0.0;
            final width = math.min(constraints.maxWidth - 2 * side, maxHeight * aspect);
            final scale = width / art.size.width;
            Rect px(Rect mm) => Rect.fromLTWH(mm.left * scale, mm.top * scale, mm.width * scale, mm.height * scale);
            // The bus cable hangs out of the device below the bus terminal.
            final cable = art.bus == null && art.lineBuses.isEmpty ? 0.0 : _cableLength * scale;
            final front = SizedBox(
              width: width,
              height: width / aspect + cable,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    right: 0,
                    height: width / aspect,
                    child: ExcludeSemantics(
                      // As a picture recording instead of a raster copy: sharp
                      // at any size.
                      child: art.asset == null
                          ? CustomPaint(painter: _GenericFrontPainter(art))
                          : createCompatVectorGraphic(
                              loader: AssetBytesLoader(art.asset!),
                              fit: BoxFit.fill,
                              strategy: RenderingStrategy.picture,
                            ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ArtPainter(
                        placed: {for (final MapEntry(:key, :value) in placed.entries) value: states[key]},
                        selected: _selected == null ? null : placed[_selected],
                        scale: scale,
                        hz: hz,
                        text: Theme.of(context).textTheme.labelSmall ?? const TextStyle(),
                        bus: art.lineBuses.isEmpty ? art.bus : null,
                        plusRight: art.busPlusRight,
                        address: art.address,
                        addressText: formatIndividual(widget.address),
                        artHeight: art.size.height,
                        pulse: _pulse,
                        pulseOut: _pulseOut,
                        indicators: art.indicators,
                        channels: art.channels,
                        lineBuses: art.lineBuses,
                        sideReach: widget.cableReach == null ? null : widget.cableReach! / scale,
                        traffic: _traffic,
                        trafficLine: _trafficLine,
                        contactColor: art.generic ? Palette.deviceInk : Palette.printInk,
                      ),
                    ),
                  ),
                  for (final MapEntry(key: i, value: c) in placed.entries)
                    Positioned.fromRect(rect: px(c.area), child: _target(i, states[i])),
                ],
              ),
            );
            final artSize = Size(width, width / aspect + cable);
            if (!callouts) {
              return Column(children: [front, if (showChips) chips()]);
            }
            if (placed.isEmpty) return _objectCallouts(context, constraints.maxWidth, front, artSize, scale, states);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _callouts(context, constraints.maxWidth, front, artSize, scale, placed, states),
                if (showChips) chips(),
              ],
            );
          },
        ),
        if (art.attribution case final a? when !widget.compact) ...[
          const SizedBox(height: HzSpace.s4),
          Text(
            a,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: hz.textMuted),
          ),
        ],
      ],
    );
  }
}

/// Length of the bus cable below a manufacturer graphic, in mm.
const _cableLength = 18.0;

/// Top and bottom edge of the front plate of a DIN-rail device, in mm.
const _plateTop = 22.0, _plateBottom = 63.0;

/// Height of the manufacturer graphic including bus cable at [width] in the
/// compact layout, for places that need a fixed size (rows with IntrinsicHeight
/// in the topology).
double compactArtHeight(DeviceArt art, double width) {
  final cable = art.bus == null && art.lineBuses.isEmpty ? 0.0 : _cableLength;
  return width * (art.size.height + cable) / art.size.width;
}

/// Maximum height of the manufacturer graphic: more room in the wide detail
/// view.
double _artMaxHeight(double width) => width >= Widths.reading ? 440.0 : 340.0;

/// Whether there is room for channel cards to the left and right of the
/// manufacturer graphic, keeping the graphic at least 260 px wide (or at full
/// size if it is smaller).
bool artCalloutsFit(DeviceArt art, double width) {
  final natural = _artMaxHeight(width) * art.size.width / art.size.height;
  return width - 2 * (_Callouts.width + _Callouts.reach) >= math.min(natural, 260);
}

/// Dimensions of the channel cards next to the manufacturer graphic.
abstract final class _Callouts {
  static const width = 200.0;
  static const height = 56.0;

  /// Abstand zwischen Karten.
  static const gap = HzSpace.s8;

  /// Height of a row for a further object in the card.
  static const otherLine = 16.0;

  /// Card height with [others] further objects.
  static double heightFor(int others) => height + others * otherLine;

  /// Gap between cards and graphic for the leader lines.
  static const reach = HzSpace.s48;

  /// Spacing of the line tracks in the gap above a channel row, in mm.
  static const lane = 0.9;

  /// Spacing of the tracks below a channel row (across the terminal strip), in
  /// mm.
  static const laneBelow = 1.1;
}

/// Channel card: short name, label and value, LED dot as on the device.
class _CalloutCard extends StatelessWidget {
  const _CalloutCard({required this.state, required this.selected, required this.onTap});

  final _ChannelState state;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final st = state;
    final label = st.channel.label.isEmpty ? s.deviceGeneral : st.channel.label;
    final value = st.text.isNotEmpty ? st.text : (st.on == null ? '–' : (st.on! ? s.deviceOn : s.deviceOff));
    final lit = st.channel.kind == ChannelKind.heating ? hz.warning : Palette.ledOn;
    return Semantics(
      button: true,
      selected: selected,
      label: s.deviceChannelSemantics([label, ?st.channel.title].join(' '), value),
      excludeSemantics: true,
      child: Material(
        color: selected ? hz.accentTint : hz.surface,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.tile,
          side: BorderSide(
            color: selected ? hz.accent : hz.lineStrong,
            width: selected ? Lines.selection : Lines.hairline,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s8),
            child: Row(
              children: [
                // Single objects (device without channels) have no short name.
                if (st.channel.label.isNotEmpty)
                  SizedBox(
                    width: HzSpace.s24,
                    child: Text(
                      label,
                      style: data.copyWith(fontWeight: FontWeight.w600, color: hz.text),
                    ),
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (st.channel.title) {
                          final t? => _shortTitle(t),
                          null => _titleOf(st) ?? label,
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.text),
                      ),
                      // Value, with the group address it comes from in small
                      // print next to it.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: data.copyWith(color: hz.text, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (st.address case final ga?) ...[
                            const SizedBox(width: HzSpace.s8),
                            Text(
                              formatGroup(ga),
                              maxLines: 1,
                              style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.textMuted),
                            ),
                          ],
                        ],
                      ),
                      // Further objects with a value, one row each.
                      for (final (name, v) in st.others)
                        SizedBox(
                          height: _Callouts.otherLine,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(color: hz.textMuted),
                                ),
                              ),
                              const SizedBox(width: HzSpace.s4),
                              Text(
                                v,
                                maxLines: 1,
                                style: context.mono(theme.textTheme.labelSmall).copyWith(color: hz.text),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // LED: filled = on (brightness by control value), ring = off,
                // dimmed = unknown, plus the value as a word.
                Container(
                  width: HzSpace.s8,
                  height: HzSpace.s8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: st.on == true ? lit.withValues(alpha: 0.35 + 0.65 * (st.fraction ?? 1)) : null,
                    border: st.on == true
                        ? null
                        : Border.all(color: st.on == false ? hz.lineStrong : hz.line, width: Lines.hairline),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Channel name from the group address of the value, without the trailing
/// function.
String? _titleOf(_ChannelState st) {
  final name = switch (st.address) {
    final a? => CatalogStore.instance.info(a)?.name,
    null => null,
  };
  return name == null || name.isEmpty ? null : _shortTitle(name);
}

/// Name without function: up to the object identifier ("EG WZ F01 Auf/Ab
/// fahren" → "EG WZ F01"), otherwise without trailing function words
/// ("Außen-Steckdose Deich Rückmeldung Schalten" → "Außen-Steckdose Deich").
String _shortTitle(String name) {
  final code = RegExp(r'^(.*?\b[A-Z]{1,3}\d{2})\b').firstMatch(name);
  if (code != null) return code[1]!;
  final words = RegExp(
    r'(\s+(schalten|status|rückmeldung|rm|dimmen|wert|auf/ab|fahren|verfahrstatus|ist-temperatur))+$',
    caseSensitive: false,
  );
  final short = name.replaceFirst(words, '');
  return short.isEmpty ? name : short;
}

/// Leader lines from the cards to the LED as right-angled paths with a dot at
/// the end; the selected one last, in accent colour and 2 px. If a telegram
/// concerns a channel, a light dot runs along its line: from the LED to the
/// card when the device sends, otherwise the other way round.
class _LeaderPainter extends CustomPainter {
  _LeaderPainter({
    required this.lines,
    required this.hz,
    required this.pulse,
    required this.pulseChannel,
    required this.pulseOut,
  }) : super(repaint: pulse);

  /// Points from the card to the LED, selected, channel.
  final List<(List<Offset>, bool, int)> lines;
  final HorizontColors hz;
  final Animation<double> pulse;
  final int? pulseChannel;
  final bool pulseOut;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (points, selected, _) in [...lines.where((l) => !l.$2), ...lines.where((l) => l.$2)]) {
      final color = selected ? hz.accent : hz.lineStrong;
      canvas.drawPath(
        Path()..addPolygon(points, false),
        Paint()
          ..color = color
          ..strokeWidth = selected ? Lines.selection : Lines.hairline
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(points.last, selected ? 3 : 2, Paint()..color = color);
    }
    final t = pulse.value;
    if (!pulse.isAnimating || t >= 1) return;
    for (final (points, _, channel) in lines) {
      if (channel != pulseChannel) continue;
      // Position along the path; length from the segments.
      final lengths = [for (var k = 1; k < points.length; k++) (points[k] - points[k - 1]).distance];
      final total = lengths.fold(0.0, (a, b) => a + b);
      var at = (pulseOut ? 1 - t : t) * total;
      var p = points.first;
      for (var k = 0; k < lengths.length; k++) {
        if (at <= lengths[k] || k == lengths.length - 1) {
          p = Offset.lerp(points[k], points[k + 1], lengths[k] == 0 ? 0 : (at / lengths[k]).clamp(0.0, 1.0))!;
          break;
        }
        at -= lengths[k];
      }
      final fade = math.min(1.0, t * 6) * (1 - t * 0.4);
      canvas.drawCircle(
        p,
        6,
        Paint()
          ..color = hz.accent.withValues(alpha: 0.35 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(p, 2.5, Paint()..color = hz.accent.withValues(alpha: fade));
    }
  }

  @override
  bool shouldRepaint(_LeaderPainter old) => true;
}

/// Drawing of the device (illustration): surfaces and hairlines from the theme,
/// terminals and LED in device colours, without glow or gradient.
class _DevicePainter extends CustomPainter {
  _DevicePainter({
    required this.layout,
    required this.states,
    required this.selected,
    required this.title,
    required this.address,
    required this.hz,
    required this.text,
  });

  final _Layout layout;
  final List<_ChannelState> states;
  final int? selected;
  final String title;
  final String address;
  final HorizontColors hz;
  final TextStyle text;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = hz.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = Lines.hairline;

    // Terminal strips (set back) and front plate (in front)
    for (final r in [layout.top, layout.bottom]) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(HzRadius.r2));
      canvas.drawRRect(rr, Paint()..color = hz.sunken);
      canvas.drawRRect(rr, line);
    }
    final front = RRect.fromRectAndRadius(layout.front, const Radius.circular(HzRadius.r6));
    canvas.drawRRect(front, Paint()..color = hz.surface);
    canvas.drawRRect(front, line);

    // Header: type and individual address
    _text(canvas, title, Offset(layout.front.left + 10, layout.front.top + 5), bold: true, maxWidth: size.width * 0.6);
    _text(canvas, address, Offset(layout.front.right - 10, layout.front.top + 5), align: TextAlign.right);

    // Channels: terminal pair at the top (1st row) or bottom (further rows)
    for (final (i, st) in states.indexed) {
      final cell = layout.cellOf(i);
      final row = i ~/ layout.columns;
      final strip = row == 0 ? layout.top : layout.bottom;
      // General objects (central, sensor inputs) have no terminals.
      if (st.channel.label.isNotEmpty) {
        _terminals(canvas, cell.center.dx, strip, label: _label(st), labelBelow: row == 0);
      }
      _channel(canvas, cell, st, selected == i);
    }

    // Programming LED, programming button and bus terminal on the right
    final side = layout.side;
    final cx = side.center.dx;
    _text(canvas, 'Prog', Offset(cx, side.top + 4), align: TextAlign.center);
    canvas.drawCircle(Offset(cx, side.top + 26), 4, Paint()..color = hz.line);
    canvas.drawCircle(Offset(cx, side.top + 42), 6, Paint()..color = hz.textMuted);
    final b = layout.bottom;
    final bus = Rect.fromLTWH(b.right - 34, b.top + 5, 24, b.height - 10);
    _text(canvas, 'KNX TP · 30 V', Offset(b.right - 42, b.center.dy - 6), small: true, align: TextAlign.right);
    // Bus terminal red/black like the original.
    canvas.drawRect(Rect.fromLTWH(bus.left, bus.top, bus.width / 2, bus.height), Paint()..color = hz.critical);
    canvas.drawRect(Rect.fromLTWH(bus.center.dx, bus.top, bus.width / 2, bus.height), Paint()..color = hz.text);
  }

  String _label(_ChannelState st) => st.channel.label.isEmpty ? s.deviceGeneral : st.channel.label;

  void _terminals(Canvas canvas, double x, Rect strip, {required String label, required bool labelBelow}) {
    const r = 5.5;
    final y = labelBelow ? strip.top + 11 : strip.bottom - 11;
    for (final dx in [-7.0, 7.0]) {
      final c = Offset(x + dx, y);
      canvas.drawCircle(c, r, Paint()..color = Palette.terminal);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = Palette.terminal.withGreen(110)
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.hairline,
      );
      // Schraubenschlitz
      canvas.drawLine(
        c + const Offset(-3, 3),
        c + const Offset(3, -3),
        Paint()
          ..color = Color.lerp(Palette.terminal, hz.text, 0.7)!
          ..strokeWidth = Lines.hairline,
      );
    }
    // Switch contact symbol and label as on the device
    final ly = labelBelow ? strip.bottom - 9 : strip.top + 9;
    final contact = Paint()
      ..color = hz.textMuted
      ..strokeWidth = Lines.hairline;
    canvas.drawLine(Offset(x - 7, ly), Offset(x - 3, ly), contact);
    canvas.drawLine(Offset(x - 3, ly), Offset(x + 3, ly - 3), contact);
    canvas.drawLine(Offset(x + 4, ly), Offset(x + 7, ly), contact);
    _text(canvas, label, Offset(x + 10, ly - 6), small: true);
  }

  void _channel(Canvas canvas, Rect cell, _ChannelState st, bool selected) {
    if (selected) {
      // Selection: accent-tint with a 2 px line at the bottom.
      final area = cell.deflate(2);
      canvas.drawRect(area, Paint()..color = hz.accentTint);
      canvas.drawRect(
        Rect.fromLTRB(area.left, area.bottom - Lines.selection, area.right, area.bottom),
        Paint()..color = hz.accent,
      );
    }
    final cx = cell.center.dx;
    _text(canvas, _label(st), Offset(cx, cell.top + 4), align: TextAlign.center, bold: true);
    final kind = st.channel.kind;
    final lit = kind == ChannelKind.heating ? hz.warning : Palette.ledOn;
    final led = Offset(cx, cell.top + 27);
    if (st.on == true) {
      final strength = 0.35 + 0.65 * (st.fraction ?? 1);
      canvas.drawCircle(led, 4.5, Paint()..color = lit.withValues(alpha: strength));
    } else {
      canvas.drawCircle(led, 4.5, Paint()..color = st.on == false ? hz.lineStrong : hz.line);
      if (st.on == null) canvas.drawCircle(led, 4.5, Paint()..color = hz.surface.withValues(alpha: 0.6));
    }
    if (st.text.isNotEmpty) _text(canvas, st.text, Offset(cx, cell.top + 38), align: TextAlign.center, small: true);
  }

  void _text(
    Canvas canvas,
    String value,
    Offset at, {
    TextAlign align = TextAlign.left,
    bool bold = false,
    bool small = false,
    double maxWidth = 120,
  }) {
    final style = text.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400);
    final tp = TextPainter(
      text: TextSpan(text: value, style: small ? style.apply(fontSizeFactor: 0.82) : style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
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
  bool shouldRepaint(_DevicePainter old) => true;
}

/// Objects of a channel with their current value: number, name, address and
/// DPT, value on the right; values in Monaspace, rows separated by hairlines.
class ChannelObjects extends StatelessWidget {
  const ChannelObjects({super.key, required this.channel, required this.latest, this.log});

  final DeviceChannel channel;
  final Map<int, Telegram> latest;

  /// With the recording, every object also says when its value came, from whom,
  /// and what it was before.
  final TelegramLog? log;

  /// How far back the previous value is looked for.
  static const _lookBack = 5000;

  /// The value telegram on the address of [last] before [last], if the recent
  /// recording has one.
  static Telegram? _previous(List<Telegram> log, Telegram last) {
    final from = log.length - 1, to = log.length > _lookBack ? log.length - _lookBack : 0;
    var seen = false;
    for (var i = from; i >= to; i--) {
      final t = log[i];
      if (t.destination != last.destination || t.type == TelegramType.read) continue;
      if (seen) return t;
      seen = identical(t, last) || !t.time.isAfter(last.time);
    }
    return null;
  }

  /// "14:02:10 · von Taster Küche · vorher Aus" for the last telegram of an object.
  String? _trail(Telegram? last) {
    final log = this.log;
    if (log == null || last == null || last.type == TelegramType.read) return null;
    final store = CatalogStore.instance;
    final before = _previous(log.log, last);
    return [
      formatTime(last.time, millis: false),
      s.objectFrom(last.outgoing ? s.locksByApp : (plainSender(last.source) ?? formatIndividual(last.source))),
      if (before != null) s.objectBefore(store.value(before)),
    ].join(metaSeparator);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final data = context.hzTheme.data;
    TextStyle mono(TextStyle? size, Color color) => (size ?? data).copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: color,
    );
    final meta = mono(theme.textTheme.bodySmall, hz.textMuted);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.surface,
        border: Border.all(color: hz.line, width: Lines.hairline),
        borderRadius: Radii.card,
      ),
      child: Column(
        children: [
          for (final (i, o) in channel.objects.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : Border(
                        top: BorderSide(color: hz.line, width: Lines.hairline),
                      ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
                child: Row(
                  children: [
                    SizedBox(
                      width: HzSpace.s32,
                      child: Text(o.number == null ? '' : '${o.number}', style: meta),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.text ?? store.info(o.address)?.name ?? formatGroup(o.address),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          Text(
                            [
                              formatGroup(o.address),
                              ?store.info(o.address)?.name,
                              if (store.dptOf(o.address) case final d?)
                                'DPT $d${dptUnit(d).isEmpty ? '' : ' (${dptUnit(d)})'}',
                            ].join(metaSeparator),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: meta,
                          ),
                          if (_trail(latest[o.address]) case final trail?)
                            Text(trail, maxLines: 1, overflow: TextOverflow.ellipsis, style: meta),
                        ],
                      ),
                    ),
                    // Switching addresses: send 0/1 directly to test an
                    // actuator or light (only with an open connection). Placed
                    // before the value so all values stay right-aligned in a
                    // column.
                    if (_switchable(o.address)) _SwitchButtons(address: o.address),
                    const SizedBox(width: HzSpace.s8),
                    Text(switch (latest[o.address]) {
                      final t? => store.value(t),
                      null => '–',
                    }, style: mono(theme.textTheme.titleSmall, hz.text)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Switching address (DPT 1) that is not a status feedback, for actuators as
/// well as push buttons. The ETS "transmit" flag doesn't help here: it is set
/// on the first address of every object, so on an actuator also on its
/// switching address.
bool _switchable(int address) {
  final info = CatalogStore.instance.catalog[address];
  return info != null && CatalogStore.instance.dptOf(address)?.main == 1 && !isStatusGroup(info);
}

/// Sends "0" and "1" to a switching address while the monitor is connected.
class _SwitchButtons extends StatelessWidget {
  const _SwitchButtons({required this.address});

  final int address;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: activeTunnel,
    builder: (context, tunnel, _) {
      if (tunnel == null) return const SizedBox.shrink();
      return ValueListenableBuilder(
        valueListenable: tunnel.state,
        builder: (context, state, _) {
          final online = state == TunnelState.connected;
          final group = formatGroup(address);
          // Control height of the theme: large enough for a finger on touch
          // devices.
          final control = context.hzTheme.controlHeight;
          return Padding(
            padding: const EdgeInsetsDirectional.only(start: HzSpace.s8, end: HzSpace.s4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: HzSpace.s8,
              children: [
                for (final v in [0, 1])
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(control * 1.25, control),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: online
                        ? () async {
                            if (await confirmWrite(context, address, small: v)) await tunnel.write(address, small: v);
                          }
                        : null,
                    child: Tooltip(message: s.deviceSendValue('$v', group), child: Text('$v')),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Layers on top of the manufacturer graphic: lit LEDs (brightness by control
/// value), channel name or value in the label field, selection as accent-tint
/// with a 2 px border. The graphic itself shows LEDs that are off.
class _ArtPainter extends CustomPainter {
  _ArtPainter({
    required this.placed,
    required this.selected,
    required this.scale,
    required this.hz,
    required this.text,
    required this.artHeight,
    required this.pulse,
    required this.pulseOut,
    required this.traffic,
    this.trafficLine = false,
    this.indicators = const [],
    this.channels = const [],
    this.lineBuses = const [],
    this.sideReach,
    this.bus,
    this.plusRight = false,
    this.address,
    this.addressText = '',
    this.contactColor = Palette.printInk,
  }) : super(repaint: Listenable.merge([pulse, traffic]));

  /// Colour of the relay rocker: print colour of the manufacturer graphic,
  /// neutral for self-drawn devices.
  final Color contactColor;

  final Map<ArtChannel, _ChannelState> placed;
  final ArtChannel? selected;
  final double scale;
  final HorizontColors hz;
  final TextStyle text;

  /// Bus terminal and device height in mm; the cable hangs below.
  final Rect? bus;
  final double artHeight;

  /// Red wire on the right in the terminal.
  final bool plusRight;

  /// Address field of the device in mm and the individual address for it.
  final Rect? address;
  final String addressText;

  /// 0…1 during a pulse; [pulseOut] = from the device into the cable.
  final Animation<double> pulse;
  final bool pulseOut;

  /// Status LEDs and their flash on telegrams.
  final List<ArtIndicator> indicators;

  /// All channels of the graphic, including those not used in the project
  /// (relay open).
  final List<ArtChannel> channels;

  /// Bus terminals of main line and sub-line (coupler); `true` = sub-line.
  final List<(Rect, bool)> lineBuses;

  /// Cables leave sideways, this far (mm) beyond the edge; otherwise downwards.
  final double? sideReach;
  final Animation<double> traffic;
  final bool trafficLine;

  @override
  void paint(Canvas canvas, Size size) {
    Rect px(Rect mm) => Rect.fromLTWH(mm.left * scale, mm.top * scale, mm.width * scale, mm.height * scale);
    _indicators(canvas);
    if (bus case final b?) _cable(canvas, b, t: pulse.value, active: pulse.isAnimating, out: pulseOut);
    // Further bus terminals (coupler): main line on telegrams from other lines,
    // sub-line on telegrams from its own, each running inwards.
    for (final (rect, sub) in lineBuses) {
      final active = traffic.isAnimating && trafficLine == sub;
      if (sideReach case final reach?) {
        _sideCable(canvas, rect, sub: sub, reach: reach, width: size.width / scale, t: traffic.value, active: active);
      } else {
        _cable(canvas, rect, t: traffic.value, active: active, out: false);
      }
    }
    if (address case final mm?) _boxText(canvas, addressText, px(mm).deflate(scale * 0.6));
    // Relay symbol: rocker closed when "Ein" (on), otherwise open.
    for (final c in channels) {
      if (c.contact case (final pivot, final open, final closed)) {
        canvas.drawLine(
          pivot * scale,
          (placed[c]?.on == true ? closed : open) * scale,
          Paint()
            ..color = contactColor
            ..strokeWidth = 0.3 * scale
            ..strokeCap = StrokeCap.round,
        );
      }
    }
    for (final MapEntry(key: c, value: st) in placed.entries) {
      if (c == selected) {
        final area = RRect.fromRectAndRadius(px(c.area), const Radius.circular(HzRadius.r2));
        canvas.drawRRect(area, Paint()..color = hz.accentTint.withValues(alpha: 0.55));
        canvas.drawRRect(
          area,
          Paint()
            ..color = hz.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = Lines.selection,
        );
      }
      if (c.led case (final center, final r) when st.on == true) {
        final lit = st.channel.kind == ChannelKind.heating ? hz.warning : Palette.ledOn;
        final strength = 0.35 + 0.65 * (st.fraction ?? 1);
        canvas.drawCircle(center * scale, r * scale * 1.1, Paint()..color = lit.withValues(alpha: strength));
      }
      if (c.label case final mm?) {
        final value = st.channel.title ?? st.text;
        if (value.isEmpty) continue;
        _boxText(canvas, value, px(mm).deflate(scale * 0.4));
      }
    }
  }

  /// Text in a field of the graphic: as large as fits, at most 72 % of the
  /// field height and not below 40 % of it; the rest is truncated. Shown in
  /// full in the tooltip and to screen readers.
  void _boxText(Canvas canvas, String value, Rect box) {
    TextPainter painter(double size) => TextPainter(
      text: TextSpan(
        text: value,
        style: text.copyWith(color: Palette.labelInk, fontSize: size, height: 1),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    final full = box.height * 0.72;
    final natural = painter(full)..layout();
    final fit = natural.width <= box.width ? full : math.max(full * box.width / natural.width * 0.95, box.height * 0.4);
    natural.dispose();
    final tp = painter(fit)..layout(maxWidth: box.width);
    tp.paint(canvas, Offset(box.center.dx - tp.width / 2, box.center.dy - tp.height / 2));
    tp.dispose();
  }

  /// Status LEDs: steady light or a flash on telegrams, with a soft glow like a
  /// real LED.
  void _indicators(Canvas canvas) {
    final t = traffic.value;
    final flash = traffic.isAnimating ? 1 - t : 0.0;
    for (final i in indicators) {
      final strength = switch (i.role) {
        IndicatorRole.on => 1.0,
        IndicatorRole.traffic => flash,
        IndicatorRole.trafficLine => trafficLine ? flash : 0.0,
        IndicatorRole.trafficOther => trafficLine ? 0.0 : flash,
      };
      if (strength <= 0) continue;
      final color = i.color == null ? Palette.ledOn : Color(i.color!);
      final c = i.center * scale;
      final r = i.radius * scale;
      canvas.drawCircle(
        c,
        r * 2.2,
        Paint()
          ..color = color.withValues(alpha: 0.35 * strength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r),
      );
      canvas.drawCircle(c, r * 1.05, Paint()..color = color.withValues(alpha: strength));
    }
  }

  /// Cable of a coupler terminal leading sideways: wires out of the terminal,
  /// sheath downwards and curving out to the line (main line left, sub-line
  /// right). Telegrams run as a light dot from the line to the coupler.
  void _sideCable(
    Canvas canvas,
    Rect b, {
    required bool sub,
    required double reach,
    required double width,
    required double t,
    required bool active,
  }) {
    canvas.save();
    canvas.scale(scale);
    final dir = sub ? 1.0 : -1.0;
    final cx = b.center.dx;
    final top = artHeight + 2.2;
    final bend = artHeight + 5.5;
    final level = artHeight + 9.0;
    for (final (x, color) in [
      (b.left + b.width * (plusRight ? 0.75 : 0.25), Palette.busPlus),
      (b.left + b.width * (plusRight ? 0.25 : 0.75), Palette.busMinus),
    ]) {
      final wire = Path()
        ..moveTo(x, b.bottom - 0.6)
        ..lineTo(x, artHeight + 0.4)
        ..lineTo(cx + (x - cx) * 0.4, top + 0.8);
      canvas.drawPath(
        wire,
        Paint()
          ..color = hz.lineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.data
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        wire,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
    final end = sub ? width + reach : -reach;
    final sheath = Path()
      ..moveTo(cx, top)
      ..lineTo(cx, bend)
      ..quadraticBezierTo(cx, level, cx + dir * 3.5, level)
      ..lineTo(end, level);
    canvas.drawPath(
      sheath,
      Paint()
        ..color = Palette.busSheath
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.2,
    );
    if (active && t < 1) {
      final metric = sheath.computeMetrics().first;
      // From the line into the coupler.
      final at = metric.getTangentForOffset(metric.length * (1 - t))!.position;
      final fade = math.min(1.0, t * 6) * (1 - t * 0.4);
      canvas.drawCircle(
        at,
        2.6,
        Paint()
          ..color = Palette.busPulse.withValues(alpha: 0.85 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0),
      );
      canvas.drawCircle(at, 0.9, Paint()..color = Palette.busPulse.withValues(alpha: fade));
    }
    canvas.restore();
  }

  /// Bus cable below the bus terminal: red and black wires from the terminal
  /// into the green sheath. A pulse runs along the wires as a bright spot (away
  /// from the device when it sends, towards it when it receives) and makes the
  /// terminal light up briefly.
  void _cable(Canvas canvas, Rect b, {required double t, required bool active, required bool out}) {
    canvas.save();
    canvas.scale(scale);
    final cx = b.center.dx;
    // Each wire in the middle of its half of the terminal.
    final plus = b.left + b.width * (plusRight ? 0.75 : 0.25);
    final minus = b.left + b.width * (plusRight ? 0.25 : 0.75);
    final plusInto = cx + (plusRight ? 0.8 : -0.8), minusInto = cx + (plusRight ? -0.8 : 0.8);
    final sheathTop = artHeight + 3.5;
    final end = artHeight + _cableLength;
    // Wires run vertically out of the terminal and bend in towards the sheath.
    Path wire(double x, double into) => Path()
      ..moveTo(x, b.bottom - 0.6)
      ..lineTo(x, artHeight + 0.6)
      ..quadraticBezierTo(x, sheathTop - 0.4, into, sheathTop + 0.6);
    for (final (x, into, color) in [(plus, plusInto, Palette.busPlus), (minus, minusInto, Palette.busMinus)]) {
      // Fine outline so the black wire stands out on a dark background too.
      canvas.drawPath(
        wire(x, into),
        Paint()
          ..color = hz.lineStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = Lines.data
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        wire(x, into),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..strokeCap = StrokeCap.round,
      );
    }
    final sheath = RRect.fromRectAndCorners(
      Rect.fromLTRB(cx - 2.3, sheathTop, cx + 2.3, end + 1),
      topLeft: const Radius.circular(1.2),
      topRight: const Radius.circular(1.2),
    );
    // The sheath fades out downwards instead of ending abruptly.
    final fadeOut = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Palette.busSheath, Palette.busSheath, Palette.busSheath.withValues(alpha: 0)],
      stops: const [0, 0.5, 1],
    ).createShader(sheath.outerRect);
    canvas.drawRRect(sheath, Paint()..shader = fadeOut);

    if (active && t < 1) {
      // Fast in, slow out; weaker further down in the fading sheath.
      final s = out ? t : 1 - t;
      final y = b.bottom + s * (end - 2 - b.bottom);
      final fade = math.min(1.0, t * 6) * (1 - t * 0.5) * (1 - 0.6 * s);
      // The terminal lights up at the start (send) or at the end (receive).
      final near = out ? 1 - t : t;
      canvas.drawRect(b, Paint()..color = Palette.busPulse.withValues(alpha: 0.5 * near * near));
      final halo = Paint()
        ..color = Palette.busPulse.withValues(alpha: 0.9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
      final core = Paint()..color = Palette.busPulse.withValues(alpha: 0.95 * fade);
      if (y < sheathTop) {
        // On both wires, which converge towards the sheath.
        final k = ((y - artHeight) / (sheathTop - artHeight)).clamp(0.0, 1.0);
        for (final (x, into) in [(plus, plusInto), (minus, minusInto)]) {
          final at = Offset(x + (into - x) * k * k, y);
          canvas.drawCircle(at, 1.8, halo);
          canvas.drawCircle(at, 0.65, core);
        }
      } else {
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, y), width: 6, height: 4), halo);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, y), width: 3, height: 1.4), core);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ArtPainter old) => true;
}

/// Front of a generic actuator in the neutral look "A": housing with terminal
/// strips at the top and bottom, front plate with pictogram, per channel a
/// number, LED (off), control element by type and label field, plus address
/// field, programming LED and button, and bus terminal. [_ArtPainter] paints
/// lights, rocker, names and address on top.
class _GenericFrontPainter extends CustomPainter {
  _GenericFrontPainter(this.art);

  final DeviceArt art;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / art.size.width;
    canvas.save();
    canvas.scale(k);
    final w = art.size.width;
    void box(Rect r, Color fill, Color edge, {double radius = 0, double stroke = 0.25}) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(radius));
      canvas.drawRRect(rr, Paint()..color = fill);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }

    Paint line(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Terminal strip with screws, evenly spaced between x0 and x1.
    void terminals(double y, double x1) {
      box(Rect.fromLTWH(2, y, w - 4, 12.4), Palette.deviceStep, Palette.deviceEdge, radius: 0.8);
      const pitch = 8.5;
      final count = ((x1 - 2) / pitch).floor();
      final start = 2 + ((x1 - 2) - (count - 1) * pitch) / 2;
      for (var i = 0; i < count; i++) {
        final c = Offset(start + i * pitch, y + 5.2);
        canvas.drawCircle(c, 2.3, Paint()..color = Palette.deviceScrew);
        canvas.drawCircle(c, 2.3, line(Palette.deviceEdge, 0.25));
        canvas.drawLine(c + const Offset(-1.5, 1.5), c + const Offset(1.5, -1.5), line(Palette.deviceScrewSlot, 0.45));
      }
    }

    void text(String value, Offset at, double size) {
      final tp = TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(
            color: Palette.deviceInk,
            fontSize: size,
            fontWeight: FontWeight.w600,
            fontFamily: HzFont.sans,
            package: HzFont.package,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 8);
      tp.paint(canvas, at);
      tp.dispose();
    }

    box(Rect.fromLTWH(0.15, 0.15, w - 0.3, 89.7), Palette.deviceHousing, Palette.deviceEdge, radius: 1.6, stroke: 0.3);
    terminals(1.2, w - 2);
    box(Rect.fromLTWH(1, 15, w - 2, 60), Palette.deviceFront, Palette.deviceEdge, radius: 1);

    // Pictogram of the device type and two decorative lines.
    final kinds = art.channelKinds;
    final kind = ChannelKind.values.firstWhere(
      (k) => kinds.where((x) => x == k).length * 2 > kinds.length,
      orElse: () => kinds.isEmpty ? ChannelKind.switching : kinds.first,
    );
    final ink = line(Palette.deviceInk, 0.35);
    canvas.save();
    canvas.translate(4, 17.6);
    canvas.scale(0.9);
    switch (kind) {
      case ChannelKind.blind:
        for (var y = 0.0; y <= 3.6; y += 1.2) {
          canvas.drawLine(Offset(0.4, y), Offset(5.6, y), ink);
        }
      case ChannelKind.heating:
        for (final x in [0.6, 3.0, 5.4]) {
          canvas.drawPath(
            Path()
              ..moveTo(x, 4)
              ..quadraticBezierTo(x + 0.8, 3, x, 2)
              ..quadraticBezierTo(x - 0.8, 1, x, 0),
            ink,
          );
        }
      case ChannelKind.dimming:
        canvas.drawCircle(const Offset(3, 2.2), 1.6, ink);
        canvas.drawLine(const Offset(0, 2.2), const Offset(0.7, 2.2), ink);
        canvas.drawLine(const Offset(5.3, 2.2), const Offset(6, 2.2), ink);
      default:
        canvas.drawPath(
          Path()
            ..moveTo(0, 2.4)
            ..lineTo(1.6, 2.4)
            ..lineTo(4, 0.8)
            ..moveTo(4.2, 2.4)
            ..lineTo(6, 2.4),
          ink,
        );
    }
    canvas.restore();
    final rule = line(Palette.deviceRule, 0.5);
    canvas.drawLine(const Offset(12, 18.6), Offset(math.min(30, w - 6), 18.6), rule);
    canvas.drawLine(const Offset(12, 20.4), Offset(math.min(23, w - 10), 20.4), rule);

    for (final (i, c) in art.channels.indexed) {
      final x = c.area.left, y = c.area.top;
      text(c.key, Offset(x + 1.4, y + 0.8), 2.6);
      if (c.led case (final led, final r)) {
        canvas.drawCircle(led, r, Paint()..color = Palette.deviceLedOffA);
        canvas.drawCircle(led, r, line(Palette.deviceLedRing, 0.2));
      }
      final channelKind = i < kinds.length ? kinds[i] : ChannelKind.switching;
      if (c.contact case (final pivot, _, final closed)) {
        // Fixed contact and supply lead; [_ArtPainter] draws the rocker.
        final contact = line(Palette.deviceInk, 0.25);
        canvas.drawLine(Offset(x + 1.4, pivot.dy), pivot, contact);
        canvas.drawPath(
          Path()
            ..moveTo(closed.dx, closed.dy - 1)
            ..lineTo(closed.dx, closed.dy)
            ..lineTo(closed.dx + 2, closed.dy),
          contact,
        );
        canvas.drawCircle(pivot, 0.35, Paint()..color = Palette.deviceInk);
      } else if (channelKind == ChannelKind.blind) {
        for (final up in [true, false]) {
          final base = up ? Offset(x + 2, y + 10) : Offset(x + 7, y + 7.8);
          final tri = Path()
            ..moveTo(base.dx, base.dy)
            ..lineTo(base.dx + 1.6, base.dy + (up ? -2.2 : 2.2))
            ..lineTo(base.dx + 3.2, base.dy)
            ..close();
          canvas.drawPath(tri, Paint()..color = Palette.deviceKey);
          canvas.drawPath(tri, line(Palette.deviceKeyEdge, 0.25));
        }
      } else if (channelKind != ChannelKind.heating) {
        box(Rect.fromLTWH(x + 2, y + 7.2, 10, 3.4), Palette.deviceKey, Palette.deviceKeyEdge, radius: 0.8);
      }
      if (c.label case final l?) {
        box(l, Palette.deviceLabel, Palette.deviceLabelEdge, radius: 0.3, stroke: 0.2);
      }
    }

    if (art.address case final a?) {
      box(a, Palette.deviceLabel, Palette.deviceLabelEdge, radius: 0.3, stroke: 0.2);
    }
    // Programming LED and button.
    canvas.drawCircle(Offset(w - 16.6, 68.9), 1.0, Paint()..color = Palette.deviceProgOff);
    canvas.drawCircle(Offset(w - 16.6, 68.9), 1.0, line(Palette.deviceLedRing, 0.2));
    box(Rect.fromLTWH(w - 13.4, 66.9, 7, 4), Palette.deviceKey, Palette.deviceKeyEdge, radius: 0.8);
    terminals(76.4, w - 18);
    // Busklemme rot (+) links, schwarz (−) rechts.
    if (art.bus case final b?) {
      canvas.drawRect(Rect.fromLTWH(b.left, b.top, b.width / 2, b.height), Paint()..color = Palette.busPlus);
      canvas.drawRect(Rect.fromLTWH(b.center.dx, b.top, b.width / 2, b.height), Paint()..color = Palette.busMinus);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GenericFrontPainter old) => old.art != art;
}
