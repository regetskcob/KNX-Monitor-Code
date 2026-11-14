import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart';
import 'installation.dart';

/// The state of an installation at one moment: the last value of every group
/// address and which devices had sent. Taken before something is done to the
/// installation (power off, a device swapped, a download from the ETS) and
/// compared afterwards.
class ValueSnapshot {
  ValueSnapshot({required this.taken, required this.values, required this.devices});

  /// Freezes [latest] at [now]; [text] renders a value for reading later.
  factory ValueSnapshot.take(Map<int, Telegram> latest, DateTime now, {required String Function(Telegram) text}) {
    final values = <int, ({String raw, String text})>{};
    final devices = <int>{};
    for (final t in latest.values) {
      if (t.type == TelegramType.read) continue;
      values[t.destination] = (raw: _raw(t), text: text(t));
      if (!t.outgoing) devices.add(t.source);
    }
    return ValueSnapshot(taken: now, values: values, devices: devices);
  }

  final DateTime taken;

  /// Per group address the value as bytes (for comparing) and as text.
  final Map<int, ({String raw, String text})> values;

  /// Devices that had sent a value.
  final Set<int> devices;

  static String _raw(Telegram t) =>
      '${t.isSmall ? 's' : 'd'}${t.data.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  /// What is different now.
  SnapshotDiff compare(Map<int, Telegram> latest, {required String Function(Telegram) text}) {
    final changed = <({int address, String before, String after})>[];
    final same = <int>[];
    final quiet = <int>[];
    final fresh = <int>[];
    final active = <int>{};
    for (final t in latest.values) {
      if (t.type == TelegramType.read) continue;
      if (t.time.isAfter(taken) && !t.outgoing) active.add(t.source);
      final before = values[t.destination];
      if (before == null) {
        fresh.add(t.destination);
      } else if (!t.time.isAfter(taken)) {
        quiet.add(t.destination);
      } else if (_raw(t) != before.raw) {
        changed.add((address: t.destination, before: before.text, after: text(t)));
      } else {
        same.add(t.destination);
      }
    }
    return SnapshotDiff(
      changed: changed..sort((a, b) => a.address.compareTo(b.address)),
      same: same..sort(),
      quiet: quiet..sort(),
      fresh: fresh..sort(),
      silentDevices: devices.difference(active).toList()..sort(),
    );
  }

  Map<String, Object?> toJson() => {
    'taken': taken.toUtc().toIso8601String(),
    'values': {
      for (final MapEntry(:key, :value) in values.entries) '$key': [value.raw, value.text],
    },
    'devices': devices.toList()..sort(),
  };

  factory ValueSnapshot.fromJson(Map<String, Object?> j) => ValueSnapshot(
    taken: DateTime.parse(j['taken']! as String).toLocal(),
    values: {
      for (final MapEntry(:key, :value) in (j['values'] as Map? ?? const {}).entries)
        if ((int.tryParse('$key'), value) case (final a?, [final String raw, final String text]))
          a: (raw: raw, text: text),
    },
    devices: {...?(j['devices'] as List?)?.whereType<int>()},
  );
}

/// The difference between a snapshot and now.
class SnapshotDiff {
  const SnapshotDiff({
    required this.changed,
    required this.same,
    required this.quiet,
    required this.fresh,
    required this.silentDevices,
  });

  /// Sent again with another value.
  final List<({int address, String before, String after})> changed;

  /// Sent again with the same value.
  final List<int> same;

  /// Not sent since the snapshot: the value on screen is the old one.
  final List<int> quiet;

  /// Addresses the snapshot did not have.
  final List<int> fresh;

  /// Devices that sent before the snapshot and not since.
  final List<int> silentDevices;
}

/// The snapshot of the active installation (`snapshot.json`); nothing is kept in
/// the demo house.
class ValueSnapshotStore extends ChangeNotifier {
  ValueSnapshotStore._();

  static final instance = ValueSnapshotStore._();
  static const path = 'snapshot.json';

  ValueSnapshot? snapshot;
  String? _loadedFor;

  Future<void> load() async {
    final id = InstallationStore.instance.active.id;
    if (_loadedFor == id) return;
    _loadedFor = id;
    snapshot = null;
    if (!DemoTunnel.active) {
      try {
        final text = await InstallationStore.instance.storage.read(path);
        if (text != null) snapshot = ValueSnapshot.fromJson((jsonDecode(text) as Map).cast());
      } on Object catch (e) {
        debugPrint('Stand nicht geladen: $e');
      }
    }
    notifyListeners();
  }

  Future<void> save(ValueSnapshot? value) async {
    snapshot = value;
    notifyListeners();
    if (DemoTunnel.active) return;
    final storage = InstallationStore.instance.storage;
    if (value == null) {
      await storage.delete(path);
    } else {
      await storage.write(path, jsonEncode(value.toJson()));
    }
  }

  @visibleForTesting
  void debugReset() {
    snapshot = null;
    _loadedFor = null;
  }
}
