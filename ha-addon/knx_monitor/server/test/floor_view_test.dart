import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Recorder recorder;
  late HttpServer server;
  late FloorViewService service;
  final now = DateTime(2026, 11, 10, 12);

  Map<String, Object?> line(int ga, DateTime at, {int type = 2}) => {
    't': at.microsecondsSinceEpoch,
    's': 0x1105,
    'd': ga,
    'y': type,
    'x': '01',
    'm': true,
  };

  Map<String, Object?> view({Object? floors}) => {
    'format': 'busclear-floor-view',
    'version': 1,
    'source': 'own',
    'floors':
        floors ??
        [
          {
            'id': 'f1',
            'name': 'Erdgeschoss',
            'aspect': 1.4,
            'image': 'floor_view_images/f1.jpg.b64',
            'rooms': [
              {'name': 'Wohnen', 'x': 0, 'y': 0, 'w': 0.5, 'h': 0.5},
            ],
            'points': [
              {
                'id': 'p1',
                'name': 'Licht',
                'kind': 'light',
                'room': 'Wohnen',
                'x': 0.2,
                'y': 0.3,
                'addresses': [2305, 2306],
              },
              {
                'id': 'p2',
                'name': 'Steckdose',
                'kind': 'socket',
                'x': 0.8,
                'y': 0.8,
                'addresses': [9],
              },
              {'id': 'p3', 'name': 'Neu', 'x': 0.5, 'y': 0.5, 'addresses': <int>[]},
            ],
          },
        ],
  };

  Future<void> write(Object? json) => File('${root.path}/floor_view.json').writeAsString(jsonEncode(json));

  Future<HttpClientResponse> get(String path, {String method = 'GET'}) async {
    final client = HttpClient();
    addTearDown(client.close);
    final request = await client.openUrl(method, Uri.parse('http://127.0.0.1:${server.port}$path'));
    return request.close();
  }

  Future<Map<String, Object?>> ready() async {
    for (var i = 0; i < 100; i++) {
      final answer = await service.describe(root, recorder);
      if (answer['loading'] != true) return answer;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('history never finished loading');
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('knx_floor');
    recorder = Recorder(root);
    service = FloorViewService(now: () => now);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => service.serve(r, root, recorder));
  });
  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });

  test('no file: nothing available, nothing fails', () async {
    final answer = await service.describe(root, recorder);
    expect(answer['available'], isFalse);
    expect(answer['floors'], isEmpty);
  });

  test('last telegram per linked address: live and from the recorded history', () async {
    await write(view());
    recorder
      ..add(line(2305, now.subtract(const Duration(days: 2))))
      ..add(line(2306, now.subtract(const Duration(hours: 3))))
      ..add(line(9, now.subtract(const Duration(hours: 1)), type: 0)) // a read is no sign of life
      ..add(line(4711, now.subtract(const Duration(hours: 1)))); // not on the plan
    await recorder.flush();
    final answer = await ready();
    expect(answer['available'], isTrue);
    final last = answer['last']! as Map;
    expect(last.keys, unorderedEquals(['2305', '2306']), reason: 'only addresses on the plan, reads do not count');
    expect(last['2305'], now.subtract(const Duration(days: 2)).millisecondsSinceEpoch);
    expect(last['2306'], now.subtract(const Duration(hours: 3)).millisecondsSinceEpoch);
    expect(answer['since'], lessThanOrEqualTo(now.subtract(const Duration(days: 2)).millisecondsSinceEpoch));

    service.observe(line(2305, now), root: root.path);
    service.observe(line(9, now, type: 0), root: root.path);
    final live = (await service.describe(root, recorder))['last']! as Map;
    expect(live['2305'], now.millisecondsSinceEpoch);
    expect(live.containsKey('9'), isFalse);
  });

  test('another installation never shows the times of the previous one', () async {
    final other = await Directory.systemTemp.createTemp('knx_floor_other');
    addTearDown(() => other.delete(recursive: true));
    // Telegrams of installation A arrive before anyone asked for a view.
    service.observe(line(2305, now), root: other.path);
    await write(view());
    final answer = await ready();
    expect(answer['last'], isEmpty, reason: 'the same address in another installation was never heard here');

    // Heard here, then the server switches away and back: nothing carries over either way.
    service.observe(line(2305, now), root: root.path);
    expect(((await service.describe(root, recorder))['last']! as Map).keys, ['2305']);
    await File('${other.path}/floor_view.json').writeAsString(jsonEncode(view()));
    final there = Recorder(other);
    expect((await service.describe(other, there))['last'], isEmpty);
    expect((await ready())['last'], isEmpty, reason: 'live times of before the switch are gone, the history has none');
  });

  test('history: only missing addresses are read, one scan at a time', () async {
    await write(view());
    recorder
      ..add(line(2306, now.subtract(const Duration(hours: 3))))
      ..add(line(4711, now.subtract(const Duration(hours: 2))));
    await recorder.flush();
    // Many requests while the scan runs start no second one.
    final answers = await Future.wait([for (var i = 0; i < 5; i++) service.describe(root, recorder)]);
    expect(answers.every((a) => a['available'] == true), isTrue);
    expect(((await ready())['last']! as Map).keys, ['2306']);

    // A point gets another address: it is read on top, the known one stays.
    final more = view();
    (((more['floors']! as List).single as Map)['points'] as List).add({
      'id': 'p4',
      'name': 'Neu',
      'x': 0.1,
      'y': 0.1,
      'addresses': [4711],
    });
    await write(more);
    final last = (await ready())['last']! as Map;
    expect(last.keys, unorderedEquals(['2306', '4711']));
    expect((await service.describe(root, recorder)).containsKey('loading'), isFalse);
  });

  test('a file from elsewhere is reduced to known fields, types and limits', () async {
    await write(
      view(
        floors: [
          'not a floor',
          {
            'id': 'f1',
            'name': '<script>alert(1)</script>${'x' * 300}',
            'aspect': 'wide',
            'image': '../../secure_keys.json',
            'secret': 'must not be passed on',
            'rooms': 'none',
            'points': [
              {
                'id': 'p1',
                'name': 7,
                'x': 9,
                'y': 'top',
                'addresses': ['x', -1, 70000, 2305],
                'onclick': 'evil()',
              },
              for (var i = 0; i < 700; i++) {'id': 'q$i', 'addresses': List.filled(40, 1)},
            ],
          },
        ],
      ),
    );
    final answer = await ready();
    final floor = (answer['floors']! as List).single as Map;
    expect(floor.keys, unorderedEquals(['id', 'name', 'aspect', 'image', 'rooms', 'points']));
    expect((floor['name'] as String).length, FloorViewService.maxText);
    expect(floor['aspect'], 1.5);
    expect(floor['image'], isFalse);
    expect(floor['rooms'], isEmpty);
    final points = floor['points'] as List;
    expect(points, hasLength(FloorViewService.maxPoints));
    expect(points.first, {
      'id': 'p1',
      'name': '',
      'kind': '',
      'room': '',
      'x': 1.0,
      'y': 0.5,
      'addresses': [2305],
    });
    expect((points[1] as Map)['addresses'], hasLength(FloorViewService.maxAddresses));
    expect(jsonEncode(answer), isNot(contains('must not be passed on')));
  });

  test('newer or foreign format: not available instead of guessed', () async {
    await write({...view(), 'version': 2});
    expect((await service.describe(root, recorder))['available'], isFalse);
    await write({'format': 'knx-monitor-home-plan', 'formatVersion': 1});
    expect((await service.describe(root, recorder))['available'], isFalse);
    await File('${root.path}/floor_view.json').writeAsString('{broken');
    expect((await service.describe(root, recorder))['available'], isFalse);
  });

  test('images: only the JPEG of a level, never another file', () async {
    final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3];
    await Directory('${root.path}/floor_view_images').create();
    await File('${root.path}/floor_view_images/f1.jpg.b64').writeAsString(base64Encode(jpeg));
    await File('${root.path}/secure_keys.json').writeAsString('{"secret":true}');
    await write(view());
    expect((await service.image(root, 'f1'))!.bytes, jpeg);
    expect(await service.image(root, 'f2'), isNull);
    expect(await service.image(root, '../secure_keys.json'), isNull);

    // The file names a path outside the image folders: nothing is opened.
    for (final path in ['secure_keys.json', '../x.jpg.b64', 'floor_view_images/../secure_keys.json', '/etc/passwd']) {
      await write(
        view(
          floors: [
            {'id': 'f1', 'image': path, 'points': <Object?>[]},
          ],
        ),
      );
      expect(await service.image(root, 'f1'), isNull, reason: path);
    }

    // Not a JPEG behind the right name.
    await write(view());
    await File('${root.path}/floor_view_images/f1.jpg.b64')
        .writeAsString(base64Encode(utf8.encode('<svg onload="x()"/>')));
    expect(await service.image(root, 'f1'), isNull);
  });

  test('HTTP: read-only, JSON without cache, image with its type', () async {
    await write(view());
    await Directory('${root.path}/floor_view_images').create();
    await File('${root.path}/floor_view_images/f1.jpg.b64').writeAsString(base64Encode([0xFF, 0xD8, 0xFF, 0xE0]));

    final json = await get('/api/floor-view');
    expect(json.statusCode, HttpStatus.ok);
    expect(json.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect((jsonDecode(await utf8.decodeStream(json)) as Map)['available'], isTrue);

    final image = await get('/api/floor-view/image?floor=f1');
    expect(image.statusCode, HttpStatus.ok);
    final etag = image.headers.value(HttpHeaders.etagHeader)!;
    expect(image.headers.contentType?.mimeType, 'image/jpeg');
    expect(image.headers.value('x-content-type-options'), 'nosniff');
    await image.drain<void>();

    // Unchanged file: 304 without a body. A changed file gets a new tag and is read again.
    final client = HttpClient();
    addTearDown(client.close);
    Future<HttpClientResponse> conditional(String tag) async {
      final request = await client.getUrl(Uri.parse('http://127.0.0.1:${server.port}/api/floor-view/image?floor=f1'));
      request.headers.set(HttpHeaders.ifNoneMatchHeader, tag);
      return request.close();
    }

    final same = await conditional(etag);
    expect(same.statusCode, HttpStatus.notModified);
    expect(await same.fold<int>(0, (n, chunk) => n + chunk.length), 0);
    final file = File('${root.path}/floor_view_images/f1.jpg.b64');
    await file.writeAsString(base64Encode([0xFF, 0xD8, 0xFF, 0xE0, 9, 9]));
    await file.setLastModified(DateTime(2027));
    final fresh = await conditional(etag);
    expect(fresh.statusCode, HttpStatus.ok);
    expect(fresh.headers.value(HttpHeaders.etagHeader), isNot(etag));
    expect(await fresh.fold<int>(0, (n, chunk) => n + chunk.length), 6);

    expect((await get('/api/floor-view/image?floor=..%2Fsecure_keys.json')).statusCode, HttpStatus.notFound);
    for (final method in ['POST', 'PUT', 'DELETE']) {
      expect((await get('/api/floor-view', method: method)).statusCode, HttpStatus.methodNotAllowed, reason: method);
    }
    expect(jsonDecode(await File('${root.path}/floor_view.json').readAsString()), view(), reason: 'never written');
  });

  group('card', () {
    final card = File('../card/${LovelaceCard.floorFileName}').readAsStringSync();

    test('has the placeholders the add-on fills in and registers its element', () {
      expect(card, contains("'__KNX_MONITOR_INGRESS__'"));
      expect(card, contains("'__KNX_MONITOR_VERSION__'"));
      expect(card, contains("const CARD = 'knx-monitor-floor-card'"));
      expect(card, contains('/api/floor-view'));
    });

    test('never builds markup from data', () {
      // Names on the plan come from a file. The card may only use createElement/textContent.
      for (final sink in ['innerHTML', 'outerHTML', 'insertAdjacentHTML', 'document.write', 'eval(', 'new Function']) {
        expect(card, isNot(contains(sink)), reason: sink);
      }
      expect(card, contains('textContent'));
      expect(card, isNot(contains("method: 'POST'")), reason: 'the card only reads');
    });
  });

  test('the floor card installs next to the chart card under its own name', () async {
    final dir = await Directory.systemTemp.createTemp('knx_card2');
    addTearDown(() => dir.delete(recursive: true));
    final template = File('${dir.path}/${LovelaceCard.floorFileName}')..writeAsStringSync("'__KNX_MONITOR_INGRESS__'");
    final card = LovelaceCard(template: template, cardFile: LovelaceCard.floorFileName, token: 'x');
    expect(card.cardUrl, '/local/knx-monitor/knx-monitor-floor-card.js');
    expect(LovelaceCard(template: template, token: 'x').cardUrl, LovelaceCard.url);
  });
}
