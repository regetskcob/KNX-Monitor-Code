// DALI datapoint types a KNX-DALI gateway sends on the bus, decoded into values (no texts).
//
// Pure Dart with nothing but dart:convert: the add-on server keeps a byte-identical copy of this file
// (ha-addon/knx_monitor/server/lib/src/dali.dart; test/dali_codec_test.dart in the app and
// test/dali_test.dart in the server compare the two), so app, add-on and box decode, check and log
// the same way. The file can move to the
// open-source package `knx` (github.com/regetskcob/dart-knx) later; nothing here depends on the app.
//
// Bit layouts: KNX System Specifications 03_07_02 "Datapoint Types" v02.02.01, clauses 6.7.1
// (237.600), 6.8.1 (238.600), 6.11 (244.600) and 6.12 (245.600), cross-checked with the field
// order in the ETS master data (knx_master.xml, DPST-237-600 … DPST-245-600). A wrong length or a
// reserved value gives `null`: the monitor then shows hex instead of a guessed text.

import 'dart:convert';

/// Fault flags of a DALI control gear, as a bit set.
abstract final class DaliFault {
  /// The lamp connected to the control gear failed.
  static const lamp = 1;

  /// Internal failure of the control gear (ballast, driver).
  static const gear = 2;

  /// Converter error (emergency lighting only).
  static const converter = 4;
}

/// Whether (main, sub) is one of the DALI types decoded here. Main type 238 also has
/// 238.001 (scene configuration), so it needs the subtype; the others have 600 only.
bool isDaliDpt(int main, int? sub) => switch (main) {
  237 || 244 || 245 => sub == null || sub == 600,
  238 => sub == 600,
  _ => false,
};

/// Whether (main, sub) reports faults per DALI address (237.600, 238.600).
bool isDaliDiagnosticDpt(int main, int? sub) => (main == 237 || main == 238) && isDaliDpt(main, sub);

/// Payload length in bytes of a DALI type, `null` for other types.
int? daliDptSize(int main) => const {237: 2, 238: 1, 244: 2, 245: 6}[main];

/// DPT 237.600 DPT_DALI_Control_Gear_Diagnostic (2 bytes, B10U6).
///
/// `r r r r r CE BF LF | RR AI Addr(6)`, most significant byte first.
class DaliGearDiagnostic {
  const DaliGearDiagnostic({
    required this.converterError,
    required this.ballastFailure,
    required this.lampFailure,
    required this.readRequest,
    required this.isGroup,
    required this.address,
  });

  /// CE, bit 10: converter error (reserved for emergency lighting).
  final bool converterError;

  /// BF, bit 9: internal failure of the control gear.
  final bool ballastFailure;

  /// LF, bit 8: failure of the connected lamp.
  final bool lampFailure;

  /// RR, bit 7: the telegram asks the gateway for this address (input). Not set: the gateway
  /// answers or reports on its own. A request carries no state.
  final bool readRequest;

  /// AI, bit 6: [address] is a DALI group (0 to 15) instead of a device (0 to 63).
  ///
  /// The prose of 03_07_02 6.7.1 contradicts itself here ("Device Address (1) or a DALI Group
  /// Address (0)"); the encoding column of the same table, the ETS master data
  /// (`Cleared="Device Address" Set="Group Address"`) and KNXUltimate all say 0 = device,
  /// 1 = group, and so does this code.
  final bool isGroup;

  /// Bits 0 to 5: DALI short address or group.
  final int address;

  /// Set flags as [DaliFault] bits.
  int get faults =>
      (lampFailure ? DaliFault.lamp : 0) |
      (ballastFailure ? DaliFault.gear : 0) |
      (converterError ? DaliFault.converter : 0);
}

/// Decodes DPT 237.600. `null` for a wrong length, set reserved bits (11 to 15) or a group
/// above 15.
DaliGearDiagnostic? decodeDaliGearDiagnostic(List<int> d) {
  if (d.length != 2 || d[0] & 0xF8 != 0) return null;
  final isGroup = d[1] & 0x40 != 0;
  final address = d[1] & 0x3F;
  if (isGroup && address > 15) return null;
  return DaliGearDiagnostic(
    converterError: d[0] & 0x04 != 0,
    ballastFailure: d[0] & 0x02 != 0,
    lampFailure: d[0] & 0x01 != 0,
    readRequest: d[1] & 0x80 != 0,
    isGroup: isGroup,
    address: address,
  );
}

/// DPT 238.600 DPT_DALI_Diagnostics (1 byte, B2U6): `BF LF Addr(6)`.
class DaliDiagnostic {
  const DaliDiagnostic({required this.ballastFailure, required this.lampFailure, required this.address});

  /// BF, bit 7: internal failure of the control gear.
  final bool ballastFailure;

  /// LF, bit 6: failure of the connected lamp.
  final bool lampFailure;

  /// Bits 0 to 5: DALI short address.
  final int address;

  /// Set flags as [DaliFault] bits.
  int get faults => (lampFailure ? DaliFault.lamp : 0) | (ballastFailure ? DaliFault.gear : 0);
}

/// Decodes DPT 238.600. `null` for a wrong length.
DaliDiagnostic? decodeDaliDiagnostic(List<int> d) {
  if (d.length != 1) return null;
  return DaliDiagnostic(ballastFailure: d[0] & 0x80 != 0, lampFailure: d[0] & 0x40 != 0, address: d[0] & 0x3F);
}

/// Fault report of one DALI address, whichever of the two diagnostic types carried it.
typedef DaliReport = ({int address, bool isGroup, int faults, bool readRequest});

/// The fault report in [d] for a diagnostic type ([main] 237 or 238), otherwise `null`.
DaliReport? decodeDaliReport(int main, List<int> d) {
  if (main == 237) {
    final v = decodeDaliGearDiagnostic(d);
    return v == null ? null : (address: v.address, isGroup: v.isGroup, faults: v.faults, readRequest: v.readRequest);
  }
  if (main == 238) {
    final v = decodeDaliDiagnostic(d);
    return v == null ? null : (address: v.address, isGroup: false, faults: v.faults, readRequest: false);
  }
  return null;
}

/// Converter mode according to the DALI converter state machine (DPT 244.600, field CM).
enum ConverterMode {
  unknown,
  normal,
  inhibit,
  hardwiredInhibit,
  rest,
  emergency,
  extendedEmergency,
  functionTest,
  durationTest,
  partialDurationTest,
}

/// A 2-bit field with "unknown, no, yes" (pending tests, converter failure).
enum ConverterFlag { unknown, no, yes }

/// DPT 244.600 DPT_Converter_Status (2 bytes, N4B4N2N2N2N2).
///
/// `CM(4) r r HS HI | FP(2) DP(2) PP(2) CF(2)`: in the hardware status nibble bit 0 is
/// "hardwired inhibit active" and bit 1 "hardwired switch on".
class ConverterStatus {
  const ConverterStatus({
    required this.mode,
    required this.hardwiredSwitch,
    required this.hardwiredInhibit,
    required this.functionTestPending,
    required this.durationTestPending,
    required this.partialDurationTestPending,
    required this.failure,
  });

  final ConverterMode mode;
  final bool hardwiredSwitch;
  final bool hardwiredInhibit;
  final ConverterFlag functionTestPending;
  final ConverterFlag durationTestPending;
  final ConverterFlag partialDurationTestPending;

  /// CF: one or more failures were detected; the kind of failure is not part of this type.
  final ConverterFlag failure;

  /// Whether a test of [kind] is pending (FP, DP, PP).
  ConverterFlag pendingOf(EmergencyTestKind kind) => switch (kind) {
    EmergencyTestKind.function => functionTestPending,
    EmergencyTestKind.duration => durationTestPending,
    EmergencyTestKind.partial => partialDurationTestPending,
  };

  /// The test running according to [mode], otherwise `null`.
  EmergencyTestKind? get running => switch (mode) {
    ConverterMode.functionTest => EmergencyTestKind.function,
    ConverterMode.durationTest => EmergencyTestKind.duration,
    ConverterMode.partialDurationTest => EmergencyTestKind.partial,
    _ => null,
  };
}

/// Decodes DPT 244.600. `null` for a wrong length or reserved values (mode 10 to 15, hardware
/// status bits 2 and 3, a 2-bit field with value 3).
ConverterStatus? decodeConverterStatus(List<int> d) {
  if (d.length != 2) return null;
  final mode = d[0] >> 4;
  if (mode >= ConverterMode.values.length || d[0] & 0x0C != 0) return null;
  final fields = [(d[1] >> 6) & 3, (d[1] >> 4) & 3, (d[1] >> 2) & 3, d[1] & 3];
  if (fields.contains(3)) return null;
  return ConverterStatus(
    mode: ConverterMode.values[mode],
    hardwiredSwitch: d[0] & 0x02 != 0,
    hardwiredInhibit: d[0] & 0x01 != 0,
    functionTestPending: ConverterFlag.values[fields[0]],
    durationTestPending: ConverterFlag.values[fields[1]],
    partialDurationTestPending: ConverterFlag.values[fields[2]],
    failure: ConverterFlag.values[fields[3]],
  );
}

/// Result of the last test of one kind (DPT 245.600, fields LTRF, LTRD, LTRP).
enum ConverterTestOutcome { unknown, passed, passedLate, failed, failedLate, stopped }

/// How the last test of one kind was started (DPT 245.600, fields SF, SD, SP).
enum ConverterTestStart { unknown, automatic, gateway }

/// DPT 245.600 DPT_Converter_Test_Result (6 bytes, N4N4N4N2N2N2N2U16U8).
///
/// `LTRF(4) LTRD(4) | LTRP(4) r(4) | SF(2) SD(2) SP(2) r(2) | LDTR(16) | LPDTR(8)`.
class ConverterTestResult {
  const ConverterTestResult({
    required this.function,
    required this.duration,
    required this.partial,
    required this.functionStart,
    required this.durationStart,
    required this.partialStart,
    required this.durationMinutes,
    required this.partialCharge,
  });

  final ConverterTestOutcome function;
  final ConverterTestOutcome duration;
  final ConverterTestOutcome partial;
  final ConverterTestStart functionStart;
  final ConverterTestStart durationStart;
  final ConverterTestStart partialStart;

  /// LDTR: battery discharge time of the last successful duration test in minutes (0 to 510,
  /// 510 means "510 min or longer").
  final int durationMinutes;

  /// LPDTR: battery charge left after the last partial duration test, 0 (deep discharge point) to
  /// 254 (fully charged); `null` for 255 (unknown).
  final int? partialCharge;

  ConverterTestOutcome outcomeOf(EmergencyTestKind kind) => switch (kind) {
    EmergencyTestKind.function => function,
    EmergencyTestKind.duration => duration,
    EmergencyTestKind.partial => partial,
  };

  ConverterTestStart startOf(EmergencyTestKind kind) => switch (kind) {
    EmergencyTestKind.function => functionStart,
    EmergencyTestKind.duration => durationStart,
    EmergencyTestKind.partial => partialStart,
  };
}

/// Decodes DPT 245.600. `null` for a wrong length or reserved values (a result 6 to 15, a start
/// method 3, set reserved bits, a discharge time above 510).
ConverterTestResult? decodeConverterTestResult(List<int> d) {
  if (d.length != 6) return null;
  final results = [d[0] >> 4, d[0] & 0x0F, d[1] >> 4];
  final starts = [(d[2] >> 6) & 3, (d[2] >> 4) & 3, (d[2] >> 2) & 3];
  final minutes = (d[3] << 8) | d[4];
  if (results.any((r) => r >= ConverterTestOutcome.values.length) ||
      starts.contains(3) ||
      d[1] & 0x0F != 0 ||
      d[2] & 0x03 != 0 ||
      minutes > 510) {
    return null;
  }
  return ConverterTestResult(
    function: ConverterTestOutcome.values[results[0]],
    duration: ConverterTestOutcome.values[results[1]],
    partial: ConverterTestOutcome.values[results[2]],
    functionStart: ConverterTestStart.values[starts[0]],
    durationStart: ConverterTestStart.values[starts[1]],
    partialStart: ConverterTestStart.values[starts[2]],
    durationMinutes: minutes,
    partialCharge: d[5] == 255 ? null : d[5],
  );
}

// --- Check kind `bits` of the watchers ------------------------------------------------------------

/// Whether [data] matches a `bits` check, the form a watcher on a flag datapoint takes for the
/// server (`check: {"bits": {...}}` in `watch_rules.json`):
///
/// - `bytes`: payload length; anything else never matches.
/// - `mask`: the flags looked at (payload as a number, most significant byte first).
/// - `set`: with it the masked flags must equal it exactly; without it any masked flag set matches.
/// - `zero`: bits that must be 0 (e.g. the read flag of DPT 237.600).
/// - `addr` with `addrMask` (default `0x3F`): the address bits must equal `addr`.
///
/// Anything unreadable never matches.
bool bitsCheckMatches(Map<String, Object?> bits, List<int> data) {
  final bytes = bits['bytes'];
  final mask = bits['mask'];
  if (bytes is! int || mask is! int || bytes < 1 || bytes > 6 || data.length != bytes) return false;
  var value = 0;
  for (final b in data) {
    value = (value << 8) | (b & 0xFF);
  }
  final zero = bits['zero'];
  if (zero is int && value & zero != 0) return false;
  final addr = bits['addr'];
  if (addr is int) {
    final addrMask = bits['addrMask'];
    if (value & (addrMask is int ? addrMask : 0x3F) != addr) return false;
  }
  final set = bits['set'];
  return set is int ? value & mask == set : value & mask != 0;
}

/// The `bits` check "a fault flag is set" for a diagnostic type ([main] 237 or 238), optionally
/// for one DALI address only ([isGroup]: a group, DPT 237.600 only). `null` for other types.
Map<String, Object?>? daliFaultBits(int main, {int? address, bool isGroup = false}) => switch (main) {
  237 => {
    'bytes': 2,
    'mask': 0x0700,
    'zero': 0x80,
    if (address != null) ...{'addr': (isGroup ? 0x40 : 0) | (address & 0x3F), 'addrMask': 0x7F},
  },
  238 when !isGroup => {'bytes': 1, 'mask': 0xC0, if (address != null) 'addr': address & 0x3F},
  _ => null,
};

// --- Emergency lighting log -----------------------------------------------------------------------

/// Kind of an emergency lighting test.
enum EmergencyTestKind { function, duration, partial }

/// Result of a test as the log keeps it.
enum EmergencyResult { passed, failed, unknown }

/// Why a result is not a plain pass, as far as the gateway reports it. DPT 245.600 itself only
/// knows [delayExceeded] and [stopped]; the others are for gateways that report more.
enum EmergencyReason { delayExceeded, stopped, battery, lamp, durationShort }

/// One entry of the emergency lighting log: a result a converter reported.
class EmergencyTest {
  const EmergencyTest({
    required this.time,
    required this.group,
    required this.kind,
    required this.result,
    required this.raw,
    this.gateway,
    this.address,
    this.start = ConverterTestStart.unknown,
    this.reasons = const [],
    this.minutes,
    this.charge,
    this.first = false,
    this.source,
    this.foreign = false,
    this.secure = false,
  });

  /// When the result arrived (not when the test ran: the datapoint carries no time).
  final DateTime time;

  /// Group address of the result object (DPT 245.600 carries no DALI address).
  final int group;

  /// Individual address of the gateway, if known.
  final int? gateway;

  /// DALI short address of the luminaire, if the mapping is known.
  final int? address;
  final EmergencyTestKind kind;
  final EmergencyResult result;
  final ConverterTestStart start;
  final List<EmergencyReason> reasons;

  /// Battery discharge time of a duration test in minutes.
  final int? minutes;

  /// Battery charge left after a partial duration test, 0 to 254.
  final int? charge;

  /// The payload as hex without spaces.
  final String raw;

  /// First result seen for this object: it may be older than [time], its age is unknown.
  final bool first;

  /// Individual address the telegram came from. Any device on the bus can send with any sender
  /// address, so this is what the telegram said, not proof.
  final int? source;

  /// The sender is not the gateway the project (or the model) names for this object: the entry is
  /// kept and shown, but never counts as a current or failed test.
  final bool foreign;

  /// The telegram arrived KNX Data Secure (authenticated). Without it a result can be forged by any
  /// device on the bus.
  final bool secure;

  /// Whether the entry may count for "current" and "failed": from the gateway, not first seen.
  bool get counts => !foreign && !first;

  /// Same result at the same object and time: one entry, however often it is read or rebuilt.
  String get key => '$group:${kind.name}:${time.millisecondsSinceEpoch}:$raw';

  Map<String, Object?> toJson() => {
    't': time.millisecondsSinceEpoch,
    'ga': group,
    if (gateway != null) 'gw': gateway,
    if (address != null) 'a': address,
    'k': kind.name,
    'r': result.name,
    if (start != ConverterTestStart.unknown) 's': start.name,
    if (reasons.isNotEmpty) 'why': [for (final r in reasons) r.name],
    if (minutes != null) 'min': minutes,
    if (charge != null) 'lvl': charge,
    'x': raw,
    if (first) 'first': true,
    if (source != null) 'src': source,
    if (foreign) 'fx': true,
    if (secure) 'sec': true,
  };

  /// `null` for a line that is not an entry (damaged file, newer format).
  static EmergencyTest? fromJson(Object? json) {
    if (json is! Map) return null;
    final t = json['t'];
    final ga = json['ga'];
    final x = json['x'];
    final kind = _byName(EmergencyTestKind.values, json['k']);
    final result = _byName(EmergencyResult.values, json['r']);
    if (t is! int || ga is! int || x is! String || kind == null || result == null) return null;
    if (t <= 0 || t > _maxMillis || x.length > 32) return null;
    final time = DateTime.fromMillisecondsSinceEpoch(t);
    final why = json['why'];
    return EmergencyTest(
      time: time,
      group: ga,
      gateway: _int(json['gw']),
      address: _int(json['a']),
      kind: kind,
      result: result,
      start: _byName(ConverterTestStart.values, json['s']) ?? ConverterTestStart.unknown,
      reasons: [
        if (why is List)
          for (final r in why) ?_byName(EmergencyReason.values, r),
      ],
      minutes: _int(json['min']),
      charge: _int(json['lvl']),
      raw: x,
      first: json['first'] == true,
      source: _int(json['src']),
      foreign: json['fx'] == true,
      secure: json['sec'] == true,
    );
  }
}

int? _int(Object? v) => v is int ? v : null;

/// Largest time a DateTime holds; larger values would throw.
const _maxMillis = 8640000000000000;

T? _byName<T extends Enum>(List<T> values, Object? name) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

/// File of the emergency lighting log for [year], relative to the installation's folder: one JSON
/// line per entry, append only.
String emergencyLogPath(int year) => 'dali_tests/$year.ndjson';

/// Largest size of one year's log file. A real installation writes far less (64 converters with a
/// weekly function test and a yearly duration test are about 3,500 lines, 700 KB); the limit only
/// stops a device that floods the bus with forged results. Beyond it one overflow line is written
/// and nothing more that year.
const emergencyLogMaxBytes = 4 * 1024 * 1024;

/// How much of a log file is read: the limit plus room for the overflow line. A larger file (put
/// there by somebody else) is read up to here, never thrown away as a whole.
const emergencyLogReadBytes = emergencyLogMaxBytes + 64 * 1024;

/// What a log file holds.
typedef EmergencyLogRead = ({List<EmergencyTest> entries, bool overflow, bool truncated});

/// Reads the text of a log file: entries, whether the writer stopped at [emergencyLogMaxBytes]
/// (overflow line), and whether lines were left out (more than [maxLines], or [cut]: the text is
/// only the beginning of a larger file). Lines that are no entry are skipped.
EmergencyLogRead readEmergencyLog(String text, {int maxLines = 200000, bool cut = false}) {
  final entries = <EmergencyTest>[];
  var overflow = false;
  var truncated = cut;
  var lines = 0;
  var start = 0;
  while (start < text.length) {
    var end = text.indexOf('\n', start);
    // The last line of a cut text may be incomplete.
    if (end < 0) {
      if (cut) break;
      end = text.length;
    }
    final line = text.substring(start, end).trim();
    start = end + 1;
    if (line.isEmpty) continue;
    if (++lines > maxLines) {
      truncated = true;
      break;
    }
    if (line.length > 2000) continue;
    try {
      final json = jsonDecode(line);
      if (json is Map && json['overflow'] == true) {
        overflow = true;
        continue;
      }
      final entry = EmergencyTest.fromJson(json);
      if (entry != null) entries.add(entry);
    } on Object {
      // A broken line: the others still count.
    }
  }
  return (entries: entries, overflow: overflow, truncated: truncated);
}

/// Entries in the text of a log file (see [readEmergencyLog]).
List<EmergencyTest> parseEmergencyLog(String text, {int maxLines = 200000}) =>
    readEmergencyLog(text, maxLines: maxLines).entries;

/// What to append to a log file of [size] bytes for [entries]: the lines, or once the file would
/// pass [emergencyLogMaxBytes] the overflow line instead (`overflow` true), or nothing if the file
/// is full already.
({String text, bool overflow}) emergencyLogChunk(int size, List<EmergencyTest> entries, DateTime now) {
  if (size >= emergencyLogMaxBytes || entries.isEmpty) return (text: '', overflow: false);
  final lines = StringBuffer();
  for (final e in entries) {
    lines.writeln(jsonEncode(e.toJson()));
  }
  final text = lines.toString();
  if (size + utf8.encode(text).length <= emergencyLogMaxBytes) return (text: text, overflow: false);
  return (text: '${jsonEncode({'overflow': true, 't': now.millisecondsSinceEpoch})}\n', overflow: true);
}

/// Turns the results a converter reports (DPT 245.600) into log entries, one per new result.
///
/// The datapoint always carries the last result of all three kinds, without a time. An entry is
/// created for a kind when its fields differ from the previous telegram at the same group address,
/// or when the converter status (DPT 244.600) showed that test since then: running (mode), or
/// pending and then no longer pending. A weekly function test that passes again has the same bytes,
/// and only the status tells that it ran. The same bytes without such a hint (a gateway repeating
/// its state, an answer to a read) create nothing; a gateway that sends no status then shows a
/// passing luminaire as overdue.
///
/// Any device can send any telegram with any sender address. So:
/// - a result whose sender is not the gateway named for the object is kept apart: it gets its own
///   baseline and is marked `foreign`, and a status from another sender is ignored;
/// - at most one entry per object, kind and origin within [minGap]; further changes only count in
///   [suppressed]. A real self-test of one kind runs at most daily (function) or yearly
///   (duration); two different results of the same kind within an hour come from a repeated manual
///   test at best and from a flooding device at worst.
class EmergencyTracker {
  /// Least time between two entries of one object and kind.
  static const minGap = Duration(hours: 1);

  final _last = <int, String>{};
  final _lastForeign = <int, String>{};
  final _ran = <int, Set<EmergencyTestKind>>{};
  final _running = <int, EmergencyTestKind>{};
  final _status = <int, ConverterStatus>{};
  final _lastEntry = <String, DateTime>{};

  /// Changes left out because of [minGap].
  int suppressed = 0;

  static String _gapKey(int group, EmergencyTestKind kind, bool foreign) => '$group:${kind.name}:$foreign';

  /// Takes over an entry already in the log (after a restart), so the same bytes do not count again.
  void seed(EmergencyTest entry) {
    (entry.foreign ? _lastForeign : _last)[entry.group] = entry.raw;
    final key = _gapKey(entry.group, entry.kind, entry.foreign);
    final last = _lastEntry[key];
    if (last == null || entry.time.isAfter(last)) _lastEntry[key] = entry.time;
  }

  /// Whether a result of [group] is known already.
  bool knows(int group) => _last.containsKey(group);

  /// The converter whose results arrive at [resultGroup] reports [status]. Only from the gateway
  /// ([trusted]): a status from anybody else could make the next unchanged result a new test.
  void status(int resultGroup, ConverterStatus status, {bool trusted = true}) {
    if (!trusted) return;
    final kind = status.running;
    if (kind == null) {
      _running.remove(resultGroup);
    } else {
      _running[resultGroup] = kind;
      (_ran[resultGroup] ??= {}).add(kind);
    }
    // Pending, then no longer pending: the test was done.
    final before = _status[resultGroup];
    if (before != null) {
      for (final k in EmergencyTestKind.values) {
        if (before.pendingOf(k) == ConverterFlag.yes && status.pendingOf(k) == ConverterFlag.no) {
          (_ran[resultGroup] ??= {}).add(k);
        }
      }
    }
    _status[resultGroup] = status;
  }

  /// New entries for the result [data] at [group] from [source]; empty if it cannot be decoded or
  /// brings nothing new. [gateway] is the gateway named for the object; a different [source] makes
  /// the entries `foreign`. [secure]: the telegram arrived KNX Data Secure.
  List<EmergencyTest> result(
    int group,
    List<int> data,
    DateTime time, {
    int? gateway,
    int? address,
    int? source,
    bool secure = false,
  }) {
    final now = decodeConverterTestResult(data);
    if (now == null) return const [];
    final foreign = source != null && gateway != null && source != gateway;
    final baseline = foreign ? _lastForeign : _last;
    final raw = _hex(data);
    final before = baseline[group];
    final previous = before == null ? null : decodeConverterTestResult(_bytes(before));
    // A test still running has no result yet: its hint stays for the telegram after it.
    final ran = foreign ? const <EmergencyTestKind>{} : ({...?_ran[group]}..remove(_running[group]));
    if (!foreign) _ran[group]?.removeAll(ran);
    baseline[group] = raw;
    final entries = <EmergencyTest>[];
    for (final kind in EmergencyTestKind.values) {
      if (now.outcomeOf(kind) == ConverterTestOutcome.unknown) continue;
      if (previous != null && !ran.contains(kind) && _same(kind, now, previous)) continue;
      final key = _gapKey(group, kind, foreign);
      final last = _lastEntry[key];
      if (last != null && time.difference(last).abs() < minGap) {
        suppressed++;
        continue;
      }
      _lastEntry[key] = time;
      entries.add(
        _entry(
          kind,
          now,
          time,
          group,
          raw,
          gateway: gateway ?? source,
          address: address,
          first: before == null,
          source: source,
          foreign: foreign,
          secure: secure,
        ),
      );
    }
    return entries;
  }

  static bool _same(EmergencyTestKind kind, ConverterTestResult a, ConverterTestResult b) =>
      a.outcomeOf(kind) == b.outcomeOf(kind) &&
      a.startOf(kind) == b.startOf(kind) &&
      (kind != EmergencyTestKind.duration || a.durationMinutes == b.durationMinutes) &&
      (kind != EmergencyTestKind.partial || a.partialCharge == b.partialCharge);

  static EmergencyTest _entry(
    EmergencyTestKind kind,
    ConverterTestResult r,
    DateTime time,
    int group,
    String raw, {
    int? gateway,
    int? address,
    required bool first,
    int? source,
    bool foreign = false,
    bool secure = false,
  }) {
    final outcome = r.outcomeOf(kind);
    final passed = outcome == ConverterTestOutcome.passed || outcome == ConverterTestOutcome.passedLate;
    final failed = outcome == ConverterTestOutcome.failed || outcome == ConverterTestOutcome.failedLate;
    return EmergencyTest(
      time: time,
      group: group,
      gateway: gateway,
      address: address,
      kind: kind,
      result: passed
          ? EmergencyResult.passed
          : failed
          ? EmergencyResult.failed
          : EmergencyResult.unknown,
      start: r.startOf(kind),
      reasons: [
        if (outcome == ConverterTestOutcome.passedLate || outcome == ConverterTestOutcome.failedLate)
          EmergencyReason.delayExceeded,
        if (outcome == ConverterTestOutcome.stopped) EmergencyReason.stopped,
      ],
      // The discharge time belongs to the last successful duration test only.
      minutes: kind == EmergencyTestKind.duration && passed ? r.durationMinutes : null,
      charge: kind == EmergencyTestKind.partial ? r.partialCharge : null,
      raw: raw,
      first: first,
      source: source,
      foreign: foreign,
      secure: secure,
    );
  }
}

// --- Notifications ----------------------------------------------------------------------------------

/// A change the [FaultDebouncer] lets through.
typedef FaultNotice = ({
  String key,
  int gateway,
  int before,
  int after,
  DateTime time,

  /// Worth a notification (a new fault flag, or back to normal after a reported fault).
  bool notify,

  /// Worth an event for automations (every stable change within the event budget).
  bool event,

  /// A summary for [gateway] instead of single notifications: [count] changes this minute.
  int count,
});

/// Calms the notifications about faults, the same in app and server: any device on the bus can make
/// a luminaire flicker between "fault" and "OK" as fast as it likes.
///
/// - A state counts once it held for [settle]; flickering in between reports nothing.
/// - A fault notification per key at most every [throttle]; "back to normal" only for a fault that
///   was notified.
/// - At most [perGatewayPerMinute] notifications per gateway and minute; beyond that one summary
///   per gateway ("12 luminaires report a fault").
/// - At most [eventsPerMinute] events per minute in all.
/// - At most [maxKeys] keys are remembered; the oldest settled ones go first.
class FaultDebouncer {
  FaultDebouncer({
    this.settle = const Duration(seconds: 30),
    this.throttle = const Duration(minutes: 5),
    this.perGatewayPerMinute = 5,
    this.eventsPerMinute = 60,
    this.maxKeys = 4096,
  });

  final Duration settle;
  final Duration throttle;
  final int perGatewayPerMinute;
  final int eventsPerMinute;
  final int maxKeys;

  final _keys = <String, _Watched>{};
  final _sent = <int, List<DateTime>>{};
  final _events = <DateTime>[];

  /// Keys remembered (for tests and limits).
  int get length => _keys.length;

  /// [key] of [gateway] now has [faults].
  void report(String key, int gateway, int faults, DateTime at) {
    final w = _keys.remove(key) ?? _Watched(gateway);
    _keys[key] = w; // most recent last
    if (w.observed != faults) {
      w
        ..observed = faults
        ..since = at;
    }
    if (_keys.length > maxKeys) {
      final settled = [
        for (final MapEntry(:key, :value) in _keys.entries)
          if (value.observed == value.announced) key,
      ];
      for (final k in settled.take(_keys.length - maxKeys)) {
        _keys.remove(k);
      }
      // Still too many (all unsettled): the oldest go.
      while (_keys.length > maxKeys) {
        _keys.remove(_keys.keys.first);
      }
    }
  }

  /// When the next change settles; `null` if none is waiting.
  DateTime? get nextDue {
    DateTime? next;
    for (final w in _keys.values) {
      if (w.observed == w.announced) continue;
      final due = w.since.add(settle);
      if (next == null || due.isBefore(next)) next = due;
    }
    return next;
  }

  /// The changes that settled by [now].
  List<FaultNotice> take(DateTime now) {
    final out = <FaultNotice>[];
    final overflow = <int, int>{};
    for (final MapEntry(:key, value: w) in _keys.entries) {
      if (w.observed == w.announced || now.difference(w.since) < settle) continue;
      final before = w.announced;
      final after = w.observed;
      w.announced = after;
      var notify = false;
      if (after != 0 && after & ~before != 0) {
        final last = w.notified;
        if (last == null || now.difference(last) >= throttle) {
          notify = true;
          w.notified = now;
          w.faultNotified = true;
        }
      } else if (after == 0 && w.faultNotified) {
        notify = true;
        w.faultNotified = false;
      }
      if (notify && !_budget(_sent[w.gateway] ??= [], now, perGatewayPerMinute)) {
        notify = false;
        overflow[w.gateway] = (overflow[w.gateway] ?? 0) + 1;
      }
      final event = _budget(_events, now, eventsPerMinute);
      out.add((
        key: key,
        gateway: w.gateway,
        before: before,
        after: after,
        time: now,
        notify: notify,
        event: event,
        count: 0,
      ));
    }
    for (final MapEntry(key: gateway, value: n) in overflow.entries) {
      out.add((key: '', gateway: gateway, before: 0, after: 0, time: now, notify: true, event: false, count: n));
    }
    return out;
  }

  /// Takes one from a budget of [max] per minute; `false` if it is used up.
  static bool _budget(List<DateTime> used, DateTime now, int max) {
    used.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (used.length >= max) return false;
    used.add(now);
    return true;
  }
}

class _Watched {
  _Watched(this.gateway);
  final int gateway;
  int observed = 0;
  int announced = 0;
  DateTime since = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? notified;
  bool faultNotified = false;
}

String _hex(List<int> data) =>
    [for (final b in data) (b & 0xFF).toRadixString(16).padLeft(2, '0')].join().toUpperCase();

List<int> _bytes(String hex) => [
  for (var i = 0; i + 1 < hex.length; i += 2) int.tryParse(hex.substring(i, i + 2), radix: 16) ?? 0,
];
