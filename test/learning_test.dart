import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/model/learning.dart';

void main() {
  tearDown(() => LocaleController.instance.debugSetLocale(const Locale('de')));

  test('Jeder Begriff hat Titel, Erklärung und im Demo-Haus ein Beispiel (außer Flags/Tunnel)', () {
    final demo = demoCatalog();
    for (final t in Term.values) {
      expect(t.title, isNotEmpty);
      expect(t.explanation, isNotEmpty);
      if (t != Term.flags && t != Term.tunnel) expect(t.example(demo), isNotNull, reason: t.name);
    }
    expect(Term.groupAddress.example(GroupCatalog.empty), isNull);
  });

  test('Beispiele aus dem eigenen Projekt', () {
    final c = GroupCatalog(
      {
        0x0801: GroupInfo(
          address: 0x0801,
          name: 'Küche Licht',
          dpt: const Dpt(1, 1),
          links: const [GroupLink(device: 0x1105, flags: ComFlags(read: true, write: true))],
        ),
        0x0901: const GroupInfo(address: 0x0901, name: 'Küche Licht Rückmeldung', dpt: Dpt(1, 1)),
        0x1000: const GroupInfo(address: 0x1000, name: 'Temperatur', dpt: Dpt(9, 1)),
      },
      devices: {
        0x1105: const DeviceInfo(address: 0x1105, name: 'Schaltaktor'),
        0x11F1: const DeviceInfo(address: 0x11F1, name: 'Tunnel 1', tunnelOf: 0x11FF),
        0x11FF: const DeviceInfo(address: 0x11FF, name: 'IP-Schnittstelle'),
      },
    );
    expect(Term.groupAddress.example(c), 'Hier: 1/0/1 heißt „Küche Licht“.');
    expect(Term.individualAddress.example(c), 'Hier: 1.1.5 ist „Schaltaktor“ auf Linie 1.1.');
    expect(Term.status.example(c), contains('Küche Licht Rückmeldung'));
    expect(Term.dpt.example(c), 'Hier: „Temperatur“ hat den Typ 9.001.');
    expect(Term.flags.example(c), 'Hier: „Küche Licht“ am Gerät 1.1.5 hat die Flags K L S.');
    expect(Term.line.example(c), 'Hier: Linie 1.1 hat 2 Geräte.');
    expect(Term.tunnel.example(c), 'Hier: 1.1.241 ist ein Tunnel von „IP-Schnittstelle“.');
    LocaleController.instance.debugSetLocale(const Locale('en'));
    expect(flagLetters(const ComFlags(read: true, transmit: true)), 'C R T');
  });

  test('Fünf Lektionen mit Begriffen', () {
    expect(lessons, hasLength(5));
    expect({for (final l in lessons) ...l.terms}, Term.values.toSet());
  });

  test('Quiz aus dem Demo-Haus: genau eine richtige Antwort je Frage', () {
    final quiz = buildQuiz(demoCatalog(), random: Random(1));
    expect(quiz.length, greaterThanOrEqualTo(5));
    for (final q in quiz) {
      expect(q.answers.toSet(), hasLength(q.answers.length), reason: q.question);
      expect(q.correct, inInclusiveRange(0, q.answers.length - 1));
    }
    final first = quiz.first;
    expect(parseGroup(first.answers[first.correct]), isNotNull);
    expect(quizScore(quiz, {for (final (i, q) in quiz.indexed) i: q.correct}), quiz.length);
    expect(quizScore(quiz, {0: (first.correct + 1) % first.answers.length}), 0);
  });

  test('Quiz ohne Projekt fällt auf allgemeine Fragen zurück', () {
    final quiz = buildQuiz(GroupCatalog.empty, random: Random(2));
    expect(quiz.map((q) => q.term), [Term.groupAddress, Term.tunnel, Term.flags]);
  });
}
