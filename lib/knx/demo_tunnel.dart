import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'dali.dart';
import 'group_catalog.dart';
import '../model/tap_points.dart';
import 'knx_tunnel.dart';
import 'telegram.dart';

/// Demo without an installation: a fictional sample house with a project and plausible live values.
/// For people without a gateway and for app review.
///
/// Behaves like a [KnxTunnel] from the outside: telegrams arrive via [telegrams], reads are
/// answered, writes switch and report back.
class DemoTunnel extends KnxTunnel {
  /// [withTapPoints]: the sample house with a second tap point on line 1.2 (issue #8), see
  /// [_atTaps]. Off by default, so the first look at the app stays as simple as it is.
  DemoTunnel({this.withTapPoints = false}) : super('demo');

  final bool withTapPoints;

  /// Whether a demo is running. If so, history, health and commissioning persist nothing.
  static bool active = false;

  /// Freeze values (e.g. for screenshots without running animations).
  static bool frozen = false;

  /// Clock of the demo telegrams; goldens set a fixed time.
  static DateTime Function() clock = DateTime.now;

  final _rng = Random(42);
  final _values = <int, double>{};
  Timer? _timer;
  int _tick = 0;

  /// Individual address of the device that sends a group address.
  final _sender = <int, int>{};

  /// Synchronously simulated demo traffic without timers and without a connection: initial state of
  /// all addresses, then [steps] steps of ongoing traffic. For goldens and images (together with
  /// [clock]).
  List<Telegram> simulate({int steps = 40}) {
    _prepare();
    final out = <Telegram>[];
    _sink = out.add;
    for (final ga in _initial()) {
      _emit(ga);
    }
    for (var i = 0; i < steps; i++) {
      _step();
    }
    _sink = null;
    return out;
  }

  /// Simulation: telegrams go here directly instead of into the stream.
  void Function(Telegram)? _sink;

  void _prepare() {
    tunnelAddress = _pa('1.1.255');
    for (final g in demoCatalog().groups.values) {
      final sender = g.links.where((l) => l.sends).firstOrNull;
      if (sender != null) _sender[g.address] = sender.device;
    }
    _seed();
  }

  /// Residents press push buttons now and then. Off while learning: there only pressing „Im
  /// Demo-Haus einen Taster drücken“ (press a button in the demo house) counts.
  bool autoPress = true;

  /// Connection type for forum package and diagnostics: no UDP, the demo house.
  @override
  String get kind => s.demoGateway;

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 5)}) async {
    active = true;
    state.value = TunnelState.connected;
    deviceName.value = s.demoGateway;
    _prepare();
    if (withTapPoints) _publishTaps();
    // Initial state step by step, then ongoing traffic.
    var i = 0;
    final initial = _initial();
    _timer = Timer.periodic(const Duration(milliseconds: 160), (t) {
      if (i < initial.length) {
        _emit(initial[i++]);
      } else {
        t.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _step());
      }
    });
    _daliTimer = Timer.periodic(const Duration(milliseconds: 700), (_) => _daliStep());
  }

  // --- DALI gateway ---------------------------------------------------------------

  Timer? _daliTimer;
  int _daliTick = 0;

  /// Faults the demo gateway reports per short address ([DaliFault] bits).
  final _daliFaults = <int, int>{3: DaliFault.gear};

  /// The gateway reports like a real one: first the state of every control gear and converter,
  /// after a while a lamp fails at short address 12, then it repeats that now and then.
  void _daliStep() {
    if (frozen) return;
    final i = _daliTick++;
    if (i < DemoDali.gearCount) return _daliEmit(DemoDali.diagnostic, _daliDiagnostic(i));
    final converter = i - DemoDali.gearCount;
    if (converter < DemoDali.converters.length * 2) {
      final address = DemoDali.converters[converter ~/ 2];
      return converter.isEven
          ? _daliEmit(DemoDali.status(address), DemoDali.statusNormal)
          : _daliEmit(DemoDali.result(address), DemoDali.resultOf(address));
    }
    if (i == 45) {
      _daliFaults[12] = DaliFault.lamp;
      return _daliEmit(DemoDali.diagnostic, _daliDiagnostic(12));
    }
    if (i > 45 && i % 60 == 0) _daliEmit(DemoDali.diagnostic, _daliDiagnostic(12));
  }

  /// DPT 237.600 for [address]: lamp failure bit 8, ballast failure bit 9.
  List<int> _daliDiagnostic(int address) {
    final faults = _daliFaults[address] ?? 0;
    return [(faults & DaliFault.lamp != 0 ? 0x01 : 0) | (faults & DaliFault.gear != 0 ? 0x02 : 0), address & 0x3F];
  }

  void _daliEmit(int ga, List<int> data, {TelegramType type = TelegramType.write}) => (_sink ?? inject)(
    Telegram(
      time: clock(),
      source: DemoDali.gateway,
      destination: ga,
      type: type,
      data: Uint8List.fromList(data),
      isSmall: data.length == 1 && _dpts[ga]?.main == 1,
    ),
  );

  /// Reads of the gateway's objects are answered with their current state.
  bool _daliRead(int ga) {
    if (!DemoDali.owns(ga)) return false;
    final address = ga & 0xFF;
    final data = ga == DemoDali.diagnostic
        ? _daliDiagnostic(12)
        : switch (_dpts[ga]?.main) {
            244 => DemoDali.statusNormal,
            245 => DemoDali.resultOf(address),
            1 => [(_daliSwitched[address] ?? false) ? 1 : 0],
            _ => null,
          };
    if (data != null) _daliEmit(ga, data, type: TelegramType.response);
    return true;
  }

  final _daliSwitched = <int, bool>{};

  /// Switching a DALI group: the gateway reports the new state on the group's status address. For
  /// group 2 it reports on group 3's address: the demo of a wrong group assignment.
  bool _daliWrite(int ga, int? small) {
    final group = DemoDali.groupOfSwitch(ga);
    if (group == null || small == null) return DemoDali.owns(ga);
    final on = small & 1 == 1;
    final answering = group == 2 ? 3 : group;
    _daliSwitched[answering] = on;
    Timer(const Duration(milliseconds: 180), () {
      if (state.value == TunnelState.connected) _daliEmit(DemoDali.groupStatus(answering), [on ? 1 : 0]);
    });
    return true;
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    _daliTimer?.cancel();
    _daliTimer = null;
    active = false;
    state.value = TunnelState.disconnected;
  }

  @override
  Future<bool?> read(int destination) async {
    inject(_telegram(destination, TelegramType.read, outgoing: true));
    // Finding for the health check: this object has no read flag.
    if (destination == _silent) return true;
    if (DemoDali.owns(destination)) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _daliRead(destination);
      return true;
    }
    if (_values.containsKey(destination)) {
      await Future<void>.delayed(Duration(milliseconds: 60 + _rng.nextInt(80)));
      inject(_telegram(destination, TelegramType.response));
    }
    return true;
  }

  @override
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) async {
    if (DemoDali.owns(destination)) {
      inject(
        Telegram(
          time: clock(),
          source: tunnelAddress!,
          destination: destination,
          type: TelegramType.write,
          data: Uint8List.fromList(small != null ? [small] : data),
          isSmall: small != null,
          outgoing: true,
        ),
      );
      _daliWrite(destination, small);
      return true;
    }
    final value = small?.toDouble() ?? _decode(destination, data);
    if (value != null) _values[destination] = value;
    inject(_telegram(destination, TelegramType.write, outgoing: true));
    // The actuator behind the command reports back on its status address.
    if (value != null) _answer(destination);
    return true;
  }

  // --- Device diagnostics -------------------------------------------------------

  /// Foreign device on the bus that is not in the demo project (for inventory and line scan).
  static final foreignDevice = _pa('1.1.44');

  /// Manufacturer ID of the demo devices (name "Demo" in the catalog).
  static const demoManufacturer = 0x00FA;

  /// Sequence number of the responses per device (T_Data_Connected).
  final _deviceSeq = <int, int>{};

  /// Demo devices answer diagnostics like real ones: connection setup, device descriptor and
  /// properties of the Device Object. Read-only; anything diagnostics does not know is only
  /// acknowledged.
  @override
  Future<void> transmit(Uint8List cemi) async {
    final i = 2 + cemi[1];
    final group = cemi[i + 1] & 0x80 != 0;
    final destination = (cemi[i + 4] << 8) | cemi[i + 5];
    final tpdu = cemi.sublist(i + 7);
    final device = demoCatalog().devices[destination];
    final present = !group && (device != null && !device.isTunnel || destination == foreignDevice);
    // Confirmation: group telegrams always, individual addresses only if the device exists.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 8), () {
        receiveCemi(
          _frame(CemiFrame.con, tunnelAddress ?? 0, destination, tpdu, group: group, error: !group && !present),
        );
      }),
    );
    if (!present || tpdu.isEmpty || tpdu[0] & 0xC0 != 0x40) return;
    // Numbered data: acknowledge and respond.
    final seq = (tpdu[0] >> 2) & 0x0F;
    final apci = ((tpdu[0] & 0x03) << 8) | (tpdu.length > 1 ? tpdu[1] : 0);
    final data = tpdu.length > 2 ? tpdu.sublist(2) : const <int>[];
    final reply = switch (apci) {
      0x300 => (0x340, const [0x07, 0xB0]), // mask TP1 System B
      0x3D5 when data.length >= 2 => (0x3D6, _property(destination, data[0], data[1])),
      _ => null,
    };
    await Future<void>.delayed(Duration(milliseconds: 20 + _rng.nextInt(30)));
    receiveCemi(_frame(CemiFrame.ind, destination, tunnelAddress ?? 0, [0xC2 | (seq << 2)]));
    if (reply == null) return;
    final (code, payload) = reply;
    final own = _deviceSeq[destination] ?? 0;
    _deviceSeq[destination] = (own + 1) & 0x0F;
    receiveCemi(
      _frame(CemiFrame.ind, destination, tunnelAddress ?? 0, [
        0x40 | (own << 2) | (code >> 8),
        code & 0xFF,
        ...payload,
      ]),
    );
  }

  /// Response to A_PropertyValue_Read: object, PID, count/start, data.
  List<int> _property(int pa, int object, int pid) {
    final device = demoCatalog().devices[pa];
    final value = switch ((object, pid)) {
      (0, 12) => [demoManufacturer >> 8, demoManufacturer & 0xFF],
      (0, 11) => demoSerial(pa),
      (0, 15) => (device?.product ?? 'X 1').codeUnits,
      (0, 9) => [0x12],
      (0, 54) => [0x00],
      (3, 13) => [demoManufacturer >> 8, demoManufacturer & 0xFF, 0x10, pa & 0xFF, 0x03],
      _ => null,
    };
    // Count 0 = property does not exist.
    return value == null ? [object, pid, 0x00, 0x01] : [object, pid, 0x10, 0x01, ...value];
  }

  /// Serial number of a demo device on the bus (6 bytes).
  static List<int> demoSerial(int pa) => [0x00, demoManufacturer & 0xFF, 0x00, 0x01, pa >> 8, pa & 0xFF];

  static Uint8List _frame(
    int code,
    int source,
    int destination,
    List<int> tpdu, {
    bool group = false,
    bool error = false,
  }) => Uint8List.fromList([
    code,
    0x00,
    0xB0 | (error ? 0x01 : 0x00),
    (group ? 0x80 : 0x00) | 0x60,
    source >> 8,
    source & 0xFF,
    destination >> 8,
    destination & 0xFF,
    tpdu.length - 1,
    ...tpdu,
  ]);

  // --- Values --------------------------------------------------------------------

  void _seed() {
    for (final MapEntry(key: ga, value: d) in _dpts.entries) {
      // The DALI gateway has its own script ([_daliStep]): its addresses stay out of the random
      // traffic, so the rest of the demo (and its images) runs as before.
      if (DemoDali.owns(ga)) continue;
      _values[ga] = switch ((d.main, d.sub)) {
        (9, 1) => ga == _ga('4/0/0') ? 11.5 : 20.5 + _rng.nextDouble() * 2,
        (9, 4) => ga == _ga('4/0/2') ? 8000 + _rng.nextDouble() * 4000 : 120 + _rng.nextDouble() * 400,
        (9, 5) => 2.4,
        (9, 7) => 55,
        (5, 1) => (_rng.nextInt(5) * 10).toDouble(),
        (14, 56) => switch (ga) {
          _ when ga == _ga('5/0/2') => 3820,
          _ when ga == _ga('5/0/3') => 7350,
          _ => 1240,
        },
        (13, 13) => ga == _ga('5/0/4') ? 18 : 18452,
        (1, 18) => _rng.nextBool() ? 1 : 0,
        _ => 0,
      };
    }
  }

  void _step() {
    if (frozen) return;
    _tick++;
    if (withTapPoints) {
      final down = _tick % tapCycle >= tapDownFrom && _tick % tapCycle < tapDownTo;
      if (down != _tapDown) {
        _tapDown = down;
        _publishTaps();
      }
    }
    final now = clock();
    if (withTapPoints) {
      // A push button on line 1.3, where no tap point is and which the project does not know:
      // seen through the couplers only, so the topology shows that line as "only indirectly
      // visible".
      if (_tick % 20 == 7) {
        (_sink ?? inject)(
          Telegram(
            time: now,
            source: _pa('1.3.7'),
            destination: _ga('3/7/1'),
            type: TelegramType.write,
            data: Uint8List.fromList([(_tick ~/ 20) & 1]),
            isSmall: true,
            hopCount: 5,
          ),
        );
      }
    }
    // Time/date every minute like a real time source.
    if (now.second < 1 || _tick == 1) {
      _emit(_ga('7/0/0'));
      _emit(_ga('7/0/1'));
    }
    double walk(int ga, double step, double lo, double hi) =>
        _values[ga] = (_values[ga]! + (_rng.nextDouble() - 0.5) * 2 * step).clamp(lo, hi);
    switch (_tick % 6) {
      case 0:
        walk(_ga('5/0/0'), 35, 60, 2600);
        _emit(_ga('5/0/0'));
      case 1:
        final room = _rooms[_rng.nextInt(_rooms.length)];
        walk(_ga('2/0/${room.$1}'), 0.15, 18, 24);
        _emit(_ga('2/0/${room.$1}'));
      case 2:
        walk(_ga('4/0/1'), 0.6, 0, 9);
        _emit(_ga('4/0/1'));
        // Wind alarm: above 7 m/s the weather station locks the blinds, below 5 it releases
        // them. Only a change sends, so the usual traffic stays as it is.
        final wind = _values[_ga('4/0/1')]!;
        final locked = _values[_windLock] == 1;
        if (!locked && wind > 7 || locked && wind < 5) {
          _values[_windLock] = locked ? 0 : 1;
          _emit(_windLock);
        }
        if (_tick % 12 == 2) {
          walk(_humidity, 2, 40, 70);
          _emit(_humidity);
        }
      case 3:
        // Valves cycle (PWM) – actuating value and state match.
        final room = _rooms[_rng.nextInt(_rooms.length)];
        final valve = _ga('2/2/${room.$1}');
        final state = _ga('2/3/${room.$1}');
        _values[valve] = (_rng.nextInt(8) * 10).toDouble();
        _values[state] = _values[state] == 1 ? 0 : 1;
        _emit(valve);
        _emit(state);
      case 4:
        walk(_ga('4/0/2'), 900, 0, 60000);
        _emit(_ga('4/0/2'));
      case 5:
        if (autoPress && _rng.nextDouble() < 0.35) pressButton();
        if (_tick % 30 == 5) {
          _values[_ga('5/0/1')] = _values[_ga('5/0/1')]! + 1;
          _emit(_ga('5/0/1'));
        }
    }
  }

  /// Someone switches a light: push button → actuator → feedback. Also on button press while
  /// learning in the demo house; [room] = room number, otherwise random.
  void pressButton({int? room}) {
    final n = room ?? _rooms[_rng.nextInt(_rooms.length)].$1;
    final cmd = _ga('1/0/$n');
    final on = _values[cmd] == 1 ? 0.0 : 1.0;
    _values[cmd] = on;
    _emit(cmd);
    _answer(cmd);
  }

  /// Initial state: every address once, in random order, but each channel in one piece: its
  /// commands first, then the status addresses that answer them ([_reactions]). Otherwise the
  /// commands of the initial state would stand there without status feedback.
  List<int> _initial() {
    final out = <int>[];
    final done = <int>{};
    for (final ga in _values.keys.toList()..shuffle(_rng)) {
      final status = _reactions[ga]?.status;
      if (status == null) {
        // A status of a command comes with its command.
        if (!_statusOfCommands.contains(ga)) out.add(ga);
      } else if (done.add(ga)) {
        // Commands answered on the same address (up/down and stop) belong to one channel.
        final channel = [
          for (final MapEntry(key: command, value: r) in _reactions.entries)
            if (r.status.any(status.contains)) command,
        ];
        done.addAll(channel);
        out
          ..addAll(channel)
          ..addAll({for (final command in channel) ..._reactions[command]!.status});
      }
    }
    return out;
  }

  /// The device behind the command [ga] reports its new state after its usual delay, so every
  /// command of the demo house has its status feedback (Reaktionszeiten, cause chain).
  void _answer(int ga) {
    final reaction = _reactions[ga];
    if (reaction == null) return;
    final command = _values[ga] ?? 0;
    void report() {
      for (final status in reaction.status) {
        final value = reaction.value?.call(command);
        if (value != null) _values[status] = value;
        _emit(status);
      }
    }

    if (_sink != null) return report();
    Timer(reaction.delay, () {
      if (state.value == TunnelState.connected) report();
    });
  }

  void _emit(int ga) {
    final t = _telegram(ga, TelegramType.write);
    final seen = withTapPoints ? _atTaps(t) : t;
    if (seen != null) (_sink ?? inject)(seen);
  }

  // --- Tap points (issue #8) -----------------------------------------------------------------

  /// Steps of one round of the second tap point: it is away from [tapDownFrom] to [tapDownTo]
  /// (about 13 seconds every 108), so the gap and its marks can be seen without waiting long.
  static const tapCycle = 120;
  static const tapDownFrom = 45;
  static const tapDownTo = 60;

  /// Has receivers on line 1.1 according to the project, but the demo coupler does not pass it:
  /// the live filter table check reports it as blocked.
  static final _blocked = _ga('4/0/1');

  /// Passed to line 1.2 although nobody listens there ("leaked", needless bus load).
  static final _leaked = _ga('5/0/0');

  @override
  DateTime get tapNow => clock();

  bool _tapDown = false;
  final _tapRng = Random(8);

  void _publishTaps() {
    tapPoints.value = [
      TapStatus(index: 0, name: s.demoGateway, label: '1.1', state: TunnelState.connected),
      TapStatus(
        index: 1,
        name: s.tapDemoName,
        label: '1.2',
        state: _tapDown ? TunnelState.disconnected : TunnelState.connected,
        error: _tapDown ? s.tapDemoDown : null,
        lag: const Duration(milliseconds: 41),
      ),
    ];
    tapLabels.value = const ['1.1', '1.2'];
  }

  /// [t] as two tap points see it: the gateway on line 1.1 (tap point 0) and an interface on
  /// line 1.2 behind the line coupler (tap point 1), which reports about 40 ms later.
  ///
  /// - Forwarded: the address has a receiver on the other line: one entry with a sighting, one
  ///   hop less there.
  /// - Filtered or line-local: seen at the sender's tap point only.
  /// - Two findings for the live filter table check: [_blocked] and [_leaked].
  /// - While the second tap point is away, what stays on line 1.2 is not seen at all (`null`),
  ///   and nothing gets a sighting there.
  Telegram? _atTaps(Telegram t) {
    if (t.outgoing) return t;
    final on12 = t.source >> 8 == 0x12;
    final group = demoCatalog().groups[t.destination];
    bool listens(int line) => group?.links.any((l) => !l.sends && l.device >> 8 == line) ?? false;
    final crosses = on12 ? listens(0x11) && t.destination != _blocked : listens(0x12) || t.destination == _leaked;
    final lag = Duration(microseconds: 36000 + _tapRng.nextInt(9000));
    if (on12) {
      if (_tapDown) return crosses ? t : null;
      return crosses ? _seenAt(t, tap: 1, hop: 6, sightings: [Sighting(0, lag, 5)]) : _seenAt(t, tap: 1, hop: 6);
    }
    if (!crosses || _tapDown) return _seenAt(t, tap: 0, hop: 6);
    return _seenAt(t, tap: 0, hop: 6, sightings: [Sighting(1, lag, 5)]);
  }

  static Telegram _seenAt(Telegram t, {required int tap, required int hop, List<Sighting> sightings = const []}) =>
      Telegram(
        time: t.time,
        source: t.source,
        destination: t.destination,
        type: t.type,
        data: t.data,
        isSmall: t.isSmall,
        priority: t.priority,
        repeated: t.repeated,
        hopCount: hop,
        tap: tap,
        sightings: sightings,
      );

  Telegram _telegram(int ga, TelegramType type, {bool outgoing = false}) {
    final dpt = _dpts[ga];
    final (small, data) = type == TelegramType.read ? (true, Uint8List.fromList([0])) : _encode(ga, dpt, type: type);
    return Telegram(
      time: clock(),
      source: outgoing ? tunnelAddress! : (_sender[ga] ?? _pa('1.1.255')),
      destination: ga,
      type: type,
      data: data,
      isSmall: small,
      outgoing: outgoing,
      // The weather station sits behind the line coupler.
      hopCount: (_sender[ga] ?? 0) >> 8 == 0x12 ? 5 : 6,
      // Finding: the heating actuator occasionally repeats (missing acknowledgement).
      repeated: !outgoing && _sender[ga] == _pa('1.1.13') && _rng.nextDouble() < 0.2,
    );
  }

  (bool, Uint8List) _encode(int ga, Dpt? dpt, {TelegramType type = TelegramType.write}) {
    final v = _values[ga] ?? 0;
    final now = clock();
    // Finding for the health check: a push button sends humidity as 1 byte instead of DPT 9.
    if (ga == _humidity && type == TelegramType.write) return (false, Uint8List.fromList([v.round()]));
    final bytes = switch ((dpt?.main, dpt?.sub)) {
      (1, _) => null,
      (5, 1) => [(v * 255 / 100).round().clamp(0, 255)],
      (9, _) => encodeDpt9(v) ?? [0, 0],
      (14, _) => (ByteData(4)..setFloat32(0, v)).buffer.asUint8List(),
      (13, _) => (ByteData(4)..setInt32(0, v.round())).buffer.asUint8List(),
      (10, _) => [(now.weekday << 5) | now.hour, now.minute, now.second],
      (11, _) => [now.day, now.month, now.year % 100],
      _ => [v.round() & 0xFF],
    };
    return bytes == null ? (true, Uint8List.fromList([v.round() & 1])) : (false, Uint8List.fromList(bytes));
  }

  double? _decode(int ga, List<int> data) => switch (_dpts[ga]?.main) {
    5 when data.isNotEmpty => data[0] * 100 / 255,
    9 when data.length == 2 => decodeDpt9(Uint8List.fromList(data)),
    _ => null,
  };
}

int _ga(String s) => parseGroup(s)!;

/// The DALI gateway of the demo house (1.1.40): a diagnostic object (DPT 237.600), four groups
/// with switch and status, three emergency converters with status (DPT 244.600) and test result
/// (DPT 245.600). All in main group 10.
abstract final class DemoDali {
  static final gateway = _pa('1.1.40');
  static final diagnostic = _ga('10/0/0');

  /// Control gear the gateway reports (short addresses 0 to 15).
  static const gearCount = 16;

  /// Short addresses of the emergency converters.
  static const converters = [16, 17, 18];
  static const groups = 4;

  static int groupSwitch(int group) => _ga('10/1/$group');
  static int groupStatus(int group) => _ga('10/2/$group');
  static int status(int address) => _ga('10/3/$address');
  static int result(int address) => _ga('10/4/$address');

  /// Whether [ga] belongs to the gateway (main group 10).
  static bool owns(int ga) => (ga >> 11) & 0x1F == 10;

  static int? groupOfSwitch(int ga) => owns(ga) && (ga >> 8) & 0x07 == 1 && ga & 0xFF < groups ? ga & 0xFF : null;

  /// DPT 244.600: normal mode, no test pending, no failure.
  static const statusNormal = [0x10, 0x55];

  /// DPT 245.600 per converter: function and duration test passed, started automatically, with
  /// the discharge time; the converter at 18 failed its last duration test.
  static List<int> resultOf(int address) => switch (address) {
    18 => const [0x13, 0x00, 0x50, 0x00, 0x00, 0xFF],
    16 => const [0x11, 0x00, 0x50, 0x00, 0x5F, 0xFF],
    _ => const [0x11, 0x00, 0x50, 0x00, 0x5C, 0xFF],
  };
}

/// Demo findings: valve state without read flag, humidity with wrong length.
final _silent = _ga('2/3/3');
final _humidity = _ga('2/4/2');

/// Lock of all blinds, set by the weather station at wind alarm.
final _windLock = _ga('3/3/0');
int _pa(String s) => parseIndividual(s)!;

/// Rooms: (number, abbreviation DE, abbreviation EN).
const _rooms = [
  (0, 'EG WZ', 'GF Living'),
  (1, 'EG KÜ', 'GF Kitchen'),
  (2, 'OG BZ', 'FF Bath'),
  (3, 'OG SZ', 'FF Bedroom'),
  (4, 'EG FL', 'GF Hall'),
  (5, 'EG AZ', 'GF Office'),
  (6, 'OG K1', 'FF Kid 1'),
  (7, 'OG K2', 'FF Kid 2'),
];

/// Rooms with a glass push button instead of a push button in a 55 frame.
const _glass = {0, 1, 4};

/// How a device answers a command: after [delay] on the addresses [status]; [value] turns the
/// commanded value into the reported one, `null` = it reports the state it has.
typedef _Reaction = ({Duration delay, List<int> status, double Function(double command)? value});

double _same(double v) => v;

/// Command → status feedback per room, with delays as real actuators have them.
final _reactions = <int, _Reaction>{
  for (final (n, _, _) in _rooms) ...{
    // Switch actuator.
    _ga('1/0/$n'): (delay: const Duration(milliseconds: 150), status: [_ga('1/1/$n')], value: _same),
    // Dimming actuator: reports the value once it is reached.
    _ga('1/2/$n'): (delay: const Duration(milliseconds: 320), status: [_ga('1/3/$n')], value: _same),
    // Blind actuator: up = 0 %, down = 100 %; stop reports where it stands. Real ones report
    // after the travel, the demo right away, so the channel does not count as slow.
    _ga('3/1/$n'): (
      delay: const Duration(milliseconds: 800),
      status: [_ga('3/0/$n')],
      value: (v) => v == 1 ? 100.0 : 0.0,
    ),
    _ga('3/2/$n'): (delay: const Duration(milliseconds: 200), status: [_ga('3/0/$n')], value: null),
    // New setpoint: the heating actuator reports actuating value and valve state.
    _ga('2/1/$n'): (delay: const Duration(milliseconds: 450), status: [_ga('2/2/$n'), _ga('2/3/$n')], value: null),
  },
};

final _statusOfCommands = {for (final r in _reactions.values) ...r.status};

final _dpts = {for (final g in demoCatalog().groups.values) g.address: ?g.dpt};

GroupCatalog? _demoCache;
String? _demoLocale;

/// Project of the sample house (names in the current language).
GroupCatalog demoCatalog() {
  final de = s.localeName.startsWith('de');
  if (_demoCache != null && _demoLocale == s.localeName) return _demoCache!;
  String t(String d, String e) => de ? d : e;
  final groups = <int, GroupInfo>{};
  void ga(String address, String name, String path, Dpt dpt, List<GroupLink> links) {
    final a = _ga(address);
    groups[a] = GroupInfo(address: a, name: name, path: path, dpt: dpt, links: links);
  }

  GroupLink send(String pa) => GroupLink(device: _pa(pa), sends: true);
  GroupLink hear(String pa) => GroupLink(device: _pa(pa));
  // Push-button keys with object text as with MDT ("T1: …", "T3/4: …").
  GroupLink press(String pa, String key) => GroupLink(device: _pa(pa), text: key, sends: true);
  GroupLink show(String pa, String key) => GroupLink(device: _pa(pa), text: key);

  for (final (n, rde, ren) in _rooms) {
    final room = t(rde, ren);
    final button = '1.1.${30 + n}';
    final light = t('T1: Licht', 'T1: Light');
    final dim = t('T2: Dimmen', 'T2: Dimming');
    final blind = t('T3/4: Rollladen', 'T3/4: Shutter');
    ga(
      '1/0/$n',
      '$room ${t('L01 Schalten', 'L01 switch')}',
      t('Beleuchtung › Schalten', 'Lighting › Switch'),
      const Dpt(1, 1),
      [press(button, light), hear('1.1.10')],
    );
    ga(
      '1/1/$n',
      '$room ${t('L01 Rückmeldung Schalten', 'L01 switch status')}',
      t('Beleuchtung › Rückmeldung', 'Lighting › Status'),
      const Dpt(1, 1),
      [send('1.1.10'), show(button, light)],
    );
    ga(
      '2/0/$n',
      '$room ${t('Ist-Temperatur', 'actual temperature')}',
      t('Heizung › Ist-Temperatur', 'Heating › Actual'),
      const Dpt(9, 1),
      [send(button), hear('1.1.13')],
    );
    ga(
      '2/1/$n',
      '$room ${t('Soll-Temperatur', 'setpoint')}',
      t('Heizung › Sollwert', 'Heating › Setpoint'),
      const Dpt(9, 1),
      [if (_glass.contains(n)) press(button, t('T5/6: Sollwert', 'T5/6: Setpoint')) else send(button), hear('1.1.13')],
    );
    ga(
      '2/2/$n',
      '$room ${t('Stellwert Heizen (%)', 'heating valve (%)')}',
      t('Heizung › Stellwert', 'Heating › Valve'),
      const Dpt(5, 1),
      [send('1.1.13')],
    );
    ga(
      '2/3/$n',
      '$room ${t('Ventil-Zustand', 'valve state')}',
      t('Heizung › Ventil-Zustand', 'Heating › Valve state'),
      const Dpt(1, 11),
      [send('1.1.13')],
    );
    ga(
      '3/0/$n',
      '$room ${t('F01 Aktuelle Position', 'W01 current position')}',
      t('Jalousien › Position', 'Blinds › Position'),
      const Dpt(5, 1),
      [send('1.1.12'), show(button, blind)],
    );
    ga(
      '3/1/$n',
      '$room ${t('F01 Auf/Ab', 'W01 up/down')}',
      t('Jalousien › Auf/Ab', 'Blinds › Up/down'),
      const Dpt(1, 8),
      [press(button, blind), hear('1.1.12')],
    );
    ga('3/2/$n', '$room ${t('F01 Stopp', 'W01 stop')}', t('Jalousien › Stopp', 'Blinds › Stop'), const Dpt(1, 7), [
      press(button, blind),
      hear('1.1.12'),
    ]);
    ga(
      '1/2/$n',
      '$room ${t('L02 Dimmwert', 'L02 dim value')}',
      t('Beleuchtung › Dimmwert', 'Lighting › Dim value'),
      const Dpt(5, 1),
      [press(button, dim), hear('1.1.11')],
    );
    ga(
      '1/3/$n',
      '$room ${t('L02 Rückmeldung Dimmwert', 'L02 dim value status')}',
      t('Beleuchtung › Rückmeldung', 'Lighting › Status'),
      const Dpt(5, 1),
      [send('1.1.11'), show(button, dim)],
    );
    if (n.isEven) {
      ga(
        '8/0/$n',
        '$room ${t('Präsenz', 'presence')}',
        t('Präsenz › Präsenz', 'Presence › Presence'),
        const Dpt(1, 18),
        [send('1.1.${60 + n}')],
      );
      ga(
        '8/1/$n',
        '$room ${t('Helligkeit', 'brightness')}',
        t('Präsenz › Helligkeit', 'Presence › Brightness'),
        const Dpt(9, 4),
        [send('1.1.${60 + n}')],
      );
    }
  }
  ga('4/0/4', t('Luftfeuchte außen', 'Outdoor humidity'), t('Wetter', 'Weather'), const Dpt(9, 7), [send('1.2.20')]);
  ga('4/0/5', t('Dämmerung', 'Twilight'), t('Wetter', 'Weather'), const Dpt(1, 24), [send('1.2.20')]);
  ga('5/0/2', t('PV-Leistung', 'PV power'), t('Energie › Leistung', 'Energy › Power'), const Dpt(14, 56), [
    send('1.1.42'),
  ]);
  ga('5/0/3', t('Wallbox Leistung', 'Wallbox power'), t('Energie › Leistung', 'Energy › Power'), const Dpt(14, 56), [
    send('1.1.43'),
  ]);
  ga('5/0/4', t('PV-Ertrag heute', 'PV yield today'), t('Energie › Zähler', 'Energy › Meter'), const Dpt(13, 13), [
    send('1.1.42'),
  ]);
  ga(
    '2/4/2',
    '${t('OG BZ', 'FF Bath')} ${t('Luftfeuchte', 'humidity')}',
    t('Heizung › Luftfeuchte', 'Heating › Humidity'),
    const Dpt(9, 7),
    [send('1.1.32')],
  );
  ga('4/0/0', t('Außentemperatur', 'Outdoor temperature'), t('Wetter', 'Weather'), const Dpt(9, 1), [
    send('1.2.20'),
    for (final r in _rooms) hear('1.1.${30 + r.$1}'),
  ]);
  ga(
    '3/3/0',
    t('Jalousien Wind Sperre', 'Blinds wind lock'),
    t('Jalousien › Sperre', 'Blinds › Lock'),
    const Dpt(1, 3),
    [send('1.2.20'), hear('1.1.12')],
  );
  ga('4/0/1', t('Windgeschwindigkeit', 'Wind speed'), t('Wetter', 'Weather'), const Dpt(9, 5), [
    send('1.2.20'),
    hear('1.1.12'),
  ]);
  ga('4/0/2', t('Außenhelligkeit', 'Outdoor brightness'), t('Wetter', 'Weather'), const Dpt(9, 4), [
    send('1.2.20'),
    hear('1.1.12'),
  ]);
  ga('4/0/3', t('Regen', 'Rain'), t('Wetter', 'Weather'), const Dpt(1, 2), [send('1.2.20'), hear('1.1.12')]);
  ga('5/0/0', t('Leistung Haus', 'House power'), t('Energie › Leistung', 'Energy › Power'), const Dpt(14, 56), [
    send('1.1.41'),
  ]);
  ga('5/0/1', t('Zählerstand Haus', 'House meter'), t('Energie › Zähler', 'Energy › Meter'), const Dpt(13, 13), [
    send('1.1.41'),
  ]);
  ga(
    '6/0/0',
    t('Rauchmelder Flur Alarm', 'Smoke detector hallway alarm'),
    t('Sicherheit › Alarm', 'Safety › Alarm'),
    const Dpt(1, 5),
    [send('1.1.50')],
  );
  // DALI gateway: diagnostics for all control gear on one address, groups, emergency converters.
  const dali = '1.1.40';
  final daliPath = t('Beleuchtung DALI', 'Lighting DALI');
  ga('10/0/0', t('DALI Diagnose Flur/Büro', 'DALI diagnostics hall/office'), daliPath, const Dpt(237, 600), [
    GroupLink(device: _pa(dali), text: t('Diagnose', 'Diagnostics'), sends: true),
  ]);
  for (var g = 0; g < DemoDali.groups; g++) {
    ga(
      '10/1/$g',
      t('DALI Gruppe $g Schalten', 'DALI group $g switch'),
      '$daliPath › ${t('Schalten', 'Switch')}',
      const Dpt(1, 1),
      [GroupLink(device: _pa(dali), text: t('Gruppe $g Schalten', 'Group $g switch'))],
    );
    ga('10/2/$g', t('DALI Gruppe $g Status', 'DALI group $g status'), '$daliPath › Status', const Dpt(1, 1), [
      GroupLink(device: _pa(dali), text: t('Gruppe $g Status', 'Group $g status'), sends: true),
    ]);
  }
  for (final a in DemoDali.converters) {
    ga(
      '10/3/$a',
      t('Notleuchte $a Status', 'Emergency luminaire $a status'),
      '$daliPath › ${t('Notlicht', 'Emergency')}',
      const Dpt(244, 600),
      [GroupLink(device: _pa(dali), text: t('Notleuchte $a Status', 'Emergency luminaire $a status'), sends: true)],
    );
    ga(
      '10/4/$a',
      t('Notleuchte $a Testergebnis', 'Emergency luminaire $a test result'),
      '$daliPath › ${t('Notlicht', 'Emergency')}',
      const Dpt(245, 600),
      [
        GroupLink(
          device: _pa(dali),
          text: t('Notleuchte $a Testergebnis', 'Emergency luminaire $a test result'),
          sends: true,
        ),
      ],
    );
  }
  ga('7/0/0', t('Uhrzeit', 'Time'), t('Zeit', 'Time'), const Dpt(10, 1), [send('1.1.20')]);
  ga('7/0/1', t('Datum', 'Date'), t('Zeit', 'Time'), const Dpt(11, 1), [send('1.1.20')]);

  // Serial number as on the bus; the dimming actuator's device was replaced (inventory).
  DeviceInfo dev(String pa, String name, String product) => DeviceInfo(
    address: _pa(pa),
    name: name,
    product: product,
    manufacturer: 'Demo',
    serial: pa == '1.1.11'
        ? '00FA0001FFFF'
        : DemoTunnel.demoSerial(_pa(pa)).map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase(),
  );
  final devices = {
    for (final d in [
      dev('1.1.1', t('Spannungsversorgung', 'Power supply'), 'PS 640 mA'),
      dev('1.1.10', t('Schaltaktor 8-fach', 'Switch actuator 8-fold'), 'SA 8'),
      dev('1.1.12', t('Jalousieaktor 4-fach', 'Blind actuator 4-fold'), 'JA 4'),
      dev('1.1.13', t('Heizungsaktor 6-fach', 'Heating actuator 6-fold'), 'HA 6'),
      dev('1.1.20', t('IP-Schnittstelle', 'IP interface'), 'IPS 1'),
      for (final (n, rde, ren) in _rooms)
        _glass.contains(n)
            ? dev('1.1.${30 + n}', '${t(rde, ren)} ${t('Glastaster', 'glass push button')}', 'GT 6')
            : dev('1.1.${30 + n}', '${t(rde, ren)} ${t('Taster', 'push button')}', 'TS 4'),
      dev('1.1.41', t('Energiezähler', 'Energy meter'), 'EZ 3'),
      dev('1.1.11', t('Dimmaktor 4-fach', 'Dimming actuator 4-fold'), 'DA 4'),
      dev('1.1.42', t('Wechselrichter', 'Inverter'), 'WR 10'),
      dev('1.1.43', 'Wallbox', 'WB 11'),
      for (final (n, rde, ren) in _rooms)
        if (n.isEven) dev('1.1.${60 + n}', '${t(rde, ren)} ${t('Präsenzmelder', 'presence detector')}', 'PM 360'),
      dev('1.1.50', t('Rauchmelder Flur', 'Smoke detector hallway'), 'RM 1'),
      dev(dali, t('DALI-Gateway Flur/Büro', 'DALI gateway hall/office'), 'DG 64'),
      dev('1.2.0', t('Linienkoppler', 'Line coupler'), 'LK 1'),
      dev('1.2.20', t('Wetterstation', 'Weather station'), 'WS 1'),
    ])
      d.address: d,
  };
  _demoLocale = s.localeName;
  return _demoCache = GroupCatalog(
    groups,
    devices: devices,
    projectName: t('Musterhaus (Demo)', 'Sample house (demo)'),
    manufacturers: const {DemoTunnel.demoManufacturer: 'Demo'},
  );
}
