import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../knx/knx_tunnel.dart';
import 'installation.dart';

/// A scheduled write job (delayed and/or cyclic, as in the ETS group monitor).
class SendJob {
  SendJob({
    required this.address,
    required this.label,
    this.small,
    this.data = const [],
    this.delay = Duration.zero,
    this.interval,
  });

  final int address;
  final String label;
  final int? small;
  final List<int> data;
  final Duration delay;

  /// `null` = send once.
  final Duration? interval;

  int sent = 0;
  DateTime? next;
  String? lastError;
  Timer? _timer;
}

/// Executes scheduled write jobs over the current tunnel. Ends with the monitor
/// (all jobs are then stopped).
class SendScheduler extends ChangeNotifier {
  SendScheduler._();

  static final instance = SendScheduler._();

  KnxTunnel? _tunnel;
  final jobs = <SendJob>[];

  void attach(KnxTunnel tunnel) => _tunnel = tunnel;

  /// Tunnel of the open monitor, `null` without a monitor.
  KnxTunnel? get tunnel => _tunnel;

  void detach(KnxTunnel tunnel) {
    if (!identical(_tunnel, tunnel)) return;
    stopAll();
    _tunnel = null;
  }

  void add(SendJob job) {
    jobs.add(job);
    job.next = DateTime.now().add(job.delay);
    job._timer = Timer(job.delay, () => _run(job));
    notifyListeners();
  }

  Future<void> _run(SendJob job) async {
    final tunnel = _tunnel;
    if (tunnel == null || !jobs.contains(job)) return;
    try {
      await tunnel.write(job.address, small: job.small, data: job.data);
      job.lastError = null;
    } on KnxException catch (e) {
      job.lastError = e.message;
    }
    job.sent++;
    final interval = job.interval;
    if (interval == null) {
      jobs.remove(job);
    } else if (jobs.contains(job)) {
      job.next = DateTime.now().add(interval);
      job._timer = Timer(interval, () => _run(job));
    }
    notifyListeners();
  }

  void stop(SendJob job) {
    job._timer?.cancel();
    jobs.remove(job);
    notifyListeners();
  }

  void stopAll() {
    for (final j in jobs) {
      j._timer?.cancel();
    }
    jobs.clear();
    notifyListeners();
  }
}

/// Most recently written or read group addresses (newest first).
class RecentAddresses {
  RecentAddresses._();

  static const _key = 'send_recent';
  static const max = 8;

  static Future<List<int>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return [
      for (final v in prefs.getStringList(InstallationStore.instance.key(_key)) ?? const <String>[]) ?int.tryParse(v),
    ];
  }

  static Future<List<int>> remember(int address) async {
    final prefs = await SharedPreferences.getInstance();
    final list = [address, ...(await load()).where((a) => a != address)].take(max).toList();
    await prefs.setStringList(InstallationStore.instance.key(_key), [for (final a in list) '$a']);
    return list;
  }
}
