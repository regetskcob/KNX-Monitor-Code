import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../l10n/locale_controller.dart';
import 'cemi.dart';
import 'group_catalog.dart';
import 'knx_tunnel.dart';
import 'telegram.dart';

/// Demo without an installation: a fictional sample house with a project and plausible live values.
/// For people without a gateway and for app review.
///
/// Behaves like a [KnxTunnel] from the outside: telegrams arrive via [telegrams], reads are
/// answered, writes switch and report back.
class DemoTunnel extends KnxTunnel {
  DemoTunnel() : super('demo');

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
    for (final ga in _values.keys.toList()..shuffle(_rng)) {
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
    // Initial state step by step, then ongoing traffic.
    var i = 0;
    final initial = _values.keys.toList()..shuffle(_rng);
    _timer = Timer.periodic(const Duration(milliseconds: 160), (t) {
      if (i < initial.length) {
        _emit(initial[i++]);
      } else {
        t.cancel();
        _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _step());
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _timer = null;
    active = false;
    state.value = TunnelState.disconnected;
  }

  @override
  Future<bool?> read(int destination) async {
    inject(_telegram(destination, TelegramType.read, outgoing: true));
    // Finding for the health check: this object has no read flag.
    if (destination == _silent) return true;
    if (_values.containsKey(destination)) {
      await Future<void>.delayed(Duration(milliseconds: 60 + _rng.nextInt(80)));
      inject(_telegram(destination, TelegramType.response));
    }
    return true;
  }

  @override
  Future<bool?> write(int destination, {int? small, List<int> data = const []}) async {
    final value = small?.toDouble() ?? _decode(destination, data);
    if (value != null) _values[destination] = value;
    inject(_telegram(destination, TelegramType.write, outgoing: true));
    // Switching: the actuator reports back via the feedback address.
    final feedback = _feedbackOf[destination];
    if (feedback != null && value != null) {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _values[feedback] = value;
      _emit(feedback);
    }
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
    final now = clock();
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
    void feedback() {
      _values[_ga('1/1/$n')] = on;
      _emit(_ga('1/1/$n'));
    }

    _sink != null ? feedback() : Timer(const Duration(milliseconds: 150), feedback);
  }

  void _emit(int ga) => (_sink ?? inject)(_telegram(ga, TelegramType.write));

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

/// Demo findings: valve state without read flag, humidity with wrong length.
final _silent = _ga('2/3/3');
final _humidity = _ga('2/4/2');
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

/// Switch command → feedback address.
final _feedbackOf = {for (final r in _rooms) _ga('1/0/${r.$1}'): _ga('1/1/${r.$1}')};

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
