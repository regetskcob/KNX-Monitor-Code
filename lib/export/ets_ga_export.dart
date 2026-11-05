import 'dart:convert';
import 'dart:typed_data';

import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../model/ets_tasks.dart';

/// Group address import for the ETS: the one way back into the ETS for names, datapoint types and
/// new addresses, shared by the "Tasks for the ETS" and the GA assistant. Both produce
/// [EtsImportEntry] lists; the two writers here differ only in format.
///
/// On import, the ETS overwrites existing addresses with the data from the file ("import data takes
/// precedence"). The file therefore contains only the addresses from the entries, each complete
/// with name, description, main and middle group, so that nothing changes beyond what is intended.
/// These formats know no flags or associations (see docs/ets-round-trip.md). Not yet verified
/// against a real ETS.
///
/// XML in the "GroupAddress-Export" format, namespace `ga-export/01`, as ETS 5/6 writes it when
/// exporting group addresses.
///
/// Only for three-level addresses; two-level and free projects return `null`, as does an empty
/// list.
String? etsImportXml(List<EtsImportEntry> entries, GroupStyle style) {
  if (style != GroupStyle.threeLevel || entries.isEmpty) return null;
  final sorted = [...entries]..sort((a, b) => a.address.compareTo(b.address));
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8" standalone="yes"?>')
    ..writeln('<GroupAddress-Export xmlns="http://knx.org/xml/ga-export/01">');
  int? openMain;
  int? openMiddle;
  for (final e in sorted) {
    final main = e.address >> 11;
    final middle = (e.address >> 8) & 0x07;
    final (mainName, middleName) = _rangeNames(e);
    if (main != openMain) {
      if (openMiddle != null) out.writeln('    </GroupRange>');
      if (openMain != null) out.writeln('  </GroupRange>');
      final start = main << 11;
      out.writeln('  <GroupRange Name="${_attr(mainName)}" RangeStart="$start" RangeEnd="${start + 2047}">');
      openMain = main;
      openMiddle = null;
    }
    if (middle != openMiddle) {
      if (openMiddle != null) out.writeln('    </GroupRange>');
      final start = (main << 11) | (middle << 8);
      out.writeln('    <GroupRange Name="${_attr(middleName)}" RangeStart="$start" RangeEnd="${start + 255}">');
      openMiddle = middle;
    }
    final description = e.description;
    final descriptionAttr = description == null || description.isEmpty ? '' : ' Description="${_attr(description)}"';
    final dptAttr = e.dpt == null ? '' : ' DPTs="${etsDptId(e.dpt!)}"';
    out.writeln(
      '      <GroupAddress Name="${_attr(e.name)}" '
      'Address="$main/$middle/${e.address & 0xFF}"$descriptionAttr$dptAttr />',
    );
  }
  if (openMiddle != null) out.writeln('    </GroupRange>');
  if (openMain != null) out.writeln('  </GroupRange>');
  out.writeln('</GroupAddress-Export>');
  return out.toString();
}

/// The same entries as CSV in the "3/1" format with range rows, as the ETS itself exports and as
/// [GroupCatalog.parseCsv] reads it.
String? etsImportCsv(List<EtsImportEntry> entries, GroupStyle style) {
  if (style != GroupStyle.threeLevel || entries.isEmpty) return null;
  final sorted = [...entries]..sort((a, b) => a.address.compareTo(b.address));
  final out = StringBuffer();
  void row(List<String> cells) =>
      out.write('${cells.map((c) => '"${_inert(c).replaceAll('"', '""')}"').join(',')}\r\n');
  row(const ['Main', 'Middle', 'Sub', 'Address', 'Central', 'Unfiltered', 'Description', 'DatapointType', 'Security']);
  int? openMain;
  int? openMiddle;
  for (final e in sorted) {
    final main = e.address >> 11;
    final middle = (e.address >> 8) & 0x07;
    final (mainName, middleName) = _rangeNames(e);
    if (main != openMain) {
      row([mainName, '', '', '$main/-/-', '', '', '', '', '']);
      openMain = main;
      openMiddle = null;
    }
    if (middle != openMiddle) {
      row(['', middleName, '', '$main/$middle/-', '', '', '', '', '']);
      openMiddle = middle;
    }
    row([
      '',
      '',
      e.name,
      '$main/$middle/${e.address & 0xFF}',
      '',
      '',
      e.description ?? '',
      e.dpt == null ? '' : etsDptId(e.dpt!),
      'Auto',
    ]);
  }
  return out.toString();
}

/// Keeps a spreadsheet from running a cell as a formula (the file also opens in Excel or Numbers,
/// and names come from foreign ETS projects). "=" and "@" at the start get a leading apostrophe,
/// as do tab and carriage return: no group address name begins with those. "+" and "-" only when
/// the rest looks like a formula ("+SUM(A1)", "-1+1"): names like "-1 Keller" or "+ Zentral" are
/// common and the ETS would take the apostrophe into the name.
String _inert(String cell) {
  if (cell.isEmpty) return cell;
  final first = cell[0];
  if (const {'=', '@', '\t', '\r'}.contains(first)) return "'$cell";
  if ((first == '+' || first == '-') && _formulaTail.hasMatch(cell.substring(1))) return "'$cell";
  return cell;
}

/// After a leading + or -: operators, parentheses or references make it a formula.
final _formulaTail = RegExp(r'[=+\-*/^&(),;:!]');

/// CSV as a file: UTF-8 with BOM so umlauts are correct in the ETS and in Excel.
Uint8List etsCsvBytes(String csv) => Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)]);

/// Main and middle group from the path, falling back to the numbers.
(String, String) _rangeNames(EtsImportEntry e) {
  final names = (e.path ?? '').split(' › ');
  final main = e.address >> 11;
  final middle = (e.address >> 8) & 0x07;
  return (names.first.isEmpty ? '$main' : names.first, names.length > 1 ? names[1] : '$main/$middle');
}

/// Only the datapoint types changed in the app (without learned data).
String? etsGroupAddressXml(GroupCatalog catalog, Map<int, Dpt> overrides) =>
    etsImportXml(EtsTasks.of(catalog, overrides).imports, catalog.style);

/// Identifier as in the ETS: "DPST-9-1" with subtype, otherwise "DPT-9".
String etsDptId(Dpt dpt) => dpt.sub == null ? 'DPT-${dpt.main}' : 'DPST-${dpt.main}-${dpt.sub}';

/// Attribute value; line breaks and tabs as character references, because an
/// XML parser turns literal ones into spaces (multi-line descriptions).
String _attr(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r', '&#xD;')
    .replaceAll('\n', '&#xA;')
    .replaceAll('\t', '&#x9;');
