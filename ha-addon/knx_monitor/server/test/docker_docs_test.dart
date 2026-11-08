import 'dart:io';

import 'package:knx_monitor_server/box.dart';
import 'package:test/test.dart';

/// The Docker guide (`tool/public-repo/docker`, published in the add-on repository) and
/// the server must agree on the environment variables. A variable that is documented but
/// never read, or read but documented nowhere, is how Docker users ended up with settings
/// that did nothing (LAN_ACCESS before 1.9.9). The smoke test in `addon.yml` runs the
/// documented `compose.yaml` and `docker run` example against the real image.
void main() {
  final root = Directory('../../..');
  final guide = File('${root.path}/tool/public-repo/docker/README.md');
  final compose = File('${root.path}/tool/public-repo/docker/compose.yaml');

  /// Names of the variables the server reads: `env['X']` and `option('X', …)`.
  Set<String> readByServer() {
    final names = <String>{};
    final pattern = RegExp(r'''(?:env\[|option\()\s*'([A-Z][A-Z0-9_]+)'\s*[\],]''');
    for (final dir in ['bin', 'lib']) {
      for (final f in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        names.addAll(pattern.allMatches(f.readAsStringSync()).map((m) => m[1]!));
      }
    }
    return names;
  }

  /// Variables in the guide (`NAME` or `NAME=…` in backticks, `-e NAME=`) and in the
  /// environment of `compose.yaml` (also the commented-out ones).
  Set<String> documented() {
    final names = <String>{};
    final text = guide.readAsStringSync();
    names.addAll(RegExp(r'`([A-Z][A-Z0-9]*_?[A-Z0-9_]*)(?:=[^`]*)?`').allMatches(text).map((m) => m[1]!));
    names.addAll(RegExp(r'-e ([A-Z][A-Z0-9_]+)=').allMatches(text).map((m) => m[1]!));
    var inEnvironment = false;
    for (final line in compose.readAsLinesSync()) {
      if (RegExp(r'^\s{4}environment:').hasMatch(line)) {
        inEnvironment = true;
      } else if (RegExp(r'^\s{4}\S').hasMatch(line)) {
        inEnvironment = false;
      } else if (inEnvironment) {
        final m = RegExp(r'^\s{6}#?\s*([A-Z][A-Z0-9_]+):').firstMatch(line);
        if (m != null) names.add(m[1]!);
      }
    }
    return names;
  }

  // Not read by the server itself: the container's time zone and the image tag in Compose.
  const outsideServer = {'TZ', 'KNX_MONITOR_VERSION'};
  // Uppercase words in the guide that are no variables.
  const noVariables = {
    'HTTP',
    'HTTPS',
    'TLS',
    'PEM',
    'UDP',
    'TCP',
    'JSON',
    'NAS',
    'URL',
    'MQTT',
    'KNX',
    'VPN',
    'ON',
    'OFF',
  };
  // Read by the server, but not for Docker users: Home Assistant, the box image, the
  // build and the project's own tests.
  const internal = {
    'ADDON_VERSION', // set by the Dockerfile
    'SUPERVISOR_TOKEN', // Home Assistant add-on
    'BOX_STICKER', 'BOX_LINK', 'WLAN_SSID', 'WLAN_PASSWORD', // KNX box image (box/)
    'DATA_DIR', 'WEB_DIR', 'CARD_DIR', // paths, fixed in the image
    'ALLOW_ALL_EXPOSED', // left unnamed on purpose next to ALLOW_ALL (tests only)
  };

  test('every documented variable is read by the server', () {
    final read = readByServer();
    final unknown = {
      for (final name in documented().difference(noVariables).difference(outsideServer))
        if (!read.contains(name) &&
            !(name.endsWith('_FILE') && secretVariables.contains(name.substring(0, name.length - 5))))
          name,
    };
    expect(unknown, isEmpty, reason: 'documented in the Docker guide, but the server never reads it');
  });

  test('every variable the server reads is in the Docker guide', () {
    final missing = readByServer().difference(documented()).difference(internal);
    expect(missing, isEmpty, reason: 'add it to tool/public-repo/docker/README.md, or to `internal` here');
  });

  test('the guide has the docker run example the smoke test runs', () {
    // addon.yml takes the first sh block after "## Without Compose" and swaps the image
    // and the password; keep these strings when the example changes.
    final text = guide.readAsStringSync();
    final block = RegExp(r'## Without Compose[\s\S]*?```sh\n([\s\S]*?)```').firstMatch(text)?[1];
    expect(block, isNotNull);
    expect(block, contains('ghcr.io/regetskcob/knx-monitor:<version>'));
    expect(block, contains('--name knx-monitor '));
    expect(block, contains("BOX_PASSWORD='your-own-password'"));
    expect(block, contains(r'"$PWD/data:/data"'));
  });
}
