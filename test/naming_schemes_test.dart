import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/object_groups.dart';

/// Gängige Gruppenadress-Schemata aus Praxis und KNX-User-Forum: Die
/// Objekte-Ansicht soll zusammengehörige Adressen in allen erkennen –
/// nicht nur im Schema des eigenen Projekts.
///
/// Je Schema: Name (bzw. Pfad › Name) je Adresse und die erwarteten Objekte
/// als Gruppen von Adressen; `*` markiert Rückmeldungen.
void main() {
  /// [entries]: Adresse → Name oder „Pfad|Name“ (Pfad mit „ › “).
  ObjectIndex index(Map<String, String> entries) => ObjectIndex.of(
    GroupCatalog({
      for (final MapEntry(key: ga, value: v) in entries.entries)
        parseGroup(ga)!: GroupInfo(
          address: parseGroup(ga)!,
          name: v.contains('|') ? v.split('|').last : v,
          path: v.contains('|') ? v.split('|').first : null,
        ),
    }),
  );

  /// Prüft Objekte: jede Liste = Adressen eines Objekts, `*` = Rückmeldung.
  void expectObjects(ObjectIndex index, List<List<String>> objects) {
    for (final members in objects) {
      final addresses = [for (final m in members) parseGroup(m.replaceAll('*', ''))!];
      final o = index.objectOf(addresses.first);
      expect(o, isNotNull, reason: 'kein Objekt für ${members.first}');
      expect(o!.members.map((m) => m.address).toSet(), addresses.toSet(), reason: 'Objekt „${o.key}“');
      expect(
        {
          for (final m in o.members)
            if (m.feedback) m.address,
        },
        {
          for (final m in members)
            if (m.endsWith('*')) parseGroup(m.substring(0, m.length - 1))!,
        },
        reason: 'Rückmeldungen in „${o.key}“',
      );
    }
  }

  test('Ort im Namen, Funktion am Ende mit Gedankenstrich (smart-home-feeling)', () {
    final i = index({
      '1/1/1': 'EG Flur — Licht schalten',
      '1/1/2': 'EG Flur — Licht Status',
      '1/1/10': 'EG Wohnen — Licht schalten',
      '1/1/11': 'EG Wohnen — Licht Status',
      '1/1/12': 'EG Wohnen — Licht dimmen',
      '1/1/13': 'EG Wohnen — Licht Dimmwert',
      '1/1/20': 'EG Küche — Licht schalten',
      '1/1/21': 'EG Küche — Licht Status',
    });
    expectObjects(i, [
      ['1/1/1', '1/1/2*'],
      ['1/1/10', '1/1/11*', '1/1/12', '1/1/13'],
      ['1/1/20', '1/1/21*'],
    ]);
    expect(i.objectOf(parseGroup('1/1/10')!)!.room, 'EG Wohnen');
  });

  test('Gewerk/Etage, Name „Geschoss – Raum – Gerät – Funktion“ (dietechwerkstatt)', () {
    final i = index({
      '1/3/0': 'OG – Treppenaufgang – Deckenlicht – Schalten',
      '1/3/1': 'OG – Treppenaufgang – Deckenlicht – Status',
      '3/2/10': 'EG – Gästezimmer – Rollladen – Behang Auf-/Abfahren',
      '3/2/11': 'EG – Gästezimmer – Rollladen – Stopp Auf/Ab',
      '3/2/12': 'EG – Gästezimmer – Rollladen – Position Status',
      '4/3/0': 'OG – Diele – Temperaturmesswert',
      '4/3/3': 'OG – Diele – Aktueller Sollwert',
      '4/3/4': 'OG – Diele – Sollwert',
      '5/2/10': 'EG – Gästezimmer – Fensterkontakte – Geöffnet Auf/Zu',
      '5/2/11': 'EG – Gästezimmer – Fensterkontakte – Kipp Auf/Zu',
      '0/1/1': 'EG – Beleuchtung – Alles Ein-/Ausschalten',
    });
    expectObjects(i, [
      ['1/3/0', '1/3/1*'],
      ['3/2/10', '3/2/11', '3/2/12*'],
      ['4/3/0*', '4/3/3*', '4/3/4'],
      ['5/2/10*', '5/2/11*'],
    ]);
    expect(i.objectOf(parseGroup('1/3/0')!)!.room, 'OG Treppenaufgang');
    expect(i.objectOf(parseGroup('1/3/0')!)!.title, 'Deckenlicht');
  });

  test('Funktion in der Mittelgruppe, gleiche Namen (ETS-Schulung)', () {
    final i = index({
      '1/1/5': 'Beleuchtung › Schalten|Küche Decke',
      '1/4/5': 'Beleuchtung › Rückmeldung Schalten|Küche Decke',
      '1/1/6': 'Beleuchtung › Schalten|Wohnen Decke',
      '1/2/6': 'Beleuchtung › Dimmen|Wohnen Decke',
      '1/3/6': 'Beleuchtung › Wert|Wohnen Decke',
      '1/5/6': 'Beleuchtung › Rückmeldung Wert|Wohnen Decke',
    });
    expectObjects(i, [
      ['1/1/5', '1/4/5*'],
      ['1/1/6', '1/2/6', '1/3/6', '1/5/6*'],
    ]);
    expect(i.objectOf(parseGroup('1/4/5')!)!.members.last.function, 'Rückmeldung Schalten');
  });

  test('Raum nur im Pfad, gleiche Namen in jedem Raum', () {
    final i = index({
      '1/0/0': 'EG › Küche|Licht Decke schalten',
      '1/0/1': 'EG › Küche|Licht Decke Status',
      '1/1/0': 'EG › Wohnen|Licht Decke schalten',
      '1/1/1': 'EG › Wohnen|Licht Decke Status',
      '1/1/2': 'EG › Wohnen|Rollladen Auf/Ab',
      '1/1/3': 'EG › Wohnen|Rollladen Stopp',
      '1/1/4': 'EG › Wohnen|Rollladen Position Status',
    });
    expectObjects(i, [
      ['1/0/0', '1/0/1*'],
      ['1/1/0', '1/1/1*'],
      ['1/1/2', '1/1/3', '1/1/4*'],
    ]);
    expect(i.objectOf(parseGroup('1/1/2')!)!.room, 'Wohnen');
  });

  test('Kürzel mit Unterstrich und Punkt', () {
    final i = index({
      '1/1/0': 'EG_KUE_LI_Decke_SW',
      '1/1/1': 'EG_KUE_LI_Decke_RM',
      '2/1/0': 'EG_WZ_JAL_Fenster_AufAb',
      '2/1/1': 'EG_WZ_JAL_Fenster_Stopp',
      '2/1/2': 'EG_WZ_JAL_Fenster_Pos_RM',
      '3/1/0': 'EG.BAD.HZG.IstTemp',
      '3/1/1': 'EG.BAD.HZG.SollTemp',
    });
    expectObjects(i, [
      ['1/1/0', '1/1/1*'],
      ['2/1/0', '2/1/1', '2/1/2*'],
      ['3/1/0*', '3/1/1'],
    ]);
  });

  test('Englische Namen', () {
    final i = index({
      '1/1/0': 'Kitchen Ceiling Light Switch',
      '1/1/1': 'Kitchen Ceiling Light Status',
      '2/1/0': 'Living Room Blind Up/Down',
      '2/1/1': 'Living Room Blind Stop',
      '2/1/2': 'Living Room Blind Position',
      '2/1/3': 'Living Room Blind Position Status',
      '3/1/0': 'Bedroom Temperature Actual',
      '3/1/1': 'Bedroom Temperature Setpoint',
    });
    expectObjects(i, [
      ['1/1/0', '1/1/1*'],
      ['2/1/0', '2/1/1', '2/1/2', '2/1/3*'],
      ['3/1/0*', '3/1/1'],
    ]);
  });

  test('Funktion vorn, Nummern und RM-Kürzel', () {
    final i = index({
      '1/1/0': 'Licht 1 Ein/Aus',
      '1/1/1': 'Licht 1 RM',
      '1/1/2': 'Licht 2 Ein/Aus',
      '1/1/3': 'Licht 2 RM',
      '1/2/0': 'Schalten Steckdose Garten',
      '1/2/1': 'Status Steckdose Garten',
    });
    expectObjects(i, [
      ['1/1/0', '1/1/1*'],
      ['1/1/2', '1/1/3*'],
      ['1/2/0', '1/2/1*'],
    ]);
  });

  test('Englisch mit Geschoss-Kürzeln und Trennern (GF – Kitchen – …)', () {
    final i = index({
      '1/0/0': 'GF - Kitchen - Downlights - Switch',
      '1/0/1': 'GF - Kitchen - Downlights - Switch Feedback',
      '1/0/2': 'GF - Kitchen - Downlights - Dim Value',
      '1/0/3': 'GF - Kitchen - Downlights - Brightness Status',
      '2/0/0': 'GF - Living - Shade - Up/Down',
      '2/0/1': 'GF - Living - Shade - Stop/Step',
      '2/0/2': 'GF - Living - Shade - Slat Angle',
      '2/0/3': 'GF - Living - Shade - Height Status',
      '3/1/0': 'FF - Bedroom - Radiator - Setpoint',
      '3/1/1': 'FF - Bedroom - Radiator - Actual Temperature',
      '3/1/2': 'FF - Bedroom - Radiator - Valve Position',
      '4/1/0': 'FF - Bedroom - Window - Opened',
      '4/1/1': 'FF - Bedroom - Window - Tilted',
    });
    expectObjects(i, [
      ['1/0/0', '1/0/1*', '1/0/2', '1/0/3*'],
      ['2/0/0', '2/0/1', '2/0/2', '2/0/3*'],
      ['3/1/0', '3/1/1*', '3/1/2'], // Ventilstellung: Befehl des Reglers
      ['4/1/0*', '4/1/1*'],
    ]);
    expect(i.objectOf(parseGroup('1/0/0')!)!.room, 'GF Kitchen');
    expect(i.objectOf(parseGroup('1/0/0')!)!.title, 'Downlights');
  });

  test('Englisch ohne Trenner, Status vorn, Raum im Pfad (function-based)', () {
    final i = index({
      '1/1/0': 'Lighting › Ground Floor|Hallway Light On/Off',
      '1/1/1': 'Lighting › Ground Floor|Hallway Light On/Off Status',
      '1/1/2': 'Lighting › Ground Floor|Status Porch Lamp',
      '1/1/3': 'Lighting › Ground Floor|Porch Lamp Toggle',
      '2/1/0': 'Blinds › Ground Floor|Study Blind Move',
      '2/1/1': 'Blinds › Ground Floor|Study Blind Position Feedback',
      '5/1/0': 'Energy › Meters|Power Heat Pump',
      '5/1/1': 'Energy › Meters|Energy Heat Pump',
    });
    expectObjects(i, [
      ['1/1/0', '1/1/1*'],
      ['1/1/2*', '1/1/3'],
      ['2/1/0', '2/1/1*'],
      ['5/1/0', '5/1/1'],
    ]);
    expect(i.objectOf(parseGroup('1/1/0')!)!.room, 'Hallway');
  });
}
