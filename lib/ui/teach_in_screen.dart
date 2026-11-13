import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/object_groups.dart';
import '../model/plain_text.dart';
import '../model/project_check.dart' show isDefaultGroupName;
import '../model/teach_in.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'telegram_row.dart' show formatTime;
import 'tool_shell.dart';

/// Opens the teach-in on the running [tunnel]; [history] is the session
/// recording, from which it already knows the background traffic.
Future<void> openTeachIn(BuildContext context, KnxTunnel tunnel, {List<Telegram> history = const []}) =>
    pushTool<void>(context, (_) => TeachInScreen(tunnel: tunnel, history: history));

/// Teaching in an installation without an ETS project: listen, catch an event,
/// ask what it was, and build a project of its own from that (Free).
class TeachInScreen extends StatefulWidget {
  const TeachInScreen({
    super.key,
    required this.tunnel,
    this.history = const [],
    this.warmUp = const Duration(seconds: 15),
  });

  final KnxTunnel tunnel;

  /// Session recording so far: whatever sends in it is background.
  final List<Telegram> history;

  /// Quiet listening at the start, before anything is caught.
  final Duration warmUp;

  /// Clock for the learning phase and window; tests set their own.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  @override
  State<TeachInScreen> createState() => _TeachInScreenState();
}

class _TeachInScreenState extends State<TeachInScreen> {
  late final _capture = EventCapture(onEvent: _onEvent, isStatus: _isStatus, warmUp: widget.warmUp);

  /// Whether it is feedback according to the project or taught-in data (name like "… Status").
  static bool _isStatus(int address) {
    final name = CatalogStore.instance.info(address)?.name;
    return name != null && ObjectIndex.isFeedbackName(name);
  }

  /// Minimum time an untouched event stays so it can be read; only after that
  /// does a newer one replace it.
  static const hold = Duration(seconds: 10);
  late final StreamSubscription<Telegram> _sub;
  late final Timer _ticker;
  final _room = TextEditingController();
  final _name = TextEditingController();
  final _device = TextEditingController();
  final _store = CatalogStore.instance;

  /// Caught event currently being named.
  BusEvent? _event;

  /// Whether [_event] was picked from the open list instead of caught: a heard
  /// address, without a triggering push button.
  bool _picked = false;

  /// Name the card started with (from the project or learned earlier); only a
  /// different one counts as naming.
  String _prefilled = '';
  final _scroll = ScrollController();
  final _dpts = <int, Dpt>{};
  final _skip = <int>{};

  /// What has sent in this session.
  final _heard = HeardAddresses();

  /// At most this many open addresses are listed; the rest is only counted.
  static const _openShown = 40;

  /// Open: heard but without a name, or with a type in the project that the bus
  /// contradicts (old project, address reassigned since).
  bool _isOpen(HeardAddress h) {
    final info = _store.info(h.address);
    return info == null || isDefaultGroupName(info) || h.contradicts(_store.dptOf(h.address));
  }

  /// Whether the device name follows the room until someone changes it.
  bool _deviceEdited = false;

  bool get _demo => widget.tunnel is DemoTunnel;

  @override
  void initState() {
    super.initState();
    _capture.seed(widget.history);
    // In the demo house nobody presses a push button by themselves during teach-in.
    if (widget.tunnel case final DemoTunnel demo) demo.autoPress = false;
    widget.history.forEach(_heard.observe);
    _sub = widget.tunnel.telegrams.listen((t) {
      _capture.add(t);
      // New address: the open list changes at once. Further values, counts and senders of a
      // known one are drawn with the next tick, not per telegram.
      final fresh = _heard.observe(t);
      if (fresh && mounted) setState(() {});
      _stale = !fresh && !t.outgoing && t.type != TelegramType.read;
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final now = TeachInScreen.clock();
      _capture.tick(now);
      // Learning phase: draw progress and show its end once.
      final learning = _capture.learningAt(now);
      if ((learning || _wasLearning || _stale) && mounted) setState(() {});
      _wasLearning = learning;
      _stale = false;
    });
    _room.addListener(_followRoom);
    // The name refines the guessed type ("Rollladen" → 1.008).
    _name.addListener(() {
      if (_event != null) setState(() {});
    });
  }

  /// Whether a heard address got a new value since the last tick.
  bool _stale = false;

  /// Whether the learning phase was still running at the last tick.
  bool _wasLearning = true;

  @override
  void dispose() {
    if (widget.tunnel case final DemoTunnel demo) demo.autoPress = true;
    _sub.cancel();
    _ticker.cancel();
    _room.dispose();
    _name.dispose();
    _device.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Room at the last call of [_followRoom]; the listener also reports mere
  /// cursor and focus changes.
  String _roomBefore = '';

  void _followRoom() {
    final room = _room.text.trim();
    if (room == _roomBefore) return;
    _roomBefore = room;
    // Room chosen: the event is being named, no new one replaces it any more.
    if (_event != null) _touched = true;
    if (_deviceEdited) return;
    _device.text = room.isEmpty ? '' : s.learnDeviceDefault(room);
  }

  /// Whether someone has already entered or chosen something on the caught event
  /// (room, name, device, type, check mark).
  bool _touched = false;

  /// Whether the caught event is currently being named and stays.
  @visibleForTesting
  bool get editing => _event != null && (_picked || _touched || _name.text.trim() != _prefilled);

  /// Shows [e] for naming and fills in what is already known, so a second rocker
  /// of the same push button or a correction only needs the name.
  void _show(BusEvent e, {required bool picked}) {
    final address = e.commands.first;
    final info = _store.info(address);
    final learned = _store.learned[address];
    final device = picked || e.own ? null : _store.device(e.initiator);
    final related = picked ? relatedGroups(address, _store.learned).firstOrNull : null;
    // Rooms only from learned data; project paths are mostly trades.
    final room = learned?.path ?? _store.learned.devices[device?.address]?.location ?? related?.path;
    _event = e;
    _picked = picked;
    _touched = false;
    _dpts.clear();
    _skip
      ..clear()
      // Only command and probable feedback ticked; the rest is "Auch gesehen" (also seen).
      ..addAll(e.feedback.where((a) => !likelyFeedback(e).contains(a)));
    _prefilled = info != null && !isDefaultGroupName(info) ? info.name : '';
    _name.text = _prefilled;
    if (room != null) {
      _roomBefore = room;
      _room.text = room;
    }
    if (device != null && !device.isTunnel) {
      _deviceEdited = true;
      _device.text = device.name;
    } else {
      _deviceEdited = false;
      _device.text = _roomBefore.isEmpty ? '' : s.learnDeviceDefault(_roomBefore);
    }
  }

  /// Names a heard address from the open list.
  void _pick(HeardAddress heard) {
    final current = _event;
    if (current != null && !_picked) _capture.passed(current);
    setState(() => _show(heard.event, picked: true));
    if (_scroll.hasClients) {
      unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut));
    }
  }

  void _onEvent(BusEvent e) {
    if (!mounted) return;
    // While naming, no new event in between. An untouched one stays for [hold]
    // and then gives way to the newer one (otherwise background traffic would
    // block the button press). Measured by the time of the telegrams.
    final current = _event;
    if (current != null) {
      if (editing || e.start.difference(current.start) < hold) return;
      _capture.passed(current);
    }
    setState(() => _show(e, picked: false));
  }

  /// For the rows of the card: change state and repaint.
  void update(VoidCallback change) => setState(() {
    _touched = true;
    change();
  });

  void _discard() {
    if (_event case final e? when !_picked) _capture.passed(e);
    setState(() => _event = null);
  }

  void _ignore() {
    final e = _event;
    if (e == null) return;
    _capture.ignore.addAll(e.commands);
    _discard();
  }

  /// Type already known for [address] (project, learned or set in the app), unless
  /// the bus contradicts it; it is shown instead of a guess.
  Dpt? _knownDpt(int address) {
    final dpt = _store.dptOf(address);
    return dpt == null || (_heard[address]?.contradicts(dpt) ?? false) ? null : dpt;
  }

  Future<void> _save() async {
    final e = _event;
    final name = _name.text.trim();
    if (e == null || name.isEmpty) return;
    final learned = teachIn(
      e,
      TeachInEntry(
        room: _room.text,
        name: name,
        device: _picked ? null : _device.text,
        dpts: {
          for (final a in [...e.commands, ...e.feedback]) a: ?_knownDpt(a),
          ..._dpts,
        },
        skip: Set.of(_skip),
        statusSuffix: s.learnStatusSuffix,
      ),
    );
    await _store.learn(learned.groups, devices: learned.devices);
    // Old project: it takes precedence over learned data, so what was named here
    // goes in as a correction – the name of what was pressed, and a type the
    // user chose or the bus contradicts. Names of feedback stay the project's.
    final renames = <int, String?>{};
    for (final g in learned.groups) {
      final known = _store.project[g.address];
      if (known == null) continue;
      if (e.commands.contains(g.address) && !isDefaultGroupName(known)) renames[g.address] = g.name;
      final contradicted = _heard[g.address]?.contradicts(_store.dptOf(g.address)) ?? false;
      if (g.dpt != null && g.dpt != _store.dptOf(g.address) && (_dpts.containsKey(g.address) || contradicted)) {
        await _store.setDpt(g.address, g.dpt);
      }
    }
    if (renames.isNotEmpty) await _store.setNames(renames);
    if (!mounted) return;
    setState(() => _event = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.learnSaved(name))));
  }

  /// Forgets one learned address at once and offers to bring it back.
  Future<void> _forget(GroupInfo group) async {
    final messenger = ScaffoldMessenger.of(context);
    final colors = context.hz;
    await _store.forget(group.address);
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        horizontMessageSnackBar(
          colors,
          s.learnForgotten(group.name),
          action: SnackBarAction(label: s.commonUndo, onPressed: () => unawaited(_store.learn([group]))),
        ),
      );
  }

  Future<void> _clearAll() async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.learnClearAll),
        content: Text(s.learnClearConfirm),
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
    if (ok ?? false) await _store.clearLearned();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.learnTitle),
        actions: [InfoAction(title: s.learnTitle, text: s.learnExplain)],
      ),
      body: ListenableBuilder(
        listenable: _store,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= Breakpoints.expanded;
            final open = _heard.where(_isOpen);
            final card = switch (_event) {
              final e? => _EventCard(state: this, event: e),
              null => _listening(context),
            };
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
                child: ListView(
                  controller: _scroll,
                  padding: Gap.page,
                  children: [
                    FigureBox(
                      figures: [
                        (label: s.learnNamed, value: formatInt(_store.learned.groups.length), status: null),
                        (label: s.learnOpenCount, value: formatInt(open.length), status: null),
                      ],
                    ),
                    if (_heard.length > 0) ...[
                      const SizedBox(height: Gap.item),
                      LinearProgressIndicator(
                        value: (_heard.length - open.length) / _heard.length,
                        minHeight: HzSpace.s4,
                        borderRadius: Radii.row,
                      ),
                      const SizedBox(height: HzSpace.s4),
                      Text(
                        s.learnProgress(_heard.length - open.length, _heard.length),
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
                      ),
                    ],
                    if (_demo) ...[
                      const SizedBox(height: Gap.item),
                      Text(s.learnDemoNote, style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint)),
                    ],
                    if (wide)
                      // The work on the left (listen, name the caught event), what is already named
                      // beside it; the card starts level with the heading on the right.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Gap.section,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: Gap.section),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [card, _openList(context, open)],
                              ),
                            ),
                          ),
                          Expanded(child: _learnedList(context)),
                        ],
                      )
                    else ...[
                      const SizedBox(height: Gap.item),
                      card,
                      _openList(context, open),
                      _learnedList(context),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _listening(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
              ),
              const SizedBox(width: HzSpace.s12),
              Expanded(child: Text(s.learnPressTitle, style: theme.textTheme.titleMedium)),
            ],
          ),
          const SizedBox(height: Gap.item),
          // Learning phase: first get to know the background traffic, then press.
          if (_capture.learningAt(TeachInScreen.clock())) ...[
            Text(s.learnWarmUp, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
            const SizedBox(height: Gap.item),
            LinearProgressIndicator(
              value: _capture.learnProgress(TeachInScreen.clock()),
              minHeight: HzSpace.s4,
              borderRadius: Radii.row,
            ),
          ] else
            Text(s.learnPressNow, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
          if (_demo) ...[
            const SizedBox(height: HzSpace.s16),
            FilledButton(
              onPressed: () {
                // Fresh event, do not append to running demo traffic; the press
                // also counts during the learning phase.
                _capture.expectPress();
                (widget.tunnel as DemoTunnel).pressButton();
              },
              child: Text(s.learnDemoPress),
            ),
          ],
          const SizedBox(height: Gap.item),
          SwitchRow(
            title: s.learnMeasurements,
            meta: s.learnMeasurementsHint,
            value: _capture.measurements,
            onChanged: (v) => setState(() => _capture.measurements = v),
          ),
        ],
      ),
    );
  }

  Widget _learnedList(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final groups = _store.learned.groups.values.toList()
      ..sort((a, b) => [a.path ?? '', a.name].join().compareTo([b.path ?? '', b.name].join()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(
          s.learnNamed,
          count: groups.length,
          trailing: groups.isEmpty
              ? null
              : IconButton(
                  tooltip: s.learnClearAll,
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearAll,
                  icon: const Icon(AppIcons.clear, size: HzIconSize.row),
                ),
        ),
        if (groups.isEmpty) Text(s.learnNothingYet, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
        // Room by room, as the house is walked through.
        for (final room in {for (final g in groups) g.path}) ...[
          Padding(
            padding: const EdgeInsets.only(top: Gap.item, bottom: HzSpace.s4),
            child: Text(
              '${room ?? s.learnNoRoom}$metaSeparator${groups.where((g) => g.path == room).length}',
              style: theme.textTheme.labelLarge?.copyWith(color: hz.textMuted),
            ),
          ),
          RowCard(
            flat: true,
            children: [
              for (final g in groups.where((g) => g.path == room))
                CardRow(
                  title: g.name,
                  meta: [formatGroup(g.address), ?g.path, ?g.dpt?.toString()].join(metaSeparator),
                  metaAddress: true,
                  trailing: IconButton(
                    tooltip: s.learnForget,
                    onPressed: () => _forget(g),
                    icon: const Icon(AppIcons.delete, size: HzIconSize.row),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// Heard addresses without a name: tap one that the value gives away
  /// ("21,5 °C" – the living room) and name it without pressing anything.
  Widget _openList(BuildContext context, List<HeardAddress> open) {
    if (open.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final hz = context.hz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHead(s.learnOpenCount, count: open.length),
        Text(
          _store.project.isEmpty ? s.learnOpenHint : s.learnOpenHintProject,
          style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
        ),
        const SizedBox(height: Gap.item),
        RowCard(
          flat: true,
          children: [
            for (final h in open.take(_openShown))
              CardRow(
                address: formatGroup(h.address),
                title: plainValue(h.last, _store.info(h.address) == null ? null : _store.dptOf(h.address)),
                meta: [
                  if (_store.project[h.address] case final known? when !isDefaultGroupName(known))
                    s.learnMismatch(known.name),
                  h.senders.map((a) => plainSender(a) ?? formatIndividual(a)).take(2).join(', '),
                  '${formatInt(h.count)}×',
                ].join(metaSeparator),
                onTap: () => _pick(h),
              ),
          ],
        ),
        if (open.length > _openShown)
          Padding(
            padding: const EdgeInsets.only(top: Gap.item),
            child: Text(
              s.learnOpenMore(open.length - _openShown),
              style: theme.textTheme.bodySmall?.copyWith(color: hz.textFaint),
            ),
          ),
      ],
    );
  }
}

/// Caught event: addresses with role and type, then the question.
class _EventCard extends StatelessWidget {
  const _EventCard({required this.state, required this.event});

  final _TeachInScreenState state;
  final BusEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Rooms from the taught-in data; project paths are mostly trades, not rooms.
    final rooms = {...knownRooms(CatalogStore.instance.learned), ..._split(s.learnRoomSuggestions)}.toList();
    final likely = likelyFeedback(event);
    final first = event.commands.firstOrNull;
    final guess = first == null ? null : event.guess(first, name: state._name.text)?.dpt;
    final picked = state._picked;
    // Heard address next to a learned one ("1/0/4 Deckenlicht" → "Deckenlicht Status"); a project
    // has its own scheme, there the neighbours would only be noise.
    final related = [
      if (picked && first != null)
        for (final g in relatedGroups(first, CatalogStore.instance.learned))
          ObjectIndex.isFeedbackName(g.name) ? g.name : '${g.name} ${s.learnStatusSuffix}',
    ];
    return SectionCard(
      title: picked
          ? s.learnPicked(formatGroup(event.commands.first))
          : s.learnCaught(formatTime(event.start, millis: false)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in event.commands) _AddressRow(state: state, event: event, address: a, command: true),
          for (final a in [
            ...event.feedback.where(likely.contains),
            ...event.feedback.where((a) => !likely.contains(a)),
          ])
            _AddressRow(state: state, event: event, address: a, command: false, likely: likely.contains(a)),
          const SizedBox(height: Gap.section),
          Text(picked ? s.learnQuestionHeard : s.learnQuestion, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.item),
          _SuggestedField(controller: state._room, label: s.learnRoom, suggestions: rooms),
          const SizedBox(height: Gap.item),
          _SuggestedField(
            controller: state._name,
            label: s.learnName,
            suggestions: [...related.take(2), ..._split(_namesFor(guess))],
            // No autofocus: on the phone the keyboard covered the event and the question.
            onSubmitted: state._save,
          ),
          if (!event.own && !picked) ...[
            const SizedBox(height: Gap.item),
            TextField(
              controller: state._device,
              decoration: InputDecoration(labelText: s.learnDevice, helperText: formatIndividual(event.initiator)),
              onChanged: (_) => state
                .._deviceEdited = true
                .._touched = true,
            ),
          ],
          const SizedBox(height: Gap.section),
          ListenableBuilder(
            listenable: state._name,
            builder: (context, _) =>
                FilledButton(onPressed: state._name.text.trim().isEmpty ? null : state._save, child: Text(s.learnSave)),
          ),
          const SizedBox(height: HzSpace.s8),
          OutlinedButton(onPressed: state._discard, child: Text(s.learnSkip)),
          if (!picked)
            TextButton(
              onPressed: state._ignore,
              child: Text(s.learnIgnore(event.commands.map(formatGroup).join(', '))),
            ),
        ],
      ),
    );
  }

  static List<String> _split(String list) => [
    for (final p in list.split(','))
      if (p.trim().isNotEmpty) p.trim(),
  ];

  static String _namesFor(Dpt? dpt) => switch ((dpt?.main, dpt?.sub)) {
    (1, 8) => s.learnNamesBlind,
    (1, _) => s.learnNamesSwitch,
    (5, _) => s.learnNamesPercent,
    (9 || 14, _) => s.learnNamesMeasure,
    _ => s.learnNamesOther,
  };
}

/// A caught address: role, sentence, type selection, "gehört dazu" (belongs to it) check mark.
class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.state,
    required this.event,
    required this.address,
    required this.command,
    this.likely = true,
  });

  final _TeachInScreenState state;
  final BusEvent event;
  final int address;
  final bool command;

  /// Whether it is probably the feedback to the command; otherwise only "Auch gesehen" (also seen).
  final bool likely;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final samples = event.of(address);
    final last = samples.lastWhere((t) => t.type != TelegramType.read, orElse: () => samples.last);
    final guess = event.guess(address, name: state._name.text);
    final fixed = state._knownDpt(address);
    final first = fixed ?? guess?.dpt;
    final candidates = [?first, ...dptCandidates(payloadLength(last)).where((d) => d != first)];
    final chosen = state._dpts[address] ?? first;
    final known = CatalogStore.instance.project[address];
    final learned = known == null && CatalogStore.instance.learned[address] != null;
    final included = !state._skip.contains(address);
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: included,
            onChanged: (v) => state.update(() => v == true ? state._skip.remove(address) : state._skip.add(address)),
          ),
          const SizedBox(width: HzSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Wrapping: with large text, address and tags do not fit on one line.
                Wrap(
                  spacing: HzSpace.s4,
                  runSpacing: HzSpace.s4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatGroup(address),
                      style: context.mono(theme.textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: HzSpace.s4),
                    HorizontBadge(
                      command ? HorizontStatus.info : HorizontStatus.neutral,
                      label: state._picked
                          ? s.learnRoleHeard
                          : command
                          ? s.learnRoleCommand
                          : likely
                          ? s.learnRoleFeedback
                          : s.learnRoleAlsoSeen,
                    ),
                    // Already in the project: the project takes precedence over taught-in data.
                    if (known != null) ...[
                      Tooltip(
                        message: s.learnInProject(known.name),
                        child: HorizontBadge(HorizontStatus.neutral, label: s.learnKnown),
                      ),
                    ],
                    if (learned) HorizontBadge(HorizontStatus.neutral, label: s.learnSource),
                  ],
                ),
                const SizedBox(height: HzSpace.s2),
                Text(
                  plainSentence(
                    last,
                    sender: plainSender(last.source),
                    target: CatalogStore.instance.info(address)?.name,
                    dpt: chosen,
                    status: !command || state._picked,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                ),
                if (candidates.isNotEmpty)
                  DropdownButton<Dpt>(
                    icon: const Icon(AppIcons.expand),
                    value: chosen,
                    isDense: true,
                    // Full width: with large text "1.001 · geraten" (guessed) would overflow otherwise.
                    isExpanded: true,
                    style: context.mono(theme.textTheme.bodyMedium),
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final d in candidates)
                        DropdownMenuItem(
                          value: d,
                          child: Text(
                            d == first && fixed == null && state._dpts[address] == null
                                ? '$d · ${s.learnGuessed}'
                                : '$d',
                          ),
                        ),
                    ],
                    onChanged: (d) => state.update(() => d == null ? null : state._dpts[address] = d),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Text field with tappable suggestions below it.
class _SuggestedField extends StatelessWidget {
  const _SuggestedField({required this.controller, required this.label, required this.suggestions, this.onSubmitted});

  final TextEditingController controller;
  final String label;
  final List<String> suggestions;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (_) => onSubmitted?.call(),
        ),
        const SizedBox(height: HzSpace.s8),
        ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s4,
            children: [
              for (final v in suggestions.take(10))
                ChoiceChip(
                  label: Text(v),
                  selected: controller.text.trim() == v,
                  onSelected: (_) => controller.text = v,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
