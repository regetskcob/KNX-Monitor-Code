import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/handover_check.dart';

void main() {
  test('Ohne alles: alle Punkte offen', () {
    final c = HandoverCheck();
    const e = HandoverEvidence();
    expect(c.missing(e), HandoverItem.values);
    expect(c.done(e), 0);
  });

  test('Projekt mit Geräten gilt als Projektdatei, eine Adressliste (CSV) nicht', () {
    final c = HandoverCheck();
    expect(c.stateOf(HandoverItem.projectFile, const HandoverEvidence(projectGroups: 200)), HandoverState.open);
    const loaded = HandoverEvidence(projectGroups: 200, projectDevices: 40);
    expect(c.stateOf(HandoverItem.projectFile, loaded), HandoverState.received);
    expect(c.detected(HandoverItem.projectFile, loaded), isTrue);
  });

  test('Passt das Projekt zur Anlage? Erst mit genug Verkehr, und nur ohne Abweichung', () {
    final c = HandoverCheck();
    const few = HandoverEvidence(projectDevices: 40, heard: 5);
    expect(few.projectFits, isNull);
    expect(c.stateOf(HandoverItem.projectCurrent, few), HandoverState.open);
    const fits = HandoverEvidence(projectDevices: 40, heard: 60);
    expect(c.stateOf(HandoverItem.projectCurrent, fits), HandoverState.received);
    const stale = HandoverEvidence(projectDevices: 40, heard: 60, unknown: 7);
    expect(stale.projectFits, isFalse);
    expect(c.stateOf(HandoverItem.projectCurrent, stale), HandoverState.open);
  });

  test('Haken von Hand gehen vor; „trifft nicht zu“ zählt als erledigt', () {
    final c = HandoverCheck({
      HandoverItem.keyring: HandoverState.notNeeded,
      HandoverItem.circuitPlan: HandoverState.received,
    });
    const e = HandoverEvidence(keyring: true);
    expect(c.detected(HandoverItem.keyring, e), isFalse);
    expect(c.missing(e), isNot(contains(HandoverItem.keyring)));
    expect(c.done(e), 2);
    final again = HandoverCheck.fromJson(c.toJson());
    expect(again.states, c.states);
    expect(HandoverCheck.fromJson({'unbekannt': 'received', 'keyring': 'kaputt'}).states, isEmpty);
  });
}
