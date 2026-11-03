import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../model/installation.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/device_inventory.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'statistics_screen.dart' show FigureBox;

String inventoryStatusText(InventoryStatus st) => switch (st) {
  InventoryStatus.match => s.invMatch,
  InventoryStatus.present => s.invPresent,
  InventoryStatus.serialMismatch => s.invSerialMismatch,
  InventoryStatus.notInProject => s.invNotInProject,
  InventoryStatus.tunnel => s.invTunnel,
  InventoryStatus.missing => s.invMissing,
  InventoryStatus.unknown => s.invUnknown,
};

HorizontStatus _status(InventoryStatus st) => switch (st) {
  InventoryStatus.match || InventoryStatus.tunnel => HorizontStatus.positive,
  InventoryStatus.serialMismatch || InventoryStatus.notInProject || InventoryStatus.missing => HorizontStatus.warning,
  InventoryStatus.present || InventoryStatus.unknown => HorizontStatus.neutral,
};

/// Manufacturer from the project; without a project the ID in readable form
/// ("Hersteller 0x0083"). The app has no table of KNX manufacturer IDs of its
/// own.
String _manufacturer(int id) =>
    CatalogStore.instance.catalog.manufacturers[id] ??
    s.invManufacturerId('0x${id.toRadixString(16).toUpperCase().padLeft(4, '0')}');

/// A diagnostics tool: title and short explanation with the main action to the
/// right; inputs and results below at full width.
class DiagnosticTool extends StatelessWidget {
  const DiagnosticTool({
    super.key,
    required this.title,
    required this.text,
    this.action,
    this.controls,
    this.children = const [],
  });

  final String title;
  final String text;

  /// Main action next to the title; tools with a field put it in [controls].
  final Widget? action;
  final Widget? controls;
  final List<Widget> children;

  /// From this text scale factor on, text and main action are stacked.
  static const _stackAboveScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: HzSpace.s2),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
      ],
    );
    // Large text: the button goes below the text, otherwise the title breaks
    // mid-word.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > _stackAboveScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stacked) ...[
          intro,
          if (action != null) Align(alignment: AlignmentDirectional.centerStart, child: action),
        ] else
          Row(
            spacing: HzSpace.s8,
            children: [
              Expanded(child: intro),
              ?action,
            ],
          ),
        if (controls != null) ...[const SizedBox(height: HzSpace.s12), controls!],
        ...children,
      ],
    );
  }
}

/// Inputs of a scan: line and device range, stacked when narrow.
class ScanControls extends StatelessWidget {
  const ScanControls({super.key, required this.line, required this.range});

  final Widget line;
  final Widget range;

  /// Below this, field and range are stacked (large text, narrow phones).
  static const _stackBelow = 300.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => c.maxWidth < _stackBelow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.item,
            children: [
              Align(alignment: AlignmentDirectional.centerStart, child: line),
              range,
            ],
          )
        : Row(
            spacing: Gap.inner,
            children: [
              line,
              Expanded(child: range),
            ],
          ),
  );
}

/// Device inventory of a line in diagnostics: check addresses at a throttled
/// rate, read properties, match against the project. Read-only.
class InventoryCard extends StatefulWidget {
  const InventoryCard({super.key, required this.tunnel, this.initial});

  final KnxTunnel tunnel;

  /// Inventory that has already run (images for store and PR).
  @visibleForTesting
  final DeviceInventory? initial;

  @override
  State<InventoryCard> createState() => _InventoryCardState();
}

class _InventoryCardState extends State<InventoryCard> {
  final _line = TextEditingController(text: '1.1');
  RangeValues _range = const RangeValues(1, 64);
  late DeviceInventory? _run = widget.initial;
  final _idle = ValueNotifier(0);
  String? _error;

  @override
  void dispose() {
    _run?.cancel();
    _run?.dispose();
    _idle.dispose();
    _line.dispose();
    super.dispose();
  }

  void _start() {
    final parts = _line.text.trim().split('.').map(int.tryParse).toList();
    if (parts.length != 2 || parts.any((p) => p == null || p < 0 || p > 15)) {
      setState(() => _error = s.scanInvalidLine);
      return;
    }
    _run?.dispose();
    setState(() {
      _error = null;
      _run = DeviceInventory(
        widget.tunnel,
        area: parts[0]!,
        line: parts[1]!,
        from: _range.start.round(),
        to: _range.end.round(),
        catalog: CatalogStore.instance.catalog,
        installation: InstallationStore.instance.active.id,
      )..start();
    });
  }

  Future<void> _share(BuildContext buttonContext, DeviceInventory run) async {
    final origin = rectOf(buttonContext);
    final csv = run.toCsv(statusText: inventoryStatusText, manufacturer: _manufacturer);
    await shareFile(context, utf8.encode('﻿$csv'), fileName(s.invFileName, 'csv'), 'text/csv', origin: origin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _run ?? _idle,
      builder: (context, _) {
        final run = _run;
        final busy = run?.running == true;
        final hasProject = CatalogStore.instance.catalog.devices.isNotEmpty;
        return DiagnosticTool(
          title: s.invTitle,
          text: s.invExplain,
          action: busy
              ? TextButton(onPressed: run!.cancel, child: Text(s.commonCancel))
              : TextButton(onPressed: _start, child: Text(s.invStart)),
          controls: Builder(
            builder: (context) {
              final line = SizedBox(
                width: 110,
                child: HorizontField(
                  label: s.scanLine,
                  child: TextField(
                    style: context.hzTheme.field,
                    controller: _line,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                    inputFormatters: const [dotForComma],
                    decoration: InputDecoration(errorText: _error, isDense: true),
                  ),
                ),
              );
              final range = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.scanRange(_range.start.round(), _range.end.round()), style: theme.textTheme.bodySmall),
                  RangeSlider(
                    values: _range,
                    min: 0,
                    max: 255,
                    divisions: 255,
                    onChanged: busy ? null : (v) => setState(() => _range = v),
                  ),
                ],
              );
              return ScanControls(line: line, range: range);
            },
          ),
          children: [
            if (run != null) ...[
              const SizedBox(height: Gap.inner),
              LinearProgressIndicator(value: run.progress, minHeight: HzSpace.s4, borderRadius: Radii.row),
              const SizedBox(height: Gap.inner),
              FigureBox(
                figures: [
                  (s.invFound, formatInt(run.entries.where((e) => e.status != InventoryStatus.missing).length)),
                  (s.scanChecked, '${run.checked} / ${run.total}'),
                  if (hasProject) ...[
                    (s.invNotInProject, formatInt(run.count(InventoryStatus.notInProject))),
                    (s.invSerialMismatch, formatInt(run.count(InventoryStatus.serialMismatch))),
                    if (run.done) (s.invMissing, formatInt(run.count(InventoryStatus.missing))),
                  ],
                ],
              ),
              if (run.entries.isNotEmpty) ...[
                const SizedBox(height: Gap.item),
                for (final (i, e) in run.entries.indexed) ...[
                  if (i > 0) const Divider(height: Lines.hairline),
                  _EntryRow(entry: e),
                ],
              ],
              if (run.done && run.entries.isNotEmpty) ...[
                const SizedBox(height: Gap.inner),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Builder(
                    builder: (buttonContext) => OutlinedButton.icon(
                      onPressed: () => _share(buttonContext, run),
                      icon: const Icon(AppIcons.table, size: 18),
                      label: Text(s.invShare),
                    ),
                  ),
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final InventoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final e = entry;
    final d = e.details;
    final st = _status(e.status);
    final program = d?.program;
    final facts = [
      if (d?.manufacturerId case final id?) _manufacturer(id),
      ?d?.orderInfo,
      if (d?.serial case final serial?) 'SN $serial',
      // For many devices 0 means "not set" (A14: all MDT "0.0").
      if (d != null) 'FW ${firmwareText(d.firmware)}',
      if (program != null)
        'App ${program.deviceType.toRadixString(16).toUpperCase().padLeft(4, '0')} v${program.version}',
      if (e.maskVersion case final m?) s.diagMaskVersion(m.toRadixString(16).toUpperCase().padLeft(4, '0')),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HzSpace.s12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(st.icon, size: HzIconSize.row, color: st.color(hz)),
          const SizedBox(width: Gap.inner),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressTitle([formatIndividual(e.address), ?e.project?.name].join('  ')),
                Text(
                  inventoryStatusText(e.status) +
                      (e.status == InventoryStatus.serialMismatch && e.projectSerial != null
                          ? ' · ${s.devSerialMismatch(e.projectSerial!)}'
                          : ''),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: st == HorizontStatus.warning ? hz.warning : hz.textMuted,
                  ),
                ),
                if (facts.isNotEmpty)
                  SelectableText(
                    facts.join(' · '),
                    style: context.figures(theme.textTheme.bodySmall).copyWith(color: hz.textFaint),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
