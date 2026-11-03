import 'dart:async';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/demo_tunnel.dart';
import '../knx/group_catalog.dart';
import '../l10n/locale_controller.dart';
import '../model/learning.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';

/// Opens lessons and the quiz, also without a connection.
Future<void> openLearn(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LearnScreen()));

/// Explains [term] in one sentence with an example from the loaded project
/// (otherwise from the demo house).
Future<void> showTerm(BuildContext context, Term term, {bool more = true}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheet) {
    final theme = Theme.of(sheet);
    final hz = sheet.hz;
    final own = CatalogStore.instance.catalog;
    final example = term.example(own) ?? term.example(demoCatalog());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(term.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.item),
            Text(term.explanation, style: theme.textTheme.bodyMedium),
            if (example != null) ...[
              const SizedBox(height: Gap.item),
              Text(example, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
            ],
            if (more) ...[
              const SizedBox(height: Gap.inner),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.pop(sheet);
                    openLearn(context);
                  },
                  icon: const Icon(AppIcons.learn, size: 18),
                  label: Text(s.glossaryMore),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  },
);

/// Tappable technical terms as chips.
class TermChips extends StatelessWidget {
  const TermChips({super.key, required this.terms, this.more = true});

  final List<Term> terms;

  /// Whether the sheet points to the lessons and the quiz.
  final bool more;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: HzSpace.s8,
    runSpacing: HzSpace.s4,
    children: [
      for (final t in terms)
        ActionChip(
          avatar: const Icon(AppIcons.glossary, size: 16),
          label: Text(t.title),
          onPressed: () => showTerm(context, t, more: more),
        ),
    ],
  );
}

/// Learning on your own installation: terms, five lessons, a mini quiz.
class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key});

  void _open(BuildContext context, String title, List<Widget> children) => unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: ListView(padding: Gap.page, children: children),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.lessonsTitle),
        actions: [InfoAction(title: s.lessonsTitle, text: s.lessonsIntro)],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListView(
            padding: Gap.page,
            children: [
              FigureBox(
                figures: [
                  (label: s.lessonsLessons, value: formatInt(lessons.length), status: null),
                  (label: s.glossaryTitle, value: formatInt(Term.values.length), status: null),
                ],
              ),
              SectionHead(s.lessonsLessons, count: lessons.length),
              RowCard(
                children: [
                  for (final lesson in lessons)
                    CardRow(
                      title: lesson.title,
                      meta: s.lessonsKind,
                      onTap: () => _open(context, lesson.title, [
                        Text(lesson.text, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: Gap.section),
                        Text(
                          s.lessonsTry(lesson.tryIt),
                          style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted),
                        ),
                        const SizedBox(height: Gap.section),
                        TermChips(terms: lesson.terms, more: false),
                      ]),
                    ),
                ],
              ),
              SectionHead(s.lessonsPractice),
              RowCard(
                children: [
                  CardRow(
                    title: s.quizTitle,
                    meta: s.quizMeta,
                    onTap: () => _open(context, s.quizTitle, const [_Quiz()]),
                  ),
                  CardRow(
                    title: s.glossaryTitle,
                    meta: s.lessonsTermCount(Term.values.length),
                    onTap: () => _open(context, s.glossaryTitle, [TermChips(terms: Term.values, more: false)]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mini quiz: questions from your own project, or from the demo house without one.
class _Quiz extends StatefulWidget {
  const _Quiz();

  @override
  State<_Quiz> createState() => _QuizState();
}

class _QuizState extends State<_Quiz> {
  List<QuizQuestion>? _quiz;
  bool _demo = false;
  int _index = 0;
  final _answers = <int, int>{};

  void _start() {
    final own = CatalogStore.instance.catalog;
    final GroupCatalog source = own.isEmpty ? demoCatalog() : own;
    setState(() {
      _demo = own.isEmpty;
      _quiz = buildQuiz(source);
      _index = 0;
      _answers.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final quiz = _quiz;
    if (quiz == null) {
      return SectionCard(
        title: s.quizTitle,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton(onPressed: _start, child: Text(s.quizStart)),
        ),
      );
    }
    if (_index >= quiz.length) {
      return SectionCard(
        title: s.quizTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.quizResult(quizScore(quiz, _answers), quiz.length), style: theme.textTheme.titleMedium),
            const SizedBox(height: Gap.inner),
            OutlinedButton(onPressed: _start, child: Text(s.quizAgain)),
          ],
        ),
      );
    }
    final q = quiz[_index];
    final answered = _answers[_index];
    return SectionCard(
      title: s.quizTitle,
      trailing: Kennung(s.quizProgress(_index + 1, quiz.length)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_demo) ...[
            Text(s.quizDemoNote, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            const SizedBox(height: Gap.item),
          ],
          Text(q.question, style: theme.textTheme.titleSmall),
          const SizedBox(height: Gap.item),
          for (final (i, a) in q.answers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: HzSpace.s8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
                onPressed: answered != null ? null : () => setState(() => _answers[_index] = i),
                // Right/wrong with a symbol and a word, not just color.
                icon: answered == null
                    ? const Icon(AppIcons.unselected, size: 18)
                    : Icon(
                        i == q.correct
                            ? AppIcons.success
                            : (i == answered ? HorizontStatus.critical.icon : AppIcons.unselected),
                        size: 18,
                        color: i == q.correct ? hz.positive : (i == answered ? hz.critical : null),
                      ),
                label: Text(a),
              ),
            ),
          if (answered != null) ...[
            const SizedBox(height: HzSpace.s4),
            Text(
              answered == q.correct ? s.quizRight : s.quizWrong,
              style: theme.textTheme.titleSmall?.copyWith(color: answered == q.correct ? hz.positive : hz.critical),
            ),
            const SizedBox(height: HzSpace.s4),
            Text(q.term.explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: Gap.inner),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(onPressed: () => setState(() => _index++), child: Text(s.quizNext)),
            ),
          ],
        ],
      ),
    );
  }
}
