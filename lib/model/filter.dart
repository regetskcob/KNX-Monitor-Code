import '../catalog_store.dart';
import 'tap_points.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'alarms.dart';
import 'analysis.dart';
import 'telegram_log.dart';

/// Quick filters (chips) and `ist:` keywords.
enum QuickFilter { alarm, repeated, unanswered, unknown, outgoing, incoming }

/// Filter for telegrams from a search query.
///
/// Syntax (case-insensitive):
/// - space = AND, comma = OR between groups, `-term` = NOT
/// - `1/2/3` exact, `1/2` or `1` range, `1/*/3` and `1/2/1*` with wildcard
/// - `1.1.5` sender, `1.1.*` line
/// - `typ:w|r|a` (`type:`), `dpt:9` or `dpt:9.001`, `von:1.1.5` (`from:`)
/// - `ist:alarm|wiederholt|antwort|projekt|eigen|fremd`
///   (`is:alarm|repeated|unanswered|unknown|own|received`)
/// - `re:licht.*(kueche|bad)` (`regex:`) regular expression over address, name,
///   range, device and value; without spaces and commas
/// - `zeit:14:05` time of day by prefix (hour, minute or second),
///   `zeit:14:05-14:10` from–to excluding the end (`time:`)
/// - otherwise: text in name, range, device or value (umlauts do not matter:
///   "kuche" finds "Küche", and so does "Kueche")
class TelegramFilter {
  TelegramFilter._(this._groups);

  factory TelegramFilter.parse(String query) {
    final groups = <List<_Term>>[];
    for (final part in query.toLowerCase().split(',')) {
      final terms = [
        for (final token in part.trim().split(RegExp(r'\s+')))
          if (token.isNotEmpty && token != '-') _Term.parse(token),
      ];
      if (terms.isNotEmpty) groups.add(terms);
    }
    return TelegramFilter._(groups);
  }

  static final empty = TelegramFilter._(const []);

  final List<List<_Term>> _groups;

  bool get isEmpty => _groups.isEmpty;

  /// Number of OR groups (for color marks per group).
  int get groupCount => _groups.length;

  /// Matches if at least one OR group matches completely.
  bool matches(Telegram t, TelegramLog log) =>
      _groups.isEmpty || _groups.any((group) => group.every((term) => term.matches(t, log)));

  /// Index of the first matching OR group, `null` if none matches.
  int? groupOf(Telegram t, TelegramLog log) {
    for (var i = 0; i < _groups.length; i++) {
      if (_groups[i].every((term) => term.matches(t, log))) return i;
    }
    return null;
  }
}

bool get _german => s.localeName.startsWith('de');

/// Search by sender in the UI language (`von:1.1.5` or `from:1.1.5`).
String senderQuery(String address) => '${_german ? 'von' : 'from'}:$address';

/// Search for all senders of [line] (`von:1.1.*`); the monitor shows it in the live list.
String lineQuery(int line) => senderQuery('${(line >> 4) & 0x0F}.${line & 0x0F}.*');

/// Whether [query] is exactly a [lineQuery] (in either language).
bool isLineQuery(String query) => RegExp(r'^(von|from):\d+\.\d+\.\*$').hasMatch(query.trim().toLowerCase());

/// Search by time of day in the UI language (`zeit:14:05` or `time:14:05`).
String timeQuery(String time) => '${_german ? 'zeit' : 'time'}:$time';

/// Normalizes text for the search: lowercase, umlauts and their spelled-out
/// forms treated alike ("Küche", "Kueche", "Kuche" → "kuche").
String normalizeSearch(String text) => text
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss')
    .replaceAll('ae', 'a')
    .replaceAll('oe', 'o')
    .replaceAll('ue', 'u');

/// Context around hits: all telegrams at most [window] before or after a hit.
/// [log] in ascending time order. Returns the visible telegrams and the set of
/// pure context rows.
({List<Telegram> visible, Set<Telegram> context}) withContext(
  List<Telegram> log,
  bool Function(Telegram) matches,
  Duration window,
) {
  final hits = [
    for (var i = 0; i < log.length; i++)
      if (matches(log[i])) i,
  ];
  if (hits.isEmpty || window == Duration.zero) {
    return (visible: [for (final i in hits) log[i]], context: const {});
  }
  final include = List<bool>.filled(log.length, false);
  var from = 0;
  for (final h in hits) {
    final start = log[h].time.subtract(window);
    final end = log[h].time.add(window);
    // Backwards to the start of the window, from the point reached so far.
    var i = h;
    while (i > from && !log[i - 1].time.isBefore(start)) {
      i--;
    }
    for (var j = i; j < log.length && !log[j].time.isAfter(end); j++) {
      include[j] = true;
      from = j;
    }
  }
  final hitSet = Set<Telegram>.identity()..addAll(hits.map((i) => log[i]));
  final visible = <Telegram>[];
  final context = Set<Telegram>.identity();
  for (var i = 0; i < log.length; i++) {
    if (!include[i]) continue;
    visible.add(log[i]);
    if (!hitSet.contains(log[i])) context.add(log[i]);
  }
  return (visible: visible, context: context);
}

/// Quick filter as a condition.
bool matchesQuick(QuickFilter f, Telegram t, TelegramLog log) => switch (f) {
  QuickFilter.alarm => activeAlarm(t) != null,
  QuickFilter.repeated => t.repeated,
  QuickFilter.unanswered => log.isUnanswered(t),
  QuickFilter.unknown => issuesOf(
    t,
    log,
  ).any((i) => i == TelegramIssue.unknownAddress || i == TelegramIssue.unknownDevice),
  QuickFilter.outgoing => t.outgoing,
  QuickFilter.incoming => !t.outgoing,
};

class _Term {
  const _Term(this.negate, this.test);

  factory _Term.parse(String token) {
    final negate = token.startsWith('-');
    final body = negate ? token.substring(1) : token;
    return _Term(negate, _test(body));
  }

  final bool negate;
  final bool Function(Telegram, TelegramLog) test;

  bool matches(Telegram t, TelegramLog log) => test(t, log) != negate;

  static final _group = RegExp(r'^[0-9*]+(/[0-9*]+){0,2}$');
  static final _individual = RegExp(r'^[0-9*]+\.[0-9*]+(\.[0-9*]+)?$');

  /// Time of day as "HH:MM:SS": a prefix matches, a range compares as text
  /// (two digits, so sorted correctly; "14:60" works as an end too).
  static bool Function(Telegram, TelegramLog) _time(String value) {
    String clock(DateTime t) => [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');
    final dash = value.indexOf('-');
    if (dash < 0) return (t, _) => clock(t.time).startsWith(value);
    final from = value.substring(0, dash);
    final to = value.substring(dash + 1);
    return (t, _) {
      final c = clock(t.time);
      return c.compareTo(from) >= 0 && (to.isEmpty || c.compareTo(to) < 0);
    };
  }

  static bool Function(Telegram, TelegramLog) _test(String body) {
    final colon = body.indexOf(':');
    if (colon > 0) {
      final key = body.substring(0, colon);
      final value = body.substring(colon + 1);
      switch (key) {
        case 'typ' || 'type':
          final types = {
            for (final c in value.split('|'))
              ?switch (c) {
                'w' || 'write' || 'schreiben' => TelegramType.write,
                'r' || 'read' || 'lesen' => TelegramType.read,
                'a' || 'antwort' || 'response' => TelegramType.response,
                _ => null,
              },
          };
          return (t, _) => types.contains(t.type);
        case 'dpt':
          return (t, _) {
            final dpt = CatalogStore.instance.dptFor(t);
            return dpt != null && (dpt.toString() == value || dpt.toString().startsWith('$value.'));
          };
        case 'von' || 'from':
          final pattern = _pattern(value, '.', 3);
          return (t, _) => pattern(t.sourceText);
        case 'ist' || 'is':
          final quick = [
            for (final v in value.split('|'))
              ?switch (v) {
                'alarm' || 'störung' || 'fault' => QuickFilter.alarm,
                'wiederholt' || 'repeated' => QuickFilter.repeated,
                'antwort' || 'unanswered' || 'ohneantwort' => QuickFilter.unanswered,
                'projekt' || 'unknown' || 'unbekannt' => QuickFilter.unknown,
                'eigen' || 'gesendet' || 'own' || 'sent' => QuickFilter.outgoing,
                'fremd' || 'empfangen' || 'received' || 'incoming' => QuickFilter.incoming,
                _ => null,
              },
          ];
          // Seen at one tap point only, while several record (issue #8).
          final single = value.split('|').any((v) => const {'einzeln', 'single', 'einmal'}.contains(v));
          return (t, log) => quick.any((q) => matchesQuick(q, t, log)) || (single && seenAtOneTapOnly(t));
        case 'zeit' || 'time':
          return _time(value);
        // Regular expression over address, name, range, device and value. The query is split
        // at spaces and commas first, so the pattern cannot contain either (use `\\s` and `.`).
        case 're' || 'regex':
          final RegExp regex;
          try {
            regex = RegExp(value, caseSensitive: false);
          } on FormatException {
            // Half-typed pattern: nothing matches until it is valid.
            return (_, _) => false;
          }
          return (t, _) {
            final store = CatalogStore.instance;
            final info = store.infoOf(t);
            return regex.hasMatch(
              [t.destinationText, ?info?.name, ?info?.path, ?store.deviceOf(t)?.name, store.value(t)].join(' '),
            );
          };
        // Tap point by its chip label (the line, e.g. "1.2"), several with |: seen there (issue #8).
        case 'messpunkt' || 'tap':
          final wanted = value.split('|').where((v) => v.isNotEmpty).toSet();
          return (t, _) {
            final labels = TapScope.labels;
            return t.taps.any((tap) => tap < labels.length && wanted.contains(labels[tap]));
          };
      }
    }
    if (_group.hasMatch(body) && body.contains('/')) {
      final pattern = _pattern(body, '/', groupStyle == GroupStyle.twoLevel ? 2 : 3);
      return (t, _) => pattern(t.destinationText);
    }
    if (groupStyle == GroupStyle.free && _group.hasMatch(body)) {
      // Free addresses: number = exactly this address (with * as wildcard) – or text.
      final pattern = _pattern(body, '/', 1);
      return (t, log) => pattern(t.destinationText) || _text(body)(t, log);
    }
    if (_group.hasMatch(body) && !body.contains('*')) {
      // Single number: main group – or part of a name/value.
      return (t, log) => t.destinationText.startsWith('$body/') || _text(body)(t, log);
    }
    if (_individual.hasMatch(body)) {
      final pattern = _pattern(body, '.', 3);
      return (t, _) => pattern(t.sourceText);
    }
    return _text(body);
  }

  /// Address pattern: a complete address matches exactly, shorter ones as a range,
  /// `*` as a wildcard for any digits.
  static bool Function(String) _pattern(String pattern, String separator, int levels) {
    final segments = pattern.split(separator);
    final escaped = segments.map((s) => RegExp.escape(s).replaceAll(r'\*', '[0-9]*')).join(RegExp.escape(separator));
    final full = segments.length == levels;
    final regex = RegExp('^$escaped${full ? r'$' : RegExp.escape(separator)}');
    return (address) => regex.hasMatch(address);
  }

  static bool Function(Telegram, TelegramLog) _text(String body) {
    final needle = normalizeSearch(body);
    return (t, _) {
      final store = CatalogStore.instance;
      final info = store.infoOf(t);
      bool has(String? text) => text != null && normalizeSearch(text).contains(needle);
      return has(info?.name) || has(info?.path) || has(store.deviceOf(t)?.name) || has(store.value(t));
    };
  }
}
