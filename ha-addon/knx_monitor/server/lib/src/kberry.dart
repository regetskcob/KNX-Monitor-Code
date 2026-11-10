import 'dart:io';

import 'link_texts.dart';

import 'package:knx_io/knx_io.dart' show Ft12CemiLink, KberryProbe, ProbeStatus, SerialLine, TtyLine;

// The FT1.2 protocol, the serial line and the HAT check (KberryProbe) come from
// package:knx_io; this file keeps what is specific to the Busclear Box.

/// How the Pi is configured for the HAT: device present and readable,
/// serial console off, UART overlay set, model.
Future<Map<String, Object?>> kberrySystem(String device) async {
  // Not FileSystemEntity.type: it reports character devices as notFound.
  final present = await File(device).exists();
  String? access;
  if (present) {
    try {
      await (await File(device).open()).close();
      access = 'ok';
    } on FileSystemException catch (e) {
      access = e.osError?.message ?? e.message;
    }
  }
  Future<String> read(String path) async {
    try {
      return await File(path).readAsString();
    } on Object {
      return '';
    }
  }

  final cmdline = await read('/proc/cmdline');
  var config = await read('/boot/firmware/config.txt');
  if (config.isEmpty) config = await read('/boot/config.txt');
  final overlays = [
    for (final line in config.split('\n'))
      if (RegExp(r'^\s*(dtoverlay=(disable-bt|miniuart-bt|uart0-pi5)|dtparam=uart0|enable_uart=)').hasMatch(line))
        line.trim(),
  ];
  final serialConsole = RegExp(r'console=(serial0|ttyAMA0|ttyS0)').hasMatch(cmdline);
  final model = (await read('/proc/device-tree/model')).replaceAll('\u0000', '').trim();
  final ok = present && access == 'ok' && !serialConsole;
  return {
    'status': (ok ? ProbeStatus.ok : ProbeStatus.fail).name,
    'device': device,
    'present': present,
    'access': ?access,
    'serialConsole': serialConsole,
    'overlays': overlays,
    if (model.isNotEmpty) 'model': model,
  };
}

/// Holds a running check and its last result for `/api/box/hat`.
class KberryService {
  KberryService({this.device = '/dev/ttyAMA0', Future<SerialLine> Function(int baud)? open})
    : _open = open ?? ((baud) => TtyLine.open(device, baud));

  final String device;
  final Future<SerialLine> Function(int baud) _open;
  bool running = false;
  String? step;
  Map<String, Object?>? report;

  Future<Map<String, Object?>> status() async => {
    'system': await kberrySystem(device),
    'running': running,
    'step': ?step,
    'report': ?report,
  };

  /// Starts a check in the background; `false` if one is already running.
  bool start(Duration listen) {
    if (running) return false;
    running = true;
    report = null;
    final probe = () async {
      try {
        report =
            linkReport(await KberryProbe(_open, onStep: (s) => step = s).run(listen: listen)) as Map<String, Object?>;
      } on Object catch (e) {
        report = {'error': linkText(e)};
      } finally {
        running = false;
        step = null;
      }
    }();
    // While the check holds the UART, a bus connection via the HAT waits.
    Ft12CemiLink.occupy(device, probe);
    return true;
  }
}
