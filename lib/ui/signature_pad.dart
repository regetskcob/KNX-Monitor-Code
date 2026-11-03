import 'package:flutter/material.dart';

import '../l10n/locale_controller.dart';
import '../model/acceptance.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Captures a signature in full screen (finger, pen or mouse). Returns `null`
/// on cancel. Releases focus first: otherwise it would return to the last
/// edited field afterwards, and the keyboard would cover the signature.
Future<Signature?> captureSignature(BuildContext context, {required String title}) {
  FocusScope.of(context).unfocus();
  return Navigator.of(context)
      .push<Signature>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _SignatureScreen(title: title)));
}

class _SignatureScreen extends StatefulWidget {
  const _SignatureScreen({required this.title});

  final String title;

  @override
  State<_SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<_SignatureScreen> {
  final _strokes = <List<Offset>>[];

  bool get _empty => Signature(_strokes).isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: BarTitle(widget.title),
        actions: [
          IconButton(
            tooltip: s.signUndo,
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.removeLast),
            icon: const Icon(AppIcons.restart),
          ),
          IconButton(
            tooltip: s.signClear,
            onPressed: _strokes.isEmpty ? null : () => setState(_strokes.clear),
            icon: const Icon(AppIcons.clear),
          ),
          TextButton(
            onPressed: _empty
                ? null
                : () => Navigator.pop(
                    context,
                    Signature([
                      for (final stroke in _strokes) [...stroke],
                    ]),
                  ),
            child: Text(s.signDone),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: Gap.page,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: SignaturePad(strokes: _strokes, onChanged: () => setState(() {})),
                ),
                const SizedBox(height: Gap.item),
                Text(
                  s.signHint,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawing area in the aspect ratio [Signature.aspect]: strokes are collected
/// relatively (0–1) in [strokes].
class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.strokes, required this.onChanged});

  final List<List<Offset>> strokes;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return AspectRatio(
      aspectRatio: Signature.aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          Offset rel(Offset p) => Offset((p.dx / box.maxWidth).clamp(0.0, 1.0), (p.dy / box.maxHeight).clamp(0.0, 1.0));
          return Semantics(
            label: s.signArea,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) {
                strokes.add([rel(d.localPosition)]);
                onChanged();
              },
              onPanUpdate: (d) {
                if (strokes.isEmpty) return;
                strokes.last.add(rel(d.localPosition));
                onChanged();
              },
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: hz.surface,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: hz.line, width: Lines.hairline),
                ),
                child: CustomPaint(
                  painter: SignaturePainter(Signature(strokes), color: hz.text, line: hz.line),
                  size: Size.infinite,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Draws a [Signature] (also as a small preview) above a baseline.
class SignaturePainter extends CustomPainter {
  SignaturePainter(this.signature, {required this.color, required this.line});

  final Signature signature;
  final Color color;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height * 0.78;
    canvas.drawLine(
      Offset(size.width * 0.05, base),
      Offset(size.width * 0.95, base),
      Paint()
        ..color = line
        ..strokeWidth = Lines.hairline,
    );
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = (size.height / 60).clamp(1.2, 3.0);
    for (final stroke in signature.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx * size.width, stroke.first.dy * size.height);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, pen);
    }
  }

  @override
  bool shouldRepaint(SignaturePainter old) => true;
}
