import 'dart:io';

import 'package:test/test.dart';

/// Was in Workflows, Dockerfile und Vorlagen festgelegt sein muss: Das prüft
/// sonst niemand, bis es beim Release auffällt.
void main() {
  String read(String path) => File('../../../$path').readAsStringSync();

  test('Basis-Image per Digest', () {
    expect(read('ha-addon/knx_monitor/Dockerfile'), matches(RegExp(r'FROM dart:[\d.]+@sha256:[0-9a-f]{64} AS build')));
  });

  test('pi-gen: Tag und Commit, Abweichung bricht ab', () {
    expect(read('.github/workflows/box-image.yml'), matches(RegExp(r"'[0-9a-f]{40}'")));
    expect(read('box/build-image.sh'), contains('PI_GEN_COMMIT'));
  });

  test('alle Actions auf Commit-SHAs', () {
    for (final name in ['addon.yml', 'box-image.yml', 'ci.yml']) {
      final uses = RegExp(r'uses:\s*(\S+)').allMatches(read('.github/workflows/$name'));
      for (final m in uses) {
        expect(m[1], matches(RegExp(r'@[0-9a-f]{40}$')), reason: '$name: ${m[1]}');
      }
    }
  });

  test('Signieren nur mit id-token und nur beim Veröffentlichen', () {
    final addon = read('.github/workflows/addon.yml');
    expect(RegExp(r'cosign sign --yes').allMatches(addon), hasLength(2));
    expect(RegExp(r'id-token: write').allMatches(addon), hasLength(2), reason: 'nur image und latest');
    final box = read('.github/workflows/box-image.yml');
    expect(RegExp(r'cosign sign-blob --yes').allMatches(box), hasLength(2));
    expect(RegExp(r'id-token: write').allMatches(box), hasLength(2));
  });

  test('Box-Release mit Prüfsummen und Signaturen', () {
    final release = read('tool/release.sh');
    final box = release.substring(release.indexOf('cmd_box() {'), release.indexOf('cmd_status() {'));
    expect(box, contains('SHA256SUMS.txt'));
    expect(box, contains('.sigstore.json'));
    final desktop = release.substring(release.indexOf('cmd_desktop() {'), release.indexOf('cmd_box() {'));
    expect(desktop, contains('SHA256SUMS.txt'));
  });

  test('Docker-Vorlage: feste Version passend zum Add-on, Kabelzugang aus', () {
    final compose = read('tool/public-repo/docker/compose.yaml');
    final version = RegExp(r'version: "([^"]+)"').firstMatch(read('ha-addon/knx_monitor/config.yaml'))![1]!;
    expect(compose, contains('knx-monitor:\${KNX_MONITOR_VERSION:-$version}'));
    expect(compose, isNot(contains(':latest')));
    expect(compose, contains(r'LAN_ACCESS: "${LAN_ACCESS:-no}"'));
    expect(read('tool/sync_public.sh'), contains('KNX_MONITOR_VERSION'));
  });

  test('Changelog nennt die Version aus config.yaml', () {
    final version = RegExp(r'version: "([^"]+)"').firstMatch(read('ha-addon/knx_monitor/config.yaml'))![1]!;
    expect(read('ha-addon/knx_monitor/CHANGELOG.md'), contains('## $version\n'));
  });
}
