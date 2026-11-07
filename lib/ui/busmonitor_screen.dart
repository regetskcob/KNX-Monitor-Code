import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/telegram_files.dart';
import '../knx/busmon.dart';
import '../knx/demo_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../knx/shared_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/expert_mode.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'busmonitor_panels.dart';
import 'common.dart';
import 'figure_box.dart';
import 'telegram_row.dart';

/// Which frames the list shows.
enum _View { all, unacked, problems }

/// Entries in the header menu.
enum _Menu { hideAcks, load, clear, export }

/// Bus monitor: all frames on the line, including acknowledgements
/// (ACK/NAK/BUSY), repetitions, transmission errors and individual addressing.
///
/// Borrows the tunnel of the live monitor ([monitor]), which disconnects on
/// opening and reconnects on closing. So one free tunnel slot is enough, even
/// if the gateway is fully occupied. On the box's KNX HAT the server provides
/// the bus monitor itself; the view then only listens.
class BusMonitorScreen extends StatefulWidget {
  const BusMonitorScreen({super.key, required this.monitor});

  final KnxTunnel monitor;

  @override
  State<BusMonitorScreen> createState() => _BusMonitorScreenState();
}

class _BusMonitorScreenState extends State<BusMonitorScreen> {
  static const _limit = 5000;

  late final _tunnel = KnxTunnel(widget.monitor.host, port: widget.monitor.port, busMonitor: true);
  StreamSubscription<BusmonFrame>? _sub;
  bool _monitorWasConnected = false;
  bool _connecting = true;
  String? _error;

  final _frames = <BusmonFrame>[];

  /// Box with KNX HAT in bus monitor mode: frames arrive through the monitor
  /// tunnel.
  late final bool _fromServer = switch (widget.monitor) {
    final SharedTunnel shared => shared.serverBusMonitor,
    _ => false,
  };

  /// Since when the bus monitor has been listening; after a while without
  /// frames a hint appears.
  DateTime? _listeningSince;
  bool _paused = false;

  /// Acknowledgements appear in the row of their telegram; separately only on
  /// request.
  bool _hideAcks = true;
  _View _view = _View.all;

  /// Nur Telegramme dieses Absenders (Tippen in „Absender“).
  int? _sender;

  int _total = 0, _data = 0, _acks = 0, _negative = 0, _errors = 0, _repeated = 0, _unacked = 0;

  /// Acknowledgements without a data frame directly before them: the interface
  /// did not pass that frame on (issue #1; the kBerry leaves out about every
  /// second one).
  int _orphanAcks = 0;

  /// Data telegram still waiting for its acknowledgement.
  BusmonFrame? _awaiting;

  /// Connection whose frames this view shows. When it drops or reconnects, a
  /// pending data frame no longer pairs with the next acknowledgement: the
  /// server starts counting afresh too.
  late final ValueNotifier<TunnelState> _connection = _fromServer ? widget.monitor.state : _tunnel.state;

  void _onConnection() => _awaiting = null;

  /// Data frames without a following ACK (for the marker in the list).
  final _withoutAck = Expando<bool>();

  /// Acknowledgement that directly followed a data telegram.
  final _ackOf = Expando<BusmonFrame>();

  Timer? _redraw;

  /// Bus load and counters per sender (for the side column).
  final _load = BusLoad();
  final _senders = <int, SenderStats>{};

  /// Selected frame (details in the side column or the sheet).
  BusmonFrame? _selected;

  /// One-second tick for the bus load history even without traffic.
  Timer? _tick;

  /// Keeps the sheet with bus load and senders in step with the page.
  final _pulse = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _connection.addListener(_onConnection);
    _start();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_paused) setState(() {});
      _pulse.value++;
    });
  }

  Future<void> _start() async {
    if (widget.monitor is DemoTunnel) {
      setState(() => _error = s.demoNoBusmonitor);
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    final monitor = widget.monitor;
    if (_fromServer) {
      _sub ??= monitor.busmon.listen(_onFrame);
      setState(() {
        _connecting = false;
        _listeningSince = DateTime.now();
      });
      return;
    }
    if (monitor is SharedTunnel) {
      // Add-on/box: the server holds the tunnel and releases it for this long.
      await monitor.releaseTunnel(true);
    } else if (monitor.state.value == TunnelState.connected) {
      _monitorWasConnected = true;
      await monitor.disconnect(); // Tunnelplatz freigeben
    }
    _sub ??= _tunnel.busmon.listen(_onFrame);
    try {
      await _tunnel.connect();
    } on KnxException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
          _listeningSince = DateTime.now();
        });
      }
    }
  }

  void _onFrame(BusmonFrame f) {
    // Acknowledgement of the previous data telegram?
    final waiting = _awaiting;
    if (waiting == null && f.isAck) _orphanAcks++;
    if (waiting != null) {
      if (f.kind != BusmonKind.data) _ackOf[waiting] = f;
      final sender = waiting.source == null ? null : _senders[waiting.source!];
      if (!f.isAck) {
        _unacked++;
        _withoutAck[waiting] = true;
        if (f.isNegative) {
          sender?.negative++;
        } else {
          sender?.unacked++;
        }
      }
      _awaiting = null;
    }
    _total++;
    switch (f.kind) {
      case BusmonKind.ack:
        _acks++;
      case BusmonKind.data:
        _data++;
        final sender = _senders.putIfAbsent(f.source!, SenderStats.new);
        sender.frames++;
        if (f.repeated) sender.repeated++;
        // Group telegrams are acknowledged; on TP broadcast/individual
        // addresses too.
        _awaiting = f;
        // Keep feeding the monitor: its tunnel is released for the bus monitor,
        // and its history (overview, objects, daily history) keeps running.
        // From the server it already receives the telegrams itself.
        if (f.telegram case final t? when !f.hasError && !_fromServer) widget.monitor.inject(t);
      case BusmonKind.nak || BusmonKind.busy || BusmonKind.nakBusy:
        _negative++;
      case BusmonKind.unknown:
        break;
    }
    if (f.hasError) _errors++;
    if (f.repeated) _repeated++;
    _load.add(f, now: DateTime.now());
    if (_paused) return;
    _frames.insert(0, f);
    if (_frames.length > _limit) _frames.removeLast();
    // At most ~20 rebuilds per second.
    _redraw ??= Timer(const Duration(milliseconds: 50), () {
      _redraw = null;
      if (mounted) setState(() {});
    });
  }

  void _clear() => setState(() {
    _frames.clear();
    _total = _data = _acks = _negative = _errors = _repeated = _unacked = _orphanAcks = 0;
    _awaiting = null;
    _selected = null;
    _load.clear();
    _senders.clear();
  });

  bool _isProblem(BusmonFrame f) =>
      f.hasError || f.isNegative || f.repeated || (_withoutAck[f] ?? false) || f.kind == BusmonKind.unknown;

  bool _inView(BusmonFrame f) => switch (_view) {
    _View.all => true,
    _View.unacked => _withoutAck[f] ?? false,
    _View.problems => _isProblem(f),
  };

  List<BusmonFrame> get _visible => [
    for (final f in _frames)
      if (!(_hideAcks && f.isAck) && _inView(f) && (_sender == null || f.source == _sender)) f,
  ];

  void _export() {
    final store = CatalogStore.instance;
    final rows = [
      'Zeit;Art;Quelle;Ziel;Name;Wert;Wiederholt;Prüfsumme ok;Status;Ohne ACK;Rohdaten',
      for (final f in _frames.reversed)
        [
          isoWithOffset(f.time),
          f.kind.name,
          f.source == null ? '' : formatIndividual(f.source!),
          f.destination == null
              ? ''
              : (f.groupAddressed ? formatGroup(f.destination!) : formatIndividual(f.destination!)),
          f.telegram == null ? '' : (store.info(f.telegram!.destination)?.name ?? ''),
          f.telegram == null ? '' : store.value(f.telegram!),
          f.repeated ? '1' : '0',
          f.checksumOk ? '1' : '0',
          '0x${f.status.toRadixString(16).padLeft(2, '0')}',
          (_withoutAck[f] ?? false) ? '1' : '0',
          hex(f.raw),
        ].map(csvCell).join(';'),
    ];
    saveBytes(context, csvBytes('${rows.join('\n')}\n'), fileName(s.busmonTitle, 'csv'), mimeType: 'text/csv');
  }

  @override
  void dispose() {
    _redraw?.cancel();
    _tick?.cancel();
    _pulse.dispose();
    _sub?.cancel();
    _connection.removeListener(_onConnection);
    if (_fromServer) {
      super.dispose();
      return;
    }
    _tunnel.disconnect().whenComplete(() async {
      _tunnel.dispose();
      final monitor = widget.monitor;
      if (monitor is SharedTunnel) return monitor.releaseTunnel(false);
      // Live-Monitor wieder verbinden.
      if (_monitorWasConnected && widget.monitor.state.value == TunnelState.disconnected) {
        try {
          await widget.monitor.connect();
        } on KnxException catch (e) {
          widget.monitor.error.value = e.message; // triggers the automatic reconnect
        }
      }
    });
    super.dispose();
  }

  /// Width of the side column when it only shows the frame details.
  static const _detailWidth = 360.0;

  /// Width of the permanent side column, like the detail column in the monitor.
  static const _sideWidth = 440.0;

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.busmonTitle),
        actions: [
          IconButton(
            tooltip: _paused ? s.monitorResume : s.monitorPause,
            onPressed: () => setState(() => _paused = !_paused),
            icon: Icon(_paused ? AppIcons.play : AppIcons.pause),
          ),
          _menu(),
          IconButton(
            tooltip: s.busmonTitle,
            onPressed: () => showInfoDialog(context, title: s.busmonTitle, content: Text(s.busmonHint)),
            icon: const Icon(AppIcons.info),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final wide = width >= Breakpoints.expanded;
          // Very wide: bus load, details and senders permanently; otherwise the
          // space belongs to the table and the column only appears with a
          // selected frame.
          final side = width >= Breakpoints.large;
          final panel = side || (wide && _selected != null);
          final panelWidth = side ? _sideWidth : _detailWidth;
          final list = _list(context, visible, wide: wide, width: panel ? width - panelWidth : width);
          if (!panel) return list;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: list),
              SizedBox(width: panelWidth, child: side ? _sidePanel(context) : _detailPanel(context)),
            ],
          );
        },
      ),
    );
  }

  /// Less frequent actions are in the menu: acknowledgements, bus load and
  /// senders, clear, CSV.
  Widget _menu() => PopupMenuButton<_Menu>(
    tooltip: s.commonMore,
    icon: Icon(AppIcons.more),
    onSelected: (entry) => switch (entry) {
      _Menu.hideAcks => setState(() => _hideAcks = !_hideAcks),
      _Menu.load => _showLoad(),
      _Menu.clear => _clear(),
      _Menu.export => _export(),
    },
    itemBuilder: (context) => [
      CheckedPopupMenuItem(value: _Menu.hideAcks, checked: _hideAcks, child: Text(s.busmonHideAcks)),
      PopupMenuItem(value: _Menu.load, child: Text('${s.busmonLoad} · ${s.busmonSenders}')),
      PopupMenuItem(value: _Menu.clear, child: Text(s.monitorClear)),
      PopupMenuItem(value: _Menu.export, enabled: _frames.isNotEmpty, child: Text(s.exportCsv)),
    ],
  );

  /// Bus load and senders in the sheet, updated continuously.
  Future<void> _showLoad() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheet) => SafeArea(
      top: false,
      child: ValueListenableBuilder(
        valueListenable: _pulse,
        builder: (context, _, _) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
          children: [
            BusLoadCard(load: _load),
            if (_senders.isNotEmpty) ...[
              const SizedBox(height: Gap.section),
              SendersCard(
                stats: _senders,
                selected: _sender,
                onFilter: (a) {
                  setState(() => _sender = _sender == a ? null : a);
                  Navigator.pop(sheet);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );

  /// Side column in wide layout: bus load, senders, frame details.
  Widget _sidePanel(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(0, Gap.item, Gap.gutter, Gap.bottom),
      children: [
        BusLoadCard(load: _load),
        const SizedBox(height: Gap.section),
        _detailCard(context),
        const SizedBox(height: Gap.section),
        if (_senders.isNotEmpty)
          SendersCard(
            stats: _senders,
            selected: _sender,
            onFilter: (a) => setState(() => _sender = _sender == a ? null : a),
          ),
      ],
    );
  }

  /// Column only for the selected frame, with a close button.
  Widget _detailPanel(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(0, Gap.item, Gap.gutter, Gap.bottom),
    children: [_detailCard(context, closable: true)],
  );

  Widget _detailCard(BuildContext context, {bool closable = false}) {
    final f = _selected;
    return SectionCard(
      title: s.busmonDetails,
      trailing: closable
          ? IconButton(
              tooltip: s.commonClose,
              onPressed: () => setState(() => _selected = null),
              icon: const Icon(AppIcons.close),
            )
          : null,
      child: f == null
          ? Text(s.busmonTapHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted))
          : BusmonFrameDetails(frame: f, ack: _ackOf[f], withoutAck: _withoutAck[f] ?? false),
    );
  }

  void _select(BusmonFrame f, {required bool wide}) {
    if (wide) {
      setState(() => _selected = identical(_selected, f) ? null : f);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
          child: BusmonFrameDetails(frame: f, ack: _ackOf[f], withoutAck: _withoutAck[f] ?? false),
        ),
      ),
    );
  }

  /// Key figures: four on a phone; conspicuous ones are added as soon as there
  /// are any.
  List<BoxFigure> _figures({required bool roomy}) {
    BoxFigure problem(String label, int value, [HorizontStatus status = HorizontStatus.warning]) =>
        (label: label, value: formatInt(value), status: value > 0 ? status : null);
    return [
      (label: s.busmonFrames, value: formatInt(_total), status: null),
      (label: s.busmonTelegrams, value: formatInt(_data), status: null),
      (label: s.busmonAck, value: formatInt(_acks), status: null),
      if (roomy || _unacked > 0) problem(s.busmonUnacked, _unacked),
      if (_negative > 0) problem(s.busmonNegative, _negative),
      if (roomy || _repeated > 0) problem(s.busmonRepeated, _repeated),
      problem(s.busmonErrors, _errors, HorizontStatus.critical),
    ];
  }

  /// From this list width on, the table with columns.
  static const _tableFrom = 620.0;

  /// From this table width on, also the raw data column.
  static const _rawFrom = 900.0;

  /// From this text size on, rows are kept instead of the table.
  static const _maxTableScale = 1.3;

  Widget _list(BuildContext context, List<BusmonFrame> visible, {required bool wide, required double width}) {
    final hz = context.hz;
    final gutter = Gap.gutterFor(MediaQuery.sizeOf(context).width);
    final table = width >= _tableFrom && MediaQuery.textScalerOf(context).scale(1) <= _maxTableScale;
    final raw = width >= _rawFrom;
    Widget row(BuildContext context, int i) => _FrameRow(
      frame: visible[i],
      withoutAck: _withoutAck[visible[i]] ?? false,
      ack: _ackOf[visible[i]],
      selected: identical(visible[i], _selected),
      gutter: table ? HzSpace.s12 : gutter,
      table: table,
      raw: raw,
      onTap: () => _select(visible[i], wide: wide),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, HzSpace.s4, gutter, Gap.inner),
          child: FigureBox(figures: _figures(roomy: width >= Breakpoints.medium)),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.item,
            children: [
              FilterBar<_View>(
                segments: [
                  ButtonSegment(value: _View.all, label: Text(s.commFilterAll)),
                  ButtonSegment(value: _View.unacked, label: Text(s.busmonUnacked)),
                  ButtonSegment(value: _View.problems, label: Text(s.topoIssues), tooltip: s.busmonOnlyProblems),
                ],
                selected: _view,
                onChanged: (v) => setState(() => _view = v),
                maxWidth: Widths.form,
              ),
              if (_sender != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InputChip(
                    label: Text(formatIndividual(_sender!), style: context.mono(Theme.of(context).textTheme.bodySmall)),
                    selected: true,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    deleteButtonTooltipMessage: s.commonDismiss,
                    onDeleted: () => setState(() => _sender = null),
                  ),
                ),
            ],
          ),
        ),
        // Errors are shown in the content, below the controls.
        if (_error case final error?)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
            child: HorizontNotice(
              HorizontStatus.critical,
              action: TextButton(onPressed: _start, child: Text(s.busmonRetry)),
              child: Text(s.busmonFailed(error)),
            ),
          ),
        if (_orphanAcks > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
            child: HorizontNotice(
              HorizontStatus.warning,
              child: Text(_fromServer ? s.busmonOrphanAcksHat(_orphanAcks) : s.busmonOrphanAcks(_orphanAcks)),
            ),
          ),
        Expanded(
          // With an error everything needed is at the top; no waiting or
          // listening below.
          child: _error != null && _frames.isEmpty
              ? const SizedBox.shrink()
              : _connecting && _frames.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(dimension: 24, child: CircularProgressIndicator.adaptive(strokeWidth: 2.5)),
                      const SizedBox(height: Gap.inner),
                      Text(s.busmonConnecting, style: TextStyle(color: hz.textMuted)),
                    ],
                  ),
                )
              : visible.isEmpty
              ? HorizontEmptyHint(
                  icon: AppIcons.live,
                  text: s.busmonEmpty,
                  // After 15 s of silence, explain instead of only showing
                  // "nothing yet".
                  detail:
                      (_listeningSince != null &&
                          _frames.isEmpty &&
                          DateTime.now().difference(_listeningSince!) > const Duration(seconds: 15))
                      ? s.busmonQuietHint
                      : s.busmonListening,
                )
              : table
              // Table on a white surface, like the cards of the page.
              ? Padding(
                  padding: EdgeInsets.fromLTRB(gutter, 0, gutter, HzSpace.s16),
                  child: Material(
                    color: hz.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: Radii.card,
                      side: BorderSide(color: hz.line, width: Lines.hairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TableHead(raw: raw),
                        Expanded(
                          child: ListView.builder(itemCount: visible.length, itemBuilder: row),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: HzSpace.s24),
                  itemCount: visible.length,
                  itemBuilder: row,
                ),
        ),
      ],
    );
  }
}

/// Column widths of the table.
abstract final class _Column {
  static const time = 104.0;
  static const address = 76.0;
  static const status = 104.0;
  static const raw = 200.0;
  static const value = 104.0;
}

/// Header row of the table.
class _TableHead extends StatelessWidget {
  const _TableHead({required this.raw});

  final bool raw;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(color: hz.textFaint, fontWeight: FontWeight.w600);
    Widget cell(String text, double width, {TextAlign? align}) => SizedBox(
      width: width,
      child: Text(text, style: style, textAlign: align, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
        child: Row(
          children: [
            cell(s.columnTime, _Column.time),
            cell(s.busmonFieldSource, _Column.address),
            cell(s.busmonFieldTarget, _Column.address),
            Expanded(child: Text(s.columnName, style: style)),
            cell(s.busmonFieldStatus, _Column.status),
            if (raw) cell(s.busmonFieldRaw, _Column.raw),
            cell(s.columnValue, _Column.value, align: TextAlign.end),
          ],
        ),
      ),
    );
  }
}

/// Zustand einer Quittung (ACK = gut, BUSY = Warnung, NAK/unbekannt = Fehler).
HorizontStatus _ackStatus(BusmonKind kind) => switch (kind) {
  BusmonKind.ack => HorizontStatus.positive,
  BusmonKind.busy => HorizontStatus.warning,
  _ => HorizontStatus.critical,
};

/// Frame row with a hairline below: on a phone "source → destination", below it
/// time and name in muted text, value on the right; wide as a table row.
/// Addresses and raw data in Monaspace. Selection: 2 px accent line on the left
/// on accent-tint.
class _FrameRow extends StatelessWidget {
  const _FrameRow({
    required this.frame,
    required this.withoutAck,
    required this.gutter,
    this.table = false,
    this.raw = false,
    this.ack,
    this.selected = false,
    this.onTap,
  });

  final bool selected;
  final VoidCallback? onTap;

  /// As a table row matching [_TableHead].
  final bool table;

  /// Table with raw data column.
  final bool raw;

  final BusmonFrame frame;
  final bool withoutAck;

  /// Side margin of the list.
  final double gutter;

  /// Following acknowledgement (ACK/NAK/BUSY), if it has already arrived.
  final BusmonFrame? ack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final f = frame;
    final store = CatalogStore.instance;
    final muted = context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted);
    final time = formatTime(f.time);

    // Acknowledgements: compact and indented below their telegram.
    if (f.kind != BusmonKind.data) {
      final status = _ackStatus(f.kind);
      final text = switch (f.kind) {
        BusmonKind.ack => s.busmonAckText,
        BusmonKind.nak => s.busmonNakText,
        BusmonKind.busy => s.busmonBusyText,
        BusmonKind.nakBusy => s.busmonNakBusyText,
        _ => s.busmonUnknownText,
      };
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter + HzSpace.s16, HzSpace.s2, gutter, HzSpace.s2),
        child: Row(
          children: [
            Icon(status.icon, size: 14, color: status.color(hz)),
            const SizedBox(width: HzSpace.s4),
            Text(text, style: theme.textTheme.bodySmall?.copyWith(color: status.color(hz))),
            const Spacer(),
            Text('$time  ${hex(f.raw)}', style: muted),
          ],
        ),
      );
    }

    final t = f.telegram;
    final target = f.destination == null
        ? ''
        : (f.groupAddressed ? formatGroup(f.destination!) : formatIndividual(f.destination!));
    final name = t == null ? s.busmonIndividual : (store.info(t.destination)?.name ?? '');
    final problems = [
      if (f.repeated) s.busmonRepeated,
      if (!f.checksumOk) s.busmonChecksum,
      if (f.hasError && f.checksumOk) s.busmonStatusError,
      if (withoutAck) s.busmonUnacked,
    ];
    return Material(
      color: problems.isEmpty ? Colors.transparent : hz.warningTint,
      child: Ink(
        // The leading line indents the content by its width. Selection and
        // hairline below the row (divider) come from Horizont.
        decoration: horizontSelectionDecoration(
          hz,
          selected: selected,
          divider: BorderSide(color: hz.line, width: Lines.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(gutter - Lines.selection, HzSpace.s8, gutter, HzSpace.s8),
            child: table
                ? _tableCells(context, target: target, name: name, problems: problems)
                : _phoneCells(context, target: target, name: name, problems: problems),
          ),
        ),
      ),
    );
  }

  /// Notice of something conspicuous: symbol and word.
  Widget _problemLine(BuildContext context, List<String> problems) {
    final hz = context.hz;
    return Row(
      children: [
        Icon(HorizontStatus.warning.icon, size: 14, color: hz.warning),
        const SizedBox(width: HzSpace.s4),
        Flexible(
          child: Text(
            problems.join(metaSeparator),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: hz.warning, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  /// Value of the telegram, empty for read requests.
  String _value() {
    final t = frame.telegram;
    return t == null || t.type == TelegramType.read ? '' : CatalogStore.instance.value(t);
  }

  Widget _phoneCells(
    BuildContext context, {
    required String target,
    required String name,
    required List<String> problems,
  }) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final f = frame;
    final t = f.telegram;
    final value = _value();
    // A positive acknowledgement is shown in the details, "Ohne ACK" (no ACK)
    // in the notice row.
    final showAck = ack != null && (!ack!.isAck || expert);
    return Row(
      children: [
        // Kind only in expert mode, like raw data.
        if (expert) ...[
          SizedBox(
            width: HzSpace.s24 + HzSpace.s4,
            child: t == null
                ? Icon(AppIcons.diagnostics, size: HzIconSize.row, color: hz.textMuted)
                : TypeBadge(type: t.type, size: 22),
          ),
          const SizedBox(width: Gap.item),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${f.source == null ? '' : formatIndividual(f.source!)} → $target',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.mono(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                [formatTime(f.time), if (name.isNotEmpty) name].join(metaSeparator),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
              ),
              if (expert)
                Text(
                  hex(f.raw),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                ),
              if (problems.isNotEmpty) _problemLine(context, problems),
            ],
          ),
        ),
        if (value.isNotEmpty) ...[
          const SizedBox(width: Gap.item),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: HzSpace.s96 + HzSpace.s24),
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
        if (showAck) ...[const SizedBox(width: Gap.item), _AckBadge(ack: ack, missing: withoutAck)],
      ],
    );
  }

  Widget _tableCells(
    BuildContext context, {
    required String target,
    required String name,
    required List<String> problems,
  }) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final f = frame;
    final address = context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textMuted);
    Widget cell(String text, double width, TextStyle? style) => SizedBox(
      width: width,
      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
    );
    return Row(
      children: [
        cell(formatTime(f.time), _Column.time, context.figures(theme.textTheme.bodySmall)),
        cell(f.source == null ? '' : formatIndividual(f.source!), _Column.address, address),
        cell(target, _Column.address, address),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              // "Ohne ACK" (no ACK) is already in the status column.
              if (problems.where((p) => p != s.busmonUnacked).toList() case final rest when rest.isNotEmpty)
                _problemLine(context, rest),
            ],
          ),
        ),
        SizedBox(
          width: _Column.status,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _AckBadge(ack: ack, missing: withoutAck),
          ),
        ),
        if (raw) cell(hex(f.raw), _Column.raw, address),
        SizedBox(
          width: _Column.value,
          child: Text(
            _value(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: context.figures(theme.textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Acknowledgement of the telegram as a badge: ACK, NAK, BUSY or "ohne ACK" (no
/// ACK).
class _AckBadge extends StatelessWidget {
  const _AckBadge({required this.ack, required this.missing});

  final BusmonFrame? ack;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final kind = ack?.kind;
    final label = switch (kind) {
      BusmonKind.ack => 'ACK',
      BusmonKind.nak => 'NAK',
      BusmonKind.busy => 'BUSY',
      BusmonKind.nakBusy => 'NAK+BUSY',
      _ when missing => s.busmonUnacked,
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    final status = kind == null || kind == BusmonKind.unknown ? HorizontStatus.warning : _ackStatus(kind);
    return HorizontBadge(status, label: label);
  }
}
