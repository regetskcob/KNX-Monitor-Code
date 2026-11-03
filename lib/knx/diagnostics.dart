import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cemi.dart';
import 'knx_tunnel.dart';
import 'telegram.dart';

/// Result of checking an individual address.
enum AddressState {
  /// A device acknowledged the connection setup on the bus.
  present,

  /// No device acknowledged – the address is free.
  free,

  /// No confirmation from the gateway – result unclear.
  unknown,
}

class AddressCheck {
  const AddressCheck(this.address, this.state, {this.maskVersion});

  final int address;
  final AddressState state;

  /// Mask version from the device descriptor (e.g. 0x07B0 = TP1 System B).
  final int? maskVersion;

  String? get maskText => maskVersion?.toRadixString(16).padLeft(4, '0').toUpperCase();
}

/// Diagnostic functions over the tunnel. All of them only read – nothing is programmed or changed.
class Diagnostics {
  Diagnostics(this.tunnel);

  final KnxTunnel tunnel;

  static const _individualAddressRead = [0x01, 0x00]; // A_IndividualAddress_Read
  static const _individualAddressResponse = 0x140;

  /// Finds devices in programming mode (programming LED on).
  ///
  /// Broadcast A_IndividualAddress_Read; only devices in programming mode respond with their
  /// address. Listens for [listen].
  Future<List<int>> findProgrammingMode({Duration listen = const Duration(seconds: 3)}) async {
    final found = <int>{};
    final sub = tunnel.frames.listen((f) {
      if (!f.isConfirmation && f.groupAddressed && f.destination == 0 && f.apci == _individualAddressResponse) {
        found.add(f.source);
      }
    });
    try {
      await tunnel.sendFrame(buildLData(destination: 0, group: true, tpdu: _individualAddressRead, system: true));
      await Future<void>.delayed(listen);
    } finally {
      await sub.cancel();
    }
    return found.toList()..sort();
  }

  /// Checks whether [address] is in use and, if so, reads the mask version.
  ///
  /// Same sequence as the ETS: T_Connect, A_DeviceDescriptor_Read in connection-oriented mode,
  /// T_Disconnect. Some gateways (Gira X1) confirm every address positively – so an address is only
  /// in use once the device itself responds.
  Future<AddressCheck> checkAddress(int address) async {
    final connection = DeviceConnection(tunnel, address);
    try {
      final connected = await connection.open();
      if (connected == null) return AddressCheck(address, AddressState.unknown);
      if (connected == false) return AddressCheck(address, AddressState.free);
      // Devices respond within milliseconds; keep it short so the line scan stays fast.
      final mask = await connection.maskVersion(timeout: const Duration(milliseconds: 1500));
      if (mask == null && !connection.heard) return AddressCheck(address, AddressState.free);
      return AddressCheck(address, AddressState.present, maskVersion: mask);
    } finally {
      await connection.close();
    }
  }

  /// Reads device properties (Device Object) over a connection. `null` if no device on [address]
  /// acknowledges.
  Future<DeviceDetails?> readDeviceInfo(int address) async {
    final c = DeviceConnection(tunnel, address);
    try {
      if (await c.open() != true) return null;
      final mask = await c.maskVersion();
      if (mask == null && !c.heard) return null;
      final manufacturer = await c.readProperty(0, Pid.manufacturerId);
      final serial = await c.readProperty(0, Pid.serialNumber);
      final order = await c.readProperty(0, Pid.orderInfo);
      final hardware = await c.readProperty(0, Pid.hardwareType);
      final firmware = await c.readProperty(0, Pid.firmwareRevision);
      final progMode = await c.readProperty(0, Pid.progMode);
      // Application: program version in the Application Program object (usually index 3 or 4).
      final program = await c.readProperty(3, Pid.programVersion) ?? await c.readProperty(4, Pid.programVersion);
      return DeviceDetails(
        address: address,
        maskVersion: mask,
        manufacturerId: manufacturer != null && manufacturer.length >= 2
            ? (manufacturer[0] << 8) | manufacturer[1]
            : null,
        serial: serial == null || serial.length < 6 ? null : hex(serial.sublist(0, 6)).replaceAll(' ', ''),
        orderInfo: order == null ? null : printableOrder(order),
        hardwareType: hardware == null ? null : hex(hardware).replaceAll(' ', ''),
        firmware: firmware == null || firmware.isEmpty ? null : firmware.first,
        programmingMode: progMode == null || progMode.isEmpty ? null : progMode.first & 0x01 == 1,
        program: program == null || program.length < 5
            ? null
            : (
                manufacturer: (program[0] << 8) | program[1],
                deviceType: (program[2] << 8) | program[3],
                version: program[4],
              ),
      );
    } finally {
      await c.close();
    }
  }

  /// Order numbers are partly ASCII, partly binary values. If it starts with readable text (at
  /// least 3 characters, followed by padding bytes or identifiers like "G1280" + FF FF 01 0F 24),
  /// only the text counts; otherwise hex.
  @visibleForTesting
  static String printableOrder(List<int> bytes) {
    final lead = bytes.takeWhile((b) => b >= 0x20 && b <= 0x7E).toList();
    final text = String.fromCharCodes(lead).trim();
    return text.length >= 3 ? text : hex(bytes).replaceAll(' ', '');
  }
}

/// Property IDs of the Device Object (KNX specification).
abstract final class Pid {
  static const firmwareRevision = 9;
  static const serialNumber = 11;
  static const manufacturerId = 12;
  static const programVersion = 13;
  static const orderInfo = 15;
  static const progMode = 54;
  static const hardwareType = 78;
}

/// Device properties that were read.
class DeviceDetails {
  const DeviceDetails({
    required this.address,
    this.maskVersion,
    this.manufacturerId,
    this.serial,
    this.orderInfo,
    this.hardwareType,
    this.firmware,
    this.programmingMode,
    this.program,
  });

  final int address;
  final int? maskVersion;
  final int? manufacturerId;

  /// 12 hex characters, e.g. "0008123456AB".
  final String? serial;
  final String? orderInfo;
  final String? hardwareType;
  final int? firmware;
  final bool? programmingMode;
  final ({int manufacturer, int deviceType, int version})? program;
}

/// Connection-oriented communication with a device (transport layer): T_Connect, numbered
/// T_Data_Connected with acknowledgements, T_Disconnect.
class DeviceConnection {
  DeviceConnection(this.tunnel, this.address);

  final KnxTunnel tunnel;
  final int address;

  static const _timeout = Duration(seconds: 3);

  int _seq = 0;
  StreamSubscription<CemiFrame>? _sub;
  final _responses = StreamController<CemiFrame>.broadcast();
  bool _open = false;

  /// The device itself sent something (acknowledgement or response).
  bool heard = false;

  Uint8List _frame(List<int> tpdu) => buildLData(destination: address, group: false, tpdu: tpdu, system: true);

  /// Establishes the connection. `true` = device acknowledged, `false` = free, `null` = no
  /// confirmation from the gateway.
  Future<bool?> open() async {
    _sub = tunnel.frames.listen((f) {
      if (f.isConfirmation || f.groupAddressed || f.source != address) return;
      heard = true;
      // Acknowledge numbered data from the device (T_Data_Connected).
      if (f.tpci & 0xC0 == 0x40) {
        final seq = (f.tpci >> 2) & 0x0F;
        // Without confirmation the connection runs into the timeout anyway.
        unawaited(tunnel.sendFrame(_frame([0xC2 | (seq << 2)])).catchError((Object _) => null));
        _responses.add(f);
      }
    });
    final connected = await tunnel.sendFrame(_frame([0x80])); // T_Connect
    _open = connected == true;
    return connected;
  }

  /// Sends an APDU (10-bit [apci] + [data]) and waits for the response with [responseApci].
  Future<CemiFrame?> request(
    int apci,
    List<int> data,
    int responseApci, {
    bool Function(CemiFrame)? match,
    Duration timeout = _timeout,
  }) async {
    if (!_open) return null;
    final response = _responses.stream
        .firstWhere((f) => f.apci == responseApci && (match == null || match(f)))
        .then<CemiFrame?>((f) => f)
        .timeout(timeout, onTimeout: () => null);
    await tunnel.sendFrame(_frame([0x40 | (_seq << 2) | (apci >> 8), apci & 0xFF, ...data]));
    _seq = (_seq + 1) & 0x0F;
    return response;
  }

  /// Mask version from device descriptor type 0.
  Future<int?> maskVersion({Duration timeout = _timeout}) async {
    final r = await request(0x300, const [], 0x340, timeout: timeout);
    final p = r?.payload;
    return p == null || p.length < 2 ? null : (p[0] << 8) | p[1];
  }

  /// A_PropertyValue_Read of one element; `null` on error/timeout.
  Future<List<int>?> readProperty(int objectIndex, int pid) async {
    final r = await request(
      0x3D5,
      [objectIndex, pid, 0x10, 0x01], // 1 element from index 1
      0x3D6,
      match: (f) => f.payload.length >= 2 && f.payload[0] == objectIndex && f.payload[1] == pid,
    );
    final p = r?.payload;
    // Count 0 in the response = property does not exist.
    if (p == null || p.length <= 4 || p[2] >> 4 == 0) return null;
    return p.sublist(4);
  }

  Future<void> close() async {
    if (_open) await tunnel.sendFrame(_frame([0x81])); // T_Disconnect
    _open = false;
    await _sub?.cancel();
    await _responses.close();
  }
}

/// Line scan: checks all addresses of a range one after another like [Diagnostics.checkAddress]
/// (T_Connect, device descriptor, T_Disconnect).
class LineScanRun extends ChangeNotifier {
  LineScanRun(this.tunnel, {required this.area, required this.line, this.from = 0, this.to = 255});

  final KnxTunnel tunnel;
  final int area;
  final int line;
  final int from;
  final int to;

  /// Results in scan order (only used and unclear addresses).
  final results = <AddressCheck>[];
  int checked = 0;
  bool running = false;
  bool done = false;

  int get total => to - from + 1;
  double get progress => total <= 0 ? 1 : checked / total;
  int address(int device) => (area << 12) | (line << 8) | device;

  List<AddressCheck> get present => [
    for (final r in results)
      if (r.state == AddressState.present) r,
  ];

  Future<void> start() async {
    if (running) return;
    running = true;
    done = false;
    results.clear();
    checked = 0;
    notifyListeners();
    final diagnostics = Diagnostics(tunnel);
    try {
      for (var device = from; device <= to && running; device++) {
        try {
          final r = await diagnostics.checkAddress(address(device));
          if (r.state != AddressState.free) results.add(r);
        } on KnxException {
          results.add(AddressCheck(address(device), AddressState.unknown));
        }
        checked++;
        notifyListeners();
      }
    } finally {
      running = false;
      done = true;
      notifyListeners();
    }
  }

  void cancel() {
    running = false;
    notifyListeners();
  }
}
