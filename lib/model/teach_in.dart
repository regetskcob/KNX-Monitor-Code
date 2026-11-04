import '../knx/dpt_guess.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';

/// An event on the bus: a device's command (e.g. a button press) and the
/// telegrams that follow shortly after (status feedback from the actuators).
///
/// Pure, without outside state; the basis for teach-in without a project and
/// later for surveying unknown installations.
class BusEvent {
  BusEvent(this.telegrams) : assert(telegrams.isNotEmpty);

  /// Telegrams in chronological order; the first one triggered the event.
  final List<Telegram> telegrams;

  DateTime get start => telegrams.first.time;
  DateTime get end => telegrams.last.time;

  /// Individual address of the triggering device.
  int get initiator => telegrams.first.source;

  /// Whether it was sent by us (switching from the app).
  bool get own => telegrams.first.outgoing;

  /// What was pressed: only the address of the first telegram. Everything else in
  /// the window – including further telegrams from the same device – is
  /// [feedback] and at most a possible status feedback ([likelyFeedback]).
  List<int> get commands => [telegrams.first.destination];

  /// Remaining group addresses: status feedback and consequences of the command.
  List<int> get feedback {
    final cmd = commands.toSet();
    return [
      ...{
        for (final t in telegrams)
          if (t.type != TelegramType.read && !cmd.contains(t.destination)) t.destination,
      },
    ];
  }

  /// Telegrams of a group address in this event.
  List<Telegram> of(int address) => [
    for (final t in telegrams)
      if (t.destination == address) t,
  ];

  /// Who sent [address] in this event (first telegram).
  int? senderOf(int address) => of(address).where((t) => t.type != TelegramType.read).firstOrNull?.source;

  /// Guessed type per group address; [names] refines it.
  DptGuess? guess(int address, {String? name}) => guessDpt(of(address), name: name);
}

/// Captures events from a telegram stream: a write telegram starts one, and
/// everything within [window] after it belongs to it. The window counts from
/// the command, not from the last telegram – otherwise dense traffic would chain
/// everything into one event. Status feedback usually arrives after 100–500 ms.
///
/// Measured values (2 bytes and more) do not start an event by default –
/// otherwise cyclic sensors would intercept every attempt – and then do not end
/// up in the event as feedback of a button press either ([unlikelyFeedback]).
/// [ignore]: addresses that never start one (e.g. skipped by the user).
///
/// Background traffic (cyclic sensors, status, logic) does not start one: an
/// event is only started by a sender that has sent nothing for [quiet] (typical
/// for a push button), or by an already recognized push button on an address
/// that has been silent that long (the next rocker of the same push button).
/// So an actuator that sends continuously does not start one even with a new
/// address. In return, capturing only listens for [warmUp] at the beginning
/// ([learningAt]); the existing capture ([seed]) counts too.
class EventCapture {
  EventCapture({
    required this.onEvent,
    this.window = const Duration(seconds: 1),
    this.measurements = false,
    this.own = false,
    this.isStatus,
    this.warmUp = Duration.zero,
    Set<int>? ignore,
  }) : ignore = ignore ?? {};

  /// Silent this long, then an address or sender counts as new.
  static const quiet = Duration(minutes: 10);

  /// Quiet listening at the start, while the bus is still unknown.
  final Duration warmUp;

  /// Last seen per group address or sender (bus time).
  final _addressSeen = <int, DateTime>{};
  final _sourceSeen = <int, DateTime>{};

  /// Start of listening (oldest known telegram or first tick).
  DateTime? _since;

  /// Whether the next write telegram starts an event in any case (demo push button).
  bool _armed = false;

  /// Senders that have already started an event – push buttons.
  final _buttons = <int>{};

  /// The next press is certain to come (demo push button): accept it without the
  /// learning phase and the quiet rule.
  void expectPress() {
    _open = null;
    _armed = true;
  }

  /// Takes over known traffic, e.g. the session's capture.
  void seed(Iterable<Telegram> history) {
    for (final t in history) {
      _remember(t);
    }
  }

  /// Whether capturing is still only listening at bus time [at], without catching anything.
  bool learningAt(DateTime at) {
    if (warmUp <= Duration.zero) return false;
    final since = _since;
    return since == null || at.difference(since) < warmUp;
  }

  /// Progress of the learning phase (0–1) at time [at].
  double learnProgress(DateTime at) {
    final since = _since;
    if (warmUp <= Duration.zero) return 1;
    if (since == null) return 0;
    return (at.difference(since).inMilliseconds / warmUp.inMilliseconds).clamp(0, 1).toDouble();
  }

  void _remember(Telegram t) {
    final since = _since;
    if (since == null || t.time.isBefore(since)) _since = t.time;
    if (t.type == TelegramType.read || t.outgoing) return;
    _addressSeen[t.destination] = t.time;
    _sourceSeen[t.source] = t.time;
  }

  bool _quietSince(Map<int, DateTime> seen, int key, DateTime at) {
    final last = seen[key];
    return last == null || at.difference(last) > quiet;
  }

  /// Like a button press: a sender that was silent, or a known push button on an
  /// address that was silent.
  bool _fresh(Telegram t) =>
      t.outgoing ||
      _quietSince(_sourceSeen, t.source, t.time) ||
      (_buttons.contains(t.source) && _quietSince(_addressSeen, t.destination, t.time));

  /// Whether the address is a status feedback (according to the project). A status
  /// never starts an event – what gets pressed is a command, not a valve state.
  final bool Function(int address)? isStatus;

  final void Function(BusEvent event) onEvent;
  final Duration window;

  /// Measured values also start an event.
  bool measurements;

  /// Telegrams sent by us (switching from the app) also start one.
  bool own;

  final Set<int> ignore;

  List<Telegram>? _open;

  /// Whether an event is currently running.
  bool get collecting => _open != null;

  /// Whether [t] can start an event.
  bool starts(Telegram t) =>
      t.type == TelegramType.write &&
      (own || !t.outgoing) &&
      (_armed || (!learningAt(t.time) && _fresh(t))) &&
      !ignore.contains(t.destination) &&
      !ignoreSources.contains(t.source) &&
      !(isStatus?.call(t.destination) ?? false) &&
      (measurements || t.isSmall || t.data.length <= 1);

  void add(Telegram t) {
    final open = _open;
    if (open != null) {
      if (!t.time.isAfter(open.first.time.add(window))) {
        open.add(t);
        _remember(t);
        return;
      }
      _close();
    }
    if (starts(t)) {
      _open = [t];
      _armed = false;
      if (!t.outgoing) _buttons.add(t.source);
    }
    _remember(t);
  }

  /// Closes an open event once its [window] has passed (call regularly, e.g.
  /// every quarter second). The first tick starts the learning phase even on a
  /// silent bus.
  void tick(DateTime now) {
    _since ??= now;
    final open = _open;
    if (open != null && now.isAfter(open.first.time.add(window))) _close();
  }

  /// Closes an open event immediately.
  void flush() {
    if (_open != null) _close();
  }

  /// Discards an open event.
  void reset() => _open = null;

  /// Devices that no longer start an event (heating actuator, weather station …).
  final ignoreSources = <int>{};

  /// How often an event with this command address or from this device went
  /// unused.
  final _passed = <int, int>{};
  final _passedSources = <int, int>{};

  /// [e] went unused (discarded or replaced by a newer one). An address that goes
  /// unused twice is background traffic (valves, presence, time); likewise a
  /// device after three times (all valves of an actuator).
  void passed(BusEvent e) {
    for (final a in e.commands) {
      if ((_passed[a] = (_passed[a] ?? 0) + 1) >= 2) ignore.add(a);
    }
    if (e.own) return;
    final s = e.initiator;
    if ((_passedSources[s] = (_passedSources[s] ?? 0) + 1) >= 3) ignoreSources.add(s);
  }

  void _close() {
    final open = _open!;
    _open = null;
    final event = BusEvent(open);
    if (measurements) return onEvent(event);
    // Measured values off: do not even show sensor values caught by chance.
    final drop = unlikelyFeedback(event);
    onEvent(drop.isEmpty ? event : BusEvent([...open.where((t) => !drop.contains(t.destination))]));
  }
}

/// Remaining addresses that are probably the status feedback to the command and
/// are therefore pre-checked: same main group as the command (common scheme
/// "1/0/4 switch, 1/1/4 status"), same length and from another device. Anything
/// else sending at the same time is only offered unchecked by teach-in as
/// "Auch gesehen" (also seen).
Set<int> likelyFeedback(BusEvent e) {
  final command = e.telegrams.first;
  final main = command.destination >> 11;
  final length = payloadLength(command);
  return {
    for (final a in e.feedback)
      if (a >> 11 == main &&
          e.of(a).any((t) => t.type != TelegramType.read && t.source != command.source && payloadLength(t) == length))
        a,
  };
}

/// Addresses of an event that probably do not belong to it: measured values
/// (2 bytes and more) that happened to arrive after a switching command.
Set<int> unlikelyFeedback(BusEvent e) {
  final starter = payloadLength(e.telegrams.first);
  if (starter >= 2) return {};
  return {
    for (final a in e.feedback)
      if (e.of(a).any((t) => t.type != TelegramType.read && payloadLength(t) >= 2)) a,
  };
}

/// What is saved when teaching in an event.
class TeachInEntry {
  const TeachInEntry({
    required this.room,
    required this.name,
    required this.dpts,
    this.device,
    this.statusSuffix = 'Status',
    this.feedback = true,
    this.skip = const {},
  });

  final String room;

  /// What was pressed, e.g. "Deckenlicht" (ceiling light).
  final String name;

  /// Name of the triggering device, e.g. "Taster Küche"; `null` = do not name it.
  final String? device;

  /// Selected type per group address.
  final Map<int, Dpt> dpts;

  /// Suffix for status addresses, e.g. "Deckenlicht Status".
  final String statusSuffix;

  /// Whether to teach in the status feedback too.
  final bool feedback;

  /// Addresses that do not belong (e.g. a sensor that happened to send).
  final Set<int> skip;
}

/// Builds group addresses and the device from [event] and [entry] in the format
/// of a CSV import (name, path = room, DPT). Several command addresses of one
/// button press (e.g. switching and dimming) are numbered.
({List<GroupInfo> groups, List<DeviceInfo> devices}) teachIn(BusEvent event, TeachInEntry entry) {
  final room = entry.room.trim();
  final name = entry.name.trim();
  final path = room.isEmpty ? null : room;
  final commands = [
    for (final a in event.commands)
      if (!entry.skip.contains(a)) a,
  ];
  final feedback = [
    if (entry.feedback)
      for (final a in event.feedback)
        if (!entry.skip.contains(a)) a,
  ];
  String numbered(String base, int i, int count) => count > 1 ? '$base ${i + 1}' : base;
  Dpt? dpt(int a) => entry.dpts[a] ?? event.guess(a, name: name)?.dpt;
  final groups = [
    for (final (i, a) in commands.indexed)
      GroupInfo(address: a, name: numbered(name, i, commands.length), path: path, dpt: dpt(a)),
    for (final (i, a) in feedback.indexed)
      GroupInfo(address: a, name: numbered('$name ${entry.statusSuffix}', i, feedback.length), path: path, dpt: dpt(a)),
  ];
  final device = entry.device?.trim();
  final devices = [
    if (!event.own && device != null && device.isNotEmpty)
      DeviceInfo(address: event.initiator, name: device, location: path),
  ];
  return (groups: groups, devices: devices);
}

/// Project and learned data combined: the project takes precedence; learned
/// names remain for addresses missing from the project. If the project only
/// lacks the type, the learned one applies.
GroupCatalog mergeLearned(GroupCatalog project, GroupCatalog learned) {
  if (learned.isEmpty && learned.devices.isEmpty) return project;
  if (project.isEmpty && project.devices.isEmpty) return learned;
  return GroupCatalog(
    {
      ...learned.groups,
      for (final MapEntry(key: a, value: g) in project.groups.entries)
        a: g.dpt == null && learned[a]?.dpt != null
            ? GroupInfo(
                address: a,
                name: g.name,
                path: g.path,
                dpt: learned[a]!.dpt,
                description: g.description,
                links: g.links,
              )
            : g,
    },
    devices: {...learned.devices, ...project.devices},
    projectName: project.projectName,
    manufacturers: project.manufacturers,
    style: project.style,
  );
}

/// [catalog] with the names corrected in the app (`CatalogStore.names`) instead of those from the
/// project; addresses the catalog does not know are skipped.
GroupCatalog withNames(GroupCatalog catalog, Map<int, String> names) {
  if (names.isEmpty) return catalog;
  return GroupCatalog(
    {
      for (final MapEntry(key: a, value: g) in catalog.groups.entries)
        a: switch (names[a]) {
          final name? => GroupInfo(
            address: a,
            name: name,
            path: g.path,
            dpt: g.dpt,
            description: g.description,
            links: g.links,
          ),
          null => g,
        },
    },
    devices: catalog.devices,
    projectName: catalog.projectName,
    manufacturers: catalog.manufacturers,
    style: catalog.style,
  );
}

/// Rooms that already occur in the learned data or the project (for suggestions).
List<String> knownRooms(GroupCatalog c) {
  final rooms = <String>{
    for (final g in c.groups.values)
      if (g.path != null && !g.path!.contains('›')) g.path!,
    for (final d in c.devices.values)
      if (d.location case final l? when !l.contains('›')) l,
  };
  return rooms.toList()..sort();
}
