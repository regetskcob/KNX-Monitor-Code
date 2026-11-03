import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../model/sound_ack.dart';
import 'sound_ack_screen.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/communication_map.dart';
import '../model/annotation.dart';
import '../model/device_art.dart';
import '../model/device_channels.dart';
import '../model/telegram_log.dart';
import '../model/topology.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'actuator_view.dart';
import 'flush_input_view.dart';
import 'live_updates.dart';
import 'presence_view.dart';
import 'push_button_view.dart';
import 'smoke_detector_view.dart';
import 'weather_view.dart';
import 'annotations.dart';
import 'annotations_screen.dart';
import 'common.dart';
import 'recording_timeline.dart';
import 'statistics_screen.dart' show FigureBox;
import 'communication_map_screen.dart';
import 'telegram_row.dart';
import '../model/plan.dart';
import '../model/device_shapes.dart';
import '../model/push_buttons.dart';
import '../model/filter.dart';
import 'plan_screen.dart';

/// Device in a sheet: sent and received telegrams, jump to the communication
/// map and monitor filter. On iPad and Mac wide enough for drawing, channels
/// and telegrams side by side.
Future<void> showDeviceSheet(
  BuildContext context, {
  required int address,
  required TelegramLog log,
  int? hops,
  ValueChanged<String>? onFilter,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  constraints: const BoxConstraints(maxWidth: Widths.dashboard),
  builder: (sheet) => SafeArea(
    top: false,
    child: DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => DeviceTraffic(
        address: address,
        log: log,
        hops: hops,
        scrollController: scroll,
        onMap: () async {
          Navigator.pop(sheet);
          await openDeviceMap(context, address: address, log: log);
        },
        onFilter: onFilter == null
            ? null
            : () {
                Navigator.pop(sheet);
                onFilter(senderQuery(formatIndividual(address)));
              },
      ),
    ),
  ),
);

/// Opens the communication map from the device (Plus).
Future<void> openDeviceMap(BuildContext context, {required int address, required TelegramLog log}) async {
  if (!await unlock(context, Feature.communicationMap) || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CommunicationMapScreen(log: log, start: MapNode.device(address)),
    ),
  );
}

class DeviceTraffic extends StatefulWidget {
  const DeviceTraffic({
    super.key,
    required this.address,
    required this.log,
    this.hops,
    this.scrollController,
    this.onMap,
    this.onFilter,
    this.onClose,
    this.embedded = false,
  });

  /// Embedded in a scrolling page (topology below the lines).
  final bool embedded;

  final int address;
  final TelegramLog log;
  final int? hops;
  final ScrollController? scrollController;
  final VoidCallback? onMap;
  final VoidCallback? onFilter;

  /// Closes the detail (embedded only, e.g. in the topology).
  final VoidCallback? onClose;

  @override
  State<DeviceTraffic> createState() => _DeviceTrafficState();
}

class _DeviceTrafficState extends State<DeviceTraffic> {
  bool _received = false;
  late List<DeviceChannel> _channels = deviceChannels(widget.address);

  /// Selected channel in the wide layout; `null` = all channels.
  int? _channel;

  @override
  void initState() {
    super.initState();
    // With a manufacturer graphic the layout changes (cards next to the
    // graphic).
    DeviceArtCatalog.instance.load().then((_) {
      if (mounted) setState(() => _channels = deviceChannels(widget.address));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final device = store.device(widget.address);
    // Addresses the device listens to or sends according to the project.
    final linked = {
      for (final g in store.catalog.groups.values)
        if (g.links.any((l) => l.device == widget.address)) g.address,
    };
    return LayoutBuilder(
      builder: (context, box) {
        // Wide: drawing across the full width, channels next to the telegrams
        // below.
        final wide = box.maxWidth >= Widths.reading;
        return ListenableBuilder(
          listenable: liveUpdates(widget.log),
          builder: (context, _) {
            final log = widget.log.log;
            final sent = [
              for (final t in log.reversed)
                if (t.source == widget.address) t,
            ];
            final received = [
              for (final t in log.reversed)
                if (t.source != widget.address && linked.contains(t.destination)) t,
            ];
            final list = _received ? received : sent;
            final metrics = FigureBox(
              figures: [
                (s.devSent, formatInt(sent.length)),
                (s.devReceived, device == null ? '—' : formatInt(received.length)),
                (s.devGroups, formatInt(linked.length)),
              ],
            );
            final mapButton = widget.onMap == null
                ? null
                : OutlinedButton.icon(
                    onPressed: widget.onMap,
                    icon: const Icon(AppIcons.communicationMap, size: 18),
                    label: Text(s.mapTitle),
                  );
            final filterButton = widget.onFilter == null
                ? null
                : OutlinedButton.icon(
                    onPressed: widget.onFilter,
                    icon: const Icon(AppIcons.filter, size: 18),
                    label: Text(s.devFilterMonitor),
                  );
            final traffic = [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text('${s.devSent} · ${sent.length}')),
                  ButtonSegment(value: true, label: Text('${s.devReceived} · ${received.length}')),
                ],
                selected: {_received},
                onSelectionChanged: (v) => setState(() => _received = v.first),
              ),
              const SizedBox(height: HzSpace.s8),
              if (_received)
                Text(
                  device == null ? s.devNoLinks : s.devReceivedHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                ),
              const SizedBox(height: HzSpace.s8),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: HzSpace.s24),
                  child: HorizontEmptyHint(icon: AppIcons.sensors, text: s.devNothing),
                )
              else
                for (final t in list.take(200)) _TrafficRow(telegram: t, showSource: _received),
            ];
            final art = artFor(widget.address);
            // Cards next to the graphic already show all channels; below only
            // the objects of the selected channel.
            final callouts = art != null && artCalloutsFit(art, box.maxWidth - 2 * Gap.gutter);
            final shape = shapeOf(widget.address, CatalogStore.instance.catalog);
            // Channels next to the telegrams only in the actuator view; the
            // other drawings show their objects themselves.
            final pickChannel =
                wide && device != null && _channels.isNotEmpty && (art != null || shape == DeviceShape.din);
            final withChannels = pickChannel && !(callouts && _channel == null);
            return ListView(
              controller: widget.scrollController,
              // Embedded (topology): scrolls with the page, no border of its
              // own.
              shrinkWrap: widget.embedded,
              physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
              padding: widget.embedded
                  ? EdgeInsets.zero
                  : EdgeInsets.fromLTRB(Gap.gutter, widget.onClose == null ? 0 : Gap.item, Gap.gutter, Gap.bottom),
              children: [
                // Header: address, below it the name, below that product, line
                // and hop.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatIndividual(widget.address),
                            style: context
                                .mono(theme.textTheme.bodyMedium)
                                .copyWith(color: hz.textMuted, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: HzSpace.s4),
                          Text(
                            device?.name ?? s.topoNotInProject,
                            style: (wide ? theme.textTheme.titleLarge : theme.textTheme.titleMedium)?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: HzSpace.s4),
                          Text(
                            [
                              ?device?.product,
                              s.devLineHops(formatLine(lineOf(widget.address)), widget.hops?.toString() ?? '—'),
                            ].join(metaSeparator),
                            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                          ),
                        ],
                      ),
                    ),
                    SoundAckButton(target: AckDevice(widget.address)),
                    if (widget.onClose != null) CloseDetailButton(onPressed: widget.onClose),
                  ],
                ),
                const SizedBox(height: Gap.inner),
                if (wide)
                  // Kennzahlen links, Aktionen rechts in einer Zeile.
                  Row(
                    spacing: HzSpace.s8,
                    children: [
                      Expanded(child: metrics),
                      ?mapButton,
                      ?filterButton,
                    ],
                  )
                else
                  metrics,
                if (device != null) ...[
                  const SizedBox(height: Gap.section),
                  deviceDrawing(
                    widget.address,
                    widget.log,
                    selected: pickChannel ? _channel : null,
                    onSelected: pickChannel ? (i) => setState(() => _channel = i) : null,
                  ),
                ],
                if (!wide) ...[
                  const SizedBox(height: Gap.section),
                  EvenRow(children: [?mapButton, ?filterButton]),
                ],
                const SizedBox(height: Gap.section),
                // Comments on this device from all sessions.
                ListenableBuilder(
                  listenable: AnnotationStore.instance,
                  builder: (context, _) {
                    final groups = {
                      for (final o in objectsOf(widget.address, CatalogStore.instance.catalog)) o.address,
                    };
                    final notes = AnnotationScope.forDevice(widget.address, groups);
                    if (notes.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Gap.section),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SectionTitle(s.annotationsCount(notes.length)),
                          for (final a in notes.take(5))
                            AnnotationTile(annotation: a, onEdit: () => editAnnotation(context, a)),
                          if (notes.length > 5)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => AnnotationsScreen(device: widget.address, groups: groups),
                                  ),
                                ),
                                child: Text(s.annotationsAll(notes.length)),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                if (withChannels)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Gap.section,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _Channels(channels: _channels, selected: _channel, log: widget.log),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: traffic),
                      ),
                    ],
                  )
                else
                  ...traffic,
              ],
            );
          },
        );
      },
    );
  }
}

/// Channels with their objects and current values: the selected channel or all
/// stacked, each with short name and label above.
class _Channels extends StatelessWidget {
  const _Channels({required this.channels, required this.selected, required this.log});

  final List<DeviceChannel> channels;
  final int? selected;
  final TelegramLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = selected == null ? channels : [channels[selected!]];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in shown.indexed) ...[
          if (i > 0) const SizedBox(height: Gap.item),
          Padding(
            padding: const EdgeInsets.only(bottom: HzSpace.s4),
            child: Text(
              [c.label.isEmpty ? s.deviceGeneral : c.label, ?c.title].join(metaSeparator),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          ChannelObjects(channel: c, latest: log.latest),
        ],
      ],
    );
  }
}

/// Telegram of the device: row with hairline, address, time and value in
/// Monaspace.
class _TrafficRow extends StatelessWidget {
  const _TrafficRow({required this.telegram, required this.showSource});

  final Telegram telegram;
  final bool showSource;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final data = context.hzTheme.data;
    final small = theme.textTheme.bodySmall;
    final store = CatalogStore.instance;
    final t = telegram;
    final name = store.info(t.destination)?.name;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
        child: Row(
          children: [
            TypeBadge(type: t.type, outgoing: t.outgoing, size: 22),
            const SizedBox(width: Gap.inner),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: t.destinationText, style: data),
                        if (name != null) TextSpan(text: '  $name'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [formatTime(t.time), if (showSource) t.sourceText].join(metaSeparator),
                    style: context.mono(small).copyWith(color: hz.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: HzSpace.s8),
            Text(
              t.type == TelegramType.read ? '' : store.value(t),
              style: data.copyWith(fontWeight: FontWeight.w600, color: hz.text),
            ),
          ],
        ),
      ),
    );
  }
}

/// Drawing of a device: with a manufacturer graphic or as a DIN-rail device the
/// actuator view (channel selection via [selected]/[onSelected]), otherwise the
/// drawing of its device kind (push button, push-button interface, detector,
/// weather).
Widget deviceDrawing(
  int address,
  TelegramLog log, {
  int? selected,
  ValueChanged<int?>? onSelected,
  bool compact = false,
}) {
  final catalog = CatalogStore.instance.catalog;
  final art = artFor(address);
  return switch (art != null ? DeviceShape.din : shapeOf(address, catalog)) {
    DeviceShape.pushButton => PushButtonView(button: pushButtonOf(address, catalog)!, log: log, compact: compact),
    DeviceShape.flushInput => FlushInputView(address: address, log: log, compact: compact),
    DeviceShape.ceilingPresence => PresenceView(address: address, log: log, compact: compact),
    DeviceShape.wallMotion => PresenceView(address: address, log: log, wall: true, compact: compact),
    DeviceShape.weatherStation => WeatherView(address: address, log: log, compact: compact),
    DeviceShape.smokeDetector => SmokeDetectorView(address: address, log: log, compact: compact),
    DeviceShape.din => ActuatorView(
      address: address,
      log: log,
      selected: selected,
      onSelected: onSelected,
      compact: compact,
    ),
  };
}

/// Channel of [device] that holds an object of group address [address]; `null`
/// if the device has no channels (push button, detector …).
int? channelAt(int device, int address) {
  final channels = deviceChannels(device);
  final i = channels.indexWhere((c) => c.label.isNotEmpty && c.objects.any((o) => o.address == address));
  return i < 0 ? null : i;
}

/// Whether [device] has a drawing: channels on [address] or a dedicated device
/// kind (push button, detector …).
bool hasDeviceDrawing(int device, int address) =>
    channelAt(device, address) != null || shapeOf(device, CatalogStore.instance.catalog) != DeviceShape.din;
