import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// Bus connection without a network, one per host.
class _Link implements BusLink {
  _Link(this.host);
  final String host;
  final _frames = StreamController<Uint8List>.broadcast();
  final _lost = Completer<String>();
  @override
  Stream<Uint8List> get frames => _frames.stream;
  void receive(Uint8List frame) => _frames.add(frame);
  @override
  int? get address => host == 'a' ? 0x1101 : 0x1201;
  @override
  String get label => 'Test $host';
  @override
  Future<void> connect() async {}
  @override
  Future<void> send(Uint8List cemi) async {}
  @override
  Future<String> get lost => _lost.future;
  void drop() {
    if (!_lost.isCompleted) _lost.complete('weg');
  }

  @override
  Future<void> close() async => drop();
}

/// L_Data.ind from 1.1.5 to 1/2/3, GroupValueWrite 1, with [hop].
Uint8List _ind({int hop = 6}) =>
    Uint8List.fromList([0x29, 0x00, 0xBC, 0x80 | (hop << 4), 0x11, 0x05, 0x0A, 0x03, 0x01, 0x00, 0x81]);

Future<void> _until(bool Function() ok) async {
  for (var i = 0; i < 200 && !ok(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ok(), isTrue);
}

void main() {
  late Directory data;
  setUp(() async => data = await Directory.systemTemp.createTemp('taps'));
  tearDown(() async => data.delete(recursive: true));

  test('BusConfig keeps only usable tap points', () {
    final c = BusConfig.fromJson({
      'taps': [
        {'mode': 'tcp', 'host': '10.0.0.2', 'name': 'Linie 1.2', 'windowMs': 99999},
        {'mode': 'udp', 'host': ''},
        {'mode': 'x', 'host': 'a'},
        {'mode': 'routing', 'host': ''},
      ],
    });
    expect(c.taps, hasLength(2));
    expect(c.taps.first['windowMs'], 5000);
    expect(BusConfig.invalidChange({'taps': 'x'}), isNotNull);
    expect(BusConfig.invalidChange({'taps': List.filled(8, {})}), isNotNull);
    expect(BusConfig.invalidChange({'taps': []}), isNull);
  });

  test('main connection and tap point: one telegram with a sighting, status lists the tap point', () async {
    final links = <String, _Link>{};
    final lines = <Map<String, Object?>>[];
    final bus = BusService(
      data,
      link: (c) => links[c.host] = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (line, {required secure, required decrypted}) => lines.add(line),
    );
    await bus.start();
    await bus.update({
      'enabled': true,
      'mode': 'udp',
      'host': 'a',
      'taps': [
        {'name': 'Linie 1.2', 'mode': 'udp', 'host': 'b'},
      ],
    });
    await _until(() => bus.state == 'connected' && links.containsKey('b'));
    await _until(() => (bus.status()['taps'] as List).first['state'] == 'connected');
    links['a']!.receive(_ind());
    links['b']!.receive(_ind(hop: 5));
    await _until(() => lines.isNotEmpty);
    expect(lines.single['sg'], [
      [1, isA<int>(), 5],
    ]);
    expect(lines.single.containsKey('tp'), isFalse);
    expect(bus.today, 1);

    // Seen only at the tap point (filtered towards the main line): leaves after the window.
    links['b']!.receive(_ind(hop: 5));
    await _until(() => lines.length == 2);
    expect(lines.last['tp'], 1);

    // Tap point drops: the main connection carries on, the tap point reconnects on its own.
    final first = links['b']!;
    first.drop();
    await _until(() => !identical(links['b'], first));
    expect(bus.state, 'connected');
    await _until(() => (bus.status()['taps'] as List).first['state'] == 'connected');
    await bus.shutdown();
  });

  test('without tap points nothing waits', () async {
    late _Link link;
    final lines = <Map<String, Object?>>[];
    final bus = BusService(
      data,
      link: (c) => link = _Link(c.host),
      describe: (_, _) async => null,
      telegram: (line, {required secure, required decrypted}) => lines.add(line),
    );
    await bus.start();
    await bus.update({'enabled': true, 'mode': 'udp', 'host': 'a'});
    await _until(() => bus.state == 'connected');
    link.receive(_ind());
    await _until(() => lines.isNotEmpty);
    expect(lines, hasLength(1));
    expect(bus.status().containsKey('taps'), isFalse);
    await bus.shutdown();
  });
}
