import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../ui/telegram_row.dart' show formatDate, formatTime;
import 'diagnostics_bundle.dart' show Scrubber;

/// Markup for forums: BBCode (KNX-User-Forum) or Markdown.
enum ForumFormat { bbcode, markdown }

/// Text snippet for a forum question: telegrams as a table, involved group addresses with name and
/// DPT, devices, connection type and app version.
///
/// Never included: passwords, keys, IP addresses, host names, serial numbers (free text goes
/// through [Scrubber]). With [pseudonymize], neutral names replace project and device names;
/// addresses and DPTs remain, because nobody in the forum can help without them.
abstract final class ForumPackage {
  /// Nobody in a forum reads more rows; the first [maxRows] are included.
  static const maxRows = 60;

  static String build({
    required List<Telegram> telegrams,
    required GroupCatalog catalog,
    required ForumFormat format,
    bool pseudonymize = false,
    String? connection,
    String? appVersion,
    String Function(Telegram)? value,
    Dpt? Function(int)? dptOf,
  }) {
    final scrub = Scrubber(known: [?catalog.projectName]);
    final list = [...telegrams]..sort((a, b) => a.time.compareTo(b.time));
    final shown = list.take(maxRows).toList();
    Dpt? dpt(int ga) => dptOf?.call(ga) ?? catalog[ga]?.dpt;
    String valueOf(Telegram t) => scrub((value ?? (t) => t.valueText)(t));

    // Neutral names in order of first appearance.
    final groupNames = <int, String>{};
    final deviceNames = <int, String>{};
    for (final t in list) {
      groupNames.putIfAbsent(t.destination, () {
        final name = catalog[t.destination]?.name;
        if (name == null) return '';
        return pseudonymize ? s.forumPseudoGroup(groupNames.length + 1) : scrub(name);
      });
      if (!t.outgoing) {
        deviceNames.putIfAbsent(t.source, () {
          final d = catalog.devices[t.source];
          if (d == null) return '';
          // Without names the product stays – it reveals nothing about the installation.
          return pseudonymize ? scrub(d.product ?? s.forumPseudoDevice(deviceNames.length + 1)) : scrub(d.name);
        });
      }
    }

    final first = list.isEmpty ? null : list.first.time;
    String time(Telegram t) => formatTime(t.time);
    String type(Telegram t) => switch (t.type) {
      TelegramType.read => 'Read',
      TelegramType.response => 'Response',
      TelegramType.write => 'Write',
    };
    String sender(Telegram t) => t.outgoing ? '${t.sourceText} (${s.forumOwn})' : t.sourceText;

    final header = [s.columnTime, s.columnSender, s.forumColumnGroup, s.columnName, s.columnType, s.columnValue];
    final rows = [
      for (final t in shown)
        [time(t), sender(t), t.destinationText, groupNames[t.destination] ?? '', type(t), valueOf(t)],
    ];
    final groups = [
      for (final MapEntry(key: ga, value: name) in groupNames.entries)
        [formatGroup(ga), name, if (dpt(ga) case final d?) 'DPT $d' else s.forumNoDpt],
    ];
    final devices = [
      for (final MapEntry(key: pa, value: name) in deviceNames.entries) [formatIndividual(pa), name],
    ];
    final meta = [
      s.forumMetaApp(appVersion ?? '?'),
      if (connection != null) s.forumMetaConnection(scrub(connection)),
      if (first != null)
        s.forumMetaRange(list.length, formatDate(first), formatTime(first), formatTime(list.last.time)),
      if (list.length > shown.length) s.forumMetaShortened(shown.length),
    ];

    final b = StringBuffer();
    switch (format) {
      case ForumFormat.markdown:
        b.writeln('**${s.forumHeading}**');
        b.writeln();
        for (final m in meta) {
          b.writeln('- $m');
        }
        b.writeln();
        b.writeln('**${s.forumTelegrams}**');
        b.writeln();
        _markdownTable(b, header, rows);
        if (groups.isNotEmpty) {
          b.writeln();
          b.writeln('**${s.forumGroups}**');
          b.writeln();
          _markdownTable(b, [s.forumColumnGroup, s.columnName, 'DPT'], groups);
        }
        if (devices.isNotEmpty) {
          b.writeln();
          b.writeln('**${s.forumDevices}**');
          b.writeln();
          _markdownTable(b, [s.columnSender, s.columnName], devices);
        }
      case ForumFormat.bbcode:
        // Tables as [CODE] with fixed columns: every forum shows them the same way.
        b.writeln('[B]${s.forumHeading}[/B]');
        b.writeln('[LIST]');
        for (final m in meta) {
          b.writeln('[*]$m');
        }
        b.writeln('[/LIST]');
        b.writeln('[B]${s.forumTelegrams}[/B]');
        b.writeln('[CODE]');
        _fixedTable(b, header, rows);
        b.writeln('[/CODE]');
        if (groups.isNotEmpty) {
          b.writeln('[B]${s.forumGroups}[/B]');
          b.writeln('[CODE]');
          _fixedTable(b, [s.forumColumnGroup, s.columnName, 'DPT'], groups);
          b.writeln('[/CODE]');
        }
        if (devices.isNotEmpty) {
          b.writeln('[B]${s.forumDevices}[/B]');
          b.writeln('[CODE]');
          _fixedTable(b, [s.columnSender, s.columnName], devices);
          b.writeln('[/CODE]');
        }
    }
    return b.toString().trimRight();
  }

  static String _md(String v) => v.replaceAll('|', r'\|').replaceAll('\n', ' ');

  static void _markdownTable(StringBuffer b, List<String> header, List<List<String>> rows) {
    b.writeln('| ${header.map(_md).join(' | ')} |');
    b.writeln('|${List.filled(header.length, ' --- ').join('|')}|');
    for (final r in rows) {
      b.writeln('| ${r.map(_md).join(' | ')} |');
    }
  }

  /// Columns aligned with spaces; BBCode brackets in the content defused.
  static void _fixedTable(StringBuffer b, List<String> header, List<List<String>> rows) {
    String clean(String v) => v.replaceAll('[', '(').replaceAll(']', ')').replaceAll('\n', ' ');
    final all = [header, ...rows].map((r) => r.map(clean).toList()).toList();
    final widths = [
      for (var c = 0; c < header.length; c++)
        all.map((r) => c < r.length ? r[c].length : 0).reduce((a, b) => a > b ? a : b),
    ];
    for (final r in all) {
      b.writeln([for (var c = 0; c < r.length; c++) r[c].padRight(widths[c])].join('  ').trimRight());
    }
  }
}
