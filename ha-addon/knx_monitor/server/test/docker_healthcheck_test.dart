import 'dart:io';

import 'package:test/test.dart';

/// Both images check themselves with `server healthcheck`. The images have no
/// shell, so nothing can guard the call: if the server did not know the
/// subcommand, every check would start a second server on the same data folder.
/// This keeps the two together.
void main() {
  final root = Directory('../../..');

  test('the HEALTHCHECK of both images calls a subcommand the server knows', () {
    final server = File('bin/server.dart').readAsStringSync();
    for (final path in ['Dockerfile', 'ha-addon/knx_monitor/Dockerfile']) {
      final lines = File('${root.path}/$path').readAsLinesSync().where((l) => l.startsWith('HEALTHCHECK')).toList();
      expect(lines, hasLength(1), reason: '$path: one HEALTHCHECK');
      final command = RegExp(r'CMD \["/app/server", "([a-z]+)"\]$').firstMatch(lines.single)?[1];
      expect(command, isNotNull, reason: '$path: HEALTHCHECK in exec form on /app/server');
      expect(server, contains("'$command'"), reason: 'bin/server.dart does not handle "$command"');
    }
  });
}
