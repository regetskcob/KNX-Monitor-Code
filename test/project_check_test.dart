import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/catalog_store.dart';
import 'package:knx_monitor/knx/demo_tunnel.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';
import 'package:knx_monitor/model/analysis.dart';
import 'package:knx_monitor/model/findings.dart';
import 'package:knx_monitor/model/project_check.dart';
import 'package:knx_monitor/l10n/app_localizations.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/project_check_screen.dart';

void main() {
  final temp = parseGroup('2/0/0')!;
  final light = parseGroup('1/1/1')!;
  final never = parseGroup('3/3/3')!;
  final known = parseIndividual('1.1.50')!;

  setUp(() {
    CatalogStore.instance.catalog = GroupCatalog(
      {
        temp: GroupInfo(address: temp, name: 'Temperatur', dpt: const Dpt(9, 1)),
        light: GroupInfo(address: light, name: 'Licht', dpt: const Dpt(1, 1)),
        never: GroupInfo(address: never, name: 'Selten', dpt: const Dpt(1, 1)),
      },
      devices: {known: DeviceInfo(address: known, name: 'Melder')},
    );
  });

  Telegram t(int ga, int src, List<int> data, {bool small = false}) => Telegram(
    time: DateTime(2026),
    source: src,
    destination: ga,
    type: TelegramType.write,
    data: Uint8List.fromList(data),
    isSmall: small,
  );

  test('findet unbekannte Adressen, Geräte, DPT-Längenfehler und nie gesehene', () {
    final log = TelegramLog()
      ..addAll([
        t(temp, known, [0x0C, 0x24]),
        t(temp, known, [0x10]), // 1 Byte statt 2
        t(light, known, [1], small: true),
        t(parseGroup('5/5/5')!, parseIndividual('1.1.99')!, [1], small: true),
        t(parseGroup('5/5/5')!, parseIndividual('1.1.99')!, [0], small: true),
      ]);
    final c = ProjectCheck.of(log);
    expect(c.total, 5);
    expect(c.unknownAddresses.single.address, parseGroup('5/5/5'));
    expect(c.unknownAddresses.single.count, 2);
    expect(c.unknownDevices.single.address, parseIndividual('1.1.99'));
    expect(c.sizeMismatches.single.address, temp);
    expect(c.sizeMismatches.single.expected, 2);
    expect(c.sizeMismatches.single.seen, {1});
    expect(c.neverSeen, [never]);
  });

  test('Zentral-Aus mit Ein: nur 1 auf Aus-Adressen, nicht bei „ein/aus“ oder Rückmeldung', () {
    final off = parseGroup('0/0/1')!;
    final onOff = parseGroup('0/0/2')!;
    final status = parseGroup('0/0/3')!;
    CatalogStore.instance.catalog = GroupCatalog({
      off: GroupInfo(address: off, name: 'Zentral Licht aus', dpt: const Dpt(1, 1)),
      onOff: GroupInfo(address: onOff, name: 'Zentral ein/aus', dpt: const Dpt(1, 1)),
      status: GroupInfo(address: status, name: 'Alles aus Status', dpt: const Dpt(1, 1)),
    });
    final log = TelegramLog()
      ..addAll([
        t(off, known, [0], small: true),
        t(off, known, [1], small: true),
        t(off, known, [1], small: true),
        t(onOff, known, [1], small: true),
        t(status, known, [1], small: true),
      ]);
    final c = ProjectCheck.of(log);
    expect(c.centralOffOn, [(address: off, count: 2)]);
    expect(issuesOf(log.log[1], log), contains(TelegramIssue.centralOffOn));
    expect(issuesOf(log.log[0], log), isNot(contains(TelegramIssue.centralOffOn)));
    expect(issuesOf(log.log[3], log), isNot(contains(TelegramIssue.centralOffOn)));
  });

  test('Lastspitze: meiste Telegramme in einer Sekunde', () {
    Telegram at(int ms) => Telegram(
      time: DateTime(2026).add(Duration(milliseconds: ms)),
      source: known,
      destination: light,
      type: TelegramType.write,
      data: Uint8List.fromList([1]),
      isSmall: true,
    );
    expect(peakPerSecond([for (var i = 0; i < 40; i++) at(i * 20), at(1500), at(2100)]), 40);
    expect(peakPerSecond(const []), 0);
  });

  group('Projekt-Prüfungen ohne Busverkehr', () {
    final pa = parseIndividual;
    const actuator = ComFlags(write: true); // K S – Schaltobjekt
    const status = ComFlags(read: true, transmit: true); // K L Ü – Rückmeldung
    const button = ComFlags(transmit: true); // K Ü – Taster
    GroupLink link(String device, ComFlags? flags, {bool first = true, int? object}) => GroupLink(
      device: pa(device)!,
      object: object,
      flags: flags,
      // Wie der Import: erste Adresse, K + Ü, kein Eingang mit S + A.
      sends: first && (flags == null || flags.communication && flags.transmit && !(flags.write && flags.update)),
    );
    GroupInfo group(String address, String name, List<GroupLink> links) =>
        GroupInfo(address: parseGroup(address)!, name: name, links: links);

    test('Rückmeldung ohne Ü, gelesen ohne L, mehrere Sender, ohne K, Geräte ohne Verknüpfung', () {
      final groups = [
        // Alles in Ordnung: Taster sendet, Aktor hört, Status mit K L Ü.
        group('1/1/1', 'Licht schalten', [link('1.1.50', button), link('1.1.5', actuator)]),
        group('1/4/1', 'Licht Rückmeldung', [link('1.1.5', status), link('1.1.50', actuator)]),
        // Status ohne Ü (nur zweite Adresse des Aktor-Objekts) und ohne L.
        group('1/4/2', 'Licht Status', [
          link('1.1.5', const ComFlags(transmit: true), first: false),
          link('1.1.50', actuator),
        ]),
        // Zwei Taster senden – Hinweis.
        group('1/1/3', 'Licht Flur', [link('1.1.50', button), link('1.1.51', button), link('1.1.5', actuator)]),
        // Anzeigeobjekt mit S Ü A sendet nicht.
        group('1/1/4', 'Licht Bad', [
          link('1.1.50', button),
          link('1.1.51', const ComFlags(write: true, transmit: true, update: true)),
        ]),
        // Objekt ohne K.
        group('1/1/5', 'Licht Keller', [link('1.1.5', const ComFlags(communication: false, write: true), object: 7)]),
      ];
      final devices = {
        for (final (a, name) in [
          ('1.1.5', 'Aktor'),
          ('1.1.50', 'Taster'),
          ('1.1.51', 'Taster 2'),
          ('1.1.120', 'Binäreingang'),
          ('1.2.0', 'Linienkoppler'),
        ])
          pa(a)!: DeviceInfo(address: pa(a)!, name: name),
        pa('1.1.36')!: DeviceInfo(address: pa('1.1.36')!, name: 'X1 · Tunnel 1', tunnelOf: pa('1.1.50')),
      };
      final lint = ProjectLint.of(GroupCatalog({for (final g in groups) g.address: g}, devices: devices));
      expect(lint.hasFlags, isTrue);
      expect(lint.statusWithoutTransmit.map((g) => g.name), ['Licht Status']);
      expect(lint.readWithoutReadFlag.map((g) => g.name), ['Licht Status']);
      expect(lint.multipleSenders.map((g) => g.name), ['Licht Flur']);
      expect(lint.objectsWithoutCommunication.single.$2.object, 7);
      // Koppler (Teilnehmer 0) und Tunnel zählen nicht.
      expect(lint.devicesWithoutLinks.map((d) => formatIndividual(d.address)), ['1.1.120']);
    });

    test('L-Flag mehrfach, ohne Sender, ohne Empfänger, volle Linie, Hauptgruppe 14/15', () {
      final groups = [
        // In Ordnung: Taster sendet, Aktor hört, Status mit genau einem L.
        group('1/1/1', 'Licht schalten', [link('1.1.50', button), link('1.1.5', actuator)]),
        group('1/4/1', 'Licht Rückmeldung', [link('1.1.5', status), link('1.1.50', actuator)]),
        // Zwei Objekte mit K L Ü auf derselben Rückmeldung.
        group('1/4/2', 'Licht Status', [link('1.1.5', status), link('1.1.6', status), link('1.1.50', actuator)]),
        // Nur Empfänger (Visu ohne Platzhalter): ohne Sender.
        group('1/1/2', 'Licht Garten', [link('1.1.5', actuator)]),
        // Nur Sender: ohne Empfänger.
        group('1/1/3', 'Licht Keller', [link('1.1.50', button)]),
        // Hauptgruppe 14 bei mehreren Linien.
        group('14/0/1', 'Wind', [link('1.2.1', button), link('1.1.5', actuator)]),
        // Ganz ohne Verknüpfung: bewirkt nichts.
        group('1/1/7', 'Licht Dachboden', []),
      ];
      final devices = {
        for (var i = 1; i <= ProjectLint.lineReserveLimit + 2; i++)
          pa('1.1.$i')!: DeviceInfo(address: pa('1.1.$i')!, name: 'Gerät $i'),
        pa('1.1.36')!: DeviceInfo(address: pa('1.1.36')!, name: 'X1 · Tunnel 1', tunnelOf: pa('1.1.50')),
        pa('1.2.1')!: DeviceInfo(address: pa('1.2.1')!, name: 'Wetterstation'),
      };
      final lint = ProjectLint.of(GroupCatalog({for (final g in groups) g.address: g}, devices: devices));
      expect(lint.multipleReadAnswers.map((g) => g.name), ['Licht Status']);
      expect(lint.withoutSender.map((g) => g.name), ['Licht Garten']);
      expect(lint.withoutReceiver.map((g) => g.name), ['Licht Keller', 'Licht Dachboden']);
      // 52 Adressen auf 1.1, der Tunnel 1.1.36 ersetzt Gerät 36 und zählt nicht.
      expect(lint.crowdedLines, [(line: pa('1.1.0')! >> 8, devices: ProjectLint.lineReserveLimit + 1)]);
      expect(lint.unfilteredMainGroups.map((g) => g.name), ['Wind']);
    });

    test('eine Linie: Hauptgruppe 14/15 kein Befund; Namen und Datentypen auch ohne Geräte', () {
      final wind = GroupInfo(address: parseGroup('14/0/1')!, name: 'Wind', dpt: const Dpt(1, 5));
      final unnamed = GroupInfo(address: parseGroup('1/1/9')!, name: 'Neue Gruppenadresse', dpt: const Dpt(1, 1));
      final untyped = GroupInfo(address: parseGroup('1/1/8')!, name: 'Licht Bad');
      final lint = ProjectLint.of(
        GroupCatalog(
          {
            for (final g in [wind, unnamed, untyped]) g.address: g,
          },
          devices: {pa('1.1.5')!: DeviceInfo(address: pa('1.1.5')!, name: 'Aktor')},
        ),
      );
      expect(lint.unfilteredMainGroups, isEmpty);
      expect(lint.crowdedLines, isEmpty);
      expect(
        [for (final i in lint.incomplete) (i.group.name, i.noName, i.noDpt)],
        [('Licht Bad', false, true), ('Neue Gruppenadresse', true, false)],
      );
    });

    test('ohne Flags (CSV, alter Katalog): nur die Geräte-Prüfung', () {
      final g = group('1/4/2', 'Licht Status', [link('1.1.5', null, first: false)]);
      final lint = ProjectLint.of(
        GroupCatalog(
          {g.address: g},
          devices: {pa('1.1.9')!: DeviceInfo(address: pa('1.1.9')!, name: 'Aktor')},
        ),
      );
      expect(lint.hasFlags, isFalse);
      expect(lint.statusWithoutTransmit, isEmpty);
      expect(lint.readWithoutReadFlag, isEmpty);
      expect(lint.devicesWithoutLinks.single.name, 'Aktor');
    });
  });

  testWidgets('Seite zeigt Busverkehr und Projekt getrennt, Befunde als Zeilen', (tester) async {
    final status = parseGroup('1/4/2')!;
    final aktor = parseIndividual('1.1.5')!;
    CatalogStore.instance.catalog = GroupCatalog(
      {
        status: GroupInfo(
          address: status,
          name: 'Licht Status',
          links: [GroupLink(device: aktor, text: 'Kanal A', flags: const ComFlags(write: true))],
        ),
      },
      devices: {
        aktor: DeviceInfo(address: aktor, name: 'Aktor'),
        parseIndividual('1.1.120')!: DeviceInfo(address: parseIndividual('1.1.120')!, name: 'MDT Binäreingang 2-fach'),
      },
    );
    addTearDown(() => CatalogStore.instance.catalog = GroupCatalog.empty);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: ProjectCheckScreen(log: TelegramLog(), onFilter: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Busverkehr'), findsOneWidget);
    expect(find.text('Projekt'), findsOneWidget);
    // Summe aller Befunde in der grünen Box.
    expect(find.textContaining('Abweichungen'), findsWidgets);
    expect(find.text('Rückmeldung ohne Ü-Flag'), findsOneWidget);
    expect(find.text('Gelesen ohne L-Flag'), findsOneWidget);
    expect(find.textContaining('1.1.5 Kanal A K S'), findsNWidgets(2));
    expect(find.text('Geräte ohne Verknüpfung'), findsOneWidget);
    expect(find.textContaining('1.1.120  MDT Binäreingang 2-fach'), findsOneWidget);
    expect(find.text('Mehrere Sender'), findsOneWidget);
    expect(find.text('L-Flag mehrfach'), findsOneWidget);
    expect(find.text('Ohne Namen oder Datentyp'), findsOneWidget);
    expect(find.text('Zentral-Aus mit Ein'), findsOneWidget);
    // Prüfungen ohne Befund bleiben als ruhige Zeile mit Ergebnis im Wort.
    expect(find.text('Keine Abweichungen'), findsWidgets);
    // Eine Linie: keine Prüfung der Hauptgruppen 14/15.
    expect(find.text('Hauptgruppe 14 oder 15'), findsNothing);
  });

  testWidgets('Demo-Haus ohne Flags: kein Hinweis auf Neuimport', (tester) async {
    CatalogStore.instance.catalog = demoCatalog();
    DemoTunnel.active = true;
    addTearDown(() {
      DemoTunnel.active = false;
      CatalogStore.instance.catalog = GroupCatalog.empty;
    });
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        home: ProjectCheckScreen(log: TelegramLog(), onFilter: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('neu importieren'), findsNothing);
    expect(find.textContaining('Das Demo-Haus hat keine Flags'), findsWidgets);
  });
}
