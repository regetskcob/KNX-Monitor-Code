import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/communication_map.dart';
import '../model/plan.dart';
import '../model/tour.dart';
import '../monitor_model.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'charts_screen.dart';
import 'communication_map_screen.dart';
import 'details_sheet.dart';
import 'log_view.dart';
import 'plan_screen.dart';
import 'project_check_screen.dart';
import 'statistics_screen.dart';
import 'topology_screen.dart';

/// What the stage of a card shows: a real view of the app with the demo house
/// (scaled down, not interactive) or a row of chips.
enum TourScene { overview, objects, live, details, charts, statistics, topology, map, projectCheck, chips }

/// An icon with a word on a card without its own view.
class TourChip {
  const TourChip(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// A card of the tour; [chapter] is `null` for the cards at the end.
class TourStep {
  const TourStep({
    required this.title,
    required this.text,
    required this.icon,
    this.chapter,
    this.scene = TourScene.chips,
    this.chips = const [],
    this.more = false,
    this.ready = false,
  });

  final TourChapter? chapter;
  final String title;
  final String text;
  final IconData icon;
  final TourScene scene;
  final List<TourChip> chips;

  /// Card with what a higher tier adds (only in the store apps).
  final bool more;

  /// Last card: open the demo house or finish.
  final bool ready;
}

/// Name of a chapter as the label shows it.
String tourChapterName(TourChapter c) => switch (c) {
  TourChapter.basics => s.tourChapterBasics,
  TourChapter.analysis => s.tourChapterAnalysis,
  TourChapter.expert => s.tourChapterExpert,
};

/// Die Karten eines Kapitels.
List<TourStep> tourChapterSteps(TourChapter c) => switch (c) {
  TourChapter.basics => [
    TourStep(
      chapter: c,
      title: s.tourWelcomeTitle,
      text: s.tourWelcomeText,
      icon: AppIcons.live,
      scene: TourScene.live,
    ),
    TourStep(
      chapter: c,
      title: s.tourConnectTitle,
      text: s.tourConnectText,
      icon: AppIcons.installation,
      chips: [
        TourChip(AppIcons.search, s.tourChipSearch),
        const TourChip(AppIcons.live, 'UDP · TCP'),
        const TourChip(AppIcons.communicationMap, 'Routing'),
        const TourChip(AppIcons.secure, 'KNX IP Secure'),
        TourChip(AppIcons.installation, s.tourChipInstallations),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourProjectTitle,
      text: s.tourProjectText,
      icon: AppIcons.import,
      chips: [
        const TourChip(AppIcons.import, '.knxproj'),
        TourChip(AppIcons.table, s.tourChipCsv),
        const TourChip(AppIcons.secure, 'Keyring'),
        TourChip(AppIcons.installation, s.tourChipLocal),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourOverviewTitle,
      text: s.tourOverviewText,
      icon: AppIcons.overview,
      scene: TourScene.overview,
    ),
    TourStep(
      chapter: c,
      title: s.tourObjectsTitle,
      text: s.tourObjectsText,
      icon: AppIcons.objects,
      scene: TourScene.objects,
    ),
    TourStep(chapter: c, title: s.tourLiveTitle, text: s.tourLiveText, icon: AppIcons.live, scene: TourScene.live),
    TourStep(
      chapter: c,
      title: s.tourFilterTitle,
      text: s.tourFilterText,
      icon: AppIcons.filter,
      chips: [
        TourChip(AppIcons.search, s.tourChipFilterName),
        const TourChip(AppIcons.search, '1/2/*'),
        TourChip(AppIcons.search, s.tourChipFilterSender),
        TourChip(AppIcons.search, s.tourChipFilterTime),
        const TourChip(AppIcons.bookmark, '…'),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourDetailsTitle,
      text: s.tourDetailsText,
      icon: AppIcons.touch,
      scene: TourScene.details,
    ),
    TourStep(
      chapter: c,
      title: s.tourHealthTitle,
      text: s.tourHealthText,
      icon: AppIcons.health,
      chips: [
        TourChip(AppIcons.sensors, s.tourChipSilent),
        TourChip(AppIcons.fileCode, s.tourChipTypes),
        TourChip(AppIcons.cycle, s.tourChipCycles),
        TourChip(AppIcons.live, s.tourChipBusQuality),
        const TourChip(AppIcons.pdf, 'PDF'),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourRecordTitle,
      text: s.tourRecordText,
      icon: AppIcons.record,
      chips: [
        TourChip(AppIcons.record, s.recordingsTitle),
        TourChip(AppIcons.annotation, s.annotationsTitle),
        TourChip(AppIcons.supportPackage, s.reportTitle),
      ],
    ),
  ],
  TourChapter.analysis => [
    TourStep(
      chapter: c,
      title: s.tourHistoryTitle,
      text: s.tourHistoryText,
      icon: AppIcons.history,
      chips: [
        TourChip(AppIcons.history, s.historyTitle),
        TourChip(AppIcons.rewind, s.tourChipTimeline),
        TourChip(AppIcons.play, s.tourChipPlayback),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourChartsTitle,
      text: s.tourChartsText,
      icon: AppIcons.chart,
      scene: TourScene.charts,
    ),
    TourStep(
      chapter: c,
      title: s.tourStatsTitle,
      text: s.tourStatsText,
      icon: AppIcons.statistics,
      scene: TourScene.statistics,
    ),
    TourStep(
      chapter: c,
      title: s.tourWatchTitle,
      text: s.tourWatchText,
      icon: AppIcons.notify,
      chips: [
        TourChip(AppIcons.notify, s.watchTitle),
        TourChip(AppIcons.notify, s.tourChipSound),
        TourChip(AppIcons.alarm, s.notifyMenu),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourExportTitle,
      text: s.tourExportText,
      icon: AppIcons.share,
      chips: [
        TourChip(AppIcons.pdf, 'PDF'),
        TourChip(AppIcons.table, 'CSV'),
        TourChip(AppIcons.fileCode, 'ETS'),
        TourChip(AppIcons.share, 'ZIP'),
      ],
    ),
  ],
  TourChapter.expert => [
    TourStep(
      chapter: c,
      title: s.tourExpertTitle,
      text: s.tourExpertText,
      icon: AppIcons.expert,
      chips: [
        TourChip(AppIcons.expert, s.expertMode),
        TourChip(AppIcons.tools, s.tourChipPort),
        const TourChip(AppIcons.secure, 'Keyring'),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourBusmonTitle,
      text: s.tourBusmonText,
      icon: AppIcons.live,
      chips: [
        TourChip(AppIcons.live, s.busmonTitle),
        TourChip(AppIcons.check, s.tourChipAck),
        TourChip(AppIcons.restart, s.tourChipRepeats),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourTopoTitle,
      text: s.tourTopoText,
      icon: AppIcons.topology,
      scene: TourScene.topology,
    ),
    TourStep(
      chapter: c,
      title: s.tourMapTitle,
      text: s.tourMapText,
      icon: AppIcons.communicationMap,
      scene: TourScene.map,
    ),
    TourStep(
      chapter: c,
      title: s.tourCheckTitle,
      text: s.tourCheckText,
      icon: AppIcons.projectCheck,
      scene: TourScene.projectCheck,
    ),
    TourStep(
      chapter: c,
      title: s.tourCommTitle,
      text: s.tourCommText,
      icon: AppIcons.commissioning,
      chips: [
        TourChip(AppIcons.commissioning, s.commTitle),
        const TourChip(AppIcons.pdf, 'PDF'),
        TourChip(AppIcons.diagnostics, s.tourChipProgMode),
        TourChip(AppIcons.topology, s.tourChipLineScan),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourSendTitle,
      text: s.tourSendText,
      icon: AppIcons.send,
      chips: [
        TourChip(AppIcons.send, s.planFeatureScheduled),
        TourChip(AppIcons.trigger, s.triggerTitle),
        TourChip(AppIcons.play, s.planFeatureReplay),
      ],
    ),
    TourStep(
      chapter: c,
      title: s.tourBoxTitle,
      text: s.tourBoxText,
      icon: AppIcons.box,
      chips: [
        TourChip(AppIcons.box, s.boxAdd),
        TourChip(AppIcons.sensors, s.tourChipWifi),
        TourChip(AppIcons.import, s.tourChipSticker),
      ],
    ),
  ],
};

/// The whole tour for [tier]: the chapters of the tier (all three without a
/// purchase path), in the store apps below Pro a card with what would be added,
/// and finally "Bereit" (ready).
List<TourStep> tourSteps(Tier tier, {required bool purchasable}) => [
  for (final c in TourProgress.chaptersFor(tier, purchasable: purchasable)) ...tourChapterSteps(c),
  if (TourProgress.hasMore(tier, purchasable: purchasable))
    TourStep(title: s.tourMoreTitle, text: s.tourMoreText, icon: AppIcons.plan, more: true),
  TourStep(title: s.tourReadyTitle, text: s.tourReadyText, icon: AppIcons.play, ready: true),
];

/// First card: the first chapter not yet seen (after an upgrade the new one),
/// otherwise the beginning.
int tourStart(List<TourStep> steps, TourProgress progress) {
  final chapters = {for (final st in steps) ?st.chapter};
  if (chapters.every(progress.seen) || chapters.every((c) => !progress.seen(c))) return 0;
  final first = chapters.firstWhere((c) => !progress.seen(c));
  return steps.indexWhere((st) => st.chapter == first);
}

/// Result of the tour: open the demo house or just go back.
enum TourResult { demo, done }

/// Opens the tour for the current tier. Only from the connect screen: the
/// scenes briefly swap the project for the demo house.
Future<TourResult?> showTour(BuildContext context) {
  final plan = Plan.instance;
  final steps = tourSteps(plan.value, purchasable: plan.purchasable);
  return Navigator.of(context).push<TourResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TourScreen(steps: steps, start: tourStart(steps, TourProgress.instance)),
    ),
  );
}

/// The tour: one card after another; the stage above or beside it shows the
/// matching view in the demo house.
class TourScreen extends StatefulWidget {
  const TourScreen({super.key, required this.steps, this.start = 0});

  final List<TourStep> steps;
  final int start;

  @override
  State<TourScreen> createState() => _TourScreenState();
}

class _TourScreenState extends State<TourScreen> {
  late final _pages = PageController(initialPage: widget.start);
  late int _index = widget.start;
  final _tunnel = DemoTunnel();
  late final MonitorModel _demo;

  @override
  void initState() {
    super.initState();
    // The scenes show the demo house; your own project comes back afterwards.
    CatalogStore.instance.beginDemo(demoCatalog());
    _demo = MonitorModel(_tunnel)..addAll(_tunnel.simulate());
    unawaited(_tunnel.connect());
    _seen(_index);
  }

  @override
  void dispose() {
    _pages.dispose();
    _demo.dispose();
    unawaited(_tunnel.disconnect().whenComplete(_tunnel.dispose));
    CatalogStore.instance.endDemo();
    super.dispose();
  }

  /// A chapter counts as seen as soon as its last card has been shown.
  void _seen(int index) {
    final steps = widget.steps;
    for (var i = 0; i <= index && i < steps.length; i++) {
      final c = steps[i].chapter;
      final last = i + 1 >= steps.length || steps[i + 1].chapter != c;
      if (c != null && last) unawaited(TourProgress.instance.markSeen(c));
    }
  }

  void _go(int delta) {
    final next = (_index + delta).clamp(0, widget.steps.length - 1);
    if (next == _index) return;
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _pages.jumpToPage(next);
    } else {
      _pages.animateToPage(next, duration: Motion.base, curve: Motion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    final step = steps[_index];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(-1),
        const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).pop(TourResult.done),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Kennung(s.tourProgress(_index + 1, steps.length)),
            actions: [
              IconButton(
                tooltip: s.tourClose,
                icon: const Icon(AppIcons.close),
                onPressed: () => Navigator.of(context).pop(TourResult.done),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: steps.length,
                    onPageChanged: (i) {
                      setState(() => _index = i);
                      _seen(i);
                    },
                    itemBuilder: (context, i) => _Card(step: steps[i], data: _demo, active: i == _index),
                  ),
                ),
                _Controls(step: step, first: _index == 0, onBack: () => _go(-1), onNext: () => _go(1)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Back and next; on the last card demo house and done.
class _Controls extends StatelessWidget {
  const _Controls({required this.step, required this.first, required this.onBack, required this.onNext});

  final TourStep step;
  final bool first;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: Gap.gutterFor(MediaQuery.sizeOf(context).width),
          vertical: HzSpace.s12,
        ),
        child: Row(
          spacing: HzSpace.s8,
          children: [
            if (!first) TextButton(onPressed: onBack, child: Text(s.tourBack)),
            const Spacer(),
            if (step.ready) ...[
              OutlinedButton(onPressed: () => Navigator.of(context).pop(TourResult.done), child: Text(s.tourDone)),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(TourResult.demo),
                icon: const Icon(AppIcons.play, size: 18),
                label: Text(s.tourOpenDemo),
              ),
            ] else
              FilledButton(onPressed: onNext, child: Text(s.tourNext)),
          ],
        ),
      ),
    );
  }
}

/// A card: stage and text, side by side from tablet width, otherwise stacked
/// (the stage on top).
class _Card extends StatelessWidget {
  const _Card({required this.step, required this.data, required this.active});

  final TourStep step;
  final MonitorModel data;
  final bool active;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= HzBreakpoint.medium && c.maxWidth > c.maxHeight * 1.1;
      final gutter = Gap.gutterFor(c.maxWidth);
      // Only the card in view moves (the demo traffic keeps running).
      final stage = TickerMode(
        enabled: active,
        child: _Stage(step: step, data: data),
      );
      final words = _Words(step: step);
      if (wide) {
        return Padding(
          padding: EdgeInsets.all(gutter),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: HzSpace.s32,
            children: [
              Expanded(flex: 3, child: stage),
              Expanded(
                flex: 2,
                child: Center(child: SingleChildScrollView(child: words)),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(gutter, HzSpace.s8, gutter, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: stage),
            const SizedBox(height: HzSpace.s16),
            Expanded(flex: 4, child: SingleChildScrollView(child: words)),
          ],
        ),
      );
    },
  );
}

/// Label with chapter (and in the store apps the tier), title, text, chips; on
/// the card for more, the way to the tiers.
class _Words extends StatelessWidget {
  const _Words({required this.step});

  final TourStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final chapter = step.chapter;
    final plan = Plan.instance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapter != null)
          Row(
            spacing: HzSpace.s8,
            children: [
              Kennung(tourChapterName(chapter)),
              // Where there is something to buy, the tier is shown too.
              if (plan.purchasable && chapter.tier != Tier.free) TierBadge(chapter.tier),
            ],
          ),
        const SizedBox(height: HzSpace.s8),
        Text(step.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: HzSpace.s12),
        Text(step.text, style: theme.textTheme.bodyLarge?.copyWith(color: hz.textMuted)),
        if (step.chips.isNotEmpty && step.scene != TourScene.chips) ...[
          const SizedBox(height: HzSpace.s16),
          _Chips(chips: step.chips),
        ],
        if (step.more) ...[
          const SizedBox(height: HzSpace.s16),
          OutlinedButton.icon(
            onPressed: () => showPlanScreen(context, need: plan.value == Tier.free ? Tier.plus : Tier.pro),
            icon: const Icon(AppIcons.plan, size: 18),
            label: Text(s.tourMorePlans),
          ),
        ],
      ],
    );
  }
}

class _Chips extends StatelessWidget {
  const _Chips({required this.chips});

  final List<TourChip> chips;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final style = Theme.of(context).textTheme.bodyMedium;
    return Wrap(
      spacing: HzSpace.s8,
      runSpacing: HzSpace.s8,
      children: [
        for (final c in chips)
          DecoratedBox(
            decoration: BoxDecoration(
              color: hz.surface,
              border: Border.all(color: hz.line, width: Lines.hairline),
              borderRadius: Radii.row,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: HzSpace.s8,
                children: [
                  Icon(c.icon, size: 18, color: hz.accentText),
                  Text(c.label, style: style),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The stage: a real view in the demo house, rendered in a frame at a fixed
/// size and fitted (phone portrait, tablet landscape), or the large icon with
/// the chips.
class _Stage extends StatelessWidget {
  const _Stage({required this.step, required this.data});

  final TourStep step;
  final MonitorModel data;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final view = _view();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.sunken,
        border: Border.all(color: hz.line, width: Lines.hairline),
        borderRadius: Radii.tile,
      ),
      child: ClipRRect(
        borderRadius: Radii.tile,
        child: view == null
            ? Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(HzSpace.s24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(step.icon, size: 56, color: hz.accentText),
                      if (step.chips.isNotEmpty) ...[const SizedBox(height: HzSpace.s24), _Chips(chips: step.chips)],
                    ],
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, c) {
                  // Wide stage (tablet, desktop): as wide as a tablet with a
                  // sidebar, in the stage's aspect ratio. Otherwise a phone,
                  // fully fitted.
                  final aspect = c.maxHeight > 0 ? c.maxWidth / c.maxHeight : 1.0;
                  final size = c.maxWidth >= 560 && aspect >= 0.9 ? Size(1024, 1024 / aspect) : const Size(393, 720);
                  return ExcludeSemantics(
                    child: IgnorePointer(
                      child: FittedBox(
                        child: SizedBox.fromSize(
                          size: size,
                          child: MediaQuery(
                            data: MediaQuery.of(context)
                                .copyWith(size: size, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
                            child: view,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget? _view() {
    final title = Kennung(s.tourDemoHouse);
    Widget log(LogTab tab) => LogView(data: data, title: title, exportTitle: 'Demo', initialTab: tab);
    return switch (step.scene) {
      TourScene.overview => log(LogTab.overview),
      TourScene.objects => log(LogTab.objects),
      TourScene.live => log(LogTab.live),
      TourScene.details => _details(),
      TourScene.charts => ChartsScreen(
        log: data,
        initial: [
          for (final a in ['2/0/1', '2/0/2', '1/1/1', '1/1/2', '4/0/3']) ?parseGroup(a),
        ],
      ),
      TourScene.statistics => StatisticsScreen(log: data, onFilter: (_) {}),
      TourScene.topology => TopologyScreen(log: data),
      TourScene.map => CommunicationMapScreen(log: data, start: MapNode.group(parseGroup('4/0/0')!)),
      TourScene.projectCheck => ProjectCheckScreen(log: data, onFilter: (_) {}),
      TourScene.chips => null,
    };
  }

  /// Details of an address with history (outdoor brightness, otherwise the first).
  Widget _details() {
    final address = parseGroup('4/0/2')!;
    final t = data.latest[address] ?? data.latest.values.firstOrNull;
    if (t == null) return const SizedBox.shrink();
    final history = [
      for (final e in data.log)
        if (e.destination == t.destination) e,
    ];
    return Material(
      child: TelegramDetails(telegram: t, tunnel: null, history: history),
    );
  }
}
