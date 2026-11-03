import 'dart:async';

import 'package:flutter/foundation.dart';

import '../knx/diagnostics.dart';
import '../knx/group_catalog.dart';
import '../knx/knx_tunnel.dart';
import '../knx/telegram.dart';

/// Comparison of a device on the bus with the project.
enum InventoryStatus {
  /// On the bus and in the project; the serial number matches or is not stored.
  match,

  /// On the bus, without a loaded project – nothing to compare.
  present,

  /// On the bus, serial number differs from the project (replaced?).
  serialMismatch,

  /// On the bus, but not in the project.
  notInProject,

  /// Tunnel address of a gateway (occupied while a tunnel is open).
  tunnel,

  /// In the project, but not found on the bus.
  missing,

  /// The gateway did not confirm the connection – result unclear.
  unknown,
}

/// Firmware version as "1.2"; "–" if unreadable or 0 (many devices report 0
/// instead of omitting the property).
String firmwareText(int? firmware) => firmware == null || firmware == 0 ? '–' : '${firmware >> 4}.${firmware & 0x0F}';

/// A device in the inventory list.
class InventoryEntry {
  InventoryEntry(this.address, this.status, {this.check, this.details, this.project});

  final int address;
  InventoryStatus status;
  final AddressCheck? check;

  /// Properties read (manufacturer, serial number …); `null` if not read
  /// (missing, System 1 without properties, timeout).
  DeviceDetails? details;

  /// Device according to the project.
  final DeviceInfo? project;

  /// Mask version from the descriptor or the details.
  int? get maskVersion => details?.maskVersion ?? check?.maskVersion;

  /// Serial number according to the project, if it differs from the one read.
  String? get projectSerial => project?.serial;
}

/// Device inventory of a line via the bus – without the ETS, read-only.
///
/// Checks address by address like the line scan (T_Connect, descriptor,
/// T_Disconnect) and, for occupied addresses, reads manufacturer, serial number,
/// order number, firmware and application over a second connection (property
/// read on the device object). Everything one after another, with [pause]
/// between addresses, so the bus stays free. Nothing is written.
class DeviceInventory extends ChangeNotifier {
  /// Result of the last complete inventory per installation (in memory only, until
  /// restart); empty until one has run in this installation.
  static final _last = <String, List<InventoryEntry>>{};

  static List<InventoryEntry> lastFor(String installation) => _last[installation] ?? const [];

  @visibleForTesting
  static void debugResetLast() => _last.clear();

  DeviceInventory(
    this.tunnel, {
    required this.area,
    required this.line,
    this.from = 0,
    this.to = 255,
    GroupCatalog? catalog,
    this.pause = const Duration(milliseconds: 150),
    this.installation = '',
  }) : catalog = catalog ?? GroupCatalog.empty;

  /// Installation the run belongs to ([lastFor]).
  final String installation;

  final KnxTunnel tunnel;
  final int area;
  final int line;
  final int from;
  final int to;
  final GroupCatalog catalog;

  /// Pause between two addresses (throttling).
  final Duration pause;

  /// Occupied, unclear and (after the run) missing devices in address order.
  final entries = <InventoryEntry>[];
  int checked = 0;
  bool running = false;
  bool done = false;

  int get total => to - from + 1;
  double get progress => total <= 0 ? 1 : checked / total;
  int address(int device) => (area << 12) | (line << 8) | device;

  int count(InventoryStatus status) => entries.where((e) => e.status == status).length;

  /// Device names for other tools (e.g. teach-in without a project): name from the
  /// project, otherwise manufacturer and order number from the device.
  Map<int, String> names({String Function(int manufacturerId)? manufacturer}) => {
    for (final e in entries) e.address: ?(e.project?.name ?? _readName(e, manufacturer)),
  };

  String? _readName(InventoryEntry e, String Function(int)? manufacturer) {
    final d = e.details;
    if (d == null) return null;
    final parts = [
      if (d.manufacturerId case final id?) manufacturer?.call(id) ?? catalog.manufacturers[id],
      d.orderInfo,
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// System 1 devices (mask 0x001x) have no properties: do not ask, otherwise
  /// every read waits for the timeout.
  static bool hasProperties(int? mask) => mask == null || mask >> 8 != 0;

  Set<int> get _tunnels {
    final gateway = tunnel.gatewayInfo.value;
    return {
      ?tunnel.tunnelAddress,
      for (final slot in gateway?.slots ?? const []) slot.address,
      for (final d in catalog.devices.values)
        if (d.isTunnel) d.address,
    };
  }

  bool _inRange(int pa) => (pa >> 12) == area && ((pa >> 8) & 0x0F) == line && (pa & 0xFF) >= from && (pa & 0xFF) <= to;

  Future<void> start() async {
    if (running) return;
    running = true;
    done = false;
    entries.clear();
    checked = 0;
    _notify();
    final diagnostics = Diagnostics(tunnel);
    final tunnels = _tunnels;
    try {
      for (var device = from; device <= to && running; device++) {
        final pa = address(device);
        try {
          final check = await diagnostics.checkAddress(pa);
          if (check.state != AddressState.free) {
            final project = catalog.devices[pa];
            final entry = InventoryEntry(
              pa,
              check.state == AddressState.unknown ? InventoryStatus.unknown : InventoryStatus.match,
              check: check,
              project: project,
            );
            entries.add(entry);
            _notify();
            if (check.state == AddressState.present && hasProperties(check.maskVersion) && running) {
              await Future<void>.delayed(pause);
              entry.details = await diagnostics.readDeviceInfo(pa);
            }
            entry.status = classify(entry, tunnels: tunnels, hasProject: catalog.devices.isNotEmpty);
          }
        } on KnxException {
          entries.add(InventoryEntry(pa, InventoryStatus.unknown, project: catalog.devices[pa]));
        }
        checked++;
        _notify();
        if (running && device < to) await Future<void>.delayed(pause);
      }
      // Project devices that did not respond (only within the checked range).
      final seen = {for (final e in entries) e.address};
      for (final d in catalog.devices.values) {
        if (d.isTunnel || seen.contains(d.address) || !_inRange(d.address)) continue;
        if ((d.address & 0xFF) >= from + checked) continue;
        entries.add(InventoryEntry(d.address, InventoryStatus.missing, project: d));
      }
      entries.sort((a, b) => a.address.compareTo(b.address));
      // For the "Aufgaben für die ETS" (ETS tasks), on the installation of this run.
      _last[installation] = List.unmodifiable(entries);
    } finally {
      running = false;
      done = true;
      _notify();
    }
  }

  /// Status of an occupied device from the project and the data read.
  static InventoryStatus classify(InventoryEntry e, {required Set<int> tunnels, required bool hasProject}) {
    if (e.status == InventoryStatus.unknown) return InventoryStatus.unknown;
    // Tunnel first: tunnel addresses maintained in the project are not a device of their own either.
    if (tunnels.contains(e.address)) return InventoryStatus.tunnel;
    if (e.project == null) return hasProject ? InventoryStatus.notInProject : InventoryStatus.present;
    final read = e.details?.serial;
    final known = e.project!.serial;
    if (read != null && known != null && read.toUpperCase() != known.toUpperCase()) {
      return InventoryStatus.serialMismatch;
    }
    return InventoryStatus.match;
  }

  void cancel() {
    running = false;
    _notify();
  }

  bool _disposed = false;

  /// The run only ends after the current query – by then the page may already be closed.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    running = false;
    super.dispose();
  }

  /// List as CSV (semicolon, Excel-compatible) for sharing.
  String toCsv({required String Function(InventoryStatus) statusText, String Function(int)? manufacturer}) {
    String cell(Object? v) {
      final text = '${v ?? ''}';
      // Defuse formulas in spreadsheets, double the quotation marks.
      final safe = RegExp(r'^[=+\-@]').hasMatch(text) ? "'$text" : text;
      return '"${safe.replaceAll('"', '""')}"';
    }

    final b = StringBuffer()
      ..writeln(
        [
          'Address',
          'Status',
          'Project name',
          'Manufacturer',
          'Order',
          'Serial',
          'Project serial',
          'Firmware',
          'Application',
          'Mask',
        ].map(cell).join(';'),
      );
    for (final e in entries) {
      final d = e.details;
      final program = d?.program;
      b.writeln(
        [
          formatIndividual(e.address),
          statusText(e.status),
          e.project?.name,
          if (d?.manufacturerId case final id?) manufacturer?.call(id) ?? catalog.manufacturers[id] ?? id else null,
          d?.orderInfo,
          d?.serial,
          e.projectSerial,
          if (d != null) firmwareText(d.firmware) else null,
          if (program != null)
            '${program.manufacturer.toRadixString(16).padLeft(4, '0')}-'
                '${program.deviceType.toRadixString(16).padLeft(4, '0')} v${program.version}'
          else
            null,
          e.maskVersion?.toRadixString(16).padLeft(4, '0').toUpperCase(),
        ].map(cell).join(';'),
      );
    }
    return b.toString();
  }
}
