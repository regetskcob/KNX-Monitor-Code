import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/demo_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/betrieb_mode.dart';
import '../model/write_notice.dart';
import '../theme/tokens.dart';
import 'betrieb/send_guard_dialog.dart';

/// Notice about interfering with the installation, until it is dismissed. The demo house has no installation.
Future<bool> acknowledgeWriteNotice(BuildContext context) async {
  if (DemoTunnel.active) return true;
  final notice = WriteNotice.instance;
  await notice.load();
  if (notice.dismissed) return true;
  if (!context.mounted) return false;
  return await showAdaptiveDialog<bool>(context: context, builder: (_) => const WriteNoticeDialog()) == true;
}

/// The liability sentence is a draft.
class WriteNoticeDialog extends StatefulWidget {
  const WriteNoticeDialog({super.key});

  @override
  State<WriteNoticeDialog> createState() => _WriteNoticeDialogState();
}

class _WriteNoticeDialogState extends State<WriteNoticeDialog> {
  bool _hide = false;

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(s.writeNoticeTitle),
    content: Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          Text(s.writeNoticeBody),
          CheckboxListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _hide,
            title: Text(s.writeNoticeHide),
            subtitle: Text(s.writeNoticeHideHint),
            onChanged: (v) => setState(() => _hide = v ?? false),
          ),
        ],
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
      horizontDialogAction(
        context,
        label: s.writeNoticeConfirm,
        primary: true,
        onPressed: () {
          // Only someone who actually writes can dismiss it.
          if (_hide) unawaited(WriteNotice.instance.dismiss());
          Navigator.pop(context, true);
        },
      ),
    ],
  );
}

/// Before writing to the bus: the notice about interfering with the
/// installation, until it is dismissed. With the `BETRIEB` switch, plain text
/// afterwards and, if needed, confirmation ([betriebConfirmWrite]).
Future<bool> confirmWrite(BuildContext context, int address, {int? small, List<int> data = const []}) async {
  if (!WriteNotice.instance.dismissed && (!await acknowledgeWriteNotice(context) || !context.mounted)) return false;
  if (!Betrieb.enabled) return true;
  return betriebConfirmWrite(context, address, small: small, data: data);
}

/// [confirmWrite] for write paths that report a refusal as an error: it then
/// appears as a message at the control.
Future<void> requireWriteConfirmation(
  BuildContext context,
  int address, {
  int? small,
  List<int> data = const [],
}) async {
  if (!await confirmWrite(context, address, small: small, data: data)) throw KnxException(s.bizSendCancelled);
}

/// Before a replay onto the bus: the notice about interfering with the
/// installation, with the `BETRIEB` switch [betriebConfirmReplay] afterwards.
Future<bool> confirmReplay(BuildContext context) async {
  if (!WriteNotice.instance.dismissed && (!await acknowledgeWriteNotice(context) || !context.mounted)) return false;
  if (!Betrieb.enabled) return true;
  return betriebConfirmReplay(context);
}
