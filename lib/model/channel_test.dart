import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import '../knx/telegram.dart';
import 'channel_control.dart';
import 'device_channels.dart';
import 'installation.dart';

/// What the installer saw when a channel was switched.
enum ChannelResult {
  /// Not checked yet.
  open,

  /// The right load reacted.
  ok,

  /// Something reacted, but not what the channel is named after: swapped or
  /// mislabelled.
  wrongLoad,

  /// Nothing reacted.
  noReaction,

  /// Left out on purpose.
  skipped;

  bool get issue => this == wrongLoad || this == noReaction;
}

/// One channel of the device in the check.
class ChannelCheck {
  ChannelCheck({
    required this.label,
    this.title,
    this.control,
    this.result = ChannelResult.open,
    this.feedback,
    this.note,
    this.time,
  });

  /// Channel label on the device ("A", "3").
  final String label;

  /// What it is called in the project.
  final String? title;

  /// How it is switched; `null` or a blind or a cautious one is triggered by
  /// hand and only rated here.
  final ChannelControl? control;

  ChannelResult result;

  /// Whether the status feedback confirmed switching on; `null` = not sent or
  /// the channel has none.
  bool? feedback;
  String? note;
  DateTime? time;

  /// Whether the app switches it itself.
  bool get automatic => control != null && control!.kind == ControlKind.toggle && !control!.caution;

  Map<String, Object?> toJson() => {
    'l': label,
    'r': result.name,
    'f': ?feedback,
    'n': ?note,
    't': ?time?.toUtc().toIso8601String(),
  };
}

/// Channel check of one device: every channel is switched on, the installer
/// says what reacted, the app notes whether the status feedback followed. It
/// answers "which channel is which lamp" and leaves a record of it.
class ChannelTest {
  ChannelTest(this.device, this.items);

  /// The channels of [device] with something to check, general objects left out.
  factory ChannelTest.of(int device, List<DeviceChannel> channels) => ChannelTest(device, [
    for (final c in channels)
      if (c.label.isNotEmpty || c.title != null) ChannelCheck(label: c.label, title: c.title, control: controlOf(c)),
  ]);

  final int device;
  final List<ChannelCheck> items;

  int get done => items.where((i) => i.result != ChannelResult.open).length;
  int get issues => items.where((i) => i.result.issue || i.feedback == false).length;

  /// Next channel without a result, the ones the app switches first.
  ChannelCheck? get next =>
      items.where((i) => i.result == ChannelResult.open && i.automatic).firstOrNull ??
      items.where((i) => i.result == ChannelResult.open).firstOrNull;

  void rate(ChannelCheck item, ChannelResult result, {String? note, DateTime? at}) {
    item
      ..result = result
      ..note = (note?.trim().isEmpty ?? true) ? null : note!.trim()
      ..time = result == ChannelResult.open ? null : (at ?? DateTime.now());
    if (result == ChannelResult.open) item.feedback = null;
  }

  /// Takes over the results saved for the same channel labels.
  void restore(Object? json) {
    if (json is! List) return;
    for (final j in json.whereType<Map<Object?, Object?>>()) {
      final item = items.where((i) => i.label == j['l']).firstOrNull;
      if (item == null) continue;
      item
        ..result = ChannelResult.values.asNameMap()[j['r']] ?? ChannelResult.open
        ..feedback = j['f'] as bool?
        ..note = j['n'] as String?
        ..time = DateTime.tryParse(j['t'] as String? ?? '')?.toLocal();
    }
  }

  List<Object?> toJson() => [
    for (final i in items)
      if (i.result != ChannelResult.open) i.toJson(),
  ];

  /// The record as plain text, one line per channel; [text] names a result,
  /// [feedback] the status feedback.
  String report({
    required String heading,
    required String Function(ChannelResult result) text,
    required String Function(bool confirmed) feedback,
  }) => [
    heading,
    '',
    for (final i in items)
      [
        [i.label, ?i.title].join(' '),
        if (i.control case final c?) formatGroup(c.address),
        text(i.result),
        if (i.feedback case final f?) feedback(f),
        ?i.note,
      ].join(' · '),
  ].join('\n');
}

/// Saved channel checks of the active installation (`channel_tests.json`), by
/// device. Nothing is kept in the demo house.
class ChannelTestStore {
  ChannelTestStore._();

  static final instance = ChannelTestStore._();
  static const path = 'channel_tests.json';

  Map<String, Object?> _all = {};
  String? _loadedFor;

  Future<void> _load() async {
    final id = InstallationStore.instance.active.id;
    if (_loadedFor == id) return;
    _loadedFor = id;
    _all = {};
    if (DemoTunnel.active) return;
    try {
      final text = await InstallationStore.instance.storage.read(path);
      if (text != null) _all = (jsonDecode(text) as Map).cast<String, Object?>();
    } on Object catch (e) {
      debugPrint('Kanalprüfung nicht geladen: $e');
    }
  }

  /// Fills [test] with what was saved for its device.
  Future<void> restore(ChannelTest test) async {
    await _load();
    test.restore(_all['${test.device}']);
  }

  /// Every saved check, rebuilt against the channels the device has now ([channelsOf]).
  Future<List<ChannelTest>> all(List<DeviceChannel> Function(int device) channelsOf) async {
    await _load();
    return [
      for (final key in _all.keys)
        if (int.tryParse(key) case final device?) ChannelTest.of(device, channelsOf(device))..restore(_all[key]),
    ]..sort((a, b) => a.device.compareTo(b.device));
  }

  Future<void> save(ChannelTest test) async {
    await _load();
    _all['${test.device}'] = test.toJson();
    if (DemoTunnel.active) return;
    await InstallationStore.instance.storage.write(path, jsonEncode(_all));
  }

  @visibleForTesting
  void debugReset() {
    _all = {};
    _loadedFor = null;
  }
}
