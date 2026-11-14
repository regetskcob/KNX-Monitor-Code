import 'dart:async';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'commissioning.dart' show isStatusGroup;
import 'device_channels.dart';
import 'locks.dart';
import 'object_groups.dart';
import 'telegram_log.dart';

/// How a channel is operated from its drawing.
enum ControlKind {
  /// One switching address: on and off.
  toggle,

  /// Blind or shutter: up, down and, where the project has one, stop.
  blind,
}

/// What operating a channel sends: the command address of the channel, the
/// stop address of a blind and the status feedback that confirms it. All of it
/// is a group telegram like from a push button – the manual keys on the device
/// itself act locally and are not on the bus.
class ChannelControl {
  const ChannelControl(this.kind, this.address, {this.stop, this.status, this.caution = false});

  final ControlKind kind;

  /// Switching address, or the up/down address of a blind (DPT 1.008: 0 = up).
  final int address;

  /// Stop or step address of a blind.
  final int? stop;

  /// Status feedback (DPT 1) that follows the command; `null` if the channel
  /// has none in the project.
  final int? status;

  /// The name says it moves or secures something (gate, door, lock, alarm,
  /// central function): ask before sending, every time.
  final bool caution;
}

final _caution = RegExp(
  r'tor\b|garage|gate|tür|door|schloss|lock|riegel|alarm|panik|panic|zentral|central|alles aus|all off|sirene|siren',
  caseSensitive: false,
);

final _move = RegExp(r'auf/ab|auf/zu|up/down|fahren|move|langzeit', caseSensitive: false);
final _stop = RegExp(r'stop|stopp|lamelle|slat|schritt|step|kurzzeit', caseSensitive: false);

/// The control of [channel], or `null` if nothing on it can be sent safely:
/// only switching addresses (DPT 1) that are not a status feedback, and no
/// heating valves – those belong to the controller.
ChannelControl? controlOf(DeviceChannel channel, {CatalogStore? store}) {
  final c = store ?? CatalogStore.instance;
  final kind = channel.kind;
  if (kind == ChannelKind.heating) return null;
  final commands = <DeviceObject>[];
  int? status;
  for (final o in channel.objects) {
    final info = c.info(o.address);
    if (info == null || c.dptOf(o.address)?.main != 1) continue;
    // A lock or enable object is not the load: sending to it would change the lock.
    if (lockSense(info, c.dptOf(o.address)) != null) continue;
    if (isStatusGroup(info)) {
      status ??= o.address;
    } else if (!commands.any((e) => e.address == o.address)) {
      commands.add(o);
    }
  }
  if (commands.isEmpty) return null;
  String text(DeviceObject o) => '${o.text ?? ''} ${c.info(o.address)?.name ?? ''}';
  if (kind == ChannelKind.blind) {
    final move =
        commands.where((o) => c.dptOf(o.address)?.sub == 8).firstOrNull ??
        commands.where((o) => _move.hasMatch(text(o)) && !_stop.hasMatch(text(o))).firstOrNull;
    if (move == null) return null;
    final stop = commands
        .where((o) => o.address != move.address)
        .where((o) => const {7, 10, 17}.contains(c.dptOf(o.address)?.sub) || _stop.hasMatch(text(o)))
        .firstOrNull;
    // A blind reports a position, not on/off: nothing to confirm with.
    return ChannelControl(ControlKind.blind, move.address, stop: stop?.address);
  }
  final command =
      commands.where((o) => const {null, 1}.contains(c.dptOf(o.address)?.sub)).firstOrNull ?? commands.first;
  return ChannelControl(
    ControlKind.toggle,
    command.address,
    status: status,
    caution: _caution.hasMatch('${channel.title ?? ''} ${text(command)}'),
  );
}

/// Whether the channel is on according to the bus: the status feedback counts,
/// without one the last command. `null` = unknown.
bool? isOn(ChannelControl control, Map<int, Telegram> latest) {
  for (final a in [?control.status, control.address]) {
    final t = latest[a];
    if (t != null && t.type != TelegramType.read && t.data.isNotEmpty) return t.data[0] & 1 == 1;
  }
  return null;
}

/// What a tap sends to a switching channel: off if it is on, otherwise on.
int toggleValue(ChannelControl control, Map<int, Telegram> latest) => isOn(control, latest) == true ? 0 : 1;

/// Waits for the status feedback [status] to report [value] with a telegram
/// that arrives after this call; `false` when [timeout] passes without one.
Future<bool> awaitFeedback(TelegramLog log, int status, int value, {Duration timeout = const Duration(seconds: 2)}) {
  final before = log.latest[status];
  final done = Completer<bool>();
  late final Timer timer;
  void check() {
    final t = log.latest[status];
    if (t == null || identical(t, before) || t.outgoing || t.type == TelegramType.read || t.data.isEmpty) return;
    if (t.data[0] & 1 != value) return;
    timer.cancel();
    log.removeListener(check);
    if (!done.isCompleted) done.complete(true);
  }

  timer = Timer(timeout, () {
    log.removeListener(check);
    if (!done.isCompleted) done.complete(false);
  });
  log.addListener(check);
  return done.future;
}

/// Something in a room that can be operated: a light, a socket, a blind.
class RoomControl {
  RoomControl(this.title, this.channel, this.control);

  final String title;

  /// The object's addresses as a channel, so operating works like on a device drawing.
  final DeviceChannel channel;
  final ChannelControl control;
}

/// Everything that can be operated, by room, from the object index of [catalog]
/// (addresses that belong together by their names). Objects without a room come
/// last under an empty name. This is a test page for the installation, not a
/// visualization: it shows what the project has, in the project's own names.
Map<String, List<RoomControl>> roomControls(GroupCatalog catalog, {CatalogStore? store}) {
  final rooms = <String, List<RoomControl>>{};
  final index = ObjectIndex.of(catalog);
  // By object: addresses that belong together by their names; an address on its own is its
  // own object.
  final members = <String, List<DeviceObject>>{};
  final objects = <String, ObjectGroup?>{};
  for (final g in catalog.groups.values) {
    final object = index.objectOf(g.address);
    final key = object?.key ?? 'ga:${g.address}';
    objects[key] = object;
    final member = object?.members.where((m) => m.address == g.address).firstOrNull;
    (members[key] ??= []).add(
      DeviceObject(address: g.address, text: member?.function ?? g.name, sends: member?.feedback ?? false),
    );
  }
  for (final MapEntry(:key, value: list) in members.entries) {
    list.sort((a, b) => a.address.compareTo(b.address));
    final object = objects[key];
    final title = object?.title ?? catalog[list.first.address]?.name ?? formatGroup(list.first.address);
    final channel = DeviceChannel('', list, title: title);
    final control = controlOf(channel, store: store);
    if (control == null) continue;
    (rooms[object?.room ?? ''] ??= []).add(RoomControl(title, channel, control));
  }
  final names = rooms.keys.toList()..sort((a, b) => a.isEmpty != b.isEmpty ? (a.isEmpty ? 1 : -1) : a.compareTo(b));
  return {for (final n in names) n: rooms[n]!..sort((a, b) => a.title.compareTo(b.title))};
}

/// What command and status feedback of a switching channel say together.
enum StatusFinding {
  /// The feedback follows the command.
  ok,

  /// Nothing heard yet on the feedback.
  unknown,

  /// The project has no status feedback for it: a display can only guess.
  noStatus,

  /// The feedback says something else than the last command: locked, switched
  /// from elsewhere without the command address knowing, or wrongly linked.
  mismatch,

  /// The feedback address does not answer a read request: a display that reads
  /// at start stays empty or wrong.
  silent;

  bool get issue => this == mismatch || this == silent || this == noStatus;
}

/// Why a display shows the wrong state: compares the last command of [control]
/// with its status feedback. [unanswered] are feedback addresses that did not
/// answer a read request.
StatusFinding statusFinding(ChannelControl control, Map<int, Telegram> latest, {Set<int> unanswered = const {}}) {
  final status = control.status;
  if (control.kind != ControlKind.toggle) return StatusFinding.unknown;
  if (status == null) return StatusFinding.noStatus;
  if (unanswered.contains(status)) return StatusFinding.silent;
  final st = latest[status];
  if (st == null || st.type == TelegramType.read || st.data.isEmpty) return StatusFinding.unknown;
  final cmd = latest[control.address];
  if (cmd == null || cmd.type == TelegramType.read || cmd.data.isEmpty) return StatusFinding.ok;
  if (cmd.data[0] & 1 == st.data[0] & 1) return StatusFinding.ok;
  // Different values: a status well after the command was changed by something
  // else (central function, timer) and is the truth; only a status that came
  // right after the command, or never did, contradicts it.
  final after = st.time.difference(cmd.time);
  return after > const Duration(seconds: 5) ? StatusFinding.ok : StatusFinding.mismatch;
}

/// Waits for any new value telegram on [address] (the answer to a read
/// request); `false` when [timeout] passes without one.
Future<bool> awaitAnswer(TelegramLog log, int address, {Duration timeout = const Duration(seconds: 2)}) {
  final before = log.latest[address];
  final done = Completer<bool>();
  late final Timer timer;
  void check() {
    final t = log.latest[address];
    if (t == null || identical(t, before) || t.outgoing || t.type == TelegramType.read) return;
    timer.cancel();
    log.removeListener(check);
    if (!done.isCompleted) done.complete(true);
  }

  timer = Timer(timeout, () {
    log.removeListener(check);
    if (!done.isCompleted) done.complete(false);
  });
  log.addListener(check);
  return done.future;
}
