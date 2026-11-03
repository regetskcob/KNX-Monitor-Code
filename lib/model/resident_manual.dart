import 'package:flutter/foundation.dart';

import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'customer.dart';

/// What a function does for residents (the words only appear in the PDF, in its language).
enum ManualKind { onOff, dim, percent, blinds, openClose, scene, temperature, setpoint, measure, other }

/// A function in the manual.
@immutable
class ManualEntry {
  const ManualEntry(this.name, this.kind);

  final String name;
  final ManualKind kind;
}

/// A room (or area) with its functions.
@immutable
class ManualRoom {
  const ManualRoom(this.title, this.entries);

  /// Empty: without a known room ("Weitere Funktionen", further functions).
  final String title;
  final List<ManualEntry> entries;
}

/// Resident manual: by room, in everyday words, without addresses.
@immutable
class ResidentManual {
  const ResidentManual({
    required this.language,
    required this.rooms,
    this.project,
    this.customer = '',
    this.note = '',
    this.contactName = '',
    this.contactPhone = '',
    this.contactEmail = '',
  });

  /// Language of the manual (`de`, `en`), independent of the app.
  final String language;
  final List<ManualRoom> rooms;
  final String? project;
  final String customer;

  /// The company's own notes ("Hauptschalter im Keller", main switch in the basement).
  final String note;
  final String contactName;
  final String contactPhone;
  final String contactEmail;
}

/// Technical things residents do not operate: status feedback, status, locks.
final _technical = RegExp(
  r'(^|[\s_\-/›(])(rm|rückmeldung|rueckmeldung|status|stat|feedback|sperr\w*|lock|diagnose|diagnostics|alarm\w*|störung\w*|fault|heartbeat|szenenspeicher)($|[\s_\-/›)])',
  caseSensitive: false,
);

/// How it is used, from the datapoint type. Without a type the name does not
/// count: better "function" than wrong operation.
ManualKind manualKindOf(Dpt? dpt) => switch ((dpt?.main, dpt?.sub)) {
  (1, 8) => ManualKind.blinds,
  (1, 9) || (1, 19) => ManualKind.openClose,
  (1, _) => ManualKind.onOff,
  (3, _) => ManualKind.dim,
  (5, 1) => ManualKind.percent,
  (9, 1) => ManualKind.temperature,
  (9, _) || (7, _) || (12, _) || (13, _) || (14, _) => ManualKind.measure,
  (17, _) || (18, _) => ManualKind.scene,
  _ => ManualKind.other,
};

/// Assembles the rooms from the project and learned names. The room comes from
/// the location of the associated device, otherwise from the group address path.
/// Pure, so it is testable without app state.
List<ManualRoom> buildManualRooms(GroupCatalog catalog) {
  final rooms = <String, Map<String, ManualEntry>>{};
  for (final g in catalog.groups.values) {
    final name = g.name.trim();
    if (name.isEmpty || name == formatGroup(g.address)) continue;
    if (_technical.hasMatch(name) || _technical.hasMatch(g.path ?? '')) continue;
    var kind = manualKindOf(g.dpt);
    if (kind == ManualKind.temperature && RegExp(r'soll|setpoint', caseSensitive: false).hasMatch(name)) {
      kind = ManualKind.setpoint;
    }
    final location = [
      for (final l in g.links)
        if (catalog.devices[l.device]?.location case final where? when where.trim().isNotEmpty) where.trim(),
    ].firstOrNull;
    final room = location ?? g.path?.trim() ?? '';
    // The same function on several addresses (switching, dimming) only once; the
    // stronger one (dimming before switching) does not win, the first entry stays.
    (rooms[room] ??= {}).putIfAbsent(name.toLowerCase(), () => ManualEntry(name, kind));
  }
  final titles = rooms.keys.toList()
    ..sort((a, b) {
      // Without a room last.
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
  return [
    for (final t in titles)
      ManualRoom(t, rooms[t]!.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()))),
  ];
}

/// Finished manual from catalog and details; [customer] comes from the record.
ResidentManual buildResidentManual({
  required GroupCatalog catalog,
  required String language,
  CustomerRecord customer = CustomerRecord.empty,
  String note = '',
  String contactName = '',
  String contactPhone = '',
  String contactEmail = '',
}) => ResidentManual(
  language: language,
  rooms: buildManualRooms(catalog),
  project: catalog.projectName,
  customer: customer.customer,
  note: note.trim(),
  contactName: contactName,
  contactPhone: contactPhone,
  contactEmail: contactEmail,
);
