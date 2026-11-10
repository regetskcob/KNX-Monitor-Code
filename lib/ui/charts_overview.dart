import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/bus_metrics.dart';
import '../model/chart_templates.dart';
import '../model/template_rules.dart';
import '../model/plan.dart';
import '../model/saved_charts.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'address_picker.dart';
import 'chart_cards.dart';
import 'charts_screen.dart';
import 'plan_screen.dart' show unlock;
import 'template_gallery_screen.dart';
import 'tool_shell.dart';
import 'value_board.dart' show columnsFor;

/// New chart: pick addresses across sections, name, save and open it.
Future<void> createChart(BuildContext context, TelegramLog log) async {
  final saved = SavedCharts.instance;
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final candidates = chartChoices(log);
  if (candidates.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(s.chartNoValues)));
    return;
  }
  final chosen = await pickAddresses(
    context,
    title: s.chartNew,
    items: candidates,
    initial: const {},
    counts: log.counts,
    history: log.history,
    log: log,
    max: SavedCharts.maxSeries,
  );
  if (chosen == null || chosen.isEmpty || !context.mounted) return;
  final name = await askChartName(context, initial: saved.uniqueName(s.chartDefaultName));
  if (name == null || name.isEmpty) return;
  final unique = saved.uniqueName(name);
  await saved.put(unique, [
    for (final t in candidates)
      if (chosen.contains(t.destination)) t.destination,
  ]);
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) => ChartsScreen(log: log, chart: unique),
    ),
  );
}

/// All saved charts of the installation as cards, below them the template
/// library ([chartTemplates], without a project derived from traffic), plus
/// "New chart" (touch: FAB, pointer: toolbar).
class ChartsOverview extends StatelessWidget {
  const ChartsOverview({super.key, required this.log});

  final TelegramLog log;

  void _open(BuildContext context, {String? chart, List<int> initial = const []}) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChartsScreen(log: log, chart: chart, initial: initial),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = SavedCharts.instance;
    final phone = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    void create() => createChart(context, log);
    final add = HorizontPrimaryAction(icon: AppIcons.add, label: s.chartNew, onPressed: create);
    unawaited(CustomTemplates.instance.load());
    return ListenableBuilder(
      listenable: Listenable.merge([saved, log, CatalogStore.instance, CustomTemplates.instance]),
      builder: (context, _) {
        final charts = saved.charts;
        final names = charts.keys.toList();
        final library = templateLibrary(log);
        return Scaffold(
          appBar: AppBar(
            title: Text(s.chartsTitle),
            actions: [
              IconButton(
                tooltip: s.galleryTitle,
                onPressed: () async {
                  if (await unlock(context, Feature.charts) && context.mounted) {
                    await pushTool<void>(context, (_) => const TemplateGalleryScreen());
                  }
                },
                icon: const Icon(AppIcons.objects),
              ),
              IconButton(
                tooltip: s.chartTemplateImport,
                onPressed: () => importTemplate(context),
                icon: const Icon(AppIcons.import),
              ),
              ...add.toolbar(context),
            ],
          ),
          floatingActionButton: add.fab(context),
          body: charts.isEmpty && library.isEmpty
              ? HorizontEmptyHint(
                  icon: AppIcons.chart,
                  text: s.chartsOverviewEmpty,
                  detail: s.chartsOverviewEmptyDetail,
                  action: (label: s.chartNew, onPressed: create),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final gutter = Gap.gutterFor(constraints.maxWidth);
                    final columns = columnsFor(constraints.maxWidth - 2 * gutter, phone: phone);
                    final hz = context.hz;
                    final theme = Theme.of(context);
                    return ListView(
                      padding: EdgeInsets.fromLTRB(gutter, HzSpace.s8, gutter, HzSpace.s96 + HzSpace.s16),
                      children: [
                        if (names.isNotEmpty) ...[
                          HorizontSectionHeader(
                            s.chartsSaved,
                            count: names.length,
                            padding: const EdgeInsets.only(bottom: Gap.item),
                          ),
                          ..._grid(columns, [
                            for (final name in names)
                              ChartCard(
                                name: name,
                                addresses: charts[name]!,
                                log: log,
                                onTap: () => _open(context, chart: name),
                              ),
                          ]),
                        ] else
                          // Nothing of your own yet: briefly explain what the
                          // templates are.
                          Padding(
                            padding: const EdgeInsets.only(bottom: Gap.item),
                            child: Text(
                              library.any((t) => t.traffic) ? s.chartTemplatesTrafficIntro : s.chartTemplatesIntro,
                              style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                            ),
                          ),
                        for (final group in _byRecipe(library)) ...[
                          HorizontSectionHeader(
                            group.first.recipeName,
                            count: group.length,
                            padding: const EdgeInsets.only(top: HzSpace.s16, bottom: Gap.item),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (group.where((t) => t.addresses.isNotEmpty && !t.adoptedIn(charts)).length >= 2)
                                  TextButton(
                                    onPressed: () => adoptTemplates(context, group),
                                    child: Text(s.chartTemplatesAdoptAll),
                                  ),
                                // Eigene, importierte Vorlage: wieder entfernbar.
                                if (group.first.rule case final rule?)
                                  IconButton(
                                    tooltip: s.chartTemplateRemove,
                                    onPressed: () => CustomTemplates.instance.remove(rule),
                                    icon: const Icon(AppIcons.delete),
                                  ),
                              ],
                            ),
                          ),
                          ..._grid(columns, [
                            for (final t in group)
                              if (t.addresses.isEmpty)
                                _NoMatchCard(name: t.name)
                              else
                                ChartCard(
                                  name: t.name,
                                  addresses: t.addresses,
                                  log: log,
                                  // Preview in full screen, which also offers
                                  // "Save selection".
                                  onTap: () async {
                                    if (await unlock(context, Feature.charts) && context.mounted) {
                                      _open(context, initial: t.addresses);
                                    }
                                  },
                                  footer: Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: t.adoptedIn(charts)
                                        ? Padding(
                                            padding: const EdgeInsets.only(top: HzSpace.s8),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              spacing: HzSpace.s4,
                                              children: [
                                                Icon(AppIcons.check, size: HzIconSize.inline, color: hz.textMuted),
                                                Text(
                                                  s.chartTemplateAdopted,
                                                  style: theme.textTheme.labelLarge?.copyWith(color: hz.textMuted),
                                                ),
                                              ],
                                            ),
                                          )
                                        : TextButton.icon(
                                            onPressed: () => adoptTemplates(context, [t]),
                                            icon: const Icon(AppIcons.add),
                                            label: Text(s.chartTemplateAdopt),
                                          ),
                                  ),
                                ),
                          ]),
                        ],
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  /// Cards in rows of [columns], each row of equal height.
  static List<Widget> _grid(int columns, List<Widget> cards) => [
    for (var line = 0; line < (cards.length / columns).ceil(); line++)
      Padding(
        padding: const EdgeInsets.only(bottom: HzSpace.s12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: HzSpace.s12,
            children: [
              for (var c = 0; c < columns; c++)
                Expanded(
                  child: line * columns + c < cards.length ? cards[line * columns + c] : const SizedBox.shrink(),
                ),
            ],
          ),
        ),
      ),
  ];

  static List<List<LibraryTemplate>> _byRecipe(List<LibraryTemplate> list) {
    final groups = <String, List<LibraryTemplate>>{};
    for (final t in list) {
      (groups[t.recipeName] ??= []).add(t);
    }
    return groups.values.toList();
  }
}

/// Custom template that matches nothing in this installation: name and hint.
class _NoMatchCard extends StatelessWidget {
  const _NoMatchCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.card,
        border: Border.all(color: hz.line, width: Lines.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(HzSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: HzSpace.s8,
          children: [
            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            Text(s.chartTemplateNoMatch, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A template as shown by the library: name, addresses, category.
class LibraryTemplate {
  const LibraryTemplate({
    required this.name,
    required this.recipeName,
    required this.addresses,
    this.traffic = false,
    this.rule,
  });

  final String name;
  final String recipeName;
  final List<int> addresses;

  /// Derived from traffic instead of the project (without an ETS project).
  final bool traffic;

  /// Name of the custom template ([TemplateRule]) it comes from.
  final String? rule;

  /// Already adopted: a custom chart with exactly these addresses.
  bool adoptedIn(Map<String, List<int>> charts) {
    if (addresses.isEmpty) return false;
    final mine = addresses.toSet();
    return charts.values.any((c) => c.length == mine.length && mine.containsAll(c));
  }
}

String _recipeName(ChartRecipe r) => switch (r) {
  ChartRecipe.climate => s.chartRecipeClimate,
  ChartRecipe.air => s.chartRecipeAir,
  ChartRecipe.light => s.chartRecipeLight,
  ChartRecipe.shading => s.chartRecipeShading,
  ChartRecipe.weather => s.chartRecipeWeather,
  ChartRecipe.energy => s.chartRecipeEnergy,
};

Object? _templatesKey;
List<ChartTemplate> _templates = const [];

/// Templates of the installation: first the bus itself (metrics, [BusMetric]),
/// then from the ETS project, or from traffic without a project.
List<LibraryTemplate> templateLibrary(TelegramLog log) => [
  ..._busTemplates(log),
  ..._customTemplates(),
  ..._addressTemplates(log),
];

/// Imported custom templates, applied to this installation's project.
List<LibraryTemplate> _customTemplates() {
  final store = CatalogStore.instance;
  return [
    for (final rule in CustomTemplates.instance.rules)
      if (applyRule(rule, store.catalog.groups, store.catalog.devices, dptOf: store.dptOf) case final matches
          when matches.isNotEmpty)
        for (final (:place, :ids) in matches)
          LibraryTemplate(
            name: place.isEmpty ? rule.name : '${rule.name} · $place',
            recipeName: rule.name,
            addresses: ids,
            rule: rule.name,
          )
      else
        // Show it even without matches so it can be removed.
        LibraryTemplate(name: rule.name, recipeName: rule.name, addresses: const [], rule: rule.name),
  ];
}

/// Reads a shared template ([TemplateRule]) and adds it to the library.
Future<void> importTemplate(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final file = await FilePicker.pickFile(type: FileType.any);
  if (file == null) return;
  try {
    final rule = TemplateRule.fromJson(jsonDecode(utf8.decode(await file.readAsBytes())));
    await CustomTemplates.instance.add(rule);
    final store = CatalogStore.instance;
    final matches = applyRule(rule, store.catalog.groups, store.catalog.devices, dptOf: store.dptOf);
    messenger.showSnackBar(
      SnackBar(
        content: Text(matches.isEmpty ? s.chartTemplateImportedNoMatch(rule.name) : s.chartTemplateImported(rule.name)),
      ),
    );
  } on FormatException {
    messenger.showSnackBar(SnackBar(content: Text(s.chartTemplateImportFailed)));
  }
}

/// At most this many lines in "Bus · Linien" (bus lines).
const _maxLines = 6;

/// Technical charts: telegrams and repetitions per minute, plus the load of the
/// busiest lines (from two lines on). None without traffic.
List<LibraryTemplate> _busTemplates(TelegramLog log) {
  if (log.log.isEmpty) return const [];
  final byLine = <int, int>{};
  for (final t in log.log) {
    if (!t.outgoing) byLine[t.source >> 8] = (byLine[t.source >> 8] ?? 0) + 1;
  }
  final lines = (byLine.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(_maxLines).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final bus = s.chartRecipeBus;
  return [
    LibraryTemplate(
      name: '$bus · ${s.chartBusOverall}',
      recipeName: bus,
      addresses: [BusMetric.telegrams.id, BusMetric.repeats.id],
    ),
    LibraryTemplate(name: '$bus · ${s.busMetricLoad}', recipeName: bus, addresses: [BusMetric.load.id]),
    if (lines.length >= 2)
      LibraryTemplate(
        name: '$bus · ${s.chartBusLines}',
        recipeName: bus,
        addresses: [for (final e in lines) BusMetric.line(e.key).id],
      ),
  ];
}

List<LibraryTemplate> _addressTemplates(TelegramLog log) {
  final store = CatalogStore.instance;
  // Only re-derive when the project or type corrections change, since the
  // overview rebuilds with every telegram.
  final key = (store.catalog, Object.hashAllUnordered(store.overrides.entries.map((e) => Object.hash(e.key, e.value))));
  if (key != _templatesKey) {
    _templatesKey = key;
    _templates = chartTemplates(store.catalog.groups, store.catalog.devices, dptOf: store.dptOf);
  }
  final fromProject = _templates;
  if (fromProject.isNotEmpty) {
    return [
      for (final t in fromProject)
        LibraryTemplate(
          name: t.place.isEmpty ? _recipeName(t.recipe) : '${_recipeName(t.recipe)} · ${t.place}',
          recipeName: _recipeName(t.recipe),
          addresses: t.addresses,
        ),
    ];
  }
  return [
    for (final (name, addresses) in _trafficTemplates(log))
      LibraryTemplate(name: name, recipeName: s.chartRecipeTraffic, addresses: addresses, traffic: true),
  ];
}

/// Adopts [templates] as custom charts (Plus); already adopted ones are
/// skipped, names are numbered if needed.
Future<void> adoptTemplates(BuildContext context, List<LibraryTemplate> templates) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!await unlock(context, Feature.charts)) return;
  final saved = SavedCharts.instance;
  final added = <String>[];
  for (final t in templates) {
    if (t.addresses.isEmpty || t.adoptedIn(saved.charts)) continue;
    final name = saved.uniqueName(t.name);
    await saved.put(name, t.addresses);
    added.add(name);
  }
  if (added.isEmpty) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        added.length == 1 ? s.chartTemplateAdoptedSnack(added.single) : s.chartTemplatesAdoptedSnack(added.length),
      ),
    ),
  );
}

/// Without a project: three or four charts from live traffic (per datapoint
/// type, the addresses with the most measured values).
List<(String, List<int>)> _trafficTemplates(TelegramLog log) {
  const charts = 4;
  const series = 4;
  final store = CatalogStore.instance;
  final byType = <String, List<int>>{};
  for (final MapEntry(key: ga, value: values) in log.history.entries) {
    final dpt = store.dptOf(ga);
    // Only measured values with a history; switching states are boring as an
    // example.
    if (dpt == null || dpt.main == 1 || values.length < 3) continue;
    (byType['$dpt'] ??= []).add(ga);
  }
  int weight(List<int> gas) => gas.fold(0, (sum, ga) => sum + (log.history[ga]?.length ?? 0));
  final groups = byType.values.toList()..sort((a, b) => weight(b).compareTo(weight(a)));
  return [
    for (final gas in groups.take(charts))
      (
        _nameOf(gas),
        (gas..sort((a, b) => (log.history[b]?.length ?? 0).compareTo(log.history[a]?.length ?? 0)))
            .take(series)
            .toList(),
      ),
  ];
}

/// Most frequent last word of the names ("Ist-Temperatur"), otherwise the unit.
String _nameOf(List<int> gas) {
  final store = CatalogStore.instance;
  final words = <String, int>{};
  for (final ga in gas) {
    final name = store.info(ga)?.name.trim() ?? '';
    if (name.isEmpty) continue;
    final last = name.split(RegExp(r'\s+')).last;
    words[last] = (words[last] ?? 0) + 1;
  }
  if (words.isNotEmpty) return (words.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
  final dpt = store.dptOf(gas.first);
  return dpt == null ? formatGroup(gas.first) : 'DPT $dpt';
}
