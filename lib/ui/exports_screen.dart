import 'dart:async';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../export/telegram_files.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/commissioning.dart';
import '../model/expert_mode.dart';
import '../model/export_history.dart';
import '../model/health.dart';
import '../model/plan.dart';
import '../model/statistics.dart';
import '../model/telegram_log.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'ai_access_screen.dart';
import 'common.dart';
import 'data_export_screen.dart';
import 'figure_box.dart';
import 'plan_screen.dart';
import 'telegram_row.dart';
import 'tool_shell.dart';

/// All exports in one place: monitor telegrams, the tools' reports, a full
/// export as ZIP, and the installation's most recently created files for
/// sharing again. Wide layouts use two columns: create on the left, recent
/// files on the right.
class ExportsScreen extends StatefulWidget {
  const ExportsScreen({
    super.key,
    required this.log,
    required this.title,
    this.note,
    this.gateway,
    this.onSelect,
    this.installationReports = true,
    this.tunnel,
  });

  /// Bus connection: health and commissioning can be checked from here while it
  /// is established.
  final KnxTunnel? tunnel;

  /// Whether to offer the installation's health and commissioning (in the
  /// monitor, not in a recording, which they don't belong to).
  final bool installationReports;

  final TelegramLog log;

  /// Title of the telegram exports (monitor or recording).
  final String title;
  final String? note;
  final String? gateway;

  /// Select telegrams: back to the monitor, in selection mode.
  final VoidCallback? onSelect;

  @override
  State<ExportsScreen> createState() => _ExportsScreenState();
}

/// What can be exported; one file per entry.
enum _Item { telegramsPdf, telegramsCsv, telegramsEts, statistics, health, commissioning }

class _ExportsScreenState extends State<ExportsScreen> {
  final _bundle = <_Item>{_Item.telegramsPdf, _Item.statistics};

  List<Telegram> get _telegrams => widget.log.log;
  HealthRun? get _health => HealthCheck.instance.last;
  Commissioning get _comm => Commissioning.instance;

  List<_Item> get _reportItems => [
    _Item.statistics,
    if (widget.installationReports) ...[_Item.health, _Item.commissioning],
  ];

  List<_Item> get _items => [_Item.telegramsPdf, _Item.telegramsCsv, _Item.telegramsEts, ..._reportItems];

  bool _available(_Item item) => switch (item) {
    _Item.telegramsPdf || _Item.telegramsCsv || _Item.telegramsEts || _Item.statistics => _telegrams.isNotEmpty,
    _Item.health => _health != null,
    _Item.commissioning => _comm.items.isNotEmpty,
  };

  String _label(_Item item) => switch (item) {
    _Item.telegramsPdf => s.exportAllPdf,
    _Item.telegramsCsv => s.exportAllCsv,
    _Item.telegramsEts => s.exportAllEts,
    _Item.statistics => s.statsPdfTitle,
    _Item.health => s.healthPdfTitle,
    _Item.commissioning => s.commPdfTitle,
  };

  String _state(_Item item) {
    if (!_available(item)) return s.exportsNoData;
    return switch (item) {
      _Item.telegramsPdf ||
      _Item.telegramsCsv ||
      _Item.telegramsEts ||
      _Item.statistics => s.telegramCount(_telegrams.length),
      _Item.health => s.exportsHealthRun(
        '${formatDate(_health!.time)} ${formatTime(_health!.time, millis: false)}',
        _health!.findings.length,
      ),
      _Item.commissioning => s.exportsCommState(_comm.checked, _comm.items.length),
    };
  }

  /// File name and type of an entry.
  (String, String) _file(_Item item) => switch (item) {
    _Item.telegramsPdf => (pdfName(widget.title), 'application/pdf'),
    _Item.telegramsCsv => (fileName(widget.title, 'csv'), 'text/csv'),
    _Item.telegramsEts => (fileName(widget.title, 'xml'), 'application/xml'),
    _Item.statistics => (pdfName(s.statsPdfTitle), 'application/pdf'),
    _Item.health => (pdfName(s.healthPdfTitle), 'application/pdf'),
    _Item.commissioning => (pdfName(s.commPdfTitle), 'application/pdf'),
  };

  PdfJob? _job(_Item item) => switch (item) {
    _Item.telegramsPdf => TelegramPdf(
      List.of(_telegrams),
      gateway: widget.gateway,
      title: widget.title,
      note: widget.note,
    ),
    _Item.statistics => StatisticsPdf(BusStatistics.of(widget.log), gateway: widget.gateway),
    _Item.health => HealthPdf(_health!, gateway: widget.gateway),
    _Item.commissioning => CommissioningPdf(_comm, gateway: widget.gateway),
    _Item.telegramsCsv || _Item.telegramsEts => null,
  };

  /// Content of an entry: PDFs in the background, texts directly.
  Future<Uint8List> _bytes(_Item item) async => switch (item) {
    _Item.telegramsCsv => csvBytes(buildCsv(_telegrams)),
    _Item.telegramsEts => utf8Bytes(buildEtsXml(_telegrams, host: widget.gateway)),
    _ => buildPdfInBackground(_job(item)!),
  };

  Future<void> _export(_Item item, Rect? origin) async {
    // Your own log and the telegrams as CSV and simple PDF are always
    // exportable, even after a subscription ends.
    const free = {_Item.commissioning, _Item.telegramsPdf, _Item.telegramsCsv};
    if (!free.contains(item) && !await unlock(context, Feature.export) || !mounted) return;
    final (name, mime) = _file(item);
    if (_job(item) case final job?) {
      await sharePdf(context, () async => job, name, origin: origin);
    } else {
      final bytes = await _bytes(item);
      if (!mounted) return;
      await saveBytes(context, bytes, name, mimeType: mime);
    }
  }

  Future<void> _exportBundle(Rect? origin) async {
    if (!await unlock(context, Feature.export) || !mounted) return;
    final items = [
      for (final item in _items)
        if (_bundle.contains(item) && _available(item)) item,
    ];
    try {
      final zip = await withProgress(context, s.exportsBuilding, () async {
        final archive = Archive();
        for (final item in items) {
          final bytes = await _bytes(item);
          archive.addFile(ArchiveFile(_file(item).$1, bytes.length, bytes));
        }
        return Uint8List.fromList(ZipEncoder().encode(archive));
      });
      final name = fileName(widget.title, 'zip');
      unawaited(ExportHistory.instance.add(name, zip, 'application/zip'));
      if (!mounted) return;
      await shareFile(context, zip, name, 'application/zip', origin: origin);
    } on Object catch (e, stack) {
      debugPrint('Gesamtexport fehlgeschlagen: $e\n$stack');
      if (mounted) showHorizontMessage(context, s.exportFailedGeneric, status: HorizontStatus.critical);
    }
  }

  /// Check button for health and commissioning; `null` for the others.
  Widget? _checkButton(_Item item) {
    if (item != _Item.health && item != _Item.commissioning) return null;
    final tunnel = widget.tunnel;
    final open = _comm.items.values.where((i) => i.state == CheckState.open || i.state == CheckState.noAnswer);
    final (running, label) = item == _Item.health
        ? (HealthCheck.instance.running, _health == null ? s.exportsCheck : s.exportsRecheck)
        // Commissioning: only open items; manually set results are kept.
        : (_comm.running, _comm.items.isEmpty ? s.exportsCheck : s.exportsCheckOpen);
    if (item == _Item.commissioning &&
        (CatalogStore.instance.catalog.isEmpty || (_comm.items.isNotEmpty && open.isEmpty && !running))) {
      return null;
    }
    if (running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: HzSpace.s8,
        children: [
          const SizedBox.square(dimension: 16, child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection)),
          Text(s.exportsChecking),
        ],
      );
    }
    final online = tunnel != null && tunnel.state.value == TunnelState.connected;
    return Tooltip(
      message: online ? label : s.exportsCheckOffline,
      child: OutlinedButton(onPressed: online ? () => _check(item, tunnel) : null, child: Text(label)),
    );
  }

  /// Starts the check without leaving the page: health with a read test,
  /// commissioning with the checklist as in the tool (status addresses).
  Future<void> _check(_Item item, KnxTunnel tunnel) async {
    switch (item) {
      case _Item.health:
        await HealthCheck.instance.load();
        await HealthCheck.instance.run(tunnel, widget.log);
      case _Item.commissioning:
        if (!await unlock(context, Feature.commissioning) || !mounted) return;
        await _comm.load();
        if (_comm.items.isEmpty) _comm.prepare(commissioningScope());
        await _comm.read(tunnel, [
          for (final i in _comm.items.values)
            if (i.state == CheckState.open || i.state == CheckState.noAnswer) i.address,
        ]);
      default:
        break;
    }
  }

  /// The server's continuous recording as an ETS file: choose the period, then
  /// download (in the browser straight to disk, natively via the save dialog).
  Future<void> _exportEtsHistory() async {
    if (!await unlock(context, Feature.export) || !mounted) return;
    final days = await showDialog<int>(context: context, builder: (_) => const _EtsHistoryDialog());
    if (days == null || !mounted) return;
    final now = DateTime.now();
    // Whole days like the long-term statistics: today and the days before.
    final from = DateTime(now.year, now.month, now.day - (days - 1));
    final all = days == _EtsHistoryDialog.all;
    final messenger = ScaffoldMessenger.of(context);
    try {
      Future<Uint8List?> load() => all ? Addon.etsHistoryAll() : Addon.etsHistory(from, now);
      final bytes = Addon.embedded ? await load() : await withProgress(context, s.exportsEtsHistoryLoading, load);
      if (bytes == null || !mounted) return;
      await saveBytes(
        context,
        bytes,
        all ? Addon.etsHistoryAllFileName(now) : Addon.etsHistoryFileName(from, now),
        mimeType: all ? 'application/zip' : 'application/xml',
      );
    } on AddonException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.exportFailed(e.message))));
    }
  }

  Future<void> _reshare(ExportEntry entry, Rect? origin) async {
    final bytes = await ExportHistory.instance.read(entry);
    if (!mounted) return;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.exportsGone)));
      return;
    }
    await shareFile(context, bytes, entry.name, entry.mimeType, origin: origin);
  }

  // Build everything inside the builder: monitor, checks and connection change
  // rows, buttons and "Läuft …" (running).
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.log, HealthCheck.instance, Commissioning.instance, ?widget.tunnel?.state]),
    builder: (context, _) => _page(context),
  );

  Widget _page(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final muted = theme.textTheme.bodySmall?.copyWith(color: hz.textFaint);
    final width = MediaQuery.sizeOf(context).width;
    final gutter = Gap.gutterFor(width);
    // Zwei Spalten, sobald zwei Kartenspalten passen (iPad quer, Mac).
    final columns = width.clamp(0, Widths.wide + 2 * gutter) - 2 * gutter >= 2 * Widths.column + Gap.section * 2;
    final side =
        gutter + ((width - 2 * gutter - (columns ? Widths.wide : Widths.reading)) / 2).clamp(0, double.infinity);

    Widget row(_Item item) => Builder(
      builder: (rowContext) {
        final available = _available(item);
        final check = _checkButton(item);
        return CardRow(
          // Not exportable without data, but it can still be checked.
          enabled: available || check != null,
          title: _label(item),
          meta: _state(item),
          chevron: available,
          trailing: check,
          onTap: available ? () => _export(item, rectOf(rowContext)) : null,
        );
      },
    );

    final telegrams = RowCard(
      children: [
        for (final item in [_Item.telegramsPdf, _Item.telegramsCsv, _Item.telegramsEts]) row(item),
        if (widget.onSelect case final onSelect?)
          CardRow(enabled: _telegrams.isNotEmpty, title: s.exportSelect, meta: s.exportSelectHint, onTap: onSelect),
      ],
    );

    final reports = RowCard(children: [for (final item in _reportItems) row(item)]);

    final selected = [
      for (final item in _items)
        if (_bundle.contains(item) && _available(item)) item,
    ];
    final bundle = SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.exportsBundleHint, style: muted),
          const SizedBox(height: HzSpace.s8),
          for (final item in _items)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              enabled: _available(item),
              value: _bundle.contains(item) && _available(item),
              title: Text(_label(item)),
              onChanged: (v) => setState(() => v! ? _bundle.add(item) : _bundle.remove(item)),
            ),
          const SizedBox(height: HzSpace.s12),
          Builder(
            builder: (buttonContext) => FilledButton(
              onPressed: selected.isEmpty ? null : () => _exportBundle(rectOf(buttonContext)),
              child: Text(s.exportsBundleButton(selected.length)),
            ),
          ),
        ],
      ),
    );

    final recent = ListenableBuilder(
      listenable: ExportHistory.instance,
      builder: (context, _) {
        final entries = ExportHistory.instance.entries;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHead(s.exportsRecent, count: entries.length),
            if (entries.isEmpty)
              Text(s.exportsRecentEmpty(ExportHistory.keep), style: muted)
            else
              RowCard(
                flat: true,
                children: [
                  for (final e in entries)
                    Builder(
                      builder: (rowContext) => CardRow(
                        title: e.name,
                        meta:
                            '${formatDate(e.time)} ${formatTime(e.time, millis: false)}$metaSeparator${formatSize(e.size)}',
                        onTap: () => _reshare(e, rectOf(rowContext)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppIcons.share, size: HzIconSize.row, color: hz.textMuted),
                            IconButton(
                              tooltip: s.exportsRemove,
                              icon: const Icon(AppIcons.delete, size: HzIconSize.row),
                              onPressed: () => ExportHistory.instance.remove(e),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );

    // Only with the add-on or box server, which records continuously; the data
    // export as in the menu only in expert mode.
    final permanent = Addon.available;
    final continuous = RowCard(
      children: [
        CardRow(title: s.exportsEtsHistory, meta: s.exportsEtsHistoryMeta, chevron: true, onTap: _exportEtsHistory),
        // AI access to the recording (MCP server of the add-on or box); the server lets only an
        // admin change it.
        CardRow(
          title: s.aiAccessTitle,
          meta: s.aiAccessMeta,
          chevron: true,
          onTap: () => pushTool<void>(context, (_) => const AiAccessScreen()),
        ),
        if (expert)
          CardRow(
            title: s.dataExportTitle,
            meta: '${s.dataExportInflux}$metaSeparator${s.dataExportPrometheus}',
            onTap: () => pushTool<void>(context, (_) => const DataExportScreen()),
          ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(s.exportsTitle)),
      body: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(side, 0, side, Gap.page.bottom),
          children: [
            if (columns)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.section * 2,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SectionHead(s.exportsData, count: _telegrams.length),
                        telegrams,
                        SectionHead(s.exportsReports),
                        reports,
                        if (permanent) ...[SectionHead(s.exportsPermanent), continuous],
                        SectionHead(s.exportsBundle),
                        bundle,
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [recent]),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionHead(s.exportsData, count: _telegrams.length),
                  telegrams,
                  SectionHead(s.exportsReports),
                  reports,
                  if (permanent) ...[SectionHead(s.exportsPermanent), continuous],
                  SectionHead(s.exportsBundle),
                  bundle,
                  recent,
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Period of the ETS history download, in whole days like the long-term
/// statistics; the server delivers at most 31 days.
class _EtsHistoryDialog extends StatefulWidget {
  const _EtsHistoryDialog();

  /// Choice for the whole history (a zip with one file per day).
  static const all = 0;

  static const choices = [1, 7, 30, all];

  @override
  State<_EtsHistoryDialog> createState() => _EtsHistoryDialogState();
}

class _EtsHistoryDialogState extends State<_EtsHistoryDialog> {
  int _days = 7;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(s.exportsEtsHistory),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.exportsEtsHistoryHint, style: theme.textTheme.bodyMedium),
          const SizedBox(height: HzSpace.s16),
          // Chips like the history settings: they wrap on the phone.
          Wrap(
            spacing: HzSpace.s8,
            runSpacing: HzSpace.s8,
            children: [
              for (final d in _EtsHistoryDialog.choices)
                ChoiceChip(
                  showCheckmark: false,
                  label: Text(d == _EtsHistoryDialog.all ? s.exportsEtsHistoryAll : s.historyDays(d)),
                  selected: _days == d,
                  onSelected: (_) => setState(() => _days = d),
                ),
            ],
          ),
          if (_days == _EtsHistoryDialog.all) ...[
            const SizedBox(height: HzSpace.s16),
            Text(s.exportsEtsHistoryAllHint, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.exportsEtsHistoryCancel)),
        FilledButton(onPressed: () => Navigator.pop(context, _days), child: Text(s.exportsEtsHistoryDownload)),
      ],
    );
  }
}

/// Short file size: "840 KB", "2,4 MB".
String formatSize(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} KB';
  return '${localizeDecimal((bytes / 1024 / 1024).toStringAsFixed(1))} MB';
}
