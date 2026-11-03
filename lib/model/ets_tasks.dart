import '../knx/group_catalog.dart';
import 'coupler_filter.dart';
import 'device_inventory.dart';
import 'project_check.dart';

/// Kind of a task for the ETS.
enum EtsTaskKind {
  // --- on group addresses, part of the group address import ---

  /// Datapoint type of the group address set or learned in the app, but different
  /// or empty in the project.
  dpt,

  /// The address only has the default name in the project; a name was learned.
  learnedName,

  /// Learned address that is missing from the project.
  learnedNew,

  // --- on group addresses, by hand in the ETS ---

  /// Address without a name (ETS default), not learned either.
  noName,

  /// Address without a datapoint type, not set in the app either.
  noDpt,

  /// Command address that no object in the project sends to (visualization,
  /// logic or panel without a placeholder) – notice.
  withoutSender,

  /// Command address without an object with C + W flags, even without any association.
  withoutReceiver,

  /// Address in main group 14 or 15 with several lines – notice.
  mainGroup1415,

  /// Seen on one line but not on another despite a receiver there: probably
  /// filtered ([EtsTask.line] = the line without a telegram) – notice.
  filterNotForwarded,

  // --- on devices and objects ---

  /// Status address that no object with the T flag sends to.
  statusWithoutTransmit,

  /// Status address without an object with C + R flags (reads stay
  /// unanswered).
  readWithoutReadFlag,

  /// Several objects with C + R flags on one address: several responses.
  multipleReadAnswers,

  /// Object with a group address but without the C flag.
  objectWithoutCommunication,

  /// Several objects send to the same address – notice, often intended.
  multipleSenders,

  /// Device without any associated group address.
  deviceWithoutLinks,

  /// Device responds on the bus but is not in the project (inventory).
  notInProject,

  /// Serial number on the bus differs from the project – device replaced?
  serialMismatch,

  /// Device is in the project but did not respond in the inventory – notice.
  missingOnBus,

  // --- Project ---

  /// Line with more than [ProjectLint.lineReserveLimit] devices – notice.
  crowdedLine,

  /// Line with addresses from other lines whose transition is not yet confirmed
  /// ([EtsTask.count] of them) – notice.
  filterCrossLine,

  /// Deviation from the company standard – notice ([EtsTask.name] says which).
  standardDeviation;

  /// Whether it belongs in the group address import (name, datapoint type, new address).
  bool get importable => this == dpt || this == learnedName || this == learnedNew;
}

/// Communication object of a device: device, number and text.
class EtsObject {
  const EtsObject(this.device, this.number, this.text);
  final int device;
  final int? number;
  final String? text;
}

/// A task: what to do where in the project.
class EtsTask {
  const EtsTask(
    this.kind, {
    this.group,
    this.device,
    this.object,
    this.objectText,
    this.others = const [],
    this.dpt,
    this.name,
    this.line,
    this.count,
    this.serial,
    this.beforeDpt,
    this.beforeName,
  });

  final EtsTaskKind kind;

  /// Affected group address.
  final int? group;

  /// Affected device (individual address).
  final int? device;

  /// Communication object on the device: number and text, as far as known.
  final int? object;
  final String? objectText;

  /// Further objects involved, e.g. the other senders on the same address – also
  /// on the same device (two channels of an actuator).
  final List<EtsObject> others;

  /// New datapoint type ([EtsTaskKind.dpt], [EtsTaskKind.learnedNew]).
  final Dpt? dpt;

  /// Learned name ([EtsTaskKind.learnedName], [EtsTaskKind.learnedNew]).
  final String? name;

  /// Line (area and line as in the individual address, without the device
  /// number) and number of devices ([EtsTaskKind.crowdedLine]) or addresses
  /// ([EtsTaskKind.filterCrossLine]).
  final int? line;
  final int? count;

  /// State in the project before the import (datapoint type or name), so the PDF
  /// can show it even if the catalog already contains what was learned.
  final Dpt? beforeDpt;
  final String? beforeName;

  /// Serial number read on the bus ([EtsTaskKind.serialMismatch],
  /// [EtsTaskKind.notInProject]).
  final String? serial;

  /// Only a notice (intended or not), not a definite deviation.
  bool get hint => switch (kind) {
    EtsTaskKind.multipleSenders ||
    EtsTaskKind.withoutSender ||
    EtsTaskKind.mainGroup1415 ||
    EtsTaskKind.filterNotForwarded ||
    EtsTaskKind.missingOnBus ||
    EtsTaskKind.crowdedLine ||
    EtsTaskKind.filterCrossLine ||
    EtsTaskKind.standardDeviation => true,
    _ => false,
  };
}

/// Deviation from the company standard for the tasks: on an address, a device
/// or a line.
typedef EtsDeviation = ({int? group, int? device, int? line, String text});

/// An address for the ETS group address import: as it should appear in the
/// project afterwards.
typedef EtsImportEntry = ({int address, String name, Dpt? dpt, String? description, String? path});

/// All tasks for the ETS: on group addresses, per device and on the project,
/// from the project checks ([ProjectLint]), the datapoint types set in the app,
/// what was learned without a project, and the device inventory. Data only, so
/// the PDF can be created in the background.
class EtsTasks {
  EtsTasks._(this.groups, this.devices, this.project, this.imports, {required this.hasFlags});

  /// [project] is the imported project (without learned data), [learned] the
  /// learned data, [inventory] the result of the last inventory (empty if none
  /// ran).
  factory EtsTasks.of(
    GroupCatalog project,
    Map<int, Dpt> overrides, {
    GroupCatalog? learned,
    List<InventoryEntry> inventory = const [],
    List<EtsDeviation> deviations = const [],
    List<FilterObservation> observations = const [],
  }) {
    learned ??= GroupCatalog.empty;
    final lint = ProjectLint.of(project);
    final filter = FilterCheck.of(project, observations: observations);
    final groups = <EtsTask>[];
    final imports = <int, EtsImportEntry>{};

    // Datapoint types: set in the app before learned. Learned types are guesses and
    // only fill gaps – a type from the project stays.
    final dpts = <int, Dpt>{
      for (final g in learned.groups.values)
        if (g.dpt case final d? when project[g.address] != null && project[g.address]!.dpt == null) g.address: d,
      ...overrides,
    };
    for (final MapEntry(key: address, value: dpt) in dpts.entries) {
      final info = project[address];
      if (info == null || info.dpt == dpt) continue;
      groups.add(EtsTask(EtsTaskKind.dpt, group: address, dpt: dpt, beforeDpt: info.dpt));
    }
    // Names and new addresses from teach-in.
    for (final g in learned.groups.values) {
      final info = project[g.address];
      final named = !isDefaultGroupName(g);
      if (info == null) {
        groups.add(EtsTask(EtsTaskKind.learnedNew, group: g.address, name: g.name, dpt: overrides[g.address] ?? g.dpt));
      } else if (named && isDefaultGroupName(info)) {
        groups.add(EtsTask(EtsTaskKind.learnedName, group: g.address, name: g.name, beforeName: info.name));
      }
    }
    for (final t in groups) {
      final info = project[t.group!];
      final learnedInfo = learned[t.group!];
      final current = imports[t.group!];
      imports[t.group!] = (
        address: t.group!,
        name: t.kind == EtsTaskKind.dpt ? current?.name ?? info?.name ?? learnedInfo?.name ?? '' : t.name ?? '',
        dpt: t.kind == EtsTaskKind.learnedName ? current?.dpt ?? dpts[t.group!] ?? info?.dpt : t.dpt ?? current?.dpt,
        description: info?.description,
        path: info?.path ?? learnedInfo?.path,
      );
    }
    // By hand in the ETS: what neither the app nor teach-in provides.
    for (final i in lint.incomplete) {
      final a = i.group.address;
      final learnedName = learned[a];
      if (i.noName && (learnedName == null || isDefaultGroupName(learnedName))) {
        groups.add(EtsTask(EtsTaskKind.noName, group: a));
      }
      if (i.noDpt && !dpts.containsKey(a)) groups.add(EtsTask(EtsTaskKind.noDpt, group: a));
    }
    for (final g in lint.withoutSender) {
      groups.add(EtsTask(EtsTaskKind.withoutSender, group: g.address));
    }
    for (final g in lint.withoutReceiver) {
      groups.add(EtsTask(EtsTaskKind.withoutReceiver, group: g.address));
    }
    for (final g in lint.unfilteredMainGroups) {
      groups.add(EtsTask(EtsTaskKind.mainGroup1415, group: g.address));
    }
    for (final n in filter.notForwarded) {
      groups.add(EtsTask(EtsTaskKind.filterNotForwarded, group: n.group.address, line: n.missingOn));
    }
    for (final d in deviations) {
      if (d.group case final g?) groups.add(EtsTask(EtsTaskKind.standardDeviation, group: g, name: d.text));
    }
    groups.sort((a, b) {
      final address = a.group!.compareTo(b.group!);
      return address != 0 ? address : a.kind.index.compareTo(b.kind.index);
    });

    final devices = <int, List<EtsTask>>{};
    void add(EtsTask t) => devices.putIfAbsent(t.device!, () => []).add(t);
    void perLink(GroupInfo g, EtsTaskKind kind, Iterable<GroupLink> links) {
      final all = links.toList();
      for (final l in all) {
        add(
          EtsTask(
            kind,
            group: g.address,
            device: l.device,
            object: l.object,
            objectText: l.text,
            others: [
              for (final o in all)
                if (!identical(o, l)) EtsObject(o.device, o.object, o.text),
            ],
          ),
        );
      }
    }

    for (final (g, l) in lint.objectsWithoutCommunication) {
      perLink(g, EtsTaskKind.objectWithoutCommunication, [l]);
    }
    for (final g in lint.statusWithoutTransmit) {
      perLink(g, EtsTaskKind.statusWithoutTransmit, g.links);
    }
    for (final g in lint.readWithoutReadFlag) {
      perLink(g, EtsTaskKind.readWithoutReadFlag, g.links);
    }
    for (final g in lint.multipleReadAnswers) {
      perLink(g, EtsTaskKind.multipleReadAnswers, g.links.where((l) => l.flags?.answersReads ?? false));
    }
    for (final g in lint.multipleSenders) {
      perLink(g, EtsTaskKind.multipleSenders, g.links.where((l) => l.sends));
    }
    for (final d in lint.devicesWithoutLinks) {
      add(EtsTask(EtsTaskKind.deviceWithoutLinks, device: d.address));
    }
    for (final d in deviations) {
      if (d.device case final device?) add(EtsTask(EtsTaskKind.standardDeviation, device: device, name: d.text));
    }
    // Inventory: only devices whose comparison means something in the ETS.
    for (final e in inventory) {
      switch (e.status) {
        case InventoryStatus.notInProject:
          add(EtsTask(EtsTaskKind.notInProject, device: e.address, serial: e.details?.serial));
        case InventoryStatus.serialMismatch:
          add(EtsTask(EtsTaskKind.serialMismatch, device: e.address, serial: e.details?.serial));
        case InventoryStatus.missing:
          add(EtsTask(EtsTaskKind.missingOnBus, device: e.address));
        case InventoryStatus.match || InventoryStatus.present || InventoryStatus.tunnel || InventoryStatus.unknown:
          break;
      }
    }
    for (final list in devices.values) {
      list.sort((a, b) {
        final hint = (a.hint ? 1 : 0).compareTo(b.hint ? 1 : 0);
        if (hint != 0) return hint;
        return (a.object ?? -1).compareTo(b.object ?? -1);
      });
    }
    return EtsTasks._(
      groups,
      Map.fromEntries(devices.entries.toList()..sort((a, b) => a.key.compareTo(b.key))),
      [
        for (final l in lint.crowdedLines) EtsTask(EtsTaskKind.crowdedLine, line: l.line, count: l.devices),
        for (final MapEntry(key: line, value: count) in filter.openByLine.entries)
          EtsTask(EtsTaskKind.filterCrossLine, line: line, count: count),
        for (final d in deviations)
          if (d.line case final line?) EtsTask(EtsTaskKind.standardDeviation, line: line, name: d.text),
      ],
      imports.values.toList()..sort((a, b) => a.address.compareTo(b.address)),
      hasFlags: lint.hasFlags,
    );
  }

  /// Tasks on group addresses, by address.
  final List<EtsTask> groups;

  /// Tasks per device, by individual address; notices last.
  final Map<int, List<EtsTask>> devices;

  /// Tasks on the project itself (lines).
  final List<EtsTask> project;

  /// Addresses for the group address import: changed datapoint types, learned
  /// names and new addresses, one entry per address.
  final List<EtsImportEntry> imports;

  /// Whether the project contains flags; otherwise the flag checks are missing
  /// (re-import the project).
  final bool hasFlags;

  /// Tasks on group addresses that the import takes care of.
  List<EtsTask> get importable => [
    for (final t in groups)
      if (t.kind.importable) t,
  ];

  /// Tasks on group addresses that have to be done by hand in the ETS.
  List<EtsTask> get manual => [
    for (final t in groups)
      if (!t.kind.importable) t,
  ];

  bool get isEmpty => groups.isEmpty && devices.isEmpty && project.isEmpty;

  int get count => groups.length + project.length + devices.values.fold(0, (n, l) => n + l.length);
}
