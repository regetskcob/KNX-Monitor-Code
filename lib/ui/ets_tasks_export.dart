import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

import '../catalog_store.dart';
import '../export/ets_ga_export.dart';
import '../export/pdf_export.dart';
import '../export/widget_capture.dart';
import '../l10n/locale_controller.dart';
import '../model/betrieb_mode.dart';
import '../model/betrieb/standard_check_text.dart';
import '../model/device_art.dart';
import '../model/device_inventory.dart';
import '../model/ets_tasks.dart';
import '../model/export_history.dart';
import '../model/installation.dart';
import '../model/telegram_log.dart';
import '../platform/addon.dart';
import '../theme/app_theme.dart';
import 'actuator_view.dart';
import 'common.dart';
import 'filter_observations.dart';

/// Width of the device drawing when rendering (logical pixels): wide enough for
/// the channel cards left and right of the graphic.
const _drawingWidth = 900.0;

/// Exports the "tasks for ETS": a PDF with an overview and one page per device
/// (drawing with channel cards, tasks, channel mapping). If datapoint types
/// were changed in the app, the group address import for ETS is included as
/// well, and the result is a ZIP. Uses the share menu or save dialog like the
/// other exports.
Future<void> exportEtsTasks(BuildContext context, {Rect? origin, TelegramLog? log}) async {
  final messenger = ScaffoldMessenger.of(context);
  final store = CatalogStore.instance;
  final deviations = await standardDeviations(store);
  final observations = await loadFilterObservations(log);
  if (!context.mounted) return;
  final tasks = EtsTasks.of(
    store.project,
    Map.of(store.overrides),
    learned: store.learned,
    inventory: DeviceInventory.lastFor(InstallationStore.instance.active.id),
    deviations: deviations,
    observations: observations,
  );
  try {
    final (bytes, name, mime) = await withProgress(context, s.etsTasksBuilding, () async {
      final drawings = await _drawings(context, tasks);
      final pdf = await buildPdfInBackground(EtsTasksPdf(tasks, drawings: drawings));
      final pdfFile = pdfName(s.etsTasks);
      final xml = etsImportXml(tasks.imports, store.catalog.style);
      if (xml == null) return (pdf, pdfFile, 'application/pdf');
      final xmlBytes = utf8.encode(xml);
      final archive = Archive()
        ..addFile(ArchiveFile(pdfFile, pdf.length, pdf))
        ..addFile(ArchiveFile(fileName(s.etsImportFile, 'xml'), xmlBytes.length, xmlBytes));
      // Company edition: the same addresses also as CSV 3/1.
      if (Betrieb.enabled) {
        final csvBytes = etsCsvBytes(etsImportCsv(tasks.imports, store.catalog.style)!);
        archive.addFile(ArchiveFile(fileName(s.etsImportFile, 'csv'), csvBytes.length, csvBytes));
      }
      return (Uint8List.fromList(ZipEncoder().encode(archive)), fileName(s.etsTasks, 'zip'), 'application/zip');
    });
    unawaited(ExportHistory.instance.add(name, bytes, mime));
    if (!context.mounted) return;
    await shareFile(context, bytes, name, mime, origin: origin);
  } on Object catch (e, stack) {
    debugPrint('Aufgaben für die ETS fehlgeschlagen: $e\n$stack');
    messenger.showSnackBar(SnackBar(content: Text(s.exportFailed('$e'))));
  }
}

/// Drawing per device with tasks, in the light appearance (paper), without live
/// values. If one is missing, the page has no image.
Future<Map<int, Uint8List>> _drawings(BuildContext context, EtsTasks tasks) async {
  await DeviceArtCatalog.instance.load();
  final light = AppTheme.light(homeAssistant: Addon.embedded);
  final log = TelegramLog();
  final drawings = <int, Uint8List>{};
  for (final device in tasks.devices.keys) {
    if (!context.mounted) break;
    // Inventory-only devices have nothing to draw in the project.
    if (CatalogStore.instance.catalog.devices[device] == null) continue;
    final png = await captureWidget(
      context,
      Theme(
        data: light,
        child: MediaQuery.withNoTextScaling(
          child: Material(
            color: light.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ActuatorView(address: device, log: log),
            ),
          ),
        ),
      ),
      width: _drawingWidth,
      pixelRatio: 1.5,
      background: light.colorScheme.surface,
    );
    if (png != null) drawings[device] = png;
  }
  log.dispose();
  return drawings;
}
