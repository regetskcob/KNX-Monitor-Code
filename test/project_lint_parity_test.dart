// The project check exists twice: in the app (lib/model/project_check.dart) and in the add-on/box
// server (ha-addon/knx_monitor/server/lib/src/project_lint.dart, for the MCP tools). Both check
// test/fixtures/project_lint/catalog.json against the same expected.json, so they cannot drift
// apart unnoticed. A rule changed on purpose: run with UPDATE_LINT_PARITY=1, then adapt the
// server until its test (project_lint_parity_test.dart there) is green again.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/project_check.dart';

const _dir = 'test/fixtures/project_lint';

void main() {
  test('Projektprüfung der App = erwartete Befunde (gemeinsam mit dem Server)', () {
    final catalog = GroupCatalog.fromJson(
      jsonDecode(File('$_dir/catalog.json').readAsStringSync()) as Map<String, Object?>,
    );
    CatalogStore.instance.catalog = catalog;
    final l = ProjectLint.of(catalog);
    List<String> groups(Iterable<GroupInfo> g) => [for (final x in g) formatGroup(x.address)]..sort();
    List<String> devices(Iterable<DeviceInfo> d) => [for (final x in d) formatIndividual(x.address)]..sort();
    final actual = <String, List<String>>{
      'status_without_transmit': groups(l.statusWithoutTransmit),
      'read_without_read_flag': groups(l.readWithoutReadFlag),
      'multiple_read_answers': groups(l.multipleReadAnswers),
      'object_without_communication': groups(l.objectsWithoutCommunication.map((e) => e.$1)),
      'multiple_senders': groups(l.multipleSenders),
      'without_sender': groups(l.withoutSender),
      'without_receiver': groups(l.withoutReceiver),
      'no_name': groups(l.incomplete.where((e) => e.noName).map((e) => e.group)),
      'no_dpt': groups(l.incomplete.where((e) => e.noDpt).map((e) => e.group)),
      'main_group_14_15': groups(l.unfilteredMainGroups),
      'device_without_links': devices(l.devicesWithoutLinks),
      'device_never_programmed': devices(l.devicesNeverProgrammed),
      'device_download_pending': devices(l.devicesPendingDownload),
      'crowded_line': [for (final c in l.crowdedLines) '${c.line >> 4}.${c.line & 0xF}']..sort(),
    };
    final expected = File('$_dir/expected.json');
    if (Platform.environment['UPDATE_LINT_PARITY'] == '1') {
      expected.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(actual)}\n');
    }
    final want = (jsonDecode(expected.readAsStringSync()) as Map<String, Object?>).map(
      (k, v) => MapEntry(k, (v! as List).cast<String>()),
    );
    expect(actual, want);
    // Every rule is exercised by the fixture.
    expect(actual.values.where((v) => v.isEmpty), isEmpty, reason: 'a rule without a case in catalog.json');
  });
}
