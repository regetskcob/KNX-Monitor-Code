// Same cases as the app's test/project_lint_parity_test.dart: the server's project check (MCP
// tools) must find exactly what the app finds. The files live in the app's test fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

const _dir = '../../../test/fixtures/project_lint';

void main() {
  test('Projektprüfung des Servers = erwartete Befunde der App', () {
    final catalog = LintCatalog.fromJson(
      jsonDecode(File('$_dir/catalog.json').readAsStringSync()) as Map<String, Object?>,
    );
    final r = ProjectLintResult.of(catalog);
    String key(Map<String, Object?> item) => (item['group_address'] ?? item['device'] ?? item['line'])! as String;
    final actual = {for (final MapEntry(:key, :value) in r.lists.entries) key: value};
    final keyed = actual.map((kind, items) => MapEntry(kind, [for (final i in items) key(i)]..sort()));
    final want = (jsonDecode(File('$_dir/expected.json').readAsStringSync()) as Map<String, Object?>).map(
      (k, v) => MapEntry(k, (v! as List).cast<String>()),
    );
    expect(keyed, want);
  });
}
