import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../knx/demo_tunnel.dart';
import 'installation.dart';

/// What the owner of a KNX installation should hold in their own hands once
/// the electrician is done – before the final invoice is paid, or when buying
/// a house. Without it nobody else can maintain or change the installation.
enum HandoverItem {
  /// The ETS project file (.knxproj) with its password.
  projectFile,

  /// The file is the state that is actually loaded in the devices.
  projectCurrent,

  /// Keyring (.knxkeys) with its password, where KNX Secure is used.
  keyring,

  /// BCU keys/device passwords, where devices are protected against download.
  devicePasswords,

  /// Access to the IP interface or router and other network devices.
  gatewayAccess,

  /// Access data and project of the visualization, server or logic module.
  visuAccess,

  /// Plans of the distribution board and the circuits.
  circuitPlan,

  /// List of devices with their location, the labels in the board match it.
  deviceList,

  /// Instruction: how to operate it, whom to call.
  instruction,
}

/// How far an item is.
enum HandoverState {
  /// Not there yet.
  open,

  /// In hand.
  received,

  /// Does not apply to this installation (no KNX Secure, no visualization …).
  notNeeded,
}

/// What the app can tell by itself, without asking.
class HandoverEvidence {
  const HandoverEvidence({
    this.projectDevices = 0,
    this.projectGroups = 0,
    this.keyring = false,
    this.heard = 0,
    this.unknown = 0,
    this.mismatched = 0,
  });

  /// Devices and group addresses of the loaded project. Group addresses
  /// without devices are a CSV export, not the project file.
  final int projectDevices, projectGroups;

  /// Whether a keyring is loaded.
  final bool keyring;

  /// Group addresses heard on the bus, and how many of them the project does
  /// not know or knows with a type the bus contradicts.
  final int heard, unknown, mismatched;

  bool get hasProjectFile => projectDevices > 0;

  /// Enough traffic to say whether the project matches the installation.
  bool get comparable => hasProjectFile && heard >= minHeard;
  static const minHeard = 20;

  /// The loaded project fits what the bus says; `null` = cannot tell yet.
  bool? get projectFits => !comparable ? null : unknown == 0 && mismatched == 0;
}

/// The handover checklist of an installation: what is ticked by hand, plus what
/// the app sees by itself.
class HandoverCheck {
  HandoverCheck([Map<HandoverItem, HandoverState>? states]) : states = states ?? {};

  final Map<HandoverItem, HandoverState> states;

  /// State of [item]: the project file and its fit come from [evidence] where
  /// the app can see them, everything else from the ticks.
  HandoverState stateOf(HandoverItem item, HandoverEvidence evidence) {
    final ticked = states[item] ?? HandoverState.open;
    if (ticked != HandoverState.open) return ticked;
    return switch (item) {
      HandoverItem.projectFile when evidence.hasProjectFile => HandoverState.received,
      HandoverItem.projectCurrent when evidence.projectFits == true => HandoverState.received,
      HandoverItem.keyring when evidence.keyring => HandoverState.received,
      _ => HandoverState.open,
    };
  }

  /// Whether the app found [item] itself rather than the user ticking it.
  bool detected(HandoverItem item, HandoverEvidence evidence) =>
      (states[item] ?? HandoverState.open) == HandoverState.open && stateOf(item, evidence) == HandoverState.received;

  List<HandoverItem> missing(HandoverEvidence evidence) => [
    for (final i in HandoverItem.values)
      if (stateOf(i, evidence) == HandoverState.open) i,
  ];

  int done(HandoverEvidence evidence) => HandoverItem.values.length - missing(evidence).length;

  Map<String, Object?> toJson() => {
    for (final MapEntry(:key, :value) in states.entries)
      if (value != HandoverState.open) key.name: value.name,
  };

  factory HandoverCheck.fromJson(Object? json) => HandoverCheck({
    if (json is Map)
      for (final MapEntry(:key, :value) in json.entries)
        if ((HandoverItem.values.asNameMap()[key], HandoverState.values.asNameMap()[value]) case (
          final item?,
          final state?,
        ))
          item: state,
  });
}

/// The checklist of the active installation (`handover_check.json`); nothing is
/// kept in the demo house.
class HandoverCheckStore extends ChangeNotifier {
  HandoverCheckStore._();

  static final instance = HandoverCheckStore._();
  static const path = 'handover_check.json';

  HandoverCheck check = HandoverCheck();
  String? _loadedFor;

  Future<void> load() async {
    final id = InstallationStore.instance.active.id;
    if (_loadedFor == id) return;
    _loadedFor = id;
    check = HandoverCheck();
    if (!DemoTunnel.active) {
      try {
        final text = await InstallationStore.instance.storage.read(path);
        if (text != null) check = HandoverCheck.fromJson(jsonDecode(text));
      } on Object catch (e) {
        debugPrint('Übergabe-Check nicht geladen: $e');
      }
    }
    notifyListeners();
  }

  Future<void> set(HandoverItem item, HandoverState state) async {
    check.states[item] = state;
    notifyListeners();
    if (DemoTunnel.active) return;
    await InstallationStore.instance.storage.write(path, jsonEncode(check.toJson()));
  }

  @visibleForTesting
  void debugReset() {
    check = HandoverCheck();
    _loadedFor = null;
  }
}
