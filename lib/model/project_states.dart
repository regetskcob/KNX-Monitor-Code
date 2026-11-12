/// Project states of an installation: every imported project stays valid from a date, so that
/// telegrams of the past keep the names and datapoint types of their time (issue #5).
///
/// Storage: the current project stays where it always was (`catalog.json`, which the server reads
/// too). `project_states.json` holds the list of states and, for every state but the current one,
/// a reverse delta: the group addresses and devices that differ from the next newer state, with
/// their older content (`null` = did not exist then). Unchanged entries are stored once, in
/// `catalog.json`. An installation without the file has one state, valid from the beginning.
///
/// The lookup by time lives in `CatalogStore` (`infoOf`, `deviceOf`, `dptFor` of a telegram): with
/// a single state it is one null check, otherwise one integer comparison for telegrams of the
/// current state. Older states are rebuilt on first use and cached.
library;

import 'dart:convert';

import '../knx/group_catalog.dart';
import '../knx/telegram.dart' show GroupStyle;

/// Most states an installation keeps; when there are more, the oldest ones are merged (the second
/// oldest then counts from the beginning).
const maxProjectStates = 12;

/// File of an installation with its project states.
const projectStatesPath = 'project_states.json';

/// One state: a project that was valid from [from] until the next state began.
class ProjectState {
  ProjectState({
    this.from,
    this.imported,
    this.name,
    this.project,
    this.count = 0,
    this.style,
    this.groups,
    this.devices,
  });

  /// Valid from this time on (inclusive); `null` = from the beginning.
  DateTime? from;

  /// When it was imported, if known (an installation from before states does not know).
  final DateTime? imported;

  /// File name of the import ("Haus.knxproj", "Home Assistant").
  final String? name;

  /// Project name from the file.
  final String? project;

  /// Number of group addresses.
  final int count;

  /// Address style, if not three-level.
  final String? style;

  /// Reverse delta against the next newer state: address → the entry as it was in this state
  /// (`GroupInfo.toJson()`), `null` = absent in this state. `null` for the current state.
  Map<int, Map<String, Object?>?>? groups;

  /// Same for devices (`DeviceInfo.toJson()`).
  Map<int, Map<String, Object?>?>? devices;

  Map<String, Object?> toJson() => {
    'from': from?.microsecondsSinceEpoch,
    'at': ?imported?.microsecondsSinceEpoch,
    'name': ?name,
    'project': ?project,
    'count': count,
    'style': ?style,
    if (groups case final g?) 'g': {for (final MapEntry(:key, :value) in g.entries) '$key': value},
    if (devices case final d?) 'd': {for (final MapEntry(:key, :value) in d.entries) '$key': value},
  };

  factory ProjectState.fromJson(Map<String, Object?> j) {
    Map<int, Map<String, Object?>?>? delta(Object? v) => v is! Map
        ? null
        : {
            for (final MapEntry(:key, :value) in v.entries)
              int.parse(key as String): (value as Map?)?.cast<String, Object?>(),
          };
    DateTime? time(Object? v) => v is int ? DateTime.fromMicrosecondsSinceEpoch(v) : null;
    return ProjectState(
      from: time(j['from']),
      imported: time(j['at']),
      name: j['name'] as String?,
      project: j['project'] as String?,
      count: j['count'] as int? ?? 0,
      style: j['style'] as String?,
      groups: delta(j['g']),
      devices: delta(j['d']),
    );
  }
}

/// A group address whose name or type differs between two states.
typedef ProjectChanged = ({GroupInfo before, GroupInfo after});

/// What a state changed against the one before.
class ProjectChanges {
  const ProjectChanges({
    this.added = const [],
    this.removed = const [],
    this.renamed = const [],
    this.retyped = const [],
  });

  final List<GroupInfo> added;
  final List<GroupInfo> removed;
  final List<ProjectChanged> renamed;

  /// Datapoint type changed (a renamed address with a new type is in both lists).
  final List<ProjectChanged> retyped;

  bool get isEmpty => added.isEmpty && removed.isEmpty && renamed.isEmpty && retyped.isEmpty;
}

/// Group addresses added, removed, renamed and retyped from [older] to [newer], by address.
ProjectChanges compareProjects(GroupCatalog older, GroupCatalog newer) {
  final added = <GroupInfo>[];
  final removed = <GroupInfo>[];
  final renamed = <ProjectChanged>[];
  final retyped = <ProjectChanged>[];
  for (final g in newer.groups.values) {
    final before = older.groups[g.address];
    if (before == null) {
      added.add(g);
      continue;
    }
    if (before.name != g.name) renamed.add((before: before, after: g));
    if (before.dpt != g.dpt) retyped.add((before: before, after: g));
  }
  for (final g in older.groups.values) {
    if (!newer.groups.containsKey(g.address)) removed.add(g);
  }
  int byAddress(GroupInfo a, GroupInfo b) => a.address.compareTo(b.address);
  int byAfter(ProjectChanged a, ProjectChanged b) => a.after.address.compareTo(b.after.address);
  return ProjectChanges(
    added: added..sort(byAddress),
    removed: removed..sort(byAddress),
    renamed: renamed..sort(byAfter),
    retyped: retyped..sort(byAfter),
  );
}

/// The states of an installation, oldest first; the last one is the current project.
class ProjectStates {
  ProjectStates([List<ProjectState>? states]) : states = states ?? [];

  final List<ProjectState> states;

  /// Whether there is more than the current project (only then anything is stored or looked up).
  bool get hasPast => states.length > 1;

  /// Start of the current state, if there are older ones.
  DateTime? get currentFrom => hasPast ? states.last.from : null;

  Map<String, Object?> toJson() => {
    'v': 1,
    'states': [for (final s in states) s.toJson()],
  };

  /// Throws on content that is not a list of states; the caller then continues with one state.
  factory ProjectStates.fromJson(Map<String, Object?> j) {
    final states = [for (final s in j['states']! as List) ProjectState.fromJson((s as Map).cast<String, Object?>())];
    if (states.isEmpty) return ProjectStates();
    // The current state carries no delta, every other one does; times ascend.
    states.last
      ..groups = null
      ..devices = null;
    for (var i = 0; i < states.length - 1; i++) {
      states[i].groups ??= {};
      states[i].devices ??= {};
    }
    for (var i = 1; i < states.length; i++) {
      final from = states[i].from;
      final before = states[i - 1].from;
      if (from == null || (before != null && !from.isAfter(before))) throw const FormatException('order');
    }
    return ProjectStates(states);
  }

  /// Index of the state valid at [time]: the last one that began at or before it, the oldest for
  /// times before the first.
  int indexAt(DateTime time) {
    for (var i = states.length - 1; i > 0; i--) {
      if (!time.isBefore(states[i].from!)) return i;
    }
    return 0;
  }

  /// The project of state [index], rebuilt from [current] (the project of the last state).
  GroupCatalog catalogOf(int index, GroupCatalog current) {
    if (index >= states.length - 1) return current;
    final groups = Map.of(current.groups);
    final devices = Map.of(current.devices);
    for (var i = states.length - 2; i >= index; i--) {
      for (final MapEntry(:key, :value) in states[i].groups!.entries) {
        if (value == null) {
          groups.remove(key);
        } else {
          groups[key] = GroupInfo.fromJson(value);
        }
      }
      for (final MapEntry(:key, :value) in states[i].devices!.entries) {
        if (value == null) {
          devices.remove(key);
        } else {
          devices[key] = DeviceInfo.fromJson(value);
        }
      }
    }
    final state = states[index];
    return GroupCatalog(
      groups,
      devices: devices,
      projectName: state.project,
      style: GroupStyle.values.asNameMap()[state.style] ?? GroupStyle.threeLevel,
      manufacturers: current.manufacturers,
      externalSenders: current.externalSenders,
    );
  }

  /// What state [index] changed against the one before; empty for the oldest.
  ProjectChanges changesOf(int index, GroupCatalog current) =>
      index <= 0 ? const ProjectChanges() : compareProjects(catalogOf(index - 1, current), catalogOf(index, current));

  static ProjectState _describe(GroupCatalog c, {DateTime? from, DateTime? imported, String? name}) => ProjectState(
    from: from,
    imported: imported,
    name: name,
    project: c.projectName,
    count: c.length,
    style: c.style == GroupStyle.threeLevel ? null : c.style.name,
  );

  /// Entries of [older] that differ from [newer], and `null` for those only [newer] has.
  static Map<int, Map<String, Object?>?> _delta<T>(
    Map<int, T> newer,
    Map<int, T> older,
    Map<String, Object?> Function(T) toJson,
  ) {
    final delta = <int, Map<String, Object?>?>{};
    for (final MapEntry(:key, :value) in older.entries) {
      final json = toJson(value);
      final now = newer[key];
      if (now == null || jsonEncode(toJson(now)) != jsonEncode(json)) delta[key] = json;
    }
    for (final key in newer.keys) {
      if (!older.containsKey(key)) delta[key] = null;
    }
    return delta;
  }

  static void _setDelta(ProjectState state, GroupCatalog newer, GroupCatalog older) {
    state
      ..groups = _delta(newer.groups, older.groups, (g) => g.toJson())
      ..devices = _delta(newer.devices, older.devices, (d) => d.toJson());
  }

  /// A project was imported at [at]: [next] replaces [previous] (the current project so far).
  /// Returns `false` when nothing changed (same content: only the file name is noted).
  ///
  /// Without a project so far, [next] simply is the project, from the beginning: telegrams
  /// recorded before the first import get its names, as they always did.
  bool push(GroupCatalog previous, GroupCatalog next, {required DateTime at, String? name}) {
    final empty = previous.isEmpty && previous.devices.isEmpty;
    if (states.isEmpty) {
      if (empty) {
        states.add(_describe(next, imported: at, name: name));
        return true;
      }
      // An installation from before states: its project counts from the beginning.
      states.add(_describe(previous));
    }
    final current = states.last;
    final probe = ProjectState();
    _setDelta(probe, next, previous);
    final same = probe.groups!.isEmpty && probe.devices!.isEmpty;
    // Same content, or the state began at this very moment (or later: a date set ahead): replace it.
    if (same || empty || (current.from != null && !at.isAfter(current.from!))) {
      final before = states.length > 1 ? catalogOf(states.length - 2, previous) : null;
      states[states.length - 1] = _describe(
        next,
        from: current.from,
        imported: same ? current.imported : at,
        name: name ?? current.name,
      );
      if (before != null) _setDelta(states[states.length - 2], next, before);
      return !same;
    }
    current
      ..groups = probe.groups
      ..devices = probe.devices;
    states.add(_describe(next, from: at, imported: at, name: name));
    while (states.length > maxProjectStates) {
      // Merge the two oldest: the second oldest now counts from the beginning.
      states.removeAt(0);
      states.first.from = null;
    }
    return true;
  }

  /// Earliest and latest time state [index] may begin: after the state before, before the one
  /// after. `null` for the oldest state, which has no date to set.
  ({DateTime? after, DateTime? before})? dateRange(int index) {
    if (index <= 0 || index >= states.length) return null;
    return (after: states[index - 1].from, before: index + 1 < states.length ? states[index + 1].from : null);
  }

  /// Sets the start of state [index]. Returns `false` if [from] is not between its neighbours
  /// (the order of the states is fixed) or [index] is the oldest state.
  bool setFrom(int index, DateTime from) {
    final range = dateRange(index);
    if (range == null) return false;
    if (range.after case final after? when !from.isAfter(after)) return false;
    if (range.before case final before? when !from.isBefore(before)) return false;
    states[index].from = from;
    return true;
  }

  /// Removes state [index]; the state before it then stays valid until the next one. Removing the
  /// current state goes back to the one before: the returned project is then the current one and
  /// has to be saved. [current] is the project of the last state.
  GroupCatalog? remove(int index, GroupCatalog current) {
    if (index < 0 || index >= states.length || states.length < 2) return null;
    if (index == states.length - 1) {
      final previous = catalogOf(index - 1, current);
      states.removeLast();
      states.last
        ..groups = null
        ..devices = null;
      if (states.length == 1) states.first.from = null;
      return previous;
    }
    if (index == 0) {
      states.removeAt(0);
      states.first.from = null;
      return null;
    }
    // In the middle: the state before has to describe itself against the state after.
    final before = catalogOf(index - 1, current);
    final after = catalogOf(index + 1, current);
    states.removeAt(index);
    _setDelta(states[index - 1], after, before);
    return null;
  }
}
