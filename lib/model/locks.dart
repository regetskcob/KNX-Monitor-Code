import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'device_channels.dart';

/// Which value of a lock address means "locked". Manufacturers differ: a lock
/// object locks on 1, an enable object (DPT 1.003, "Freigabe") locks on 0.
enum LockSense { lockOnOne, lockOnZero }

final _lockName = RegExp(r'sperr|\block|\bdisable|\binhibit|zwangsf|forced', caseSensitive: false);
final _enableName = RegExp(r'freigabe|freigeben|\benable', caseSensitive: false);
final _statusName = RegExp(r'status|rückmeld|rueckmeld|\brm\b|feedback|\bstate\b', caseSensitive: false);

/// How [g] locks, or `null` if it is not a lock address. The name decides
/// before the datapoint type; [inverted] are the addresses whose reading the
/// user has turned around.
LockSense? lockSense(GroupInfo g, Dpt? dpt, {Set<int> inverted = const {}}) {
  if (dpt != null && dpt.main != 1) return null;
  final LockSense sense;
  if (_lockName.hasMatch(g.name)) {
    sense = LockSense.lockOnOne;
  } else if (_enableName.hasMatch(g.name) || dpt?.sub == 3) {
    sense = LockSense.lockOnZero;
  } else {
    return null;
  }
  if (!inverted.contains(g.address)) return sense;
  return sense == LockSense.lockOnOne ? LockSense.lockOnZero : LockSense.lockOnOne;
}

/// One period in which an address was locked.
class LockSpan {
  LockSpan(this.start, {this.repeats = 0});

  /// The telegram that locked: who and when.
  final Telegram start;

  /// The telegram that released it; `null` while it is still locked.
  Telegram? end;

  /// Further "locked" telegrams during the span (cyclic sending).
  int repeats;

  /// The start is only the first evidence: a response to a read request, or
  /// the address was already locked when the recording began.
  bool get sinceAtLeast => start.type == TelegramType.response;

  Duration length(DateTime now) => (end?.time ?? now).difference(start.time);
}

/// A lock address with everything the recording says about it.
class LockTrack {
  LockTrack(this.info, this.sense, this.targets);

  final GroupInfo info;
  final LockSense sense;

  /// Devices the lock acts on: those that receive the address (project links).
  final List<int> targets;

  /// Lock periods, oldest first.
  final spans = <LockSpan>[];

  /// Last value telegram on the address.
  Telegram? last;

  int get address => info.address;

  /// `null` = nothing heard yet.
  bool? get locked => last == null ? null : spans.isNotEmpty && spans.last.end == null;

  /// The running lock, if any.
  LockSpan? get active => locked == true ? spans.last : null;

  /// Whether the address reports a lock rather than setting one.
  bool get isStatus => _statusName.hasMatch(info.name);
}

bool _locks(LockSense sense, Telegram t) => (t.data.isNotEmpty && t.data[0] & 1 == 1) == (sense == LockSense.lockOnOne);

/// All lock addresses of [catalog] with their lock periods from [history]
/// (chronological): who locked what when, and when and by whom it was
/// released. Read requests say nothing and are skipped.
List<LockTrack> lockTracks(
  GroupCatalog catalog,
  List<Telegram> history, {
  CatalogStore? store,
  Set<int> inverted = const {},
}) {
  final c = store ?? CatalogStore.instance;
  final tracks = <int, LockTrack>{};
  for (final g in catalog.groups.values) {
    final sense = lockSense(g, c.dptOf(g.address), inverted: inverted);
    if (sense == null) continue;
    tracks[g.address] = LockTrack(g, sense, [
      for (final l in g.links)
        if (!l.sends) l.device,
    ]);
  }
  if (tracks.isEmpty) return const [];
  for (final t in history) {
    final track = tracks[t.destination];
    if (track == null || t.type == TelegramType.read) continue;
    track.last = t;
    final open = track.spans.isNotEmpty && track.spans.last.end == null ? track.spans.last : null;
    if (_locks(track.sense, t)) {
      if (open == null) {
        track.spans.add(LockSpan(t));
      } else {
        open.repeats++;
      }
    } else if (open != null) {
      open.end = t;
    }
  }
  return tracks.values.toList()..sort((a, b) {
    // Locked first, then by the most recent activity.
    if ((a.locked == true) != (b.locked == true)) return a.locked == true ? -1 : 1;
    final at = a.last?.time, bt = b.last?.time;
    if (at == null || bt == null) return at == bt ? a.address.compareTo(b.address) : (at == null ? 1 : -1);
    return bt.compareTo(at);
  });
}

/// The lock that is active on [channel] right now, from the lock objects among
/// its own objects; `null` if none is locked.
LockTrack? activeLockOf(DeviceChannel channel, List<LockTrack> tracks) {
  final addresses = {for (final o in channel.objects) o.address};
  return tracks.where((t) => t.locked == true && addresses.contains(t.address)).firstOrNull;
}

final _hasLocks = Expando<bool>();

/// Whether [catalog] has lock addresses at all (remembered per catalog).
bool hasLocks(GroupCatalog catalog, {CatalogStore? store}) => _hasLocks[catalog] ??= () {
  final c = store ?? CatalogStore.instance;
  return catalog.groups.values.any((g) => lockSense(g, c.dptOf(g.address)) != null);
}();
