import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';
import '../model/expert_mode.dart';
import '../l10n/locale_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/app_icons.dart';

/// Input format for writing. `dpt == null` means raw data in hex.
class WriteFormat {
  const WriteFormat(this.label, this.dpt);

  /// Format matching the DPT from the ETS catalog.
  factory WriteFormat.forDpt(Dpt dpt) => WriteFormat('DPT $dpt', dpt);

  final String label;
  final Dpt? dpt;

  bool get isSwitch => dpt?.main == 1;
  String get unit => dpt == null ? '' : dptUnit(dpt!);
}

List<WriteFormat> get writeFormats => [
  WriteFormat('${s.writeFormatSwitch} · 1.001', const Dpt(1, 1)),
  WriteFormat('${s.dptNamePercent} · 5.001', const Dpt(5, 1)),
  WriteFormat('${s.writeFormatNumber} · 5.010', const Dpt(5, 10)),
  WriteFormat('${s.writeFormatDecimal} · 9.xxx', const Dpt(9)),
  WriteFormat('${s.writeFormatScene} · 17.001', const Dpt(17, 1)),
  // Expert mode: more types as in the ETS group monitor.
  if (expert) ...[
    WriteFormat('${s.writeFormatNumber} · 7.001', const Dpt(7, 1)),
    WriteFormat('${s.writeFormatNumber} · 8.001', const Dpt(8, 1)),
    WriteFormat('${s.writeFormatNumber} · 12.001', const Dpt(12, 1)),
    WriteFormat('${s.writeFormatNumber} · 13.001', const Dpt(13, 1)),
    WriteFormat('${s.writeFormatDecimal} · 14.xxx', const Dpt(14)),
    WriteFormat('${s.dptNameText} · 16.000', const Dpt(16, 0)),
    WriteFormat('${s.writeFormatTime} · 10.001', const Dpt(10, 1)),
    WriteFormat('${s.writeFormatDate} · 11.001', const Dpt(11, 1)),
    WriteFormat('${s.writeFormatHvac} · 20.102', const Dpt(20, 102)),
    WriteFormat('${s.writeFormatColor} · 232.600', const Dpt(232, 600)),
  ],
  WriteFormat(s.writeFormatHex, null),
];

/// Control for writing a value to a group address.
///
/// With a known [dpt] the format is preselected (on/off buttons for DPT 1,
/// otherwise an input field with unit). [initial] prefills the field, e.g.
/// with the last received telegram. [onWrite] sends the encoded telegram and
/// throws a [KnxException] on errors.
class WriteValueControl extends StatefulWidget {
  const WriteValueControl({super.key, required this.onWrite, this.dpt, this.initial, this.primary = true});

  final Dpt? dpt;
  final Telegram? initial;

  /// Whether writing is the main action of the view (filled button). Otherwise,
  /// e.g. next to "Lesen" (read) in the details, an outlined button.
  final bool primary;

  /// Returns the bus confirmation: true = acknowledged, false = not acknowledged, null = unknown.
  final Future<bool?> Function({int? small, List<int> data}) onWrite;

  @override
  State<WriteValueControl> createState() => _WriteValueControlState();
}

class _WriteValueControlState extends State<WriteValueControl> {
  final _value = TextEditingController();
  late WriteFormat _format;
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    final dpt = widget.dpt;
    _format = dpt != null && canEncodeDpt(dpt) ? WriteFormat.forDpt(dpt) : _guessFormat(widget.initial);
    _value.text = _prefill(widget.initial);
  }

  /// Without a DPT: guesses the format from the length of the last value
  /// (1 bit → switching, 1 byte → percent, 2 bytes → float, otherwise hex).
  static WriteFormat _guessFormat(Telegram? t) {
    final formats = writeFormats;
    if (t == null || t.type == TelegramType.read) return formats[1];
    if (t.isSmall) return formats[0];
    return switch (t.data.length) {
      1 => formats[1],
      2 => formats[3],
      _ => formats.last,
    };
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  /// Current value as editable text (number without unit, or hex).
  String _prefill(Telegram? t) {
    if (t == null || t.type == TelegramType.read || _format.isSwitch) return '';
    if (_format.dpt == null) return hex(t.data);
    final decoded = decodeDpt(_format.dpt!, t);
    if (decoded == null) return '';
    // Text, time, date, color: as decoded.
    if (dptInputHint(_format.dpt!) != null) return decoded.replaceFirst(RegExp(r'^\D+\s'), '');
    return RegExp(r'^-?[\d.,]+').stringMatch(decoded) ?? '';
  }

  Future<void> _write({int? small, List<int> data = const [], required String label}) async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final confirmed = await widget.onWrite(small: small, data: data);
      _status = '${s.writeDone(label)}${confirmationText(confirmed)}';
      _statusIsError = confirmed == false;
    } on KnxException catch (e) {
      _status = e.message;
      _statusIsError = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _writeInput() {
    final dpt = _format.dpt;
    final ({int? small, List<int> data})? enc;
    if (dpt == null) {
      final bytes = parseHex(_value.text);
      enc = bytes == null ? null : (small: null, data: bytes);
    } else {
      enc = encodeForDpt(dpt, _value.text);
    }
    if (enc == null) {
      setState(() {
        _status = s.writeInvalidValue(_format.label);
        _statusIsError = true;
      });
      return;
    }
    final unit = _format.unit;
    _write(
      small: enc.small,
      data: enc.data,
      label: dpt == null
          ? hex(enc.data)
          : dpt.main == 16
          ? '„${_value.text}“'
          : '${_value.text.trim()}${unit.isEmpty ? '' : ' $unit'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    final status = _statusIsError ? HorizontStatus.critical : HorizontStatus.positive;
    final fixed = widget.dpt != null && _format.dpt == widget.dpt;
    final formats = [if (fixed) _format, ...writeFormats];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!fixed) ...[
          HorizontField(
            label: s.writeFormatLabel,
            child: DropdownButtonFormField<String>(
              initialValue: _format.label,
              decoration: InputDecoration(isDense: true),
              items: [for (final f in formats) DropdownMenuItem(value: f.label, child: Text(f.label))],
              onChanged: (l) => setState(() {
                _format = formats.firstWhere((f) => f.label == l);
                _status = null;
              }),
            ),
          ),
          const SizedBox(height: Gap.inner),
        ],
        if (_format.isSwitch) _switchButtons() else _valueInput(),
        AnimatedSize(
          duration: Motion.fastOf(context),
          curve: Motion.curve,
          child: _status == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: Gap.inner),
                  // State with symbol and word: check mark or octagon.
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(status.icon, size: 18, color: status.color(hz)),
                      const SizedBox(width: HzSpace.s8),
                      Expanded(
                        child: Text(_status!, style: TextStyle(color: _statusIsError ? hz.critical : hz.text)),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _switchButtons() {
    final (off, on) = dpt1Labels(_format.dpt?.sub);
    Widget button(String label, int v) => Expanded(
      child: OutlinedButton(
        onPressed: _busy ? null : () => _write(small: v, label: label),
        child: Text(label),
      ),
    );
    return Row(
      children: [
        button(off, 0),
        const SizedBox(width: Gap.inner),
        button(on, 1),
      ],
    );
  }

  /// Uhrzeit bzw. Datum von jetzt eintragen.
  void _fillNow() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    _value.text = _format.dpt?.main == 10
        ? '${two(now.hour)}:${two(now.minute)}:${two(now.second)}'
        : '${two(now.day)}.${two(now.month)}.${now.year}';
  }

  /// Minimum width for field and button side by side (at text scale 1); below
  /// it the button sits under the field.
  static const _rowMinWidth = 240.0;

  Widget _valueInput() {
    final hexMode = _format.dpt == null;
    final hint = _format.dpt == null ? null : dptInputHint(_format.dpt!);
    final textMode = hexMode || hint != null;
    final control = context.hzTheme.controlHeight;
    // No visible title ("Wert", value): the section heading says enough.
    // The screen reader still gets the label.
    // [fill]: the field fills the row height next to the button (at least the
    // theme's control height), the content is centered; with large text the
    // row grows with it.
    Widget field({required bool fill}) => Semantics(
      label: s.writeValueLabel,
      child: TextField(
        controller: _value,
        keyboardType: textMode
            ? TextInputType.text
            : const TextInputType.numberWithOptions(decimal: true, signed: true),
        textInputAction: TextInputAction.send,
        autocorrect: false,
        expands: fill,
        minLines: fill ? null : 1,
        maxLines: fill ? null : 1,
        textAlignVertical: TextAlignVertical.center,
        style: context.hzTheme.data,
        decoration: InputDecoration(
          hintText: hexMode ? '0C 1A' : hint,
          suffixIcon: const {10, 11}.contains(_format.dpt?.main)
              ? HorizontFieldIconButton(tooltip: s.writeNow, icon: const Icon(AppIcons.dateTime), onPressed: _fillNow)
              : null,
          suffixText: _format.unit.isEmpty ? null : _format.unit,
          isDense: true,
          contentPadding: fill ? const EdgeInsets.symmetric(horizontal: HzSpace.s12, vertical: HzSpace.s4) : null,
        ),
        onSubmitted: (_) => _writeInput(),
      ),
    );
    // No extra margin around the tap target: button and field have the same height.
    const shrink = ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap);
    final button = widget.primary
        ? FilledButton.icon(
            style: shrink,
            onPressed: _busy ? null : _writeInput,
            icon: const Icon(AppIcons.send, size: 18),
            label: Text(s.writeButton),
          )
        : OutlinedButton.icon(
            style: shrink,
            onPressed: _busy ? null : _writeInput,
            icon: const Icon(AppIcons.send, size: 18),
            label: Text(s.writeButton),
          );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < MediaQuery.textScalerOf(context).scale(_rowMinWidth);
        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(fill: false),
              const SizedBox(height: Gap.inner),
              button,
            ],
          );
        }
        // Button and field on one line, aligned at the top and of equal height.
        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: control),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: field(fill: true)),
                const SizedBox(width: Gap.inner),
                button,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Addition to the status message depending on the bus confirmation (L_Data.con).
String confirmationText(bool? confirmed) => switch (confirmed) {
  true => ' · ${s.confirmAcknowledged}',
  false => ' · ${s.confirmNotAcknowledged}',
  null => ' · ${s.confirmNoConfirmation}',
};
