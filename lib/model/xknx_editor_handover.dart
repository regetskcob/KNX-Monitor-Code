import 'dart:convert';

import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'ets_task_text.dart';
import 'ets_tasks.dart';
import 'project_check.dart';

/// Marker at the start of every comment line Busclear writes into the XKNX Editor, so a later
/// handover replaces its own lines and leaves the user's text alone.
const xknxNoteMarker = '[Busclear]';

/// Line in the project's comment listing the elements Busclear annotated (editor ids), so the next
/// handover can clear notes that no longer apply.
const xknxIndexMarker = '[Busclear-Index]';

/// A note for one element of the project: a group address or a device.
class XknxEditorNote {
  XknxEditorNote({this.group, this.device}) : assert((group == null) != (device == null));

  final int? group;
  final int? device;
  final List<String> lines = [];

  Map<String, Object?> toJson(GroupStyle style) => {
    if (group != null) 'group_address': formatGroupAddress(group!, style),
    if (device != null) 'device_address': formatIndividual(device!),
    'lines': lines,
  };
}

/// What Busclear hands over to the XKNX Editor: corrections the editor can apply on its own
/// ([operations], in the format of its `project_batch`) and everything else as notes for the
/// comments of group addresses and devices ([notes]).
///
/// Corrections only where they are unambiguous: datapoint types and names set in the app, learned
/// addresses, the C flag of an associated object, and the L flag of the object that sends a status
/// nobody can read. The rest needs a decision in the project and becomes a note.
class XknxEditorHandover {
  XknxEditorHandover._(this.operations, this.notes, this.style, this.projectName);

  /// [dptSuggestions]: datapoint types from the recorded history (server, `dpt_suggestions` of
  /// `/api/project-evidence`); only "high" ones for addresses still without a type become
  /// corrections, the others notes.
  factory XknxEditorHandover.of(
    EtsTasks tasks,
    GroupCatalog project, {
    List<Map<String, Object?>> dptSuggestions = const [],
  }) {
    final style = project.style;
    String ga(int a) => formatGroupAddress(a, style);
    final operations = <Map<String, Object?>>[];
    final seen = <String>{};
    void op(String name, Map<String, Object?> params) {
      final entry = {'op': name, 'params': params};
      if (seen.add(jsonEncode(entry))) operations.add(entry);
    }

    final notes = <String, XknxEditorNote>{};
    void note({int? group, int? device, required String text}) {
      final key = group != null ? 'g$group' : 'd$device';
      final n = notes.putIfAbsent(key, () => XknxEditorNote(group: group, device: device));
      final line = '$xknxNoteMarker $text';
      if (!n.lines.contains(line)) n.lines.add(line);
    }

    String text(EtsTask t) => [etsTaskTitle(t), etsTaskTodo(t)].where((x) => x.isNotEmpty).join(': ');

    for (final t in tasks.groups) {
      final a = t.group!;
      switch (t.kind) {
        case EtsTaskKind.dpt when t.dpt?.sub != null:
          op('set_group_address_dpt', {'group_address': ga(a), 'dpt': dptToken(t.dpt!)});
        case EtsTaskKind.rename || EtsTaskKind.learnedName when (t.name ?? '').isNotEmpty:
          op('rename_group_address', {'group_address': ga(a), 'name': t.name});
        case EtsTaskKind.learnedNew:
          op('create_group_address', {
            'address': ga(a),
            'name': t.name ?? '',
            if (t.dpt case final d? when d.sub != null) 'dpt': dptToken(d),
          });
        // Notices (often intended) stay in Busclear; comments only for deviations.
        default:
          if (!t.hint) note(group: a, text: text(t));
      }
    }
    for (final MapEntry(key: device, value: list) in tasks.devices.entries) {
      for (final t in list) {
        if (t.hint) continue;
        final ref = t.ref;
        final address = formatIndividual(device);
        if (t.kind == EtsTaskKind.objectWithoutCommunication && ref != null) {
          op('set_com_object_flag', {
            'device_address': address,
            'com_object_ref_id': ref,
            'flag': 'communication',
            'value': true,
          });
        } else if (t.kind == EtsTaskKind.readWithoutReadFlag && ref != null && t.sends) {
          // The object that sends the status answers the read; L on every listener would give
          // several answers.
          op('set_com_object_flag', {
            'device_address': address,
            'com_object_ref_id': ref,
            'flag': 'read',
            'value': true,
          });
        } else if (t.group != null && t.kind != EtsTaskKind.deviceWithoutLinks) {
          note(device: device, text: '${formatGroupAddress(t.group!, style)} ${text(t)}');
        } else {
          note(device: device, text: text(t));
        }
      }
    }
    for (final d in dptSuggestions) {
      final printed = d['group_address'];
      final dpt = d['dpt'];
      if (printed is! String || dpt is! String) continue;
      final a = parseGroupAddress(printed, style);
      if (a == null || project[a]?.dpt != null) continue;
      // Set in the app wins: that correction is already among the operations.
      if (operations.any(
        (o) => o['op'] == 'set_group_address_dpt' && (o['params']! as Map)['group_address'] == printed,
      )) {
        continue;
      }
      if (d['certainty'] == 'high') {
        op('set_group_address_dpt', {'group_address': printed, 'dpt': dpt});
      } else {
        note(group: a, text: s.xknxNoteDptLikely(dpt));
      }
    }
    final lint = ProjectLint.of(project);
    for (final d in lint.devicesNeverProgrammed) {
      note(device: d.address, text: s.xknxNoteNeverProgrammed);
    }
    for (final d in lint.devicesPendingDownload) {
      final parts = d.pendingDownload.map((p) => downloadPartName(p)).join(', ');
      note(device: d.address, text: '${s.checkDevicesPendingDownload}: $parts');
    }
    return XknxEditorHandover._(operations, notes.values.toList(), style, project.projectName);
  }

  final List<Map<String, Object?>> operations;
  final List<XknxEditorNote> notes;
  final GroupStyle style;
  final String? projectName;

  bool get isEmpty => operations.isEmpty && notes.isEmpty;

  /// File for an AI assistant connected to the editor, or for later: operations for
  /// `project_batch`, notes for `project_set_comment`.
  Map<String, Object?> toJson() => {
    'format': 'busclear-xknx-editor',
    'version': 1,
    if (projectName != null) 'project': projectName,
    'instructions':
        'Apply "operations" with the XKNX Editor MCP tool project_batch (dry_run first). '
        'Append each note\'s "lines" to the comment of its group address or device '
        '(project_get_comment / project_set_comment), replacing earlier lines that start with '
        '"$xknxNoteMarker". Nothing is programmed: download the changed devices in the editor.',
    'operations': operations,
    'notes': [for (final n in notes) n.toJson(style)],
  };
}

/// DPST token as the editor stores it ("DPST-1-1"); main type only as "DPT-9".
String dptToken(Dpt d) => d.sub == null ? 'DPT-${d.main}' : 'DPST-${d.main}-${d.sub}';

/// Name of a download part for notes (locale of the app).
String downloadPartName(DownloadPart p) => switch (p) {
  DownloadPart.address => s.downloadPartAddress,
  DownloadPart.application => s.downloadPartApplication,
  DownloadPart.parameters => s.downloadPartParameters,
  DownloadPart.groups => s.downloadPartGroups,
  DownloadPart.medium => s.downloadPartMedium,
};

/// Comment with Busclear's lines replaced by [lines]: the user's own text stays, earlier Busclear
/// lines (and the index line) go.
String mergeXknxComment(String? existing, List<String> lines) {
  final own = (existing ?? '')
      .split('\n')
      .where((l) => l.trim().isNotEmpty && !l.startsWith(xknxNoteMarker) && !l.startsWith(xknxIndexMarker));
  return [...own, ...lines].join('\n');
}

/// Elements annotated last time, from the project comment's index line: `g:` group address ids,
/// `d:` device node ids.
({Set<int> groups, Set<int> devices}) parseXknxIndex(String? projectComment) {
  final line = (projectComment ?? '').split('\n').where((l) => l.startsWith(xknxIndexMarker)).firstOrNull;
  Set<int> ids(String prefix) => {
    for (final m in RegExp('$prefix:([0-9,]*)').allMatches(line ?? ''))
      for (final v in m.group(1)!.split(',')) ?int.tryParse(v),
  };
  return (groups: ids('g'), devices: ids('d'));
}

/// Index line for the project comment.
String xknxIndexLine(Iterable<int> groups, Iterable<int> devices) =>
    '$xknxIndexMarker g:${(groups.toList()..sort()).join(',')} d:${(devices.toList()..sort()).join(',')}';
