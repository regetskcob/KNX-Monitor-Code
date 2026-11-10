import 'dart:math';

import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import 'commissioning.dart' show isStatusGroup;

/// Technical terms beginners can tap: a one-sentence explanation plus an example
/// from their own project or the demo house.
enum Term {
  groupAddress,
  individualAddress,
  status,
  dpt,
  flags,
  line,
  tunnel;

  String get title => switch (this) {
    groupAddress => s.termGroupAddress,
    individualAddress => s.termIndividualAddress,
    status => s.termStatus,
    dpt => s.termDpt,
    flags => s.termFlags,
    line => s.termLine,
    tunnel => s.termTunnel,
  };

  /// Explanation in one sentence.
  String get explanation => switch (this) {
    groupAddress => s.termGroupAddressText,
    individualAddress => s.termIndividualAddressText,
    status => s.termStatusText,
    dpt => s.termDptText,
    flags => s.termFlagsText,
    line => s.termLineText,
    tunnel => s.termTunnelText,
  };

  /// Example from [c]; `null` if none fits there.
  String? example(GroupCatalog c) {
    final groups = c.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
    final devices = c.devices.values.where((d) => !d.isTunnel).toList()..sort((a, b) => a.address.compareTo(b.address));
    switch (this) {
      case groupAddress:
        final g = groups.where((g) => g.dpt?.main == 1 && !isStatusGroup(g)).firstOrNull ?? groups.firstOrNull;
        return g == null ? null : s.termExampleGroup(formatGroup(g.address), g.name);
      case individualAddress:
        final d = devices.firstOrNull;
        return d == null
            ? null
            : s.termExampleDevice(formatIndividual(d.address), d.name, '${d.address >> 12}.${(d.address >> 8) & 0x0F}');
      case status:
        final g = groups.where(isStatusGroup).firstOrNull;
        return g == null ? null : s.termExampleStatus(formatGroup(g.address), g.name);
      case dpt:
        final g = groups.where((g) => g.dpt != null && g.dpt!.main != 1).firstOrNull;
        return g == null ? null : s.termExampleDpt(g.name, '${g.dpt}');
      case flags:
        for (final g in groups) {
          for (final l in g.links) {
            if (l.flags case final f?) {
              return s.termExampleFlags(g.name, formatIndividual(l.device), flagLetters(f));
            }
          }
        }
        return null;
      case line:
        final lines = <int, int>{};
        for (final d in devices) {
          lines[d.address >> 8] = (lines[d.address >> 8] ?? 0) + 1;
        }
        if (lines.isEmpty) return null;
        final busiest = lines.entries.reduce((a, b) => b.value > a.value ? b : a);
        return s.termExampleLine('${busiest.key >> 4}.${busiest.key & 0x0F}', busiest.value);
      case tunnel:
        final t = c.devices.values.where((d) => d.isTunnel).firstOrNull;
        return t == null ? null : s.termExampleTunnel(formatIndividual(t.address), c.devices[t.tunnelOf]?.name ?? '');
    }
  }
}

/// Flags in the notation of the German ETS (K L S Ü A) or English (C R W T U).
String flagLetters(ComFlags f) {
  final de = s.localeName.startsWith('de');
  return [
    if (f.communication) de ? 'K' : 'C',
    if (f.read) de ? 'L' : 'R',
    if (f.write) de ? 'S' : 'W',
    if (f.transmit) de ? 'Ü' : 'T',
    if (f.update) de ? 'A' : 'U',
  ].join(' ');
}

/// Where a lesson's "try it" leads in the monitor.
enum LessonTarget { live, overview, health, gateway }

/// A short lesson: what it is about, which terms, what can be tried out in the
/// demo house.
class Lesson {
  const Lesson(this.title, this.text, this.terms, this.tryIt, this.target);

  final String title;
  final String text;
  final List<Term> terms;

  /// To try out (demo house or own installation).
  final String tryIt;

  /// The place in the monitor [tryIt] talks about.
  final LessonTarget target;
}

/// The lessons in learning order.
List<Lesson> get lessons => [
  Lesson(
    s.lessonSwitchTitle,
    s.lessonSwitchText,
    const [Term.groupAddress, Term.status],
    s.lessonSwitchTry,
    LessonTarget.live,
  ),
  Lesson(
    s.lessonWhoTitle,
    s.lessonWhoText,
    const [Term.individualAddress, Term.line],
    s.lessonWhoTry,
    LessonTarget.live,
  ),
  Lesson(s.lessonValuesTitle, s.lessonValuesText, const [Term.dpt], s.lessonValuesTry, LessonTarget.overview),
  Lesson(s.lessonReadTitle, s.lessonReadText, const [Term.flags, Term.status], s.lessonReadTry, LessonTarget.health),
  Lesson(s.lessonConnectTitle, s.lessonConnectText, const [Term.tunnel], s.lessonConnectTry, LessonTarget.gateway),
];

/// A quiz question with answers; [correct] is the index of the right one.
class QuizQuestion {
  const QuizQuestion(this.question, this.answers, this.correct, this.term);

  final String question;
  final List<String> answers;
  final int correct;

  /// Term that explains the answer.
  final Term term;
}

/// Mini quiz from [c] (own project or demo house). Questions without matching
/// data are dropped; [random] shuffles the answers.
List<QuizQuestion> buildQuiz(GroupCatalog c, {Random? random}) {
  final rng = random ?? Random();
  final groups = c.groups.values.toList()..sort((a, b) => a.address.compareTo(b.address));
  final devices = c.devices.values.where((d) => !d.isTunnel).toList()..sort((a, b) => a.address.compareTo(b.address));
  final out = <QuizQuestion>[];

  QuizQuestion ask(String q, String right, List<String> wrong, Term term) {
    final answers = [right, ...wrong]..shuffle(rng);
    return QuizQuestion(q, answers, answers.indexOf(right), term);
  }

  final ga = groups.where((g) => !isStatusGroup(g)).firstOrNull;
  final device = devices.firstOrNull;
  out.add(
    ask(s.quizWhichGroup, ga == null ? '1/0/1' : formatGroup(ga.address), [
      device == null ? '1.1.30' : formatIndividual(device.address),
      '192.168.1.20',
    ], Term.groupAddress),
  );

  if (device != null) {
    final line = '${device.address >> 12}.${(device.address >> 8) & 0x0F}';
    out.add(
      ask(s.quizWhichLine(formatIndividual(device.address)), line, [
        '${device.address & 0xFF}',
        '${device.address >> 12}/${(device.address >> 8) & 0x0F}',
      ], Term.line),
    );
  }

  final typed = groups.where((g) => g.dpt != null && const {1, 5, 9}.contains(g.dpt!.main)).toList();
  if (typed.isNotEmpty) {
    final g = typed[rng.nextInt(typed.length)];
    final kinds = {1: s.quizDptSwitch, 5: s.quizDptPercent, 9: s.quizDptFloat};
    out.add(
      ask(s.quizWhichDpt(g.name), kinds[g.dpt!.main]!, [
        for (final MapEntry(:key, :value) in kinds.entries)
          if (key != g.dpt!.main) value,
      ], Term.dpt),
    );
  }

  final status = groups.where(isStatusGroup).firstOrNull;
  if (status != null) {
    out.add(ask(s.quizWhatStatus(status.name), s.quizStatusRight, [s.quizStatusWho, s.quizStatusTime], Term.status));
  }

  out.add(ask(s.quizTunnelBusy, s.quizTunnelRight, [s.quizTunnelWrongGa, s.quizTunnelWrongDpt], Term.tunnel));
  out.add(ask(s.quizFlagRead, s.quizFlagReadRight, [s.quizFlagTransmit, s.quizFlagWrite], Term.flags));
  return out;
}

/// Scores a quiz: correctly answered questions.
int quizScore(List<QuizQuestion> quiz, Map<int, int> answers) => [
  for (final (i, q) in quiz.indexed)
    if (answers[i] == q.correct) i,
].length;
