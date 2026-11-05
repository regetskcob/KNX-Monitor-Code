import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../export/pdf_export.dart';
import '../model/export_history.dart';
import '../knx/group_catalog.dart';
import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';

/// Card in Horizont style: `surface` fill, hairline, radius 10, a label as
/// heading on top (optionally with a count). Use sparingly: lists do not need a
/// card per row.
/// Section title: green bar, title, count.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.count, this.maxLines = 2});

  final String title;
  final int? count;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 15,
          decoration: BoxDecoration(color: hz.accent, borderRadius: Radii.row),
        ),
        const SizedBox(width: HzSpace.s8),
        Flexible(
          child: Text(title, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
        ),
        if (count != null) ...[
          const SizedBox(width: HzSpace.s8),
          Text(formatInt(count!), style: context.figures(theme.textTheme.bodyMedium).copyWith(color: hz.textFaint)),
        ],
      ],
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.count,
    this.trailing,
    required this.child,
    this.soft = false,
    this.flat = false,
    this.padding,
  });

  final String? title;

  /// Count after the label ("ALARME & STÖRUNGEN · 1").
  final int? count;
  final Widget? trailing;
  final Widget child;

  /// Green box instead of a hairline for key figures and summaries.
  final bool soft;

  /// Without fill, frame or padding, for sidebars whose sections are separated
  /// only by label and hairlines.
  final bool flat;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    // Material instead of DecoratedBox: lists/tiles inside show their press
    // feedback.
    return Material(
      color: flat ? Colors.transparent : (soft ? hz.accentTint : hz.surface),
      shape: RoundedRectangleBorder(
        borderRadius: soft ? Radii.box : Radii.card,
        side: soft || flat ? BorderSide.none : BorderSide(color: hz.line, width: Lines.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? (flat ? EdgeInsets.zero : const EdgeInsets.all(Gap.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null || trailing != null) ...[
              Row(
                children: [
                  if (title != null) Expanded(child: SectionTitle(title!, count: count)),
                  ?trailing,
                ],
              ),
              const SizedBox(height: Gap.inner),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Runs [work] and meanwhile shows a non-dismissible dialog with [label] and a
/// spinner; it also closes on errors.
Future<T> withProgress<T>(BuildContext context, String label, Future<T> Function() work) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var showing = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialog) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator.adaptive(),
              const SizedBox(width: HzSpace.s16),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      ),
    ).whenComplete(() => showing = false),
  );
  try {
    return await work();
  } finally {
    if (showing) navigator.pop();
    showing = false;
  }
}

/// Creates the PDF of a job in the background and then opens the share menu.
/// [job] may prepare something first (chart image). While it is being created,
/// a dialog shows progress; every error ends as a message. [origin] anchors the
/// popover on the iPad.
/// Linux and Windows have no share menu (printing only puts the PDF into the
/// temp folder there and opens it), so they get the save dialog instead.
Future<void> sharePdf(BuildContext context, Future<PdfJob> Function() job, String filename, {Rect? origin}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  try {
    final bytes = await withProgress(context, s.pdfBuilding, () async => buildPdfInBackground(await job()));
    if (!kIsWeb && const {TargetPlatform.linux, TargetPlatform.windows}.contains(defaultTargetPlatform)) {
      if (!context.mounted) return;
      return await saveBytes(context, bytes, filename, mimeType: 'application/pdf');
    }
    unawaited(ExportHistory.instance.add(filename, bytes, 'application/pdf'));
    await Printing.sharePdf(bytes: bytes, filename: filename, bounds: origin);
  } on Object catch (e, stack) {
    // Also report programming errors (Error), not just exceptions: otherwise
    // the button would give no feedback at all.
    debugPrint('PDF fehlgeschlagen: $e\n$stack');
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.pdfExportFailedGeneric, status: HorizontStatus.critical));
  }
}

/// Screen rectangle of a widget (for popover anchors).
Rect? rectOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  return box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
}

/// File name with timestamp, e.g. "KNX-Telegramme 2026-10-14 15-40.pdf".
String pdfName(String prefix) {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final safe = prefix.replaceAll(RegExp(r'[/\\:*?"<>|]'), '-');
  return '$safe ${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}-${two(n.minute)}.pdf';
}

/// Saves [bytes] via the system dialog (Files app, iCloud …).
Future<void> saveBytes(BuildContext context, Uint8List bytes, String fileName, {String mimeType = 'text/plain'}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  try {
    final uri = await FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
    if (uri != null) {
      messenger.showSnackBar(SnackBar(content: Text(s.exportSaved(fileName))));
      unawaited(ExportHistory.instance.add(fileName, bytes, mimeType));
    }
  } on Exception catch (e) {
    debugPrint('Speichern fehlgeschlagen: $e');
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.exportFailedGeneric, status: HorizontStatus.critical));
  }
}

/// Shares a finished file again (from the recent exports): PDF via the print
/// share menu, everything else via the system share menu; Linux and Windows
/// save instead of sharing.
Future<void> shareFile(BuildContext context, Uint8List bytes, String name, String mimeType, {Rect? origin}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  try {
    if (!kIsWeb && const {TargetPlatform.linux, TargetPlatform.windows}.contains(defaultTargetPlatform)) {
      final uri = await FilePicker.saveFile(fileName: name, bytes: bytes, mimeType: mimeType);
      if (uri != null) messenger.showSnackBar(SnackBar(content: Text(s.exportSaved(name))));
      return;
    }
    if (mimeType == 'application/pdf') {
      await Printing.sharePdf(bytes: bytes, filename: name, bounds: origin);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
        fileNameOverrides: [name],
        sharePositionOrigin: origin,
      ),
    );
  } on Object catch (e) {
    debugPrint('Teilen fehlgeschlagen: $e');
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.exportFailedGeneric, status: HorizontStatus.critical));
  }
}

/// File name with timestamp and an arbitrary extension.
String fileName(String prefix, String extension) => pdfName(prefix).replaceFirst(RegExp(r'\.pdf$'), '.$extension');

/// Menu "Oben anheften" (pin to top) or "Nicht mehr anheften" (unpin) on a
/// section header; [at] = mouse position (right click), otherwise below the
/// header. `true` = selected.
Future<bool> showPinMenu(BuildContext context, {required bool pinned, Offset? at}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = at ?? (box == null ? Offset.zero : box.localToGlobal(Offset(box.size.width / 2, box.size.height)));
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final ok = await showMenu<bool>(
    context: context,
    position: RelativeRect.fromRect(origin & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      PopupMenuItem(
        value: true,
        child: ListTile(
          leading: Icon(pinned ? AppIcons.pinOutline : AppIcons.pin),
          title: Text(pinned ? s.sectionUnpin : s.sectionPin),
        ),
      ),
    ],
  );
  return ok == true;
}

/// Cards in columns side by side as soon as each column is at least [minWidth]
/// wide (iPad landscape, Mac); otherwise stacked. With [heights] (estimated
/// heights) each card goes into the currently shortest column, otherwise
/// round-robin, so the reading order stays row by row.
class CardColumns extends StatelessWidget {
  const CardColumns({
    super.key,
    required this.children,
    this.heights,
    this.minWidth = Widths.column,
    this.maxColumns = 3,
    this.gap = Gap.section,
  });

  final List<Widget> children;
  final List<double>? heights;
  final double minWidth;
  final int maxColumns;
  final double gap;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final fit = ((c.maxWidth + gap) / (minWidth + gap)).floor();
      final columns = fit.clamp(1, children.length.clamp(1, maxColumns));
      if (columns == 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: children);
      }
      final lanes = [for (var i = 0; i < columns; i++) <Widget>[]];
      final filled = List.filled(columns, 0.0);
      for (final (i, child) in children.indexed) {
        var lane = i % columns;
        if (heights case final h?) {
          lane = 0;
          for (var l = 1; l < columns; l++) {
            if (filled[l] < filled[lane]) lane = l;
          }
          filled[lane] += h[i];
        }
        lanes[lane].add(child);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: gap,
        children: [
          for (final lane in lanes)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: gap, children: lane),
            ),
        ],
      );
    },
  );
}

/// Buttons of equal width side by side as long as each fits its share;
/// otherwise stacked at full width. This way no label wraps, not even on narrow
/// phones, with large text or in English.
class EvenRow extends MultiChildRenderObjectWidget {
  const EvenRow({super.key, required super.children, this.spacing = HzSpace.s8});

  final double spacing;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderEvenRow(spacing);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderEvenRow).spacing = spacing;
}

class _EvenRowParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderEvenRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _EvenRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _EvenRowParentData> {
  _RenderEvenRow(this._spacing);

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  List<RenderBox> get _children {
    final out = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      out.add(child);
      child = childAfter(child);
    }
    return out;
  }

  /// Width per button side by side, or `null` if one does not fit.
  double? _slot(double width) {
    final children = _children;
    if (children.isEmpty) return 0;
    final slot = (width - _spacing * (children.length - 1)) / children.length;
    return children.every((c) => c.getMaxIntrinsicWidth(double.infinity) <= slot) ? slot : null;
  }

  Size _arrange(BoxConstraints constraints, {required bool dry}) {
    final children = _children;
    final width = constraints.maxWidth;
    final slot = _slot(width);
    Size size(RenderBox child, BoxConstraints c) {
      if (dry) return child.getDryLayout(c);
      child.layout(c, parentUsesSize: true);
      return child.size;
    }

    var height = 0.0;
    if (slot != null) {
      // Measure the tallest label first, then make all equally tall.
      for (final child in children) {
        height = math.max(height, size(child, BoxConstraints.tightFor(width: slot)).height);
      }
      for (final (i, child) in children.indexed) {
        size(child, BoxConstraints.tightFor(width: slot, height: height));
        if (!dry) (child.parentData! as _EvenRowParentData).offset = Offset(i * (slot + _spacing), 0);
      }
    } else {
      for (final (i, child) in children.indexed) {
        if (i > 0) height += _spacing;
        final s = size(child, BoxConstraints.tightFor(width: width));
        if (!dry) (child.parentData! as _EvenRowParentData).offset = Offset(0, height);
        height += s.height;
      }
    }
    return constraints.constrain(Size(width, height));
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _EvenRowParentData) child.parentData = _EvenRowParentData();
  }

  @override
  void performLayout() => size = _arrange(constraints, dry: false);

  @override
  Size computeDryLayout(BoxConstraints constraints) => _arrange(constraints, dry: true);

  @override
  double computeMinIntrinsicWidth(double height) =>
      _children.fold(0, (w, c) => math.max(w, c.getMinIntrinsicWidth(height)));

  @override
  double computeMaxIntrinsicWidth(double height) {
    final children = _children;
    final widest = children.fold<double>(0, (w, c) => math.max(w, c.getMaxIntrinsicWidth(height)));
    return children.isEmpty ? 0 : widest * children.length + _spacing * (children.length - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _arrange(BoxConstraints(maxWidth: width), dry: true).height;

  @override
  double computeMaxIntrinsicHeight(double width) => computeMinIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// Title "address  name" (e.g. "1/4/5  EG HWR Rückmeldung"): the address up to
/// the double space in Monaspace, the name in the UI font. Values and addresses
/// are measured, names are read.
class AddressTitle extends StatelessWidget {
  const AddressTitle(this.title, {super.key, this.maxLines = 2});

  final String title;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final address = context.mono(Theme.of(context).textTheme.bodyMedium).copyWith(fontWeight: FontWeight.w600);
    final name = Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500);
    final i = title.indexOf('  ');
    return Text.rich(
      i <= 0
          ? TextSpan(text: title, style: address)
          : TextSpan(
              children: [
                TextSpan(text: title.substring(0, i), style: address),
                TextSpan(text: title.substring(i), style: name),
              ],
            ),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}

/// Addresses (IP, individual) need a dot: a typed comma is replaced.
/// Why the QR scanner shows nothing: not permitted is different from no camera.
String scannerProblem(MobileScannerException error) =>
    error.errorCode == MobileScannerErrorCode.permissionDenied ? s.scanCameraDenied : s.boxScanNoCamera;

/// As usual on iOS and Android: whoever scrolls a list wants to see it, so the
/// keyboard closes.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(BuildContext context) =>
      switch (Theme.of(context).platform) {
        TargetPlatform.iOS || TargetPlatform.android => ScrollViewKeyboardDismissBehavior.onDrag,
        _ => ScrollViewKeyboardDismissBehavior.manual,
      };
}

const dotForComma = _DotForComma();

class _DotForComma extends TextInputFormatter {
  const _DotForComma();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.text.contains(',') ? newValue.copyWith(text: newValue.text.replaceAll(',', '.')) : newValue;
}

/// Divider between the rows of a [ToolSection] box.
class ToolSectionDivider extends StatelessWidget {
  const ToolSectionDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: Gap.section),
    child: Divider(height: Lines.hairline),
  );
}

/// A tool or check as a row of a box (diagnostics, project comparison): title
/// and explanation on the left (fixed width), inputs or result to the right;
/// stacked when narrow. [children] below at full width.
class ToolSection extends StatelessWidget {
  const ToolSection({
    super.key,
    required this.title,
    required this.text,
    required this.controls,
    this.count,
    this.children = const [],
  });

  final String title;

  /// Count after the title (findings); `null` for none.
  final int? count;

  /// Explanation below the title; empty = none.
  final String text;
  final Widget controls;
  final List<Widget> children;

  /// Width of the explanation on the left.
  static const _textWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Kennung(title, count: count),
        if (text.isNotEmpty) ...[
          const SizedBox(height: Gap.item),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted)),
        ],
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < _textWidth * 2 + Gap.section) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  intro,
                  const SizedBox(height: HzSpace.s16),
                  controls,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Gap.section,
              children: [
                SizedBox(width: _textWidth, child: intro),
                Expanded(child: controls),
              ],
            );
          },
        ),
        ...children,
      ],
    );
  }
}

/// "Schließen" (close) for in-page details (device, address, coupler): with a
/// frame and a word instead of a bare X, so it is clearly distinct from
/// "Zurück" (back) at the top left, which leaves the whole page.
class CloseDetailButton extends StatelessWidget {
  const CloseDetailButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: const Icon(AppIcons.close, size: 18),
    label: Text(MaterialLocalizations.of(context).closeButtonLabel),
  );
}

/// Set flags as in ETS, e.g. "K L Ü" (English "C R T").
String formatFlags(ComFlags f) {
  final letters = s.flagLetters.characters.toList();
  final text = [
    if (f.communication) letters[0],
    if (f.read) letters[1],
    if (f.write) letters[2],
    if (f.transmit) letters[3],
    if (f.update) letters[4],
  ].join(' ');
  return text.isEmpty ? s.flagsNone : text;
}

/// Sender line in Horizont style: "ein Projekt von regetskcob" (a project by
/// regetskcob) with the umbrella brand glyph, quietly at the end of the menu
/// and on the about page. Like [HorizontLockup] on one baseline, but the text
/// wraps in narrow sidebars and with large text.
/// Versions for support and bug reports, at the very bottom of the menu: the
/// app, plus the server in the add-on or via the box, e.g. "KNX Monitor 1.7.9
/// (13) · Add-on 1.7.9". Selectable for copying.
class VersionLine extends StatefulWidget {
  const VersionLine({super.key});

  @override
  State<VersionLine> createState() => _VersionLineState();
}

class _VersionLineState extends State<VersionLine> {
  late final Future<String> _text = _load();

  static Future<String> _load() async {
    final parts = <String>[];
    try {
      final p = await PackageInfo.fromPlatform();
      parts.add(s.versionApp(p.buildNumber.isEmpty ? p.version : '${p.version} (${p.buildNumber})'));
    } on Object {
      parts.add(s.versionApp('?'));
    }
    if (Addon.available) {
      try {
        final server = (await Addon.status())['version'] as String?;
        if (server != null) parts.add(Addon.box != null ? s.versionBox(server) : s.versionAddon(server));
      } on Object {
        // Server unreachable: only the app.
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text,
    builder: (context, snap) => SelectableText(
      snap.data ?? '',
      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.hz.textMuted),
    ),
  );
}

class SenderLine extends StatelessWidget {
  const SenderLine({super.key});

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final style = Theme.of(context).textTheme.bodySmall!.copyWith(color: hz.textMuted);
    final mark = MediaQuery.textScalerOf(context).scale(style.fontSize! * 1.15);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        ExcludeSemantics(
          child: HorizontMark(HorizontProduct.regetskcob, size: mark, color: hz.textMuted),
        ),
        SizedBox(width: mark * 0.35),
        Flexible(child: Text(s.aboutSender, style: style)),
      ],
    );
  }
}

/// Header title that wraps onto two lines and gets slightly smaller on a narrow
/// phone next to several buttons, instead of being truncated ("Inbetriebnah…",
/// "Unterschrift…").
class BarTitle extends StatelessWidget {
  const BarTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The style the header really uses for the title (AppBar sets it as
    // DefaultTextStyle); the theme alone may be smaller.
    final style = DefaultTextStyle.of(context).style;
    return LayoutBuilder(
      builder: (context, c) {
        final one = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final fits = one.width <= c.maxWidth;
        one.dispose();
        if (fits) return Text(text, maxLines: 1, style: style);
        final small = theme.textTheme.titleMedium?.copyWith(height: 1.15) ?? style;
        // If even a single word does not fit (large text), better truncate than
        // break mid-word ("Commissionin|g").
        final widest = text
            .split(RegExp(r'\s+'))
            .map((w) {
              final p = TextPainter(
                text: TextSpan(text: w, style: small),
                maxLines: 1,
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout();
              final width = p.width;
              p.dispose();
              return width;
            })
            .fold(0.0, math.max);
        if (widest > c.maxWidth) {
          // One long word ("Inbetriebnahme" on a 360 dp phone): slightly
          // smaller, down to 14 pt at most; only below that truncate.
          final size = small.fontSize ?? 16;
          final fitted = (size * c.maxWidth / widest).floorToDouble();
          if (fitted >= 14) return Text(text, maxLines: 2, style: small.copyWith(fontSize: fitted));
          return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: small);
        }
        return Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: small);
      },
    );
  }
}

/// Explanatory subtitle of a switch (`SwitchListTile`) as body text. Horizont's
/// list default sets subtitles in the data font, which is right for addresses
/// and values, not for sentences.
class SwitchHint extends StatelessWidget {
  const SwitchHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted));
}

/// For fields in [showDialog]: the dialog still builds while fading out, so
/// disposing immediately leads to "used after being disposed".
void disposeAfterDialog(TextEditingController controller) {
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
}
