import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/fault_hunt.dart';
import '../model/watch_rules.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'recordings_screen.dart' show openRecording;
import 'telegram_row.dart' show formatDate, formatTime;
import 'watch_screen.dart';

/// Fault hunt (Pro): catch sporadic faults over days with the KNX box (or in
/// the add-on). Rules come from the watchers; for each hit the server keeps two
/// minutes before and one after.
class FaultHuntScreen extends StatefulWidget {
  const FaultHuntScreen({super.key, this.client = const FaultHuntClient()});

  final FaultHuntClient client;

  @override
  State<FaultHuntScreen> createState() => _FaultHuntScreenState();
}

class _FaultHuntScreenState extends State<FaultHuntScreen> {
  static const _durations = [1, 3, 7, 14];

  FaultHuntDef? _hunt;
  List<HuntWindow> _windows = const [];
  bool _loading = true;
  String? _error;

  // Neue Jagd
  final _name = TextEditingController();
  final _chosen = <String>{};
  int _days = 7;
  bool _night = false;
  TimeOfDay _from = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _to = const TimeOfDay(hour: 6, minute: 0);

  @override
  void initState() {
    super.initState();
    // New or changed watchers are available right away (also from the watcher
    // screen).
    WatchRules.instance.addListener(_onRules);
    _refresh();
  }

  @override
  void dispose() {
    WatchRules.instance.removeListener(_onRules);
    _name.dispose();
    super.dispose();
  }

  void _onRules() {
    if (mounted) setState(() {});
  }

  Future<void> _openWatchers() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WatchScreen()));
    if (mounted) await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final hunt = await widget.client.current();
      final windows = hunt == null ? const <HuntWindow>[] : await widget.client.windows(hunt.id);
      if (!mounted) return;
      setState(() {
        _hunt = hunt;
        _windows = windows;
        _error = null;
      });
    } on Object catch (e) {
      debugPrint('Fehlerjagd laden: $e');
      if (mounted) setState(() => _error = s.huntLoadFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Watchers the server can check (text datapoint types are only checked by
  /// the app).
  List<WatchRule> get _candidates => [
    for (final r in WatchRules.instance.value)
      if (r.serverCheck() != null) r,
  ];

  Future<void> _start() async {
    final rules = [
      for (final r in _candidates)
        if (_chosen.contains(r.id)) r,
    ];
    if (rules.isEmpty) return;
    final hunt = FaultHuntDef.fromWatchers(
      rules,
      name: _name.text.trim().isEmpty ? rules.first.describe() : _name.text.trim(),
      duration: Duration(days: _days),
      from: _night ? _from.hour * 60 + _from.minute : null,
      to: _night ? _to.hour * 60 + _to.minute : null,
    );
    await widget.client.start(hunt);
    _chosen.clear();
    _name.clear();
    await _refresh();
  }

  Future<void> _stop(FaultHuntDef hunt) async {
    await widget.client.stop(hunt);
    await _refresh();
  }

  Future<void> _saveWindow(FaultHuntDef hunt, HuntWindow w) async {
    try {
      final recording = await widget.client.save(hunt, w);
      if (!mounted) return;
      await openRecording(context, recording.id);
    } on Object catch (e) {
      debugPrint('Treffer laden: $e');
      if (mounted) showHorizontMessage(context, s.huntSaveFailed, status: HorizontStatus.critical);
    }
  }

  Future<void> _pick(bool from) async {
    final picked = await showTimePicker(context: context, initialTime: from ? _from : _to);
    if (picked == null) return;
    setState(() => from ? _from = picked : _to = picked);
  }

  String _clock(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _windowText(FaultHuntDef h) {
    String clock(int m) => _clock(TimeOfDay(hour: m ~/ 60, minute: m % 60));
    return h.hasWindow ? s.huntWindow(clock(h.from!), clock(h.to!)) : s.huntAllDay;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final hunt = _hunt;
    final running = hunt != null && hunt.activeAt(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(s.huntTitle),
        actions: [
          if (Addon.available)
            IconButton(tooltip: s.huntRefresh, onPressed: _refresh, icon: const Icon(AppIcons.restart)),
        ],
      ),
      body: !Addon.available
          ? HorizontEmptyHint(icon: AppIcons.hunt, text: s.huntNeedsBox)
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: Widths.reading),
                child: ListView(
                  padding: Gap.page,
                  children: [
                    Text(
                      Addon.box != null ? s.huntExplain : s.huntExplainAddon,
                      style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                    ),
                    const SizedBox(height: Gap.section),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error case final e?) HorizontNotice(HorizontStatus.critical, child: Text(e)),
                    if (hunt != null) _current(context, hunt, running: running),
                    if (!running && !_loading) ...[const SizedBox(height: Gap.section), _newHunt(context)],
                    if (hunt != null && _windows.isNotEmpty) ...[
                      const SizedBox(height: Gap.section),
                      ..._results(context, hunt),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _current(BuildContext context, FaultHuntDef hunt, {required bool running}) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final hits = _windows.fold<int>(0, (n, w) => n + w.hits.length);
    return SectionCard(
      soft: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kennung(running ? s.huntRunning : s.huntEnded),
          const SizedBox(height: Gap.item),
          Text(hunt.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: HzSpace.s4),
          Text(
            [
              s.huntUntil('${formatDate(hunt.until)} ${formatTime(hunt.until, seconds: false)}'),
              _windowText(hunt),
              s.huntHits(hits),
            ].join(metaSeparator),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
          for (final r in hunt.rules) ...[
            const SizedBox(height: HzSpace.s4),
            Text(r['label'] as String? ?? '', style: context.mono(theme.textTheme.bodySmall)),
          ],
          if (running) ...[
            const SizedBox(height: HzSpace.s16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () => _stop(hunt),
                icon: const Icon(AppIcons.stop, size: 18),
                label: Text(s.huntStop),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _newHunt(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final candidates = _candidates;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Kennung(s.huntNew),
        const SizedBox(height: Gap.item),
        if (candidates.isEmpty)
          HorizontEmptyHint(
            icon: AppIcons.watch,
            text: s.huntNoWatchers,
            action: (label: s.watchTitle, onPressed: _openWatchers),
          )
        else ...[
          Text(s.huntChooseRules, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          for (final r in candidates)
            CheckboxListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _chosen.contains(r.id),
              onChanged: (v) => setState(() => v == true ? _chosen.add(r.id) : _chosen.remove(r.id)),
              title: Text(CatalogStore.instance.info(r.address)?.name ?? formatGroup(r.address)),
              subtitle: Text(r.describe(), style: context.mono(theme.textTheme.bodySmall)),
            ),
          const SizedBox(height: Gap.inner),
          HorizontField(
            label: s.huntName,
            child: TextField(
              controller: _name,
              style: context.hzTheme.field,
              decoration: InputDecoration(hintText: s.huntNameHint),
            ),
          ),
          const SizedBox(height: Gap.inner),
          Kennung(s.huntDuration),
          const SizedBox(height: Gap.item),
          Wrap(
            spacing: Gap.item,
            children: [
              for (final d in _durations)
                ChoiceChip(
                  label: Text(s.huntDays(d)),
                  selected: _days == d,
                  onSelected: (_) => setState(() => _days = d),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(s.huntOnlyWindow),
            subtitle: SwitchHint(Addon.box != null ? s.huntOnlyWindowExplain : s.huntOnlyWindowExplainAddon),
            value: _night,
            onChanged: (v) => setState(() => _night = v),
          ),
          if (_night)
            Wrap(
              spacing: Gap.item,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton(onPressed: () => _pick(true), child: Text(_clock(_from))),
                const Text('–'),
                OutlinedButton(onPressed: () => _pick(false), child: Text(_clock(_to))),
              ],
            ),
          const SizedBox(height: Gap.inner),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              onPressed: _chosen.isEmpty ? null : _start,
              icon: const Icon(AppIcons.hunt, size: 18),
              label: Text(s.huntStart),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _results(BuildContext context, FaultHuntDef hunt) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final senders = huntSenders(_windows);
    return [
      Kennung(s.huntSenders),
      const SizedBox(height: Gap.item),
      Text(
        [
          for (final (source, count) in senders.take(5))
            '${[formatIndividual(source), ?store.device(source)?.name].join(' ')} ($count×)',
        ].join(metaSeparator),
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: Gap.section),
      Kennung(s.huntResults, count: _windows.length),
      const SizedBox(height: Gap.item),
      const Divider(height: Lines.hairline),
      for (final w in _windows) ...[
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            '${formatDate(w.hits.first.time)} ${formatTime(w.hits.first.time, seconds: false)}'
            '${w.hits.length > 1 ? ' · ${s.huntHits(w.hits.length)}' : ''}',
          ),
          subtitle: Text(
            [
              w.hits.first.label,
              s.huntFrom([formatIndividual(w.hits.first.source), ?store.device(w.hits.first.source)?.name].join(' ')),
            ].join(metaSeparator),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
          trailing: TextButton(onPressed: () => _saveWindow(hunt, w), child: Text(s.huntOpen)),
        ),
        const Divider(height: Lines.hairline),
      ],
    ];
  }
}
