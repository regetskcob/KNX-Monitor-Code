import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../catalog_store.dart';
import '../export/telegram_files.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/annotation.dart';
import '../model/bus_metrics.dart';
import '../model/template_rules.dart';
import '../model/saved_charts.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'address_picker.dart';
import 'chart_cards.dart' show chartChoices;
import 'annotations.dart';
import 'common.dart';
import 'figure_box.dart';
import 'history_chart.dart';
import 'telegram_row.dart';
import '../model/installation.dart';
import '../platform/addon.dart';

/// A series in the chart.
class ChartSeries {
  ChartSeries(this.address, this.points, this.kind, this.dpt, this.color);

  final int address;
  final List<ChartPoint> points;
  final ChartKind kind;
  final Dpt? dpt;
  final Color color;

  /// Technical metric instead of a group address ([BusMetric]).
  BusMetric? get metric => BusMetric.of(address);

  String get name => chartSeriesName(address);

  /// Identifier for export and hints: "1/2/3" or "telegrams", "line 1.1".
  String get label => switch (metric) {
    final m? => m.line == null ? m.key : 'line ${BusMetric.lineLabel(m.line!)}',
    null => formatGroup(address),
  };

  /// The unit determines the panel: series with the same unit share a y-axis.
  String get unit =>
      metric != null ? BusMetric.unit : (kind == ChartKind.step ? '0/1' : (dpt == null ? '' : dptUnit(dpt!)));

  /// Value of a point for the legend and crosshair.
  String valueOf(ChartPoint p) =>
      metric != null ? '${chartNumber(p.value)} ${BusMetric.unit}' : CatalogStore.instance.value(p.telegram);

  /// Value that applied at time [t] (last point before it).
  ChartPoint? valueAt(DateTime t) {
    ChartPoint? last;
    for (final p in points) {
      if (p.time.isAfter(t)) break;
      last = p;
    }
    return last;
  }
}

/// Name of a series: group address from the project or "1/2/3", metric like
/// "Telegramme/min".
String chartSeriesName(int id) => BusMetric.of(id)?.name ?? CatalogStore.instance.info(id)?.name ?? formatGroup(id);

/// Series for [id] from [log]: group address (values of the telegrams) or
/// technical metric (telegrams per minute). `null` without values.
ChartSeries? seriesFor(int id, TelegramLog log, Color color) {
  if (BusMetric.of(id) case final metric?) {
    final rates = metric.rates(log.log, now: log.live ? DateTime.now() : null);
    if (rates.isEmpty) return null;
    return ChartSeries(id, [for (final (t, v) in rates) ChartPoint(t, v, _noTelegram(t))], ChartKind.line, null, color);
  }
  return seriesOf(id, log.forAddress(id), color);
}

/// Series of the group address [id] from [telegrams] (any order). `null`
/// without values.
ChartSeries? seriesOf(int id, List<Telegram> telegrams, Color color) {
  final dpt = CatalogStore.instance.dptOf(id);
  final d = chartData(dpt, telegrams..sort((x, y) => x.time.compareTo(y.time)));
  if (d.points.isEmpty) return null;
  return ChartSeries(
    id,
    d.points,
    // A single value has no kind yet: switching value by type.
    d.kind == ChartKind.none
        ? (dpt?.main == 1 || d.points.every((p) => p.telegram.isSmall && p.value <= 1)
              ? ChartKind.step
              : ChartKind.line)
        : d.kind,
    dpt,
    color,
  );
}

/// Placeholder telegram for points of a metric (not a real telegram).
Telegram _noTelegram(DateTime t) =>
    Telegram(time: t, source: 0, destination: 0, type: TelegramType.write, data: Uint8List(0), isSmall: false);

/// Up to [max] points: keeps minimum and maximum per pixel column so short
/// peaks do not vanish when thinning out.
List<ChartPoint> downsample(List<ChartPoint> points, int max) {
  if (points.length <= max || max < 4) return points;
  final buckets = max ~/ 2;
  final t0 = points.first.time.microsecondsSinceEpoch;
  final span = math.max(1, points.last.time.microsecondsSinceEpoch - t0);
  final result = <ChartPoint>[];
  var i = 0;
  for (var b = 0; b < buckets && i < points.length; b++) {
    final end = t0 + span * (b + 1) / buckets;
    ChartPoint? lo, hi;
    while (i < points.length && points[i].time.microsecondsSinceEpoch <= end) {
      final p = points[i++];
      if (lo == null || p.value < lo.value) lo = p;
      if (hi == null || p.value > hi.value) hi = p;
    }
    if (lo == null || hi == null) continue;
    if (identical(lo, hi)) {
      result.add(lo);
    } else {
      result.addAll(lo.time.isBefore(hi.time) ? [lo, hi] : [hi, lo]);
    }
  }
  if (!identical(result.last, points.last)) result.add(points.last);
  return result;
}

/// Period of the charts: what the app holds in memory, or a longer one from the
/// history of the add-on or box.
enum ChartPeriod {
  loaded(null),
  today(null),
  week(7),
  month(30);

  const ChartPeriod(this.days);

  /// Days back for [week] and [month]; [today] starts at midnight.
  final int? days;

  String get label => switch (this) {
    loaded => s.chartsPeriodLoaded,
    today => s.chartsPeriodToday,
    _ => s.historyDays(days!),
  };

  /// Start of the period at [now]; `null` for [loaded].
  DateTime? from(DateTime now) => switch (this) {
    loaded => null,
    today => DateTime(now.year, now.month, now.day),
    // Calendar days: across a clock change the same time of day.
    _ => DateTime(now.year, now.month, now.day - days!, now.hour, now.minute, now.second),
  };
}

/// Several group addresses over time: one panel per unit, shared time axis,
/// crosshair with all values, saved selection, export.
class ChartsScreen extends StatefulWidget {
  const ChartsScreen({super.key, required this.log, this.initial = const [], this.chart, this.onOpenAddress});

  /// Tapping the legend: details of the group address (read, write, map).
  final ValueChanged<int>? onOpenAddress;

  /// Opens a saved chart (name); changes are stored in it.
  final String? chart;

  final TelegramLog log;
  final List<int> initial;

  @override
  State<ChartsScreen> createState() => _ChartsScreenState();
}

class _ChartsScreenState extends State<ChartsScreen> {
  static const _maxSeries = SavedCharts.maxSeries;
  static const _lastKey = 'chart_last';

  List<int> _selected = [];
  SavedCharts get _saved => SavedCharts.instance;

  /// Offenes gespeichertes Diagramm; `null` = freie Auswahl.
  String? _chart;
  DateTime? _cursor;

  /// The crosshair was placed by a click or tap: it stays there (the pointer
  /// may move on to the action next to it) until the next click.
  bool _pinned = false;

  void _pin(DateTime t) => setState(() {
    _cursor = t;
    _pinned = true;
  });

  /// Height per chart dragged by the user; `null` = fills the screen.
  double? _panelHeight;

  static const _periodKey = 'chart_period';

  /// Chosen period (the selected chip).
  ChartPeriod _period = ChartPeriod.loaded;

  /// Period the chart shows. While a longer period loads, the previous chart
  /// stays (dimmed) instead of briefly showing the loaded telegrams.
  ChartPeriod _shown = ChartPeriod.loaded;

  /// Telegrams of the selected addresses from the server for [_shown].
  Map<int, List<Telegram>>? _remote;

  /// End of [_remote]; newer telegrams come from the log.
  DateTime? _remoteTo;
  bool _remoteLoading = false;
  String? _remoteError;

  /// First day of the server's history; periods reaching no further back than
  /// a shorter one are hidden. `null` while unknown (then all are offered).
  DateTime? _historyStart;

  /// Periods worth offering: one only if the history reaches further back
  /// than the next shorter one.
  List<ChartPeriod> get _periods {
    final start = _historyStart;
    if (start == null) return ChartPeriod.values;
    final now = DateTime.now();
    return [
      ChartPeriod.loaded,
      ChartPeriod.today,
      if (start.isBefore(ChartPeriod.today.from(now)!)) ChartPeriod.week,
      if (start.isBefore(ChartPeriod.week.from(now)!)) ChartPeriod.month,
    ];
  }

  /// Latest request; an older answer arriving late is dropped.
  int _remoteRequest = 0;

  /// Minimum distance between two data points in full screen, in pixels.
  static const _pointSpacing = 14.0;
  final _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    _chart = widget.chart;
    _selected = [...widget.initial];
    _saved.addListener(_onSaved);
    _load();
  }

  @override
  void dispose() {
    _saved.removeListener(_onSaved);
    super.dispose();
  }

  void _onSaved() {
    if (mounted) setState(() {});
  }

  void _open(String? chart) {
    setState(() {
      _chart = chart;
      _selected = chart == null ? [] : [...?_saved.charts[chart]];
    });
    _reloadRemote();
  }

  Future<void> _setPeriod(ChartPeriod period) async {
    // Tapping the selected chip again does not ask the server again, unless
    // the last attempt failed.
    if (period == _period && _remoteError == null) {
      return;
    }
    if (period == _period) return _reloadRemote();
    setState(() {
      _period = period;
      _remoteError = null;
      // The loaded telegrams are at hand: switch at once.
      if (period == ChartPeriod.loaded) _shown = period;
    });
    unawaited(_reloadRemote());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_periodKey, period.name);
  }

  /// Fetches [_period] for the selected addresses from the add-on or box.
  Future<void> _reloadRemote() async {
    final request = ++_remoteRequest;
    final now = DateTime.now();
    final from = _period.from(now);
    final addresses = {
      for (final a in _selected)
        if (BusMetric.of(a) == null) a: CatalogStore.instance.dptOf(a),
    };
    if (from == null || !Addon.available || addresses.isEmpty) {
      if (mounted) {
        setState(() {
          _remoteLoading = false;
          if (from != null && addresses.isEmpty) _shown = _period;
        });
      }
      return;
    }
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
    });
    try {
      final result = await Addon.historyTelegrams(addresses, from, now);
      if (!mounted || request != _remoteRequest) return;
      setState(() {
        _remote = result;
        _remoteTo = now;
        _shown = _period;
        _remoteLoading = false;
      });
    } on Object catch (e) {
      if (!mounted || request != _remoteRequest) return;
      setState(() {
        // Without an answer (server stopped, network gone) a plain sentence
        // instead of the browser's technical message.
        _remoteError = e is AddonException ? e.message : s.chartsPeriodUnreachable;
        _remoteLoading = false;
      });
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _saved.load();
    var period = Addon.available
        ? ChartPeriod.values.where((p) => p.name == prefs.getString(_periodKey)).firstOrNull
        : null;
    if (Addon.available) {
      try {
        final storage = (await Addon.status())['storage'] as Map<String, Object?>?;
        _historyStart = DateTime.tryParse(storage?['first'] as String? ?? '');
      } on Object catch (e) {
        debugPrint('Verlaufsbeginn unbekannt: $e');
      }
      // A remembered period the history no longer covers: the longest one it does.
      if (period != null && !_periods.contains(period)) period = _periods.last;
    }
    final last = [
      for (final v in prefs.getStringList(InstallationStore.instance.key(_lastKey)) ?? const <String>[])
        ?int.tryParse(v),
    ];
    if (!mounted) return;
    setState(() {
      if (_chart case final chart?) {
        _selected = [...?_saved.charts[chart]];
      } else if (_selected.isEmpty) {
        _selected = last;
      }
      if (period != null) _period = period;
    });
    unawaited(_reloadRemote());
  }

  Future<void> _store() async {
    // Open chart: the selection belongs to it; otherwise "last shown".
    if (_chart case final chart?) return _saved.put(chart, _selected);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(InstallationStore.instance.key(_lastKey), [for (final a in _selected) '$a']);
  }

  void _toggle(int address) {
    setState(() {
      if (!_selected.remove(address) && _selected.length < _maxSeries) _selected.add(address);
    });
    _store();
    _reloadRemote();
  }

  /// A longer period shows the server's history; what arrived since then comes
  /// from the log, so the chart keeps running live.
  bool get _fromServer => _shown != ChartPeriod.loaded && Addon.available;

  List<ChartSeries> _series() {
    final dark = Theme.of(context).colorScheme.isDark;
    final remote = _remote;
    ChartSeries? of(int i, int a) {
      final color = Palette.series(i, dark: dark);
      if (!_fromServer || remote == null || BusMetric.of(a) != null) return seriesFor(a, widget.log, color);
      final since = _remoteTo!;
      return seriesOf(a, [
        ...?remote[a],
        for (final t in widget.log.forAddress(a))
          if (t.time.isAfter(since)) t,
      ], color);
    }

    return [for (final (i, a) in _selected.indexed) ?of(i, a)];
  }

  Future<void> _pick() async {
    final log = widget.log;
    // Metrics (telegrams/min …) are not part of the selection and stay.
    final metrics = _selected.where((a) => BusMetric.of(a) != null).length;
    final chosen = await pickAddresses(
      context,
      title: _chart ?? s.chartsAdd,
      items: chartChoices(log),
      initial: _selected.where((a) => BusMetric.of(a) == null).toSet(),
      counts: log.counts,
      history: log.history,
      log: log,
      max: _maxSeries - metrics,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      // Order (colors) of the existing series stays.
      _selected = [
        for (final a in _selected)
          if (chosen.contains(a) || BusMetric.of(a) != null) a,
        for (final a in chosen)
          if (!_selected.contains(a)) a,
      ];
    });
    await _store();
    unawaited(_reloadRemote());
  }

  Future<String?> _askName({String initial = ''}) => askChartName(context, initial: initial);

  /// Per series the value that applied at [t] and the different one before it,
  /// for the comment.
  static List<ChartValue> _valuesAt(DateTime t, List<ChartSeries> series) => [
    for (final sr in series)
      if (sr.points.lastIndexWhere((p) => !p.time.isAfter(t)) case final i when i >= 0)
        ChartValue(
          group: sr.address,
          name: sr.name,
          now: sr.valueOf(sr.points[i]),
          before: switch (sr.points.sublist(0, i).lastIndexWhere((p) => p.value != sr.points[i].value)) {
            final j when j >= 0 => sr.valueOf(sr.points[j]),
            _ => null,
          },
        ),
  ];

  /// "Comment here" next to the pinned crosshair; to its left near the right
  /// edge. The cross unpins it, the crosshair follows the pointer again.
  Widget _commentHere(DateTime t0, DateTime t1, double width, List<ChartSeries> series) {
    final c = _cursor!;
    final span = math.max(1, t1.microsecondsSinceEpoch - t0.microsecondsSinceEpoch);
    final x = (width - _MultiChartPainter.right) * (c.microsecondsSinceEpoch - t0.microsecondsSinceEpoch) / span;
    final chip = InputChip(
      avatar: const Icon(AppIcons.annotation, size: 16),
      label: Text(s.chartsAnnotateHere),
      onPressed: () =>
          annotateChart(context, time: c, groups: [..._selected], from: t0, to: t1, values: _valuesAt(c, series)),
      deleteButtonTooltipMessage: s.commonClose,
      onDeleted: () => setState(() => _pinned = false),
    );
    return x > width * 0.6
        ? Positioned(right: width - x + HzSpace.s8, top: HzSpace.s8, child: chip)
        : Positioned(left: x + HzSpace.s8, top: HzSpace.s8, child: chip);
  }

  /// Period chips; while loading a small indicator, an error below them.
  Widget _periodBar(List<ChartSeries> series) {
    final hz = context.hz;
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textMuted);
    return Padding(
      padding: const EdgeInsets.only(top: Gap.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: HzSpace.s8,
        children: [
          Tooltip(
            message: s.chartsPeriodLoadedHint,
            child: Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final p in _periods)
                  ChoiceChip(
                    showCheckmark: false,
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) => _setPeriod(p),
                  ),
                if (_remoteLoading)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
                  ),
              ],
            ),
          ),
          if (_remoteError case final error?)
            Row(
              children: [
                Flexible(child: Text(s.chartsPeriodFailed(error), style: muted)),
                const SizedBox(width: HzSpace.s8),
                TextButton(onPressed: _reloadRemote, child: Text(s.chartsPeriodRetry)),
              ],
            ),
          if (_fromServer && series.any((sr) => sr.metric != null)) Text(s.chartsPeriodMetrics, style: muted),
        ],
      ),
    );
  }

  Future<void> _rename() async {
    final from = _chart;
    if (from == null) return;
    final name = await _askName(initial: from);
    if (name == null || name.isEmpty || name == from) return;
    await _saved.put(name, _selected, from: from);
    setState(() => _chart = name);
  }

  Future<void> _delete() async {
    final chart = _chart;
    if (chart == null) return;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.chartDeleteTitle),
        content: Text(s.chartDeleteText(chart)),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.commonDelete,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _saved.remove(chart);
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _saveSelection() async {
    final name = await _askName();
    if (name == null || name.isEmpty) return;
    final unique = _saved.uniqueName(name);
    await _saved.put(unique, _selected);
    setState(() => _chart = unique);
  }

  Future<void> _exportPng() async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    if (!mounted) return;
    await saveBytes(context, bytes, fileName(s.chartsTitle, 'png'), mimeType: 'image/png');
  }

  /// Saves the chart as a template (roles instead of addresses,
  /// [TemplateRule]).
  Future<void> _shareTemplate() async {
    final name = _chart;
    if (name == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final store = CatalogStore.instance;
    final (:rule, :dropped) = ruleFromChart(
      name,
      _selected,
      store.catalog.groups,
      store.catalog.devices,
      dptOf: store.dptOf,
    );
    if (rule == null) {
      messenger.showSnackBar(SnackBar(content: Text(s.chartShareTemplateEmpty)));
      return;
    }
    final json = const JsonEncoder.withIndent('  ').convert(rule.toJson());
    await saveBytes(context, utf8Bytes(json), fileName(rule.name, 'json'), mimeType: 'application/json');
    if (dropped > 0) messenger.showSnackBar(SnackBar(content: Text(s.chartShareTemplateDropped(dropped))));
  }

  Future<void> _exportCsv(List<ChartSeries> series) async {
    final rows = StringBuffer(
      '${[s.columnTime, s.columnAddress, s.columnName, s.columnValue].map(csvCell).join(',')}\r\n',
    );
    for (final sr in series) {
      for (final p in sr.points) {
        rows.write('${[p.time.toIso8601String(), sr.label, sr.name, p.value].map(csvCell).join(',')}\r\n');
      }
    }
    await saveBytes(context, utf8Bytes(rows.toString()), fileName(s.chartsTitle, 'csv'), mimeType: 'text/csv');
  }

  Widget _removeButton(int address) => IconButton(
    tooltip: s.commonDelete,
    visualDensity: VisualDensity.compact,
    onPressed: () => _toggle(address),
    icon: const Icon(AppIcons.close, size: HzIconSize.row),
  );

  /// Row of a series: color swatch, name, address; on the right the value at
  /// the crosshair, otherwise the current one. Tapping opens the address.
  Widget _seriesRow(ChartSeries sr, TextStyle data) {
    final point = _cursor == null ? sr.points.lastOrNull : sr.valueAt(_cursor!);
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: SizedBox.square(
        dimension: HzSpace.s12,
        child: ColoredBox(color: sr.color),
      ),
      minLeadingWidth: HzSpace.s12,
      title: Text(sr.name),
      subtitle: sr.metric != null
          ? null
          : Text(
              formatGroup(sr.address),
              style: context.mono(theme.textTheme.bodySmall).copyWith(color: context.hz.textFaint),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: HzSpace.s4,
        children: [
          if (point != null)
            Text(
              sr.valueOf(point),
              style: context.figures(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
            ),
          _removeButton(sr.address),
        ],
      ),
      onTap: widget.onOpenAddress == null || sr.metric != null ? null : () => widget.onOpenAddress!(sr.address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final data = context.hzTheme.data;
    // Time axis: Monaspace one step smaller (caption), muted.
    final axis = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: HzFont.mono,
      package: HzFont.package,
      fontFeatures: data.fontFeatures,
      color: hz.textMuted,
    );
    return ListenableBuilder(
      listenable: widget.log,
      builder: (context, _) {
        final series = _series();
        final waiting = [
          for (final a in _selected)
            if (!series.any((sr) => sr.address == a)) a,
        ];
        // Numbers share one panel per unit (for comparison); switching values
        // get their own row per address, since drawn on top of each other you
        // could no longer tell who switches when.
        final byUnit = <String, List<ChartSeries>>{};
        final lanes = <ChartSeries>[];
        for (final sr in series) {
          if (sr.kind == ChartKind.step) {
            lanes.add(sr);
          } else {
            (byUnit[sr.unit] ??= []).add(sr);
          }
        }
        final times = series.expand((sr) => sr.points.map((p) => p.time)).toList();
        final t0 = times.isEmpty ? DateTime.now() : times.reduce((a, b) => a.isBefore(b) ? a : b);
        final t1 = times.isEmpty ? DateTime.now() : times.reduce((a, b) => a.isAfter(b) ? a : b);
        // Without a dragged height the charts share the free space.
        final free =
            MediaQuery.sizeOf(context).height -
            MediaQuery.paddingOf(context).vertical -
            260 -
            lanes.length * _LanePainter.height;
        // Capped: the addresses are listed below and stay in view.
        final panelHeight = _panelHeight ?? math.max(140.0, math.min(280.0, free / byUnit.length.clamp(1, 8)));
        return Scaffold(
          appBar: AppBar(
            title: Text(_chart ?? s.chartsTitle),
            actions: [
              // Comment at the crosshair: what stood out there, with time
              // window and series.
              IconButton(
                tooltip: _cursor == null
                    ? s.chartsAnnotateHint
                    : s.chartsAnnotate(
                        DateUtils.isSameDay(_cursor, DateTime.now())
                            ? formatTime(_cursor!)
                            : '${formatTick(_cursor!, const Duration(days: 1))} ${formatTime(_cursor!)}',
                      ),
                onPressed: _cursor == null || series.isEmpty
                    ? null
                    : () => annotateChart(
                        context,
                        time: _cursor!,
                        groups: [..._selected],
                        from: t0,
                        to: t1,
                        values: _valuesAt(_cursor!, series),
                      ),
                icon: const Icon(AppIcons.annotation),
              ),
              IconButton(tooltip: s.chartsAdd, onPressed: _pick, icon: const Icon(AppIcons.add)),
              PopupMenuButton<String>(
                icon: Icon(AppIcons.more),
                tooltip: s.chartsMore,
                onSelected: (v) => switch (v) {
                  '\u0000save' => _saveSelection(),
                  '\u0000png' => _exportPng(),
                  '\u0000csv' => _exportCsv(series),
                  '\u0000clear' => () {
                    setState(() => _selected = []);
                    _store();
                    _reloadRemote();
                  }(),
                  '\u0000rename' => _rename(),
                  '\u0000template' => _shareTemplate(),
                  '\u0000delete' => _delete(),
                  _ => _open(v),
                },
                itemBuilder: (context) => [
                  if (_chart == null)
                    PopupMenuItem(
                      value: '\u0000save',
                      enabled: _selected.isNotEmpty,
                      child: Text(s.chartsSaveSelection),
                    )
                  else ...[
                    PopupMenuItem(value: '\u0000rename', child: Text(s.chartRename)),
                    PopupMenuItem(value: '\u0000template', child: Text(s.chartShareTemplate)),
                    PopupMenuItem(value: '\u0000delete', child: Text(s.chartDelete)),
                  ],
                  PopupMenuItem(value: '\u0000png', enabled: series.isNotEmpty, child: Text(s.chartsExportPng)),
                  PopupMenuItem(value: '\u0000csv', enabled: series.isNotEmpty, child: Text(s.chartsExportCsv)),
                  PopupMenuItem(value: '\u0000clear', enabled: _selected.isNotEmpty, child: Text(s.chartsClear)),
                  if (!_saved.isEmpty) const PopupMenuDivider(),
                  for (final name in _saved.charts.keys)
                    CheckedPopupMenuItem(value: name, checked: name == _chart, child: Text(name)),
                ],
              ),
            ],
          ),
          body: series.isEmpty && waiting.isEmpty
              ? HorizontEmptyHint(
                  icon: AppIcons.chart,
                  text: s.chartsEmpty,
                  action: (label: s.chartsAdd, onPressed: _pick),
                )
              : ListView(
                  padding: Gap.page,
                  children: [
                    if (Addon.available) _periodBar(series),
                    // Comments in the visible time window; tapping shows them,
                    // the crosshair jumps there.
                    ListenableBuilder(
                      listenable: AnnotationStore.instance,
                      builder: (context, _) {
                        final notes = series.isEmpty ? const <Annotation>[] : AnnotationScope.inRange(t0, t1);
                        if (notes.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: Gap.item),
                          child: Wrap(
                            spacing: Gap.item,
                            runSpacing: Gap.item,
                            children: [
                              for (final n in notes)
                                ActionChip(
                                  avatar: Icon(AppIcons.annotationSet, size: 16, color: hz.warning),
                                  label: Text(
                                    [
                                      formatTime(n.time, millis: false),
                                      if (n.note.isNotEmpty) n.note,
                                    ].join(metaSeparator),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onPressed: () async {
                                    setState(() => _cursor = n.time);
                                    await editAnnotation(context, n);
                                    if (mounted) setState(() {});
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    if (series.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: HzSpace.s96),
                        child: HorizontEmptyHint(icon: AppIcons.chart, text: s.chartsWaiting),
                      )
                    else ...[
                      const SizedBox(height: Gap.inner),
                      // Dimmed while another period loads; the chips show the spinner.
                      AnimatedOpacity(
                        opacity: _remoteLoading ? 0.4 : 1,
                        duration: Motion.of(context, Motion.fast),
                        child: SectionCard(
                          padding: const EdgeInsets.all(HzSpace.s8),
                          child: RepaintBoundary(
                            key: _boundary,
                            child: ColoredBox(
                              color: hz.surface,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  // All values visible: with many points wider
                                  // than the window and scrollable sideways,
                                  // newest on the right when opened. The y-axis
                                  // and row names stay fixed.
                                  const gutter = _MultiChartPainter.left;
                                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                                  final viewport = constraints.maxWidth - gutter;
                                  final points = series.fold(0, (n, sr) => math.max(n, sr.points.length));
                                  // From the server the period fits the window
                                  // (already thinned); the loaded telegrams keep
                                  // their spacing and scroll.
                                  final width = _fromServer ? viewport : math.max(viewport, points * _pointSpacing);
                                  final scrolls = width > viewport;
                                  DateTime timeAt(double x) {
                                    final f = (x / (width - _MultiChartPainter.right)).clamp(0.0, 1.0);
                                    return DateTime.fromMicrosecondsSinceEpoch(
                                      t0.microsecondsSinceEpoch +
                                          ((t1.microsecondsSinceEpoch - t0.microsecondsSinceEpoch) * f).round(),
                                    );
                                  }

                                  final axisStyle = axis ?? data;
                                  final axisHeight =
                                      (TextPainter(
                                        text: TextSpan(text: '0', style: axisStyle),
                                        textDirection: TextDirection.ltr,
                                        textScaler: MediaQuery.textScalerOf(context),
                                      )..layout()).height +
                                      2 * HzSpace.s4;
                                  _MultiChartPainter numbers(
                                    String unit,
                                    List<ChartSeries> list, {
                                    required bool axisOnly,
                                  }) => _MultiChartPainter(
                                    series: list,
                                    unit: unit,
                                    t0: t0,
                                    t1: t1,
                                    cursor: _cursor,
                                    colors: hz,
                                    label: data,
                                    textScale: textScale,
                                    maxPoints: (width * 2).round(),
                                    axisOnly: axisOnly,
                                  );
                                  _LanePainter lane(ChartSeries sr, {required bool axisOnly}) => _LanePainter(
                                    series: sr,
                                    t0: t0,
                                    t1: t1,
                                    cursor: _cursor,
                                    colors: hz,
                                    label: data,
                                    textScale: textScale,
                                    axisOnly: axisOnly,
                                  );

                                  final plots = Stack(
                                    children: [
                                      GestureDetector(
                                        // Wider than the window: dragging scrolls,
                                        // crosshair via tap/pointer.
                                        onHorizontalDragUpdate: scrolls
                                            ? null
                                            : (d) => _pin(timeAt(d.localPosition.dx)),
                                        onTapDown: (d) => _pin(timeAt(d.localPosition.dx)),
                                        child: MouseRegion(
                                          onHover: (e) {
                                            if (!_pinned) setState(() => _cursor = timeAt(e.localPosition.dx));
                                          },
                                          child: Column(
                                            children: [
                                              for (final MapEntry(key: unit, value: list) in byUnit.entries)
                                                SizedBox(
                                                  height: panelHeight,
                                                  width: width,
                                                  child: CustomPaint(painter: numbers(unit, list, axisOnly: false)),
                                                ),
                                              for (final sr in lanes)
                                                SizedBox(
                                                  height: _LanePainter.height,
                                                  width: width,
                                                  child: CustomPaint(painter: lane(sr, axisOnly: false)),
                                                ),
                                              SizedBox(
                                                height: axisHeight,
                                                width: width,
                                                child: CustomPaint(
                                                  painter: _TimeAxisPainter(
                                                    t0: t0,
                                                    t1: t1,
                                                    cursor: _cursor,
                                                    style: axisStyle,
                                                    cursorStyle: axisStyle.copyWith(
                                                      color: hz.text,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                    textScaler: MediaQuery.textScalerOf(context),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Beside the tap area, so tapping it does not move the crosshair.
                                      if (_pinned && _cursor != null) _commentHere(t0, t1, width, series),
                                    ],
                                  );
                                  final nameStyle = data.copyWith(
                                    color: hz.text,
                                    fontSize: data.fontSize == null
                                        ? null
                                        : data.fontSize! * _MultiChartPainter._labelRatio,
                                  );
                                  return Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: gutter,
                                        child: Column(
                                          children: [
                                            for (final MapEntry(key: unit, value: list) in byUnit.entries)
                                              SizedBox(
                                                height: panelHeight,
                                                width: gutter,
                                                child: CustomPaint(painter: numbers(unit, list, axisOnly: true)),
                                              ),
                                            for (final sr in lanes)
                                              SizedBox(
                                                height: _LanePainter.height,
                                                width: gutter,
                                                child: CustomPaint(painter: lane(sr, axisOnly: true)),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Stack(
                                          children: [
                                            if (scrolls)
                                              SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                reverse: true,
                                                child: plots,
                                              )
                                            else
                                              plots,
                                            // Names of the switching rows fixed at the left edge.
                                            for (final (i, sr) in lanes.indexed)
                                              Positioned(
                                                left: HzSpace.s8,
                                                right: _MultiChartPainter.right + HzSpace.s8,
                                                top: byUnit.length * panelHeight + i * _LanePainter.height,
                                                height: _LanePainter.height,
                                                child: IgnorePointer(
                                                  child: Align(
                                                    alignment: Alignment.centerLeft,
                                                    child: Text(
                                                      sr.name,
                                                      style: nameStyle,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Drag height
                      Semantics(
                        label: s.chartsResize,
                        child: GestureDetector(
                          onVerticalDragUpdate: (d) =>
                              setState(() => _panelHeight = (panelHeight + d.delta.dy).clamp(100.0, 600.0)),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.resizeRow,
                            child: SizedBox(
                              height: HzSpace.s24,
                              child: Center(
                                child: Container(
                                  width: HzSpace.s48,
                                  height: HzSpace.s4,
                                  decoration: BoxDecoration(color: hz.lineStrong, borderRadius: Radii.row),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Legend for the dashed ends: only when a line has one.
                    if (byUnit.values
                        .expand((l) => l)
                        .any((sr) => t1.difference(sr.points.last.time) > t1.difference(t0) * 0.01))
                      Text(
                        s.chartsDashedHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textMuted),
                      ),
                    if (series.isNotEmpty || waiting.isNotEmpty) ...[
                      SectionHead(s.chartsAddresses, detail: s.hpRoomsOf(series.length, _selected.length)),
                      RowCard(
                        children: [
                          for (final sr in series) _seriesRow(sr, data),
                          // Selected but no telegram yet: the series appears
                          // with the first one.
                          for (final a in waiting)
                            CardRow(
                              title: chartSeriesName(a),
                              meta: s.chartsNoValuesYet,
                              trailing: _removeButton(a),
                              onTap: widget.onOpenAddress == null || a < 0 ? null : () => widget.onOpenAddress!(a),
                            ),
                        ],
                      ),
                      const SizedBox(height: Gap.item),
                      OutlinedButton(onPressed: _pick, child: Text(s.chartsAdd)),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// A panel (one unit) with several series and a crosshair.
class _MultiChartPainter extends CustomPainter {
  _MultiChartPainter({
    required this.series,
    required this.unit,
    required this.t0,
    required this.t1,
    required this.cursor,
    required this.colors,
    required this.label,
    required this.maxPoints,
    this.textScale = 1,
    this.axisOnly = false,
  });

  /// Only the y labels (fixed column on the left, width [left]); otherwise only
  /// the panel without labels, left-aligned, as it scrolls sideways.
  final bool axisOnly;

  /// Grid, labels and crosshair from the theme; series in data colors.
  final HorizontColors colors;

  /// Style `data` (Monaspace) for the y labels.
  final TextStyle label;

  /// The user's text scale.
  final double textScale;

  /// Y labels one step smaller than `data` (caption instead of callout).
  static final _labelRatio = HzType.caption.size / HzType.data.size;

  static const left = 88.0;
  static const right = 12.0;

  /// Space on top for the unit, shown once above the y-axis.
  static const _top = 22.0;
  static const _bottom = 10.0;

  final List<ChartSeries> series;
  final String unit;
  final DateTime t0;
  final DateTime t1;
  final DateTime? cursor;
  final int maxPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(0, _top, size.width - right, size.height - _bottom);
    final step = series.every((sr) => sr.kind == ChartKind.step);
    final values = series.expand((sr) => sr.points.map((p) => p.value));
    var lo = step ? 0.0 : values.reduce(math.min);
    var hi = step ? 1.0 : values.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    } else if (!step) {
      final pad = (hi - lo) * 0.1;
      lo -= pad;
      hi += pad;
    }
    final a = t0.microsecondsSinceEpoch.toDouble();
    final b = math.max(t1.microsecondsSinceEpoch.toDouble(), a + 1);
    double x(DateTime t) => plot.left + plot.width * (t.microsecondsSinceEpoch - a) / (b - a);
    double y(double v) => plot.bottom - plot.height * (v - lo) / (hi - lo);

    final dpt = series.first.dpt;
    // Round values instead of fractions of the range; the unit is shown above.
    final ticks = step ? [0.0, 1.0] : niceTicks(lo, hi);
    if (axisOnly) {
      for (final v in ticks) {
        _label(
          canvas,
          step ? chartLabel(dpt, ChartKind.step, v) : chartNumber(v),
          Offset(size.width - HzSpace.s8, y(v)),
        );
      }
      if (!step && unit.isNotEmpty) _label(canvas, unit, Offset(size.width - HzSpace.s8, _top / 2));
      return;
    }

    // Grid as hairlines, without a frame.
    final gridPaint = Paint()
      ..color = colors.line
      ..strokeWidth = Lines.hairline;
    for (final v in ticks) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), gridPaint);
    }

    canvas.save();
    canvas.clipRect(plot);
    for (final sr in series) {
      final pts = downsample(sr.points, maxPoints);
      final stroke = Paint()
        ..color = sr.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = Lines.selection
        ..strokeJoin = StrokeJoin.round;
      // Steps: a KNX value holds until the next telegram arrives.
      final path = Path()..moveTo(x(pts.first.time), y(pts.first.value));
      for (var i = 1; i < pts.length; i++) {
        path
          ..lineTo(x(pts[i].time), y(pts[i - 1].value))
          ..lineTo(x(pts[i].time), y(pts[i].value));
      }
      canvas.drawPath(path, stroke);
      // The last value holds until the end of the period, dashed because it is
      // still open.
      _dash(canvas, Offset(x(pts.last.time), y(pts.last.value)), plot.right, stroke);
    }
    final c = cursor;
    if (c != null) {
      final cx = x(c);
      canvas.drawLine(
        Offset(cx, plot.top),
        Offset(cx, plot.bottom),
        Paint()
          ..color = colors.lineStrong
          ..strokeWidth = Lines.hairline,
      );
      // Values at the crosshair as plain dots, without a halo.
      for (final sr in series) {
        final p = sr.valueAt(c);
        if (p != null) canvas.drawCircle(Offset(cx, y(p.value)), HzSpace.s4, Paint()..color = sr.color);
      }
    }
    canvas.restore();
  }

  static void _dash(Canvas canvas, Offset from, double toX, Paint paint) {
    final dash = Paint()
      ..color = paint.color.withValues(alpha: 0.6)
      ..strokeWidth = paint.strokeWidth;
    for (var x = from.dx; x < toX; x += 2 * HzSpace.s4) {
      canvas.drawLine(Offset(x, from.dy), Offset(math.min(x + HzSpace.s4, toX), from.dy), dash);
    }
  }

  void _label(Canvas canvas, String s, Offset rightCenter) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: label.copyWith(color: colors.textMuted),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.linear(_labelRatio * textScale),
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: left - HzSpace.s8);
    tp.paint(canvas, Offset(rightCenter.dx - tp.width, rightCenter.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_MultiChartPainter old) =>
      old.series != series ||
      old.cursor != cursor ||
      old.t0 != t0 ||
      old.t1 != t1 ||
      old.maxPoints != maxPoints ||
      old.axisOnly != axisOnly ||
      old.colors != colors ||
      old.label != label ||
      old.textScale != textScale;
}

/// One row per switching value: active as a band in the series color, the name
/// inside the row (the left column is too narrow for names, the caller places
/// it fixed on top), on the left the state at the crosshair or the last one;
/// time axis and crosshair as above.
class _LanePainter extends CustomPainter {
  _LanePainter({
    required this.series,
    required this.t0,
    required this.t1,
    required this.cursor,
    required this.colors,
    required this.label,
    this.textScale = 1,
    this.axisOnly = false,
  });

  static const height = 40.0;
  static const _pad = HzSpace.s4;

  final ChartSeries series;
  final DateTime t0;
  final DateTime t1;
  final DateTime? cursor;
  final HorizontColors colors;
  final TextStyle label;
  final double textScale;

  /// Like [_MultiChartPainter.axisOnly]: only the state on the left or only the
  /// row.
  final bool axisOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final c = cursor;
    final pts = series.points;
    if (axisOnly) {
      final now = c == null ? pts.lastOrNull : series.valueAt(c);
      if (now == null) return;
      final state = TextPainter(
        text: TextSpan(
          text: chartLabel(series.dpt, ChartKind.step, now.value),
          style: label.copyWith(color: colors.textMuted),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.linear(_MultiChartPainter._labelRatio * textScale),
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, size.width - HzSpace.s8));
      state.paint(canvas, Offset(size.width - HzSpace.s8 - state.width, (size.height - state.height) / 2));
      return;
    }
    final plot = Rect.fromLTRB(0, _pad, size.width - _MultiChartPainter.right, size.height - _pad);
    final a = t0.microsecondsSinceEpoch.toDouble();
    final b = math.max(t1.microsecondsSinceEpoch.toDouble(), a + 1);
    double x(DateTime t) => plot.left + plot.width * (t.microsecondsSinceEpoch - a) / (b - a);

    canvas.drawLine(
      plot.bottomLeft,
      plot.bottomRight,
      Paint()
        ..color = colors.line
        ..strokeWidth = Lines.hairline,
    );
    // Active sections: tinted area, top edge in full color, so the band is
    // recognizable even without color.
    final fill = Paint()..color = series.color.withValues(alpha: 0.35);
    final edge = Paint()
      ..color = series.color
      ..strokeWidth = Lines.selection;
    for (var i = 0; i < pts.length; i++) {
      if (pts[i].value < 0.5) continue;
      final from = x(pts[i].time);
      final to = i + 1 < pts.length ? x(pts[i + 1].time) : plot.right;
      final band = Rect.fromLTRB(from, plot.top, math.max(to, from + Lines.selection), plot.bottom);
      canvas.drawRect(band, fill);
      canvas.drawLine(band.topLeft, band.topRight, edge);
    }

    if (c != null) {
      final cx = x(c);
      canvas.drawLine(
        Offset(cx, plot.top),
        Offset(cx, plot.bottom),
        Paint()
          ..color = colors.lineStrong
          ..strokeWidth = Lines.hairline,
      );
    }
  }

  @override
  bool shouldRepaint(_LanePainter old) =>
      old.series != series ||
      old.cursor != cursor ||
      old.t0 != t0 ||
      old.t1 != t1 ||
      old.axisOnly != axisOnly ||
      old.colors != colors ||
      old.label != label ||
      old.textScale != textScale;
}

/// Time axis below the panels: times at regular intervals so you know where you
/// are even in the middle of a scrolled history; the crosshair highlighted at
/// its position, covered ticks are dropped.
class _TimeAxisPainter extends CustomPainter {
  _TimeAxisPainter({
    required this.t0,
    required this.t1,
    required this.cursor,
    required this.style,
    required this.cursorStyle,
    required this.textScaler,
  });

  /// Mindestabstand zweier Uhrzeiten.
  static const _spacing = 160.0;

  final DateTime t0;
  final DateTime t1;
  final DateTime? cursor;
  final TextStyle style;
  final TextStyle cursorStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final right = size.width - _MultiChartPainter.right;
    final a = t0.microsecondsSinceEpoch;
    final span = math.max(t1.microsecondsSinceEpoch - a, 1);
    double x(DateTime t) => right * (t.microsecondsSinceEpoch - a) / span;
    DateTime at(double x) => DateTime.fromMicrosecondsSinceEpoch(a + (span * x / right).round());
    // Over more than one day (or another day) the crosshair also names the day.
    final days = !DateUtils.isSameDay(t0, t1) || !DateUtils.isSameDay(t1, DateTime.now());
    TextPainter text(DateTime t, TextStyle style) => TextPainter(
      text: TextSpan(
        text: days
            ? '${formatTick(t, const Duration(days: 1))} ${formatTime(t, millis: false)}'
            : formatTime(t, millis: false),
        style: style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    // Left- or right-aligned at the ends, otherwise centered below the
    // position.
    double left(TextPainter tp, double x) => (x - tp.width / 2).clamp(0.0, size.width - tp.width);

    final c = cursor;
    final picked = c == null ? null : text(c, cursorStyle);
    final pickedLeft = picked == null ? 0.0 : left(picked, x(c!));
    // Round times (full minutes, hours, days) instead of equal intervals.
    final (:ticks, :step) = timeTicks(at(0), at(right), math.max(1, (right / _spacing).floor()));
    for (final t in ticks) {
      final tp = TextPainter(
        text: TextSpan(text: formatTick(t, step), style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      final l = left(tp, x(t));
      if (picked != null && l < pickedLeft + picked.width + HzSpace.s8 && pickedLeft < l + tp.width + HzSpace.s8) {
        continue;
      }
      tp.paint(canvas, Offset(l, HzSpace.s4));
    }
    picked?.paint(canvas, Offset(pickedLeft, HzSpace.s4));
  }

  @override
  bool shouldRepaint(_TimeAxisPainter old) =>
      old.t0 != t0 ||
      old.t1 != t1 ||
      old.cursor != cursor ||
      old.style != style ||
      old.cursorStyle != cursorStyle ||
      old.textScaler != textScaler;
}

/// Asks for a chart name (new or rename).
Future<String?> askChartName(BuildContext context, {String initial = ''}) => showAdaptiveDialog<String>(
  context: context,
  builder: (context) => _ChartNameDialog(initial: initial),
);

class _ChartNameDialog extends StatefulWidget {
  const _ChartNameDialog({required this.initial});

  final String initial;

  @override
  State<_ChartNameDialog> createState() => _ChartNameDialogState();
}

class _ChartNameDialogState extends State<_ChartNameDialog> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, _name.text.trim());

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(s.chartName),
    content: Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.only(top: Gap.item),
        child: TextField(style: context.hzTheme.field, controller: _name, autofocus: true, onSubmitted: (_) => _done()),
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
      horizontDialogAction(context, label: s.commonSave, primary: true, onPressed: _done),
    ],
  );
}
