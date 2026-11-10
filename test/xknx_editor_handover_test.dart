import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/knx/xknx_parser.dart';
import 'package:knx_monitor/model/ets_tasks.dart';
import 'package:knx_monitor/model/xknx_editor_handover.dart';
import 'package:knx_monitor/platform/xknx_editor_client.dart';

GroupLink _link(String pa, ComFlags f, {bool first = true, String? ref}) => GroupLink(
  device: parseIndividual(pa)!,
  flags: f,
  sends: first && f.transmit && f.communication && !(f.write && f.update),
  ref: ref,
);

GroupCatalog _project() {
  const status = ComFlags(transmit: true); // C T, kein L
  const display = ComFlags(write: true, transmit: true, update: true);
  final groups = [
    GroupInfo(
      address: parseGroup('1/4/2')!,
      name: 'Licht Status',
      dpt: const Dpt(1, 1),
      links: [
        _link('1.1.5', status, ref: 'M-0083_A-1_O-2_R-2'),
        _link('1.1.50', display, ref: 'M-0083_A-2_O-9_R-9'),
      ],
    ),
    GroupInfo(
      address: parseGroup('1/1/5')!,
      name: 'Licht Keller',
      links: [_link('1.1.5', const ComFlags(communication: false, write: true), ref: 'M-0083_A-1_O-7_R-7')],
    ),
    GroupInfo(address: parseGroup('1/1/6')!, name: 'Licht Garten', dpt: const Dpt(1, 1)),
  ];
  final devices = {
    for (final a in ['1.1.5', '1.1.50']) parseIndividual(a)!: DeviceInfo(address: parseIndividual(a)!, name: a),
    parseIndividual('1.1.60')!: DeviceInfo(
      address: parseIndividual('1.1.60')!,
      name: 'Neu',
      pendingDownload: const [DownloadPart.groups],
    ),
  };
  return GroupCatalog({for (final g in groups) g.address: g}, devices: devices, projectName: 'Testhaus');
}

/// Whether [ops] contain exactly this operation (maps compared by value).
bool _has(List<Map<String, Object?>> ops, Map<String, Object?> op) => ops.any((o) => jsonEncode(o) == jsonEncode(op));

void main() {
  setUp(() => CatalogStore.instance.catalog = _project());

  test('Korrekturen nur, wo eindeutig; der Rest als Notiz', () {
    final project = _project();
    final tasks = EtsTasks.of(
      project,
      {parseGroup('1/1/5')!: const Dpt(1, 1), parseGroup('1/1/6')!: const Dpt(9)},
      names: {parseGroup('1/1/6')!: 'Garten Licht'},
    );
    final h = XknxEditorHandover.of(tasks, project);
    final ops = h.operations;
    expect(
      _has(ops, {
        'op': 'set_group_address_dpt',
        'params': {'group_address': '1/1/5', 'dpt': 'DPST-1-1'},
      }),
      isTrue,
    );
    expect(
      _has(ops, {
        'op': 'rename_group_address',
        'params': {'group_address': '1/1/6', 'name': 'Garten Licht'},
      }),
      isTrue,
    );
    // Nur Haupttyp: keine Korrektur.
    expect(
      ops.where((o) => o['op'] == 'set_group_address_dpt' && (o['params']! as Map)['group_address'] == '1/1/6'),
      isEmpty,
    );
    // L-Flag nur am sendenden Status-Objekt, nicht an der Anzeige.
    final flags = ops.where((o) => o['op'] == 'set_com_object_flag').map((o) => jsonEncode(o['params'])).toList();
    expect(
      flags,
      contains(
        jsonEncode({
          'device_address': '1.1.5',
          'com_object_ref_id': 'M-0083_A-1_O-2_R-2',
          'flag': 'read',
          'value': true,
        }),
      ),
    );
    expect(flags.where((f) => f.contains('M-0083_A-2_O-9_R-9')), isEmpty);
    expect(
      flags,
      contains(
        jsonEncode({
          'device_address': '1.1.5',
          'com_object_ref_id': 'M-0083_A-1_O-7_R-7',
          'flag': 'communication',
          'value': true,
        }),
      ),
    );
    // Notizen: Download ausstehend am Gerät, Hinweise an Adressen, alle mit Marke.
    final pending = h.notes.firstWhere((n) => n.device == parseIndividual('1.1.60'));
    // Ohne Verknüpfung und Download ausstehend.
    expect(pending.lines, hasLength(2));
    expect(h.notes.expand((n) => n.lines).every((l) => l.startsWith('$xknxNoteMarker ')), isTrue);
    final json = h.toJson();
    expect(json['format'], 'busclear-xknx-editor');
    expect((json['notes']! as List).any((n) => (n as Map)['device_address'] == '1.1.60'), isTrue);
  });

  test('Datentyp-Vorschläge aus dem Verlauf: sicher als Korrektur, sonst Notiz', () {
    final project = _project();
    String? dptOp(XknxEditorHandover h, String ga) => [
      for (final o in h.operations)
        if (o['op'] == 'set_group_address_dpt' && (o['params']! as Map)['group_address'] == ga)
          (o['params']! as Map)['dpt'] as String,
    ].singleOrNull;

    final sure = XknxEditorHandover.of(
      EtsTasks.of(project, const {}),
      project,
      dptSuggestions: [
        {'group_address': '1/1/5', 'dpt': 'DPST-1-1', 'certainty': 'high'},
        // Has a type already: nothing to do.
        {'group_address': '1/4/2', 'dpt': 'DPST-1-11', 'certainty': 'high'},
      ],
    );
    expect(dptOp(sure, '1/1/5'), 'DPST-1-1');
    expect(dptOp(sure, '1/4/2'), isNull);

    // Set in the app: the app's type wins, no second correction.
    final app = XknxEditorHandover.of(
      EtsTasks.of(project, {parseGroup('1/1/5')!: const Dpt(1, 1)}),
      project,
      dptSuggestions: [
        {'group_address': '1/1/5', 'dpt': 'DPST-1-19', 'certainty': 'high'},
      ],
    );
    expect(dptOp(app, '1/1/5'), 'DPST-1-1');

    final likely = XknxEditorHandover.of(
      EtsTasks.of(project, const {}),
      project,
      dptSuggestions: [
        {'group_address': '1/1/5', 'dpt': 'DPST-5-1', 'certainty': 'medium'},
      ],
    );
    expect(dptOp(likely, '1/1/5'), isNull);
    expect(
      likely.notes.firstWhere((n) => n.group == parseGroup('1/1/5')).lines.any((l) => l.contains('DPST-5-1')),
      isTrue,
    );
  });

  test('Kommentar: eigener Text bleibt, alte Busclear-Zeilen werden ersetzt', () {
    expect(mergeXknxComment(null, ['$xknxNoteMarker a']), '$xknxNoteMarker a');
    expect(
      mergeXknxComment('Eigene Notiz\n$xknxNoteMarker alt\n', ['$xknxNoteMarker neu']),
      'Eigene Notiz\n$xknxNoteMarker neu',
    );
  });

  test('aus einem .xknx: Download ausstehend wird Notiz', () {
    final c = parseXknx(File('test/fixtures/xknx/testhaus.xknx').readAsBytesSync());
    final h = XknxEditorHandover.of(EtsTasks.of(c, const {}), c);
    expect(h.notes.where((n) => n.device == parseIndividual('1.1.20')), hasLength(1));
    expect(h.notes.where((n) => n.device == parseIndividual('1.1.30')), hasLength(1));
  });

  group('XknxEditorClient', () {
    // Simulated editor: SSE answers, session header, records calls and comments.
    MockClient editor({required List<String> calls, Map<int, String>? comments, int status = 200}) {
      comments ??= {};
      return MockClient((request) async {
        if (status != 200) return http.Response('', status);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final method = body['method'] as String;
        if (method == 'initialize') {
          return http.Response(
            '{"jsonrpc":"2.0","id":${body['id']},"result":{}}',
            200,
            headers: {'mcp-session-id': 'abc'},
          );
        }
        if (method.startsWith('notifications/')) return http.Response('', 202);
        expect(request.headers['mcp-session-id'], 'abc');
        final name = body['params']['name'] as String;
        final args = (body['params']['arguments'] as Map).cast<String, Object?>();
        calls.add(name);
        final Object result = switch (name) {
          'project_status' => {'open': true, 'path': '/x.xknx'},
          'project_info' => {'name': 'Testhaus', 'path': '/x.xknx'},
          'project_batch' when args['dry_run'] == true => {'dry_run': true, 'valid': true, 'results': <Object?>[]},
          'project_batch' => {
            'applied': true,
            'results': [
              for (final (i, o) in (args['operations']! as List).indexed)
                if ((o as Map)['op'] == 'set_comment')
                  () {
                    final p = (o['params'] as Map).cast<String, Object?>();
                    comments![p['kind'] == 'project' ? -1 : p['element_id']! as int] = p['text']! as String;
                    return {'index': i, 'status': 'ok'};
                  }()
                else if (i == 0)
                  {'index': i, 'status': 'error', 'error': 'nope'}
                else
                  {'index': i, 'status': 'ok'},
            ],
          },
          'project_list_group_addresses' => {
            'items': [
              {'id': 7, 'address': '1/4/2'},
              {'id': 8, 'address': '1/1/5'},
              {'id': 9, 'address': '1/1/6'},
            ],
          },
          'project_list_devices' => {
            'items': [
              {'node_id': 1, 'individual_address': '1.1.5'},
              {'node_id': 2, 'individual_address': '1.1.50'},
              {'node_id': 3, 'individual_address': '1.1.60'},
            ],
          },
          'project_get_comment' => {'text': comments![args['kind'] == 'project' ? -1 : args['element_id']] ?? ''},
          _ => {'error': 'unknown'},
        };
        final event = jsonEncode({
          'jsonrpc': '2.0',
          'id': body['id'],
          'result': {
            'content': [
              {'type': 'text', 'text': jsonEncode(result)},
            ],
          },
        });
        return http.Response.bytes(
          utf8.encode('event: message\ndata: $event\n\n'),
          200,
          headers: {'content-type': 'text/event-stream; charset=utf-8'},
        );
      });
    }

    test('übergibt: Probelauf, Batch, Kommentare angehängt', () async {
      final calls = <String>[];
      final comments = <int, String>{3: 'Eigener Text'};
      final client = XknxEditorClient(
        xknxEditorDefaultEndpoint,
        client: editor(calls: calls, comments: comments),
      );
      expect((await client.openProject())!.name, 'Testhaus');
      final project = _project();
      final h = XknxEditorHandover.of(EtsTasks.of(project, {parseGroup('1/1/5')!: const Dpt(1, 1)}), project);
      final r = await client.apply(h);
      // Probelauf, Korrekturen, Kommentare: drei Batches.
      expect(calls.where((c) => c == 'project_batch'), hasLength(3));
      expect(calls, isNot(contains('project_set_comment')));
      expect(r.applied, h.operations.length - 1);
      expect(r.failed.single, contains('nope'));
      expect(r.noted, h.notes.length);
      expect(comments[3], startsWith('Eigener Text\n$xknxNoteMarker'));
      // Index im Projektkommentar; beim nächsten Mal ohne Befund an 1.1.60 wird dort aufgeräumt.
      expect(parseXknxIndex(comments[-1]).devices, contains(3));
      final empty = XknxEditorHandover.of(EtsTasks.of(GroupCatalog(const {}), const {}), GroupCatalog(const {}));
      await client.apply(empty);
      expect(comments[3], 'Eigener Text');
      expect(parseXknxIndex(comments[-1]).devices, isEmpty);
    });

    test('Token nur über HTTPS oder an diesen Rechner', () async {
      final calls = <String>[];
      final remote = XknxEditorClient(
        Uri.parse('http://192.168.1.50:8766/mcp'),
        token: 't',
        client: editor(calls: calls),
      );
      await expectLater(
        remote.openProject(),
        throwsA(isA<XknxEditorException>().having((e) => e.message, 'message', XknxEditorException.insecureToken)),
      );
      expect(calls, isEmpty);
      final local = XknxEditorClient(
        xknxEditorDefaultEndpoint,
        token: 't',
        client: editor(calls: calls),
      );
      expect(await local.openProject(), isNotNull);
      final tls = XknxEditorClient(
        Uri.parse('https://editor.local/mcp'),
        token: 't',
        client: editor(calls: calls),
      );
      expect(await tls.openProject(), isNotNull);
      final open = XknxEditorClient(Uri.parse('http://192.168.1.50:8766/mcp'), client: editor(calls: calls));
      expect(await open.openProject(), isNotNull);
    });

    test('Geräte des Editors in Adressreihenfolge', () async {
      final client = XknxEditorClient(xknxEditorDefaultEndpoint, client: editor(calls: []));
      expect(await client.deviceAddresses(), ['1.1.5', '1.1.50', '1.1.60']);
    });

    test('Token fehlt: verständlicher Fehler', () async {
      final client = XknxEditorClient(xknxEditorDefaultEndpoint, client: editor(calls: [], status: 401));
      expect(client.openProject(), throwsA(isA<XknxEditorException>().having((e) => e.message, 'message', '401')));
    });
  });
}
