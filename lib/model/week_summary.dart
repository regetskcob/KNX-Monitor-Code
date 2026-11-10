import '../l10n/locale_controller.dart';

/// One finding of the weekly overview (`/api/summary`), with the words the app shows.
class WeekFinding {
  const WeekFinding(this.kind, this.warn, this.text);

  /// `clocks`, `multi_responders`, `read_storms`, `chatty`, `silent`, `unknown_senders`,
  /// `repeats`, `load`, `disconnected`, `tap_gaps` (unknown kinds of newer servers are dropped).
  final String kind;
  final bool warn;
  final String text;
}

/// The weekly overview of the add-on or box: figures and findings of the last seven days.
class WeekSummary {
  const WeekSummary({
    required this.days,
    required this.perDay,
    required this.loadMean,
    required this.loadMax,
    required this.repeats,
    required this.availability,
    required this.findings,
  });

  factory WeekSummary.fromJson(Map<String, Object?> j) {
    num n(String k) => (j[k] as num?) ?? 0;
    return WeekSummary(
      days: (j['days'] as int?) ?? 7,
      perDay: n('per_day_mean').round(),
      loadMean: n('load_mean_pct').toDouble(),
      loadMax: n('load_max_pct').toDouble(),
      repeats: n('repeats').round(),
      availability: (j['availability_pct'] as num?)?.toDouble(),
      findings: [
        for (final f in (j['findings'] as List? ?? const []).whereType<Map<Object?, Object?>>())
          ?_finding(f.cast<String, Object?>()),
      ],
    );
  }

  final int days;
  final int perDay;
  final double loadMean;
  final double loadMax;
  final int repeats;

  /// Share of the time the recording ran with a bus connection, `null` without heartbeats.
  final double? availability;
  final List<WeekFinding> findings;

  bool get warn => findings.any((f) => f.warn);

  /// One sentence on the state, for the card's head.
  String get headline => warn ? s.weekSumWarn : (findings.isEmpty ? s.weekSumAllGood : s.weekSumHints(findings.length));

  static WeekFinding? _finding(Map<String, Object?> f) {
    final kind = f['kind'];
    final warn = f['severity'] == 'warn';
    String list(Object? v, [int max = 3]) {
      final items = [for (final e in (v as List? ?? const [])) '$e'];
      return items.length > max ? '${items.take(max).join(', ')} …' : items.join(', ');
    }

    String groups(Object? v) => list([
      for (final g in (v as List? ?? const []).whereType<Map<Object?, Object?>>())
        [g['group'], g['name']].where((e) => e != null && e != '').join(' '),
    ], 2);
    final text = switch (kind) {
      'clocks' => s.weekSumClocks(list(f['senders']), list(f['groups']), _pct(f['share'])),
      'multi_responders' => s.weekSumMultiResponders(groups(f['groups']), (f['count'] as int?) ?? 0),
      'read_storms' => s.weekSumReadStorms(
        [f['sender'], f['name']].where((e) => e != null && e != '').join(' '),
        (f['max_per_minute'] as int?) ?? 0,
      ),
      'chatty' => s.weekSumChatty(groups(f['groups'])),
      'silent' => s.weekSumSilent(
        list([
          for (final d in (f['devices'] as List? ?? const []).whereType<Map<Object?, Object?>>())
            [d['address'], d['name']].where((e) => e != null && e != '').join(' '),
        ], 2),
        (f['count'] as int?) ?? 0,
      ),
      'unknown_senders' => s.weekSumUnknown(list(f['senders'])),
      'repeats' => s.weekSumRepeats((f['count'] as int?) ?? 0, _pct(f['share'])),
      'load' => s.weekSumLoadHigh(_pct(f['max'])),
      'disconnected' => s.weekSumDisconnected((f['count'] as int?) ?? 0, (f['minutes'] as int?) ?? 0),
      'tap_gaps' => s.weekSumTapGaps(list(f['taps']), (f['minutes'] as int?) ?? 0),
      _ => null,
    };
    return text == null || kind is! String ? null : WeekFinding(kind, warn, text);
  }

  static String _pct(Object? v) => formatPercent((v as num?)?.toDouble() ?? 0);
}

/// "0,8 %", "95,3 %", "15 %" in the app's language: one decimal below 100, none when it is 0.
String formatPercent(double v) {
  var text = v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
  return '${s.localeName.startsWith('de') ? text.replaceAll('.', ',') : text} %';
}
