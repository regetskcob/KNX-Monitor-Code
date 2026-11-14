import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../knx/active_tunnel.dart';
import '../knx/knx_tunnel.dart';
import '../l10n/locale_controller.dart';
import '../model/channel_control.dart';
import '../model/device_channels.dart';
import '../model/lock_prefs.dart';
import '../model/telegram_log.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'channel_test_screen.dart';
import 'locks_screen.dart';
import 'write_confirm.dart';

/// Whether a tap on a channel or key of a device drawing sends to the bus
/// instead of selecting it. Off at every start: nobody switches by accident.
final operateMode = ValueNotifier<bool>(false);

/// What the last tap did, shown next to the switch: the device sheet is a
/// modal sheet, a snack bar would appear behind it.
final operateResult = ValueNotifier<(String, HorizontStatus)?>(null);

/// Switch above a device drawing that arms [operateMode]; hidden without a
/// connection.
class OperateBar extends StatefulWidget {
  const OperateBar({super.key, this.device, this.log});

  /// Device and log for the channel check; without them only the switch.
  final int? device;
  final TelegramLog? log;

  @override
  State<OperateBar> createState() => _OperateBarState();
}

class _OperateBarState extends State<OperateBar> {
  int? get device => widget.device;
  TelegramLog? get log => widget.log;

  @override
  void initState() {
    super.initState();
    unawaited(LockPrefs.instance.load());
  }

  /// Leaving the drawing disarms: the mode must never outlive its visible switch.
  @override
  void dispose() {
    scheduleMicrotask(() {
      operateMode.value = false;
      operateResult.value = null;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: activeTunnel,
    builder: (context, tunnel, _) {
      if (tunnel == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: Listenable.merge([operateMode, operateResult]),
        builder: (context, _) {
          final on = operateMode.value;
          final result = operateResult.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: Gap.item),
            child: Wrap(
              spacing: HzSpace.s12,
              runSpacing: HzSpace.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text(s.operateMode),
                  selected: on,
                  onSelected: (v) {
                    operateResult.value = null;
                    operateMode.value = v;
                  },
                ),
                if ((device, log) case (final device?, final log?))
                  ActionChip(
                    label: Text(s.channelTestTitle),
                    onPressed: () => unawaited(openChannelTest(context, device, log)),
                  ),
                if (on && result != null)
                  Semantics(liveRegion: true, child: HorizontBadge(result.$2, label: result.$1))
                else if (on)
                  Text(
                    s.operateHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// What a key of a pair does: the first is on/up, the second off/down.
enum OperateKey { first, second }

/// Sends what operating [channel] means and reports what came back: a switching
/// channel toggles (or follows [key]) and is confirmed by its status feedback;
/// a blind asks for up, stop or down unless [key] says it.
Future<void> operateChannel(
  BuildContext context,
  DeviceChannel channel,
  TelegramLog log, {
  OperateKey? key,
  required String name,
}) async {
  void say(String text, {HorizontStatus? status}) => operateResult.value = (text, status ?? HorizontStatus.neutral);

  final tunnel = activeTunnel.value;
  if (tunnel == null || tunnel.state.value != TunnelState.connected) return say(s.operateOffline);
  await LockPrefs.instance.load();
  if (!context.mounted) return;
  final control = controlOf(channel);
  if (control == null) return say(s.operateNothing(name));

  if (control.kind == ControlKind.blind) {
    final move = switch (key) {
      OperateKey.first => _BlindMove.up,
      OperateKey.second => _BlindMove.down,
      null => await showModalBottomSheet<_BlindMove>(
        context: context,
        builder: (_) => _BlindSheet(name: name, stop: control.stop != null),
      ),
    };
    if (move == null || !context.mounted) return;
    final address = move == _BlindMove.stop ? control.stop! : control.address;
    final value = move == _BlindMove.up ? 0 : 1;
    if (!await confirmWrite(context, address, small: value)) return;
    // `false` = rejected, `null` = no confirmation in time: neither was sent.
    if (await tunnel.write(address, small: value) != true) {
      return say(s.operateNotSent(name), status: HorizontStatus.critical);
    }
    // A blind reports no on/off: at least say when its lock object is set.
    if (activeLockText(channel, log) case (final since, final who)) {
      return say(s.operateLocked(name, since, who), status: HorizontStatus.warning);
    }
    return say(
      s.operateSent(name, switch (move) {
        _BlindMove.up => s.operateUp,
        _BlindMove.down => s.operateDown,
        _BlindMove.stop => s.operateStop,
      }),
    );
  }

  if (control.caution) {
    final go = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.operateCautionTitle(name)),
        content: Text(s.operateCautionBody),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(
            context,
            label: s.operateCautionSend,
            primary: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;
  }
  final value = switch (key) {
    OperateKey.first => 1,
    OperateKey.second => 0,
    null => toggleValue(control, log.latest),
  };
  final text = value == 1 ? s.deviceOn : s.deviceOff;
  if (!await confirmWrite(context, control.address, small: value)) return;
  final status = control.status;
  final confirmed = status == null ? null : awaitFeedback(log, status, value);
  if (await tunnel.write(control.address, small: value) != true) {
    return say(s.operateNotSent(name), status: HorizontStatus.critical);
  }
  if (confirmed == null) return say(s.operateSent(name, text));
  // Success is what the actuator reports, not what was sent: a locked channel
  // takes the telegram and stays as it is.
  if (await confirmed) {
    say(s.operateConfirmed(name, text), status: HorizontStatus.positive);
  } else if (activeLockText(channel, log) case (final since, final who)) {
    say(s.operateLocked(name, since, who), status: HorizontStatus.warning);
  } else {
    say(s.operateNoFeedback(name, text), status: HorizontStatus.warning);
  }
}

enum _BlindMove { up, stop, down }

class _BlindSheet extends StatelessWidget {
  const _BlindSheet({required this.name, required this.stop});

  final String name;
  final bool stop;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: Gap.page,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.item,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          Text(s.operateBlindHint, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
          FilledButton(onPressed: () => Navigator.pop(context, _BlindMove.up), child: Text(s.operateUp)),
          if (stop)
            OutlinedButton(onPressed: () => Navigator.pop(context, _BlindMove.stop), child: Text(s.operateStop)),
          FilledButton(onPressed: () => Navigator.pop(context, _BlindMove.down), child: Text(s.operateDown)),
        ],
      ),
    ),
  );
}
