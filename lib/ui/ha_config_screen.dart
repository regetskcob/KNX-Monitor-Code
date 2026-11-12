import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../catalog_store.dart';
import '../export/ha_config.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart' show RowColumns;

/// Home Assistant configuration from the ETS project: preview with selection by
/// rooms and types, uncertain mappings marked, device suggestions to accept,
/// output as `knx.yaml` to share or copy.
class HaConfigScreen extends StatefulWidget {
  const HaConfigScreen({super.key});

  @override
  State<HaConfigScreen> createState() => _HaConfigScreenState();
}

class _HaConfigScreenState extends State<HaConfigScreen> {
  late final List<HaEntity> _entities = HaConfig.fromCatalog(CatalogStore.instance.catalog);
  late final Set<String> _selected = {for (final e in _entities) e.id};
  late final List<HaDevice> _proposals = HaConfig.devices(_entities, CatalogStore.instance.catalog);

  /// Accepted device suggestions; none at first, the user decides.
  final Set<String> _devices = {};
  final _platforms = HaPlatform.values.toSet();
  Set<String>? _rooms;
  bool _onlyUncertain = false;
  bool _preview = false;
  String _version = '';

  static const _fileName = 'knx.yaml';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }, onError: (Object _) {});
  }

  String _room(HaEntity e) => e.room ?? s.haNoRoom;

  List<String> get _allRooms => {for (final e in _entities) _room(e)}.toList()..sort();

  bool _visible(HaEntity e) =>
      _platforms.contains(e.platform) &&
      (_rooms == null || _rooms!.contains(_room(e))) &&
      (!_onlyUncertain || e.uncertain);

  List<HaEntity> get _chosen => [
    for (final e in _entities)
      if (_visible(e) && _selected.contains(e.id)) e,
  ];

  List<HaDevice> get _acceptedDevices => [
    for (final d in _proposals)
      if (_devices.contains(d.id)) d,
  ];

  String _yaml() =>
      HaConfig.toYaml(_chosen, catalog: CatalogStore.instance.catalog, appVersion: _version, devices: _acceptedDevices);

  Future<void> _share(BuildContext buttonContext) async {
    final origin = rectOf(buttonContext);
    await shareFile(context, utf8.encode(_yaml()), _fileName, 'application/yaml', origin: origin);
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: _yaml()));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.haCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final visible = _entities.where(_visible).toList();
    final chosen = _chosen;
    final uncertain = chosen.where((e) => e.uncertain).length;
    final byRoom = <String, List<HaEntity>>{};
    for (final e in visible) {
      (byRoom[_room(e)] ??= []).add(e);
    }
    final names = {for (final e in _entities) e.id: e.name};
    final visibleIds = {for (final e in visible) e.id};
    final proposals = _proposals.where((d) => d.entities.any(visibleIds.contains)).toList();
    final deviceOf = {
      for (final d in _acceptedDevices)
        for (final id in d.entities) id: d,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(s.haTitle),
        actions: [
          IconButton(tooltip: s.haCopy, onPressed: chosen.isEmpty ? null : _copy, icon: const Icon(AppIcons.copy)),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: s.haShare,
              onPressed: chosen.isEmpty ? null : () => _share(buttonContext),
              icon: Icon(AppIcons.share),
            ),
          ),
        ],
      ),
      // Below expanded one list; from there on up to [Widths.wide]: explanation and key figures
      // beside the filters, device suggestions in columns, the rooms as blocks side by side.
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= Breakpoints.expanded;
          final intro = [
            Text(s.haExplain, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
            const SizedBox(height: Gap.inner),
            _WhereItGoes(addon: Addon.available),
            const SizedBox(height: Gap.section),
            // Key figures in the green box; the total is the main
            // value.
            SectionCard(
              soft: true,
              child: Wrap(
                spacing: HzSpace.s24,
                runSpacing: HzSpace.s12,
                children: [
                  _Figure(label: s.haEntities, value: formatInt(chosen.length), main: true),
                  _Figure(label: s.haUncertain, value: formatInt(uncertain)),
                  for (final p in HaPlatform.values)
                    if (chosen.any((e) => e.platform == p))
                      _Figure(label: p.title, value: formatInt(chosen.where((e) => e.platform == p).length)),
                ],
              ),
            ),
          ];
          final filters = [
            SectionTitle(s.haTypes),
            const SizedBox(height: Gap.item),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              children: [
                for (final p in HaPlatform.values)
                  if (_entities.any((e) => e.platform == p))
                    FilterChip(
                      label: Text(p.title),
                      selected: _platforms.contains(p),
                      onSelected: (on) => setState(() => on ? _platforms.add(p) : _platforms.remove(p)),
                    ),
                FilterChip(
                  avatar: Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                  label: Text(s.haOnlyUncertain),
                  selected: _onlyUncertain,
                  onSelected: (on) => setState(() => _onlyUncertain = on),
                ),
              ],
            ),
            const SizedBox(height: Gap.inner),
            SectionTitle(s.haRooms),
            const SizedBox(height: Gap.item),
            Wrap(
              spacing: HzSpace.s8,
              runSpacing: HzSpace.s8,
              children: [
                FilterChip(
                  label: Text(s.haAllRooms),
                  selected: _rooms == null,
                  onSelected: (_) => setState(() => _rooms = null),
                ),
                for (final r in _allRooms)
                  FilterChip(
                    label: Text(r),
                    selected: _rooms?.contains(r) ?? false,
                    onSelected: (on) => setState(() {
                      final rooms = _rooms ?? <String>{};
                      on ? rooms.add(r) : rooms.remove(r);
                      _rooms = rooms.isEmpty ? null : rooms;
                    }),
                  ),
              ],
            ),
          ];
          final deviceRows = [
            for (final d in proposals)
              _DeviceRow(
                device: d,
                members: [for (final id in d.entities) names[id] ?? id],
                accepted: _devices.contains(d.id),
                onChanged: (on) => setState(() => on ? _devices.add(d.id) : _devices.remove(d.id)),
              ),
          ];
          List<Widget> room(String name, List<HaEntity> list) => [
            SectionTitle(name, count: list.length),
            const SizedBox(height: Gap.item),
            for (final e in list)
              _EntityRow(
                entity: e,
                device: deviceOf[e.id],
                selected: _selected.contains(e.id),
                onChanged: (on) => setState(() => on ? _selected.add(e.id) : _selected.remove(e.id)),
              ),
          ];
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.dashboard),
              child: _entities.isEmpty
                  ? Padding(
                      padding: Gap.page,
                      child: Text(s.haEmpty, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
                    )
                  : ListView(
                      padding: Gap.page,
                      children: [
                        if (wide)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            spacing: Gap.section,
                            children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: intro),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: filters),
                              ),
                            ],
                          )
                        else ...[
                          ...intro,
                          const SizedBox(height: Gap.section),
                          ...filters,
                        ],
                        if (proposals.isNotEmpty) ...[
                          const SizedBox(height: Gap.section),
                          // Title left, both actions right; on a narrow phone or with large text the
                          // actions move below the title.
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SectionTitle(s.haDevices, count: proposals.length),
                              Wrap(
                                children: [
                                  // Both apply to the visible suggestions, like the filters above.
                                  TextButton(
                                    onPressed: () => setState(() => _devices.addAll(proposals.map((d) => d.id))),
                                    child: Text(s.haDevicesAll),
                                  ),
                                  TextButton(
                                    onPressed: proposals.any((d) => _devices.contains(d.id))
                                        ? () => setState(() => _devices.removeAll(proposals.map((d) => d.id)))
                                        : null,
                                    child: Text(s.haDevicesNone),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // The explanation does not run across a wide window.
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: Widths.dashboard),
                              child: Text(
                                s.haDevicesExplain,
                                style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                              ),
                            ),
                          ),
                          const SizedBox(height: Gap.item),
                          if (wide) _Lanes(children: deviceRows) else ...deviceRows,
                        ],
                        const SizedBox(height: Gap.section),
                        if (wide) ...[
                          CardColumns(
                            // A row is roughly as high as the heading with its gap; a doubt adds a line.
                            heights: [
                              for (final list in byRoom.values)
                                1 + list.fold(0, (sum, e) => sum + (e.uncertain ? 1.5 : 1)),
                            ],
                            children: [
                              for (final MapEntry(key: name, value: list) in byRoom.entries)
                                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: room(name, list)),
                            ],
                          ),
                          const SizedBox(height: Gap.section),
                        ] else
                          for (final MapEntry(key: name, value: list) in byRoom.entries) ...[
                            ...room(name, list),
                            const SizedBox(height: Gap.section),
                          ],
                        // Preview of the file as it will be shared.
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: () => setState(() => _preview = !_preview),
                            icon: Icon(_preview ? AppIcons.collapse : AppIcons.expand, size: 18),
                            label: Text(s.haPreview),
                          ),
                        ),
                        if (_preview)
                          SectionCard(
                            child: SelectableText(_yaml(), style: context.hzTheme.data.copyWith(fontSize: 12)),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}

/// Rows that draw their own hairline, in newspaper columns (down the first, then the next) as
/// soon as each is at least [Widths.column] wide.
class _Lanes extends StatelessWidget {
  const _Lanes({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = RowColumns.columnsFor(context, box.maxWidth, Widths.column).clamp(1, children.length);
      final perColumn = (children.length / columns).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: RowColumns.gap,
        children: [
          for (var i = 0; i < columns; i++)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children.skip(i * perColumn).take(perColumn).toList(),
              ),
            ),
        ],
      );
    },
  );
}

/// Where the file belongs; in the add-on with the path in the Home Assistant
/// folder.
class _WhereItGoes extends StatelessWidget {
  const _WhereItGoes({required this.addon});

  final bool addon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(AppIcons.info, size: HzIconSize.row, color: context.hz.textMuted),
          const SizedBox(width: Gap.inner),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(addon ? s.haWhereAddon : s.haWhere, style: theme.textTheme.bodyMedium),
                const SizedBox(height: HzSpace.s4),
                SelectableText('knx: !include knx.yaml', style: context.hzTheme.data),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// An entity with selection, platform and addresses; uncertain ones with a
/// symbol and reason (never color alone).
class _EntityRow extends StatelessWidget {
  const _EntityRow({required this.entity, required this.selected, required this.onChanged, this.device});

  final HaEntity entity;

  /// Accepted device the entity belongs to.
  final HaDevice? device;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final e = entity;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.name, style: theme.textTheme.bodyLarge),
                      Text(
                        [e.platform.key, for (final a in e.groups) formatGroup(a)].join(' · '),
                        style: context.mono(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                      ),
                      if (device != null)
                        Padding(
                          padding: const EdgeInsets.only(top: HzSpace.s4),
                          child: Row(
                            children: [
                              Icon(AppIcons.objects, size: 16, color: hz.textMuted),
                              const SizedBox(width: HzSpace.s4),
                              Expanded(
                                child: Text(
                                  s.haDeviceOf(device!.name),
                                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (e.uncertain)
                        Padding(
                          padding: const EdgeInsets.only(top: HzSpace.s4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(HorizontStatus.warning.icon, size: 16, color: hz.warning),
                              const SizedBox(width: HzSpace.s4),
                              Expanded(
                                child: Text(
                                  e.doubts.map((d) => d.text).join(' · '),
                                  style: theme.textTheme.bodySmall?.copyWith(color: hz.warning),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: HzSpace.s8),
                Switch.adaptive(value: selected, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Device suggestion with a switch: name, what it was detected by, and the
/// entities Home Assistant groups in it.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.members, required this.accepted, required this.onChanged});

  final HaDevice device;
  final List<String> members;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final d = device;
    final source = switch (d.source) {
      HaDeviceSource.nameScheme => s.haDeviceFromNames,
      HaDeviceSource.busDevice => s.haDeviceFromBus(d.name, formatIndividual(d.busAddress!)),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: hz.line, width: Lines.hairline),
        ),
      ),
      child: MergeSemantics(
        child: InkWell(
          onTap: () => onChanged(!accepted),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: HzSpace.s8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(AppIcons.objects, size: HzIconSize.row, color: hz.textMuted),
                const SizedBox(width: Gap.inner),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.name, style: theme.textTheme.bodyLarge),
                      Text(
                        [if (d.room != null && d.room != d.name) d.room!, source].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                      ),
                      Text(members.join(' · '), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(width: HzSpace.s8),
                Switch.adaptive(value: accepted, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Key figure of the green box: label, the value below.
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.main = false});

  final String label;
  final String value;
  final bool main;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final hz = context.hz;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.bodySmall?.copyWith(color: hz.accentText)),
        Text(
          value,
          style: context
              .figures(main ? theme.titleLarge : theme.titleMedium)
              .copyWith(color: main ? hz.accentText : hz.text, fontWeight: main ? FontWeight.w700 : FontWeight.w600),
        ),
      ],
    );
  }
}
