import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../export/telegram_files.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/tokens.dart';
import '../model/analysis.dart';
import '../model/expert_mode.dart';
import '../model/plan.dart';
import '../model/filter.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/telegram_log.dart';
import '../model/saved_charts.dart';
import 'bus_activity.dart';
import 'chart_cards.dart';
import 'charts_overview.dart';
import 'catalog_actions.dart';
import 'charts_screen.dart';
import 'common.dart';
import 'forum_sheet.dart';
import 'communication_map_screen.dart';
import 'device_sheet.dart';
import 'details_sheet.dart';
import 'exports_screen.dart';
import 'live_list.dart';
import 'object_board.dart';
import 'project_check_screen.dart';
import 'statistics_screen.dart';
import 'send_sheet.dart';
import 'teach_in_screen.dart';
import 'weekly_report_screen.dart';
import 'telegram_row.dart';
import 'tool_shell.dart';
import 'more_menu.dart';
import 'plan_screen.dart';
import 'topology_screen.dart';
import 'value_board.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../model/communication_map.dart';
import '../model/live_plain.dart';
import '../model/installation.dart';

enum LogTab { overview, objects, live }

const _paneWidth = Widths.inspector;

/// From this content width (16″ notebook, 21:9, QHD) the live list runs as its
/// own column next to the overview (split view). The view switcher is then not
/// needed; "Objekte" (objects) opens from the menu. iPad 13″ landscape (~1136)
/// keeps the tabs: two columns would be too narrow.
const _liveSideFrom = 1400.0;

/// Shared view for the live monitor and recordings: overview (cards) and live
/// list, focus on a group address with history, selection and PDF export.
class LogView extends StatefulWidget {
  const LogView({
    super.key,
    required this.data,
    required this.title,
    required this.exportTitle,
    this.tunnel,
    this.actions = const [],
    this.expertActions = const [],
    this.tools = const [],
    this.menuToggles,
    this.menuFooter,
    this.banner,
    this.exportNote,
    this.gateway,
    this.floatingStart,
    this.liveAction,
    this.floatingStartLiveOnly = false,
    this.confirmLeave,
    this.onReadStatus,
    this.initialTab = LogTab.overview,
    this.openAddress,
  });

  final TelegramLog data;

  /// Connection for reading/writing; `null` for recordings.
  final KnxTunnel? tunnel;

  /// Label line above the title (gateway or recording, state). The title below
  /// it is the selected view.
  final Widget title;

  /// Additional actions in the header (e.g. recording).
  final List<Widget> actions;

  /// More icons in the header, only in expert mode.
  final List<Widget> expertActions;

  /// Tools of the host view (e.g. diagnostics), in addition to comparison, statistics and map.
  final List<ToolEntry> tools;

  /// Additional switches in the menu (e.g. notifications), built when it opens.
  final List<MenuToggle> Function()? menuToggles;

  /// Actions at the end of the menu (e.g. clear, disconnect, delete).
  final List<MenuAction> Function()? menuFooter;

  /// Notice above the content (e.g. connection lost).
  final Widget? banner;

  /// View shown when opening.
  final LogTab initialTab;

  /// Group addresses whose details are to be opened from outside (for example
  /// from a watcher's notification).
  final Stream<int>? openAddress;

  /// Control of the live view in the header (pause); on phones [floatingStart]
  /// floats instead.
  final Widget? liveAction;

  /// Floating control at the bottom left (play/pause or playback).
  final Widget? floatingStart;

  /// Whether [floatingStart] shows only in the live list; in the overview and
  /// objects it would cover cards.
  final bool floatingStartLiveOnly;

  /// Asks before leaving with "Back" (monitor: disconnect?); `true` = leave.
  /// `null` = no confirmation (recordings).
  final Future<bool> Function()? confirmLeave;

  /// "Status lesen" (read status) in the empty monitor (live only, not for recordings).
  final VoidCallback? onReadStatus;

  final String exportTitle;
  final String? exportNote;
  final String? gateway;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> with SingleTickerProviderStateMixin {
  final _search = TextEditingController();

  /// While searching (field focused) the floating buttons step back.
  final _searchFocus = FocusNode();
  final _keys = FocusNode(debugLabel: 'Monitor');

  /// Phone with search focused: the title bar slides away, as usual on iOS.
  late final _searchBar = AnimationController(vsync: this);
  late LogTab _tab = widget.initialTab;

  /// Whether the split view is active (see [_liveSideFrom]); set during build.
  bool _split = false;

  /// Telegram shown in the details; its address is "focused".
  Telegram? _focused;

  /// Last focused; stays visible during the fade-out animation.
  Telegram? _lastFocused;

  /// Selection for the PDF export. `null` = not in selection mode.
  Set<Telegram>? _selection;

  /// Whether the display was paused only for the selection and resumes afterwards.
  bool _pausedBySelection = false;

  TelegramLog get _data => widget.data;

  /// Limits rebuilds under high load: overview ~15/s, live list ~30/s.
  /// Animations run independently at the full frame rate.
  late final _throttled = ThrottledListenable(widget.data, () => _tab == LogTab.live ? 33 : 66);
  CatalogStore get _store => CatalogStore.instance;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _searchFocus.addListener(() {
      _searchBar.duration = Motion.of(context);
      _searchFocus.hasFocus ? _searchBar.forward() : _searchBar.reverse();
      setState(() {});
    });
    _loadSaved();
    // Charts belong to the installation: per ETS project, without a project per gateway.
    SavedCharts.instance.useScope(_store.catalog.projectName ?? widget.gateway ?? '');
    _store.addListener(_rebuild);
    ExpertMode.instance.addListener(_rebuild);
    ToolShell.instance.open.addListener(_onSidebar);
    // Tool pages show the menu of the first (outer) monitor; a recording that
    // opens its own view on top of it does not replace it.
    ToolShell.instance.menu ??= _moreMenu;
    _openSub = widget.openAddress?.listen((ga) {
      if (mounted) _openAddress(ga);
    });
  }

  StreamSubscription<int>? _openSub;

  /// Whether the project hint above the overview was dismissed in this session.
  static bool _projectHintDismissed = false;

  @override
  void dispose() {
    _openSub?.cancel();
    _throttled.dispose();
    _store.removeListener(_rebuild);
    ExpertMode.instance.removeListener(_rebuild);
    ToolShell.instance.open.removeListener(_onSidebar);
    if (ToolShell.instance.menu == _moreMenu) ToolShell.instance.menu = null;
    _search.dispose();
    _searchFocus.dispose();
    _keys.dispose();
    _searchBar.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  /// Search query → filter, only reparsed when it changes.
  TelegramFilter get _filter {
    final q = _search.text.trim();
    if (q != _filterQuery) {
      _filterQuery = q;
      _parsedFilter = TelegramFilter.parse(q);
    }
    return _parsedFilter;
  }

  String _filterQuery = '';
  TelegramFilter _parsedFilter = TelegramFilter.empty;

  /// Active quick filters (chips), combined with the search by AND.
  final _quick = <QuickFilter>{};

  /// Whether the filter is temporarily switched off (the input stays).
  bool _filterOff = false;

  /// Context around matches in the live list (seconds before and after).
  Duration _contextWindow = Duration.zero;
  static const _contextChoices = [0, 1, 2, 5, 10, 30];
  Set<Telegram> _contextRows = const {};

  bool _matches(Telegram t) {
    if (_filterOff) return true;
    final f = _filter;
    return f.matches(t, _data) && _quick.every((q) => matchesQuick(q, t, _data));
  }

  /// Addresses matched by all quick filters (for the overview and objects).
  Set<int> _quickAddresses = const {};

  /// The overview and objects show the last value per address, but quick filters
  /// like "Ohne Antwort" (no response) match read requests. There the address counts.
  bool _boardMatches(Telegram t) {
    if (_filterOff) return true;
    return _filter.matches(t, _data) && (_quick.isEmpty || _quickAddresses.contains(t.destination));
  }

  Set<int> _addressesMatchingQuick() {
    Set<int>? hits;
    for (final q in _quick) {
      final set = {
        for (final t in _data.log)
          if (matchesQuick(q, t, _data)) t.destination,
      };
      hits = hits == null ? set : hits.intersection(set);
    }
    return hits ?? const {};
  }

  /// Color mark per OR group when the search has several.
  Color? _markOf(Telegram t) {
    final f = _filter;
    if (_filterOff || f.groupCount < 2) return null;
    final i = f.groupOf(t, _data);
    return i == null ? null : Palette.series(i, dark: Theme.of(context).colorScheme.isDark);
  }

  List<Telegram> _visible() {
    _contextRows = const {};
    _quickAddresses = _tab != LogTab.live && _quick.isNotEmpty ? _addressesMatchingQuick() : const {};
    if (_tab == LogTab.live && _filtered && !_filterOff && _contextWindow > Duration.zero) {
      final r = withContext(_data.visibleLog, _matches, _contextWindow);
      _contextRows = r.context;
      return r.visible;
    }
    return switch (_tab) {
      LogTab.live => _data.visibleLog.where(_matches).toList(),
      LogTab.overview || LogTab.objects =>
        _data.latest.values.where(_boardMatches).toList()..sort((a, b) => a.destination.compareTo(b.destination)),
    };
  }

  // --- Saved filters ---------------------------------------------------------

  static const _savedKey = 'saved_filters';

  /// From 600: menu as a sidebar on the left, collapsible via "…"; shared with
  /// the tool pages ([ToolShell]).
  List<String> _saved = const [];

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _saved = prefs.getStringList(InstallationStore.instance.key(_savedKey)) ?? const [];
    });
    await ToolShell.instance.load();
  }

  void _onSidebar() {
    if (mounted) setState(() {});
  }

  Future<void> _storeSaved(List<String> saved) async {
    setState(() => _saved = saved);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(InstallationStore.instance.key(_savedKey), saved);
  }

  void _showFilterHelp() => showAdaptiveDialog<void>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(s.filterHelp),
      content: Material(
        type: MaterialType.transparency,
        child: SingleChildScrollView(child: SelectableText(s.filterHelpBody, style: const TextStyle(height: 1.5))),
      ),
      actions: [horizontDialogAction(context, label: s.commonClose, onPressed: () => Navigator.pop(context))],
    ),
  );

  // --- Focus, selection, export ----------------------------------------------

  void _focus(Telegram? t) => setState(() {
    _focused = t;
    if (t != null) _lastFocused = t;
  });

  void _startSelection([Telegram? first]) => setState(() {
    _selection = {?first};
    if (!_data.paused) {
      _data.setPaused(true); // keep the list from running away while selecting
      _pausedBySelection = true;
    }
  });

  void _endSelection() => setState(() {
    _selection = null;
    if (_pausedBySelection) _data.setPaused(false);
    _pausedBySelection = false;
  });

  void _toggleSelected(Telegram t) => setState(() {
    if (!_selection!.remove(t)) _selection!.add(t);
  });

  Future<void> _export(List<Telegram> telegrams, Rect? origin) async {
    final simple = !Plan.instance.allows(Feature.export);
    await sharePdf(
      context,
      () async => TelegramPdf(
        telegrams,
        gateway: widget.gateway,
        title: widget.exportTitle,
        note: widget.exportNote,
        simple: simple,
      ),
      pdfName(widget.exportTitle),
      origin: origin,
    );
  }

  Future<void> _saveCsv(List<Telegram> telegrams) async {
    await saveBytes(context, utf8Bytes(buildCsv(telegrams)), fileName(widget.exportTitle, 'csv'), mimeType: 'text/csv');
  }

  Future<void> _saveEts(List<Telegram> telegrams) async {
    if (!await unlock(context, Feature.export) || !mounted) return;
    await saveBytes(
      context,
      utf8Bytes(buildEtsXml(telegrams, host: widget.gateway)),
      fileName(widget.exportTitle, 'xml'),
      mimeType: 'application/xml',
    );
  }

  /// Details of a group address as a sheet, from anywhere (objects, tools).
  void _openAddress(int ga) {
    final history = _data.forAddress(ga);
    final t = _data.latest[ga] ?? (history.isEmpty ? null : history.last);
    if (t == null) return;
    showDetailsSheet(
      context,
      t,
      tunnel: widget.tunnel,
      history: history,
      issues: issuesOf(t, _data),
      gateway: widget.gateway,
      onFilter: _filterAndReturn,
      onOpenChart: _openChart,
      onOpenDevice: _openDevice,
      onOpenMap: _openMap,
      log: _data,
    );
  }

  /// Reads several addresses one after another; the responses appear in the monitor.
  Future<void> _readAll(List<int> addresses) async {
    final tunnel = widget.tunnel;
    if (tunnel == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(s.objectReadSent(addresses.length))));
    for (final ga in addresses) {
      try {
        await tunnel.read(ga);
      } on KnxException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      // Like commissioning: at most about 5 read requests per second.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  /// Device sheet: traffic of a device, map, filter.
  void _openDevice(int address) => showDeviceSheet(context, address: address, log: _data, onFilter: _filterAndReturn);

  /// Communication map starting from a group address (Pro).
  Future<void> _openMap(int ga) async {
    if (await unlock(context, Feature.communicationMap)) {
      _push(
        (_) => CommunicationMapScreen(
          log: _data,
          start: MapNode.group(ga),
          onOpenAddress: _openAddress,
          onOpenDevice: _openDevice,
        ),
      );
    }
  }

  /// Chart for a group address (Plus).
  Future<void> _openChart(int ga) async {
    if (await unlock(context, Feature.charts)) {
      _push((_) => ChartsScreen(log: _data, initial: [ga], onOpenAddress: _openAddress));
    }
  }

  void _onTap(Telegram t, {required bool twoPane}) {
    if (_selection != null) return _toggleSelected(t);
    if (twoPane) {
      _focus(identical(_focused, t) ? null : t);
    } else {
      showDetailsSheet(
        context,
        t,
        tunnel: widget.tunnel,
        history: _data.forAddress(t.destination),
        issues: issuesOf(t, _data),
        gateway: widget.gateway,
        filtered: _search.text.trim() == t.destinationText,
        onFilter: _toggleFilter,
        onOpenChart: _openChart,
        onOpenDevice: _openDevice,
        onOpenMap: _openMap,
        log: _data,
      );
    }
  }

  void _onLongPress(Telegram t) => _selection == null ? _startSelection(t) : _toggleSelected(t);

  /// Right-click on a telegram: the essentials from the details without opening them.
  Future<void> _telegramMenu(Telegram t, Offset at, {required bool twoPane}) async {
    final messenger = ScaffoldMessenger.of(context);
    final filtered = _search.text.trim() == t.destinationText;
    final size = MediaQuery.sizeOf(context);
    final choice = await showMenu<void Function()>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy, size.width - at.dx, size.height - at.dy),
      items: [
        PopupMenuItem(
          value: () => _onTap(t, twoPane: twoPane),
          child: Text(s.telegramMenuDetails),
        ),
        PopupMenuItem(
          value: () => _toggleFilter(t.destinationText),
          child: Text(filtered ? s.detailsFilterOff : s.detailsFilter),
        ),
        PopupMenuItem(
          value: () {
            final name = _store.info(t.destination)?.name;
            final text = [t.destinationText, ?name, _store.value(t)].join(' ');
            Clipboard.setData(ClipboardData(text: text));
            messenger.showSnackBar(SnackBar(content: Text(s.detailsCopied)));
          },
          child: Text(s.detailsCopy),
        ),
        PopupMenuItem(value: () => _onLongPress(t), child: Text(s.telegramMenuSelect)),
      ],
    );
    if (mounted) choice?.call();
  }

  /// Keyboard (Mac, Windows, iPad): search, Esc, space for pause. When someone types,
  /// characters go into the field: space only counts when nothing else has focus.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyF && (keyboard.isMetaPressed || keyboard.isControlPressed)) {
      _searchFocus.requestFocus();
      _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_searchFocus.hasFocus) {
        _cancelSearch();
      } else if (_selection != null) {
        _endSelection();
      } else if (_focused != null) {
        _focus(null);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.space && node.hasPrimaryFocus && _selection == null) {
      _data.setPaused(!_data.paused);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// "Cancel" as on iOS: clears the filter, closes the keyboard, brings back the title bar.
  void _cancelSearch() {
    _search.clear();
    _keys.requestFocus();
  }

  // --- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selection = _selection;
    return PopScope(
      canPop: selection == null && _focused == null && widget.confirmLeave == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (selection != null) return _endSelection();
        if (_focused != null) return _focus(null);
        final navigator = Navigator.of(context);
        if (await widget.confirmLeave!()) navigator.pop();
      },
      child: Focus(
        focusNode: _keys,
        autofocus: true,
        onKeyEvent: _onKey,
        child: ListenableBuilder(
          listenable: Listenable.merge([_throttled, _searchBar]),
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              // Horizont: below 600 a tab bar, from 600 a sidebar, inspector on
              // the right as soon as the content next to it is still expanded-wide.
              // From 600 the menu is a sidebar; on touch devices the views stay at
              // the bottom (as on the phone), with a pointer at the top of the bar.
              // The bar depends on the width alone, as on the tool pages.
              final sidebar = selection == null && constraints.maxWidth >= Breakpoints.expanded;
              final contentWidth = constraints.maxWidth - (sidebar ? Widths.sidebar : 0);
              // The column also stays on the iPad 11″ in landscape (940 next to the sidebar).
              final canSplit = contentWidth - _paneWidth >= 500;
              final showPane = canSplit && _focused != null;
              final visible = _visible();
              // Split view on very wide screens: values on the left, traffic on the right.
              final room = contentWidth - (showPane ? _paneWidth : 0);
              final liveSide = selection == null && room >= _liveSideFrom;
              _split = liveSide;
              // In split view there is only the overview; live runs alongside.
              if (liveSide && _tab != LogTab.overview) _tab = LogTab.overview;
              // Below [wideRowBreakpoint]: compact rows instead of a cramped table.
              final liveWidth = (room * 0.25).clamp(560.0, wideRowBreakpoint - 1);
              // Narrow next to the sidebar (iPad mini portrait): search above the
              // content as on the phone, otherwise it pushes out the title.
              _searchBelow =
                  _phone(context) || contentWidth < (_tabsBelow ? _searchInHeaderTouch : _searchInHeaderFrom);
              return Scaffold(
                // Controls on the left (pause, playback) and write on the right in
                // one slot: this keeps both reliably on one line.
                floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
                floatingActionButton: _fabBar(
                  selection,
                  paneOpen: showPane,
                  start: sidebar ? Widths.sidebar : 0,
                  width: contentWidth - (showPane ? _paneWidth : 0) - 2 * HzSpace.s16,
                ),
                // Phone: views as tabs at the bottom (thumb reach, more room at the top).
                bottomNavigationBar: _tabsBelow && selection == null && !liveSide ? _bottomTabs() : null,
                body: SafeArea(
                  top: false,
                  bottom: false,
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: Motion.of(context),
                        curve: Motion.curve,
                        width: sidebar ? Widths.sidebar : 0,
                        decoration: BoxDecoration(
                          color: context.hz.surface,
                          border: Border(
                            right: BorderSide(color: context.hz.line, width: Lines.hairline),
                          ),
                        ),
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerRight,
                            minWidth: Widths.sidebar,
                            maxWidth: Widths.sidebar,
                            child: !_phone(context)
                                ? SafeArea(bottom: false, child: MoreSidebar(menu: _moreMenu))
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            // The header belongs to the content; the sidebar runs all the way up.
                            _head(
                              selection != null
                                  ? _selectionBar(selection, visible)
                                  : _appBar(
                                      compact: constraints.maxWidth < Breakpoints.expanded,
                                      paneOpen: showPane,
                                      // In split view the search field ends above the filter button,
                                      // flush with the overview and live column; the buttons sit above live.
                                      searchEnd: liveSide
                                          ? liveWidth + (showPane ? _paneWidth : 0) + Gap.gutterFor(room - liveWidth)
                                          : null,
                                    ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  // Hints, search and box belong to the overview; details and live open beside it.
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _contentHead(),
                                        Expanded(child: _content(visible, twoPane: canSplit)),
                                      ],
                                    ),
                                  ),
                                  // The detail column fades in as soon as an address is focused,
                                  // between the overview and live.
                                  AnimatedContainer(
                                    duration: Motion.slowOf(context),
                                    curve: Motion.curve,
                                    width: showPane ? _paneWidth : 0,
                                    child: ClipRect(
                                      child: OverflowBox(
                                        alignment: Alignment.centerLeft,
                                        minWidth: _paneWidth,
                                        maxWidth: _paneWidth,
                                        child: canSplit ? _columnCard(_detailPane()) : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ),
                                  // Live stays at the far right; the details slide in before it.
                                  if (liveSide)
                                    SizedBox(
                                      width: liveWidth,
                                      child: _columnCard(_liveSide(twoPane: canSplit)),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Header inside the content instead of on the Scaffold: needs the height including the status bar.
  Widget _head(PreferredSizeWidget bar) =>
      SizedBox(height: bar.preferredSize.height + MediaQuery.paddingOf(context).top, child: bar);

  /// Column next to the overview (details, live) as a card on the background.
  Widget _columnCard(Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(0, Gap.inner, Gap.gutterWide, Gap.gutter),
    child: Material(
      color: context.hz.surface,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.box,
        side: BorderSide(color: context.hz.line, width: Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    ),
  );

  /// Live list as a side column (split view from [_liveSideFrom]): same filter
  /// as the overview, tapping opens the details.
  Widget _liveSide({required bool twoPane}) {
    final items = _data.visibleLog.where(_matches).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.gutterWide, Gap.inner, Gap.gutterWide, Gap.item),
          child: SectionTitle(s.tabLive, count: items.length),
        ),
        Expanded(
          child: items.isEmpty
              ? HorizontEmptyHint(icon: AppIcons.live, text: s.busmonEmpty)
              : LiveList(
                  items: items,
                  live: !_data.paused && _data.recentRate < TelegramLog.animationRateLimit,
                  isFresh: _data.isFresh,
                  issuesOf: (t) => issuesOf(t, _data),
                  selection: null,
                  focused: twoPane ? _focused : null,
                  onTap: (t) => _onTap(t, twoPane: twoPane),
                  onLongPress: _onLongPress,
                  onContextMenu: (t, at) => _telegramMenu(t, at, twoPane: twoPane),
                  markOf: _markOf,
                ),
        ),
      ],
    );
  }

  /// Above all columns in full width: hints, search, green box, filters.
  /// This keeps the box in place when details or live open beside it.
  Widget _contentHead() {
    final hasProject = !_store.catalog.isEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < wideRowBreakpoint;
        final gutter = Gap.gutterFor(constraints.maxWidth);
        return Column(
          children: [
            ?widget.banner,
            // Phone: search above the content; with enough room it sits in the title bar.
            if (_searchBelow)
              Padding(
                padding: EdgeInsets.fromLTRB(gutter, Gap.item, gutter, Gap.inner),
                child: Row(
                  children: [
                    Expanded(child: _searchField()),
                    // On the phone next to the filter: write, or cancel while searching.
                    AnimatedSize(
                      duration: Motion.of(context),
                      curve: Motion.curve,
                      child: !_searchBelow
                          ? const SizedBox.shrink()
                          : _searchFocus.hasFocus && _phone(context)
                          ? TextButton(onPressed: _cancelSearch, child: Text(s.commonCancel))
                          : widget.tunnel == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsetsDirectional.only(start: Gap.item),
                              child: _writeButton(widget.tunnel!),
                            ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: Gap.inner),
            AnimatedSize(
              duration: Motion.of(context),
              curve: Motion.curve,
              child: !hasProject && !_projectHintDismissed && !expert
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
                      child: CatalogTile(
                        onDismiss: () => setState(() => _projectHintDismissed = true),
                        onTeachIn: _teachIn,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            // Activity and (with enough room) the quick filters in one row; on the
            // phone the filters are reached via the search (e.g. "wiederholt", repeated).
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
              child: BusActivity(
                data: _data,
                compact: compact,
                detailed: expert,
                footer: widget.tunnel == null
                    ? null
                    : HealthStatusLine(tunnel: widget.tunnel, onOpenHealth: widget.onReadStatus),
              ),
            ),
            // What is currently filtered, as chips; otherwise it is only visible
            // in the search field.
            AnimatedSize(
              duration: Motion.of(context),
              curve: Motion.curve,
              child: _filtered
                  ? Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Gap.inner),
                      child: Align(alignment: AlignmentDirectional.centerStart, child: _activeFilters()),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }

  Widget _content(List<Telegram> visible, {required bool twoPane}) {
    // "Objekte" (objects) needs the names from the ETS project.
    final hasProject = !_store.catalog.isEmpty;
    if (!hasProject && _tab == LogTab.objects) _tab = LogTab.overview;
    return Column(
      children: [
        Expanded(
          // Switch views without a cross-fade; the scaffold stays in place.
          child: AnimatedSwitcher(
            duration: Duration.zero,
            child: KeyedSubtree(
              key: ValueKey((_tab, visible.isEmpty)),
              child: switch (_tab) {
                LogTab.live || LogTab.overview when visible.isEmpty => _empty(),
                LogTab.live => LiveList(
                  items: visible,
                  live: !_data.paused && _data.recentRate < TelegramLog.animationRateLimit,
                  isFresh: _data.isFresh,
                  issuesOf: (t) => issuesOf(t, _data),
                  selection: _selection,
                  focused: twoPane ? _focused : null,
                  onTap: (t) => _onTap(t, twoPane: twoPane),
                  onLongPress: _onLongPress,
                  onContextMenu: (t, at) => _telegramMenu(t, at, twoPane: twoPane),
                  isContext: _contextRows.isEmpty ? null : _contextRows.contains,
                  markOf: _markOf,
                ),
                LogTab.objects => ObjectBoard(
                  data: _data,
                  matches: _boardMatches,
                  onFilter: (q) => _search.text = q,
                  onOpenAddress: _openAddress,
                  onRead: widget.tunnel == null ? null : _readAll,
                  empty: _filtered ? _empty() : null,
                ),
                LogTab.overview => ValueBoard(
                  items: visible,
                  counts: _data.counts,
                  history: _data.history,
                  log: _data,
                  selection: _selection,
                  focused: twoPane ? _focused : null,
                  onTap: (t) => _onTap(t, twoPane: twoPane),
                  onLongPress: _onLongPress,
                  leading: [
                    ChartCardsSliver(
                      log: _data,
                      onAdd: () => createChart(context, _data),
                      onOpen: (name) async {
                        if (await unlock(context, Feature.charts)) {
                          _push((_) => ChartsScreen(log: _data, chart: name, onOpenAddress: _openAddress));
                        }
                      },
                    ),
                  ],
                ),
              },
            ),
          ),
        ),
      ],
    );
  }

  bool get _filtered => _search.text.trim().isNotEmpty || _quick.isNotEmpty;

  /// Empty state with a fitting next action: clear the filter or read the status.
  Widget _empty() {
    if (_filtered && _data.log.isNotEmpty) {
      return HorizontEmptyHint(
        icon: AppIcons.filter,
        text: s.filterNoMatch,
        action: (
          label: s.filterClear,
          onPressed: () => setState(() {
            _search.clear();
            _quick.clear();
          }),
        ),
      );
    }
    final read = widget.onReadStatus;
    return HorizontEmptyHint(
      icon: AppIcons.sensors,
      text: _tab == LogTab.live ? s.liveWaiting : s.boardEmpty,
      detail: read == null ? null : s.emptyMonitorHint,
      action: read == null ? null : (label: s.emptyReadStatus, onPressed: read),
    );
  }

  Widget _searchField() => TextField(
    style: context.hzTheme.field,
    controller: _search,
    focusNode: _searchFocus,
    autocorrect: false,
    decoration: InputDecoration(
      isDense: true,
      constraints: const BoxConstraints.tightFor(height: _headControl),
      contentPadding: const EdgeInsets.symmetric(horizontal: HzSpace.s16, vertical: HzSpace.s12),
      hintText: _store.catalog.isEmpty ? s.filterHint : s.filterHintProject,
      suffixIcon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_search.text.isNotEmpty) ...[
            HorizontFieldIconButton(
              tooltip: _filterOff ? s.filterOn : s.filterOff,
              isSelected: _filterOff,
              icon: Icon(_filterOff ? AppIcons.hide : AppIcons.show),
              onPressed: () => setState(() => _filterOff = !_filterOff),
            ),
            HorizontFieldIconButton(tooltip: s.filterClear, icon: const Icon(AppIcons.close), onPressed: _search.clear),
          ],
          if (!_phone(context)) _quickFilters(),
          PopupMenuButton<String>(
            tooltip: s.savedFilters,
            style: context.hzTheme.fieldIconButton,
            icon: const Icon(AppIcons.bookmark),
            onSelected: (query) => switch (query) {
              '\u0000save' => _storeSaved([_search.text.trim(), ..._saved.where((q) => q != _search.text.trim())]),
              '\u0000help' => _showFilterHelp(),
              _ => _search.text = query,
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: '\u0000save',
                enabled: _search.text.trim().isNotEmpty,
                child: ListTile(leading: const Icon(AppIcons.bookmarkAdd), title: Text(s.saveCurrentFilter)),
              ),
              PopupMenuItem(
                value: '\u0000help',
                child: ListTile(leading: const Icon(AppIcons.help), title: Text(s.filterHelp)),
              ),
              const PopupMenuDivider(),
              if (_saved.isEmpty)
                PopupMenuItem(enabled: false, child: Text(s.noSavedFilters))
              else
                for (final q in _saved)
                  PopupMenuItem(
                    value: q,
                    child: ListTile(
                      title: Text(q, style: context.hzTheme.data),
                      trailing: IconButton(
                        tooltip: s.deleteFilter,
                        icon: const Icon(AppIcons.delete, size: 18),
                        onPressed: () {
                          Navigator.pop(context);
                          _storeSaved(_saved.where((x) => x != q).toList());
                        },
                      ),
                    ),
                  ),
            ],
          ),
        ],
      ),
    ),
  );

  /// Chips for alarms, repetitions, unanswered reads, project deviations.
  bool _phone(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

  /// Content width from which the search fits into the title bar without
  /// cutting off the title (search field, title, record button).
  static const _searchInHeaderFrom = 900.0;

  /// Without a switcher in the header (tabs at the bottom) the field fits earlier.
  static const _searchInHeaderTouch = 640.0;

  /// Whether the search sits above the content instead of in the title bar; set per layout.
  bool _searchBelow = false;

  List<LogTab> get _tabs => [LogTab.overview, if (!_store.catalog.isEmpty) LogTab.objects, LogTab.live];

  static String _tabLabel(LogTab t) => switch (t) {
    LogTab.overview => s.tabOverview,
    LogTab.objects => s.tabObjects,
    LogTab.live => s.tabLive,
  };

  void _selectTab(int i) {
    if (defaultTargetPlatform == TargetPlatform.iOS) HapticFeedback.selectionClick();
    setState(() => _tab = _tabs[i]);
  }

  /// Phone: views as a tab bar at the bottom, selection as a line above the target.
  Widget _bottomTabs() {
    final hz = context.hz;
    final theme = Theme.of(context);
    return Material(
      color: hz.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: hz.line, width: Lines.hairline),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(HzSpace.s8, HzSpace.s4, HzSpace.s8, HzSpace.s4),
            child: Row(
              spacing: HzSpace.s4,
              children: [
                for (final (i, tab) in _tabs.indexed)
                  Expanded(
                    child: Semantics(
                      selected: tab == _tab,
                      button: true,
                      child: Material(
                        color: tab == _tab ? hz.accentTint : Colors.transparent,
                        borderRadius: Radii.tile,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => _selectTab(i),
                          child: SizedBox(
                            height: 44,
                            child: Center(
                              child: Text(
                                _tabLabel(tab),
                                maxLines: 1,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: tab == _tab ? hz.accentText : hz.textMuted,
                                  fontWeight: tab == _tab ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Toolbar, selection as a tint.
  bool get _pointer => context.hzTheme.density == HorizontDensity.pointer;

  /// Views as tabs at the bottom: on touch devices and in every narrow window
  /// (Mac dragged to 400 pt), where the switcher no longer fits at the top.
  bool get _tabsBelow => MediaQuery.sizeOf(context).width < Breakpoints.expanded;

  /// Height of the filter, switcher and "Schreiben" (write) in the header.
  static const _headControl = 44.0;

  /// Views as one control at field height, selection as a tinted surface.
  Widget _viewSwitch() {
    final hz = context.hz;
    return Container(
      key: const ValueKey('viewSwitch'),
      height: _headControl,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: hz.surface,
        borderRadius: Radii.tile,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 2,
        children: [
          for (final t in _tabs)
            Semantics(
              button: true,
              selected: t == _tab,
              child: Material(
                color: t == _tab ? hz.accentTint : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => setState(() => _tab = t),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _tabLabel(t),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: t == _tab ? hz.accentText : hz.textMuted,
                          fontWeight: t == _tab ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Quick filters as one "Filter" button with a drop-down menu (alarms,
  /// repeated, no response, not in project; in live mode also the context around
  /// matches). The button counts active filters and is tinted in the selection.
  Widget _quickFilters() {
    final hz = context.hz;
    final counts = {
      QuickFilter.alarm: _data.activeAlarmCount,
      QuickFilter.repeated: _data.repeatedCount,
      QuickFilter.unanswered: _data.unansweredCount,
      if (!_store.catalog.isEmpty) QuickFilter.unknown: _data.latest.keys.where((a) => _store.info(a) == null).length,
    };
    // Lean: only filters that have something to match (active ones stay).
    bool shown(QuickFilter f) => counts.containsKey(f) && (expert || counts[f]! > 0 || _quick.contains(f));
    final withContext = _tab == LogTab.live && _filtered && !_filterOff;
    final filters = [
      (QuickFilter.alarm, s.quickAlarm, AppIcons.alarm, null as String?),
      (QuickFilter.repeated, s.quickRepeated, AppIcons.restart, _repeatedTooltip),
      (QuickFilter.unanswered, s.quickUnanswered, AppIcons.read, s.healthUnansweredTooltip),
      (QuickFilter.unknown, s.quickUnknown, AppIcons.noProject, null),
    ].where((f) => shown(f.$1)).toList();
    final query = _search.text.trim();
    if (filters.isEmpty && !withContext && query.isEmpty) return const SizedBox.shrink();
    final active =
        _quick.length +
        (withContext && _contextWindow > Duration.zero ? 1 : 0) +
        (query.isNotEmpty && !_filterOff ? 1 : 0);
    return PopupMenuButton<Object>(
      tooltip: s.quickFilterButton,
      position: PopupMenuPosition.under,
      onSelected: (v) => setState(() {
        switch (v) {
          case QuickFilter f:
            _quick.contains(f) ? _quick.remove(f) : _quick.add(f);
          case int seconds:
            _contextWindow = Duration(seconds: seconds);
          case String _:
            _filterOff = !_filterOff;
        }
      }),
      itemBuilder: (context) => [
        // Search from the field above (also "Im Monitor filtern", filter in monitor):
        // visible here and switchable like with the eye icon in the field.
        if (query.isNotEmpty) ...[
          CheckedPopupMenuItem<Object>(
            value: query,
            checked: !_filterOff,
            child: Row(
              children: [
                Icon(AppIcons.search, size: 18, color: hz.textMuted),
                const SizedBox(width: HzSpace.s8),
                Flexible(
                  child: Text(query, style: context.hzTheme.data, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          if (filters.isNotEmpty) const PopupMenuDivider(),
        ],
        for (final (f, label, icon, tooltip) in filters)
          CheckedPopupMenuItem<Object>(
            value: f,
            checked: _quick.contains(f),
            child: Tooltip(
              message: tooltip ?? label,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: f == QuickFilter.alarm ? hz.critical : hz.textMuted),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(child: Text(label)),
                  if (counts[f]! > 0) Text('${counts[f]}', style: context.hzTheme.data.copyWith(color: hz.textMuted)),
                ],
              ),
            ),
          ),
        if (withContext) ...[
          const PopupMenuDivider(),
          for (final v in _contextChoices)
            CheckedPopupMenuItem<Object>(
              value: v,
              checked: _contextWindow.inSeconds == v,
              child: Text(v == 0 ? s.filterContextOff : s.filterContextSeconds(v)),
            ),
        ],
      ],
      // In the filter field; the icon counts active filters.
      child: SizedBox.square(
        dimension: _headControl,
        child: Center(
          child: active > 0
              ? Text(
                  '$active',
                  style: context
                      .figures(Theme.of(context).textTheme.labelLarge)
                      .copyWith(color: hz.accentText, fontWeight: FontWeight.w700),
                )
              : Icon(AppIcons.filter, size: HzIconSize.row, color: hz.textMuted),
        ),
      ),
    );
  }

  /// Active filters: the search (tapping switches it off and on again, the
  /// cross clears it) and the quick filters.
  Widget _activeFilters() {
    final query = _search.text.trim();
    final labels = {
      QuickFilter.alarm: s.quickAlarm,
      QuickFilter.repeated: s.quickRepeated,
      QuickFilter.unanswered: s.quickUnanswered,
      QuickFilter.unknown: s.quickUnknown,
    };
    return Wrap(
      spacing: HzSpace.s8,
      runSpacing: HzSpace.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(s.filterActive, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: context.hz.textMuted)),
        if (query.isNotEmpty)
          InputChip(
            avatar: const Icon(AppIcons.search, size: 16),
            label: Text(query, style: context.hzTheme.data),
            tooltip: _filterOff ? s.filterOn : s.filterOff,
            selected: !_filterOff,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filterOff = !_filterOff),
            deleteButtonTooltipMessage: s.filterClear,
            onDeleted: _search.clear,
          ),
        for (final f in _quick)
          InputChip(
            label: Text(labels[f]!),
            selected: true,
            showCheckmark: false,
            onSelected: (_) => setState(() => _quick.remove(f)),
            deleteButtonTooltipMessage: s.filterClear,
            onDeleted: () => setState(() => _quick.remove(f)),
          ),
      ],
    );
  }

  /// Explanation plus share of all telegrams (hint at missing acknowledgements).
  String get _repeatedTooltip {
    final total = _data.total;
    if (_data.repeatedCount == 0 || total == 0) return s.healthRepeatedTooltip;
    final rate = _data.repeatedCount * 100 / total;
    return '${s.healthRepeatedTooltip} · ${localizeDecimal(rate.toStringAsFixed(rate < 10 ? 1 : 0))} %';
  }

  Widget _detailPane() {
    final t = _focused ?? _lastFocused;
    if (t == null) return const SizedBox.shrink();
    // Show the newest telegram of the address when the focused one comes from
    // the overview (where the current state counts).
    return AnimatedSwitcher(
      duration: Motion.of(context),
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curveOut,
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      transitionBuilder: (child, a) => FadeTransition(opacity: a, child: child),
      child: TelegramDetails(
        key: ValueKey(t.destination),
        telegram: _tab == LogTab.overview ? (_data.latest[t.destination] ?? t) : t,
        tunnel: widget.tunnel,
        history: _data.forAddress(t.destination),
        issues: issuesOf(t, _data),
        gateway: widget.gateway,
        onClose: () => _focus(null),
        filtered: _search.text.trim() == t.destinationText,
        onFilter: _toggleFilter,
        onOpenChart: _openChart,
        onOpenDevice: _openDevice,
        onOpenMap: _openMap,
        around: _data.log,
      ),
    );
  }

  /// Filter from the details: tapping again removes it.
  /// Filter from a tool: in "Objekte" (objects) senders and times do not match,
  /// otherwise it would say "Nichts passt" (nothing matches) although there are hits.
  void _showFiltered(String q) {
    _search.text = q;
    if (_tab == LogTab.objects) setState(() => _tab = LogTab.overview);
  }

  void _toggleFilter(String q) => _search.text = _search.text.trim() == q ? '' : q;

  void _push(Widget Function(BuildContext) builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  /// Tool with the toolbar next to it (see [ToolShell]).
  void _pushTool(Widget Function(BuildContext) builder) => pushTool<void>(context, builder);

  /// Sets filters and jumps from tools back into the monitor.
  void _filterAndReturn(String query) {
    final route = ModalRoute.of(context);
    _search.text = query;
    Navigator.of(context).popUntil((r) => r == route || r.isFirst);
  }

  /// Comparison, statistics, map, plus the tools of the host view.
  List<ToolEntry> get _tools => [
    ...widget.tools,
    // In split view without a switcher: the (more specific) object view as its own page.
    if (_split && !_store.catalog.isEmpty)
      ToolEntry(
        icon: AppIcons.objects,
        title: s.tabObjects,
        subtitle: s.toolObjects,
        group: ToolGroup.bus,
        order: 3,
        open: (_) => _pushTool(
          (_) => Scaffold(
            appBar: AppBar(title: Text(s.tabObjects)),
            body: ListenableBuilder(
              listenable: _data,
              builder: (context, _) => ObjectBoard(
                data: _data,
                matches: _boardMatches,
                onFilter: _filterAndReturn,
                onOpenAddress: _openAddress,
                onRead: widget.tunnel == null ? null : _readAll,
              ),
            ),
          ),
        ),
      ),
    ToolEntry(
      icon: AppIcons.projectCheck,
      expertOnly: true,
      title: s.checkTitle,
      feature: Feature.projectCheck,
      subtitle: s.toolCheck,
      group: ToolGroup.check,
      order: 2,
      open: (_) => _pushTool((_) => ProjectCheckScreen(log: _data, onFilter: _showFiltered)),
    ),
    ToolEntry(
      icon: AppIcons.chart,
      expertOnly: true,
      title: s.chartsTitle,
      feature: Feature.charts,
      subtitle: s.toolCharts,
      group: ToolGroup.analyze,
      order: 1,
      open: (_) => _pushTool((_) => ChartsOverview(log: _data)),
    ),
    ToolEntry(
      icon: AppIcons.statistics,
      title: s.statsTitle,
      feature: Feature.statistics,
      subtitle: s.toolStats,
      group: ToolGroup.analyze,
      open: (_) => _pushTool((_) => StatisticsScreen(log: _data, gateway: widget.gateway, onFilter: _showFiltered)),
    ),
    ToolEntry(
      icon: AppIcons.topology,
      expertOnly: true,
      title: s.topoTitle,
      feature: Feature.topology,
      subtitle: s.topoTool,
      group: ToolGroup.bus,
      order: 1,
      open: (_) => _pushTool((_) => TopologyScreen(log: _data, tunnel: widget.tunnel, onFilter: _filterAndReturn)),
    ),
    ToolEntry(
      icon: AppIcons.communicationMap,
      expertOnly: true,
      title: s.mapTitle,
      feature: Feature.communicationMap,
      subtitle: s.toolMap,
      group: ToolGroup.bus,
      order: 2,
      open: (_) => _pushTool(
        (_) =>
            // As a tool, always start with the overview.
            CommunicationMapScreen(log: _data, onOpenAddress: _openAddress, onOpenDevice: _openDevice),
      ),
    ),
  ];

  final _menuKey = GlobalKey();

  /// Exports as their own page: telegrams, reports, full export, recent files.
  /// Teach-in without a project, only with a connection.
  VoidCallback? get _teachIn => switch (widget.tunnel) {
    final tunnel? => () => openTeachIn(context, tunnel, history: widget.data.log),
    null => null,
  };

  void _openExports() => _pushTool(
    (page) => ExportsScreen(
      log: _data,
      title: widget.exportTitle,
      note: widget.exportNote,
      gateway: widget.gateway,
      installationReports: widget.tunnel != null,
      tunnel: widget.tunnel,
      // Selecting happens in the monitor: close the page, turn on selection mode.
      onSelect: () {
        Navigator.of(page).pop();
        _startSelection();
      },
    ),
  );

  /// Content of "Mehr" (more): tools, data, settings, closing items.
  MoreMenu _moreMenu() => MoreMenu(
    home: MenuAction(
      icon: AppIcons.overview,
      title: s.tabOverview,
      selected: _tab == LogTab.overview,
      onTap: () {
        if (mounted) setState(() => _tab = LogTab.overview);
      },
    ),
    tools: _tools,
    data: [
      MenuAction(
        icon: _store.catalog.isEmpty ? AppIcons.noProject : AppIcons.project,
        title: s.projectMenu,
        onTap: () => showProjectSheet(context, onTeachIn: _teachIn),
      ),
      MenuAction(icon: AppIcons.share, title: s.exportsTitle, onTap: _openExports),
      // Only where there is something to buy (stores); otherwise everything is free anyway.
      if (Plan.instance.beta)
        MenuAction(icon: AppIcons.plan, title: s.planBetaTitle, onTap: () => showBetaInfo(context)),
      if (Plan.instance.purchasable)
        MenuAction(icon: AppIcons.plan, title: s.planTitle, onTap: () => showPlanScreen(context)),
    ],
    toggles: [
      ...?widget.menuToggles?.call(),
      MenuToggle(
        icon: AppIcons.live,
        title: s.livePlainTitle,
        value: LivePlainSetting.instance.value,
        onChanged: (on) {
          LivePlainSetting.instance.set(on);
          setState(() {});
        },
      ),
    ],
    pinned: MenuToggle(
      icon: AppIcons.expert,
      title: s.expertMode,
      value: ExpertMode.instance.value,
      onChanged: ExpertMode.instance.set,
    ),
    footer: widget.menuFooter?.call() ?? const [],
  );

  PreferredSizeWidget _appBar({required bool compact, required bool paneOpen, double? searchEnd}) {
    final bar = _toolbar(compact: compact, paneOpen: paneOpen, searchInActions: compact || searchEnd == null);
    if (_phone(context) && _searchBar.value > 0) {
      final shown = 1 - Motion.curve.transform(_searchBar.value);
      final top = MediaQuery.paddingOf(context).top;
      return PreferredSize(
        preferredSize: Size.fromHeight(bar.preferredSize.height * shown),
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.bottomCenter,
            maxHeight: bar.preferredSize.height + top,
            child: Opacity(opacity: shown, child: bar),
          ),
        ),
      );
    }
    if (compact || searchEnd == null) return bar;
    return PreferredSize(
      preferredSize: bar.preferredSize,
      child: Stack(
        children: [
          Positioned.fill(child: bar),
          Positioned(
            right: searchEnd,
            top: MediaQuery.paddingOf(context).top,
            bottom: 0,
            width: Widths.search,
            child: Center(child: _searchField()),
          ),
        ],
      ),
    );
  }

  AppBar _toolbar({required bool compact, required bool paneOpen, required bool searchInActions}) {
    final tunnel = widget.tunnel;
    // Label (gateway, state) above the small title instead of a large title.
    // From 600 a back button on the left if needed, next to it the sidebar
    // button; there is no "…" then.
    return AppBar(
      // A two-line title (label + view) needs room to the line below.
      toolbarHeight: _pointer ? 72 : 68,
      // Title flush with the content below.
      titleSpacing: compact ? null : Gap.gutterWide,
      actionsPadding: compact ? null : const EdgeInsetsDirectional.only(end: Gap.gutterWide),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [widget.title, Text(_tabLabel(_tab), maxLines: 1)],
      ),
      actions: [
        // From 600: search right-aligned in the title bar instead of its own row.
        if (searchInActions && !_searchBelow) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: Widths.search),
            child: SizedBox(width: Widths.search, child: _searchField()),
          ),
          const SizedBox(width: HzSpace.s8),
        ],
        if (!_tabsBelow && !_split) ...[_viewSwitch(), const SizedBox(width: HzSpace.s8)],
        if (widget.liveAction case final action? when _tab == LogTab.live && !_phone(context)) action,
        ...widget.actions,
        // Write in the header; on the phone next to the filter.
        if (!_searchBelow && tunnel != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HzSpace.s4),
            child: _writeButton(tunnel),
          ),
        // Experts: most frequent tools directly; selection via the export dialog or long press.
        if (expert && !compact) ...widget.expertActions,
        // Phone: menu as its own page; from 600 it sits in the sidebar.
        if (compact)
          IconButton(
            key: _menuKey,
            tooltip: s.menuTitle,
            icon: Icon(AppIcons.more),
            onPressed: () => showMoreMenu(context, _moreMenu, anchor: _menuKey.currentContext!),
          ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(Set<Telegram> selection, List<Telegram> visible) {
    final all = visible.isNotEmpty && visible.every(selection.contains);
    return AppBar(
      leading: IconButton(tooltip: s.selectEnd, icon: const Icon(AppIcons.close), onPressed: _endSelection),
      title: BarTitle(selection.isEmpty ? s.selectTitle : s.selectCount(selection.length)),
      actions: [
        IconButton(
          tooltip: s.exportCsv,
          onPressed: selection.isEmpty ? null : () => _saveCsv(selection.toList()),
          icon: const Icon(AppIcons.table),
        ),
        IconButton(
          tooltip: s.exportEts,
          onPressed: selection.isEmpty ? null : () => _saveEts(selection.toList()),
          icon: const Icon(AppIcons.fileCode),
        ),
        // For a question in the forum: text to paste, identifiers removed.
        IconButton(
          tooltip: s.forumTitle,
          onPressed: selection.isEmpty
              ? null
              // Recording without a tunnel: the recorded gateway (the package removes identifiers).
              : () => showForumSheet(context, selection.toList(), connection: widget.tunnel?.kind ?? widget.gateway),
          icon: const Icon(AppIcons.report),
        ),
        TextButton(
          onPressed: visible.isEmpty
              ? null
              : () => setState(() => all ? selection.removeAll(visible) : selection.addAll(visible)),
          child: Text(all ? s.selectNone : s.selectAll),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  /// "Schreiben" (write) button, disabled without a connection.
  Widget _writeButton(KnxTunnel tunnel) => ValueListenableBuilder(
    valueListenable: tunnel.state,
    builder: (context, state, _) => FilledButton(
      onPressed: state == TunnelState.connected ? () => showSendSheet(context, tunnel) : null,
      style: FilledButton.styleFrom(minimumSize: const Size(0, _headControl)),
      child: Text(s.writeButton),
    ),
  );

  Widget? _fabBar(Set<Telegram>? selection, {required bool paneOpen, required double start, required double width}) {
    if (_searchFocus.hasFocus) return null;
    final lead =
        selection == null &&
            (!widget.floatingStartLiveOnly || _tab == LogTab.live) &&
            (widget.liveAction == null || _phone(context))
        ? widget.floatingStart
        : null;
    final end = _fab(selection);
    if (lead == null && end == null) return null;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: start),
      child: SizedBox(
        width: math.max(0, width),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              // IntrinsicHeight: the slot passes down the full screen height, and
              // some contents (the recordings player with slider and chip) would
              // otherwise take all of it.
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                heightFactor: 1,
                child: IntrinsicHeight(child: lead ?? const SizedBox.shrink()),
              ),
            ),
            ?end,
          ],
        ),
      ),
    );
  }

  Widget? _fab(Set<Telegram>? selection) {
    if (selection != null) {
      if (selection.isEmpty) return null;
      return Builder(
        builder: (fabContext) => FloatingActionButton.extended(
          onPressed: () => _export(selection.toList(), rectOf(fabContext)),
          icon: const Icon(AppIcons.pdf),
          label: Text(s.selectExport(selection.length)),
        ),
      );
    }
    return null;
  }
}

/// Forwards changes of [source] throttled: at most every [intervalMs]
/// milliseconds; the last change is never lost.
class ThrottledListenable extends ChangeNotifier {
  ThrottledListenable(this.source, this.intervalMs) {
    source.addListener(_onChange);
  }

  final Listenable source;
  final int Function() intervalMs;
  Timer? _timer;
  DateTime _last = DateTime(0);

  void _onChange() {
    if (_timer != null) return;
    final wait = Duration(milliseconds: intervalMs()) - DateTime.now().difference(_last);
    if (wait <= Duration.zero) {
      _fire();
    } else {
      _timer = Timer(wait, _fire);
    }
  }

  void _fire() {
    _timer = null;
    _last = DateTime.now();
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    source.removeListener(_onChange);
    super.dispose();
  }
}
