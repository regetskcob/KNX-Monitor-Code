import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../catalog_store.dart';
import '../export/pdf_export.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/device_label.dart';
import '../model/installation.dart';
import '../model/site_photos.dart';
import '../model/telegram_log.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'device_sheet.dart';
import 'figure_box.dart' show RowColumns;

/// Camera and scanning only on phone and tablet: the desktop apps have no
/// camera permission; in the add-on images are chosen as files.
bool get _hasCamera => !kIsWeb && const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);

/// Photo documentation of the distribution board and QR labels (Pro). Photos
/// stay on the device in the installation's folder.
class SiteDocsScreen extends StatefulWidget {
  const SiteDocsScreen({super.key, required this.log});

  final TelegramLog log;

  @override
  State<SiteDocsScreen> createState() => _SiteDocsScreenState();
}

class _SiteDocsScreenState extends State<SiteDocsScreen> {
  final _photos = SitePhotoStore.instance;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_photos.load());
  }

  Future<void> _store(Uint8List? bytes) async {
    if (bytes == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final jpeg = await compute(compressSitePhoto, bytes);
      final caption = mounted ? await _askCaption('') : null;
      await _photos.add(jpeg, caption: caption ?? '');
    } on SitePhotoQuotaExceeded {
      messenger.showSnackBar(SnackBar(content: Text(s.siteDocsQuota)));
    } on FormatException {
      messenger.showSnackBar(SnackBar(content: Text(s.siteDocsUnreadable)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _takePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.camera);
      await _store(await file?.readAsBytes());
    } on PlatformException catch (e) {
      // Camera denied or not available.
      debugPrint('Kamera: $e');
      messenger.showSnackBar(SnackBar(content: Text(s.boxScanNoCamera)));
    }
  }

  Future<void> _pickPhoto() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    await _store(await file?.readAsBytes());
  }

  Future<String?> _askCaption(String initial) async {
    final controller = TextEditingController(text: initial);
    final text = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.siteDocsCaption),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: s.siteDocsCaptionHint),
          ),
        ),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog)),
          horizontDialogAction(
            dialog,
            label: s.commonSave,
            primary: true,
            onPressed: () => Navigator.pop(dialog, controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    return text;
  }

  Future<void> _editCaption(SitePhoto photo) async {
    final text = await _askCaption(photo.caption);
    if (text != null) await _photos.setCaption(photo.id, text);
  }

  Future<void> _delete(SitePhoto photo) async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog.adaptive(
        title: Text(s.siteDocsDelete),
        actions: [
          horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog, false)),
          horizontDialogAction(
            dialog,
            label: s.commonDelete,
            primary: true,
            destructive: true,
            onPressed: () => Navigator.pop(dialog, true),
          ),
        ],
      ),
    );
    if (ok ?? false) await _photos.remove(photo.id);
  }

  /// Labels for the selected devices as PDF.
  Future<void> _labels(BuildContext button) async {
    final store = CatalogStore.instance;
    final all = deviceLabels(store.catalog, InstallationStore.instance.active.id);
    final picked = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LabelPicker(labels: all),
    );
    if (picked == null || picked.isEmpty || !mounted || !button.mounted) return;
    final labels = deviceLabels(store.catalog, InstallationStore.instance.active.id, only: picked);
    await sharePdf(button, () async => DeviceLabelsPdf(labels), pdfName(s.siteDocsLabelsPdf), origin: rectOf(button));
  }

  /// Scans a label and opens the device.
  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _LabelScanScreen()));
    if (text == null || !mounted) return;
    final installations = InstallationStore.instance;
    final result = resolveDeviceLabel(
      text,
      activeId: installations.active.id,
      nameOf: (id) => installations.byId(id)?.name,
    );
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case LabelOpenDevice(:final address):
        await showDeviceSheet(context, address: address, log: widget.log);
      case LabelOtherInstallation(:final installationName, :final address):
        messenger.showSnackBar(
          SnackBar(content: Text(s.siteDocsScanOther(formatIndividual(address), installationName))),
        );
      case LabelUnknownInstallation(:final address):
        messenger.showSnackBar(SnackBar(content: Text(s.siteDocsScanUnknown(formatIndividual(address)))));
      case LabelForeign():
        messenger.showSnackBar(SnackBar(content: Text(s.siteDocsScanForeign)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final hasDevices = CatalogStore.instance.catalog.devices.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(s.siteDocsTitle)),
      // Below expanded both cards one below the other in reading width; from there on the photos
      // as a grid of tiles on the left and the labels beside them, up to [Widths.wide].
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= Breakpoints.expanded;
          final inner = box.maxWidth.clamp(0, Widths.wide) - 2 * Gap.gutter;
          // The photo card takes two thirds of the row.
          final tiles = RowColumns.columnsFor(
            context,
            (inner - Gap.section) * 2 / 3 - 2 * Gap.card,
            _tileWidth,
            max: 4,
            gap: Gap.section,
          );
          Widget hint(String text) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
            ),
          );
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? Widths.wide : Widths.reading),
              child: ListenableBuilder(
                listenable: _photos,
                builder: (context, _) {
                  final photos = SectionCard(
                    title: s.siteDocsPhotos,
                    count: _photos.photos.length,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hint(s.siteDocsPhotosHint),
                        const SizedBox(height: Gap.item),
                        Wrap(
                          spacing: HzSpace.s8,
                          runSpacing: HzSpace.s8,
                          children: [
                            if (_hasCamera)
                              FilledButton.icon(
                                onPressed: _busy ? null : _takePhoto,
                                icon: const Icon(AppIcons.image, size: 18),
                                label: Text(s.siteDocsTakePhoto),
                              ),
                            OutlinedButton(onPressed: _busy ? null : _pickPhoto, child: Text(s.siteDocsPickPhoto)),
                          ],
                        ),
                        if (!wide)
                          for (final p in _photos.photos) _PhotoRow(photo: p, onEdit: _editCaption, onDelete: _delete)
                        else if (_photos.photos.isNotEmpty) ...[
                          const SizedBox(height: Gap.section),
                          CardGrid(
                            columns: tiles,
                            children: [
                              for (final p in _photos.photos)
                                _PhotoRow(
                                  key: ValueKey(p.id),
                                  photo: p,
                                  onEdit: _editCaption,
                                  onDelete: _delete,
                                  tile: true,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                  final labels = SectionCard(
                    title: s.siteDocsLabels,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        hint(hasDevices ? s.siteDocsLabelsHint : s.siteDocsLabelsNoProject),
                        const SizedBox(height: Gap.item),
                        Wrap(
                          spacing: HzSpace.s8,
                          runSpacing: HzSpace.s8,
                          children: [
                            Builder(
                              builder: (button) => FilledButton.icon(
                                onPressed: hasDevices ? () => _labels(button) : null,
                                icon: const Icon(AppIcons.qrCode, size: 18),
                                label: Text(s.siteDocsLabelsCreate),
                              ),
                            ),
                            if (_hasCamera)
                              OutlinedButton.icon(
                                onPressed: _scan,
                                icon: const Icon(AppIcons.qrScan, size: 18),
                                label: Text(s.siteDocsScan),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                  return ListView(
                    padding: Gap.page,
                    children: [
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: Gap.section,
                          children: [
                            Expanded(flex: 2, child: photos),
                            Expanded(child: labels),
                          ],
                        )
                      else ...[
                        photos,
                        const SizedBox(height: Gap.section),
                        labels,
                      ],
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  /// Minimum width of a photo tile in the grid.
  static const _tileWidth = 240.0;
}

class _PhotoRow extends StatefulWidget {
  const _PhotoRow({super.key, required this.photo, required this.onEdit, required this.onDelete, this.tile = false});

  /// A tile of the grid on wide windows: the picture large on top, caption and actions below.
  final bool tile;

  final SitePhoto photo;
  final ValueChanged<SitePhoto> onEdit;
  final ValueChanged<SitePhoto> onDelete;

  @override
  State<_PhotoRow> createState() => _PhotoRowState();
}

class _PhotoRowState extends State<_PhotoRow> {
  late final Future<Uint8List?> _bytes = SitePhotoStore.instance.read(widget.photo.id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.photo;
    final picture = FutureBuilder(
      future: _bytes,
      builder: (context, snapshot) => switch (snapshot.data) {
        final bytes? => ClipRRect(
          borderRadius: Radii.row,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            // The tile gives the size; the thumbnail of the row keeps the picture's own.
            width: widget.tile ? double.infinity : null,
            height: widget.tile ? double.infinity : null,
            semanticLabel: p.caption,
            errorBuilder: (_, _, _) => const Icon(AppIcons.image),
          ),
        ),
        null => const Icon(AppIcons.image),
      },
    );
    final caption = Text(p.caption.isEmpty ? s.siteDocsNoCaption : p.caption, style: theme.textTheme.bodyMedium);
    final actions = [
      IconButton(tooltip: s.siteDocsCaption, onPressed: () => widget.onEdit(p), icon: const Icon(AppIcons.edit)),
      IconButton(tooltip: s.siteDocsDelete, onPressed: () => widget.onDelete(p), icon: const Icon(AppIcons.delete)),
    ];
    if (widget.tile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(aspectRatio: 4 / 3, child: picture),
          const SizedBox(height: HzSpace.s4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: Gap.inner),
                  child: caption,
                ),
              ),
              ...actions,
            ],
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Gap.item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(dimension: 88, child: picture),
          const SizedBox(width: HzSpace.s12),
          Expanded(child: caption),
          ...actions,
        ],
      ),
    );
  }
}

/// Selection of the devices for the label sheet.
class _LabelPicker extends StatefulWidget {
  const _LabelPicker({required this.labels});

  final List<DeviceLabel> labels;

  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final _picked = {for (final l in widget.labels) l.address};

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DraggableScrollableSheet(
      expand: false,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.gutter),
            child: Wrap(
              spacing: HzSpace.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked),
                  child: Text(s.siteDocsLabelsCount(_picked.length)),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _picked.isEmpty ? _picked.addAll(widget.labels.map((l) => l.address)) : _picked.clear();
                  }),
                  child: Text(_picked.isEmpty ? s.siteDocsLabelsAll : s.siteDocsLabelsNone),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              children: [
                for (final l in widget.labels)
                  CheckboxListTile.adaptive(
                    value: _picked.contains(l.address),
                    onChanged: (v) => setState(() => v == true ? _picked.add(l.address) : _picked.remove(l.address)),
                    title: Text('${formatIndividual(l.address)}  ${l.function}'),
                    subtitle: l.place.isEmpty ? null : Text(l.place),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LabelScanScreen extends StatefulWidget {
  const _LabelScanScreen();

  @override
  State<_LabelScanScreen> createState() => _LabelScanScreenState();
}

class _LabelScanScreenState extends State<_LabelScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.siteDocsScan)),
    body: MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final text = capture.barcodes.firstOrNull?.rawValue;
        if (_done || text == null || text.isEmpty) return;
        _done = true;
        Navigator.pop(context, text);
      },
      errorBuilder: (context, error) => Center(
        child: HorizontEmptyHint(text: scannerProblem(error), status: HorizontStatus.warning),
      ),
    ),
  );
}
