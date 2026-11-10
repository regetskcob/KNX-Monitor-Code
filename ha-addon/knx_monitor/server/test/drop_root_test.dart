import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

void main() {
  group('requestedUser', () {
    test('without PUID nothing is asked for', () {
      expect(requestedUser({}), isNull);
      expect(requestedUser({'PUID': ' ', 'PGID': '1000'}), isNull);
    });

    test('PGID defaults to PUID', () {
      expect(requestedUser({'PUID': '1000'}), (uid: 1000, gid: 1000));
      expect(requestedUser({'PUID': '1001', 'PGID': '100'}), (uid: 1001, gid: 100));
    });

    test('root, negative, too large or no number is refused, not ignored', () {
      for (final env in [
        {'PUID': '0'},
        {'PUID': '1000', 'PGID': '0'},
        {'PUID': '-1'},
        {'PUID': '65535'},
        {'PUID': 'daniel'},
      ]) {
        expect(() => requestedUser(env), throwsA(isA<DropRootException>()), reason: '$env');
      }
    });
  });

  test('handOverPaths: the data folder with everything below, the mount point alone, no links followed', () async {
    final root = await Directory.systemTemp.createTemp('drop');
    addTearDown(() => root.delete(recursive: true));
    final data = Directory('${root.path}/app');
    await File('${data.path}/installations/default/server.json').create(recursive: true);
    final outside = await Directory('${root.path}/outside').create();
    await File('${outside.path}/secret').create();
    await Link('${data.path}/link').create(outside.path);
    final paths = handOverPaths(data).toList();
    expect(paths.first, root.absolute.path);
    expect(paths, contains(data.absolute.path));
    expect(paths, contains(endsWith('installations/default/server.json')));
    expect(paths, contains(endsWith('/link')));
    expect(paths.where((p) => p.contains('outside')), isEmpty);
  });

  test('dropRoot does nothing without PUID', () {
    expect(dropRoot({}, Directory.systemTemp), isNull);
  });
}
