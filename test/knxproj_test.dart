import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/handover_package.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/knxproj_parser.dart';
import 'package:knx_monitor/knx/telegram.dart';

const _project = '''<?xml version="1.0" encoding="utf-8"?>
<KNX xmlns="http://knx.org/xml/project/21">
  <Project Id="P-0ABC">
    <Installations>
      <Installation Name="">
        <Topology>
          <Area Id="P-0ABC-0_A-1" Name="Haus" Address="1">
            <Line Id="P-0ABC-0_L-1" Name="Linie 1" Address="1">
              <Segment Id="P-0ABC-0_S-1" Number="0">
                <DeviceInstance Id="P-0ABC-0_DI-1" Name="Aktor Licht EG" ProductRefId="M-0008_H-1_P-1" Address="5" Description="Verteiler EG" SerialNumber="AAgSNFZ4">
                  <ComObjectInstanceRefs>
                    <ComObjectInstanceRef RefId="O-0_R-1" Text="Kanal A" FunctionText="Schalten" Links="GA-1 GA-2" />
                    <ComObjectInstanceRef RefId="O-3_R-3" Links="GA-3" />
                  </ComObjectInstanceRefs>
                  <AdditionalAddresses><Address Address="6" /><Address Address="7" Name="Visu" /></AdditionalAddresses>
                </DeviceInstance>
                <DeviceInstance Id="P-0ABC-0_DI-2" Name="" ProductRefId="M-0008_H-1_P-2" Hardware2ProgramRefId="M-0008_H-1_HP-1" Address="18">
                  <ComObjectInstanceRefs>
                    <ComObjectInstanceRef RefId="O-12_R-9" Links="GA-3" />
                    <ComObjectInstanceRef RefId="O-13_R-1" Links="GA-2" />
                  </ComObjectInstanceRefs>
                </DeviceInstance>
              </Segment>
            </Line>
          </Area>
        </Topology>
        <Locations>
          <Space Type="Building" Name="Haus">
            <Space Type="Floor" Name="EG">
              <Space Type="Room" Name="Küche">
                <DeviceInstanceRef RefId="P-0ABC-0_DI-1" />
              </Space>
            </Space>
          </Space>
        </Locations>
        <GroupAddresses>
          <GroupRanges>
            <GroupRange Name="Licht" RangeStart="2048" RangeEnd="4095">
              <GroupRange Name="Schalten" RangeStart="2304" RangeEnd="2559">
                <GroupAddress Id="P-0ABC-0_GA-1" Address="2305" Name="Küche Decke" DatapointType="DPST-1-1" Description="Spots" />
                <GroupAddress Id="P-0ABC-0_GA-2" Address="2306" Name="Alles Licht" DatapointType="DPST-1-1" />
              </GroupRange>
            </GroupRange>
            <GroupRange Name="Klima" RangeStart="4096" RangeEnd="6143">
              <GroupAddress Id="P-0ABC-0_GA-3" Address="4096" Name="Temperatur Küche" DatapointType="DPST-9-1" />
            </GroupRange>
          </GroupRanges>
        </GroupAddresses>
      </Installation>
    </Installations>
  </Project>
</KNX>''';

const _hardware = '''<?xml version="1.0" encoding="utf-8"?>
<KNX xmlns="http://knx.org/xml/project/21"><ManufacturerData><Manufacturer RefId="M-0008">
  <Hardware><Hardware Id="M-0008_H-1" Name="HW"><Products>
    <Product Id="M-0008_H-1_P-1" Text="Switch actuator 4-gang" />
    <Product Id="M-0008_H-1_P-2" Text="Room temperature controller" />
  </Products><Hardware2Programs>
    <Hardware2Program Id="M-0008_H-1_HP-1"><ApplicationProgramRef RefId="M-0008_A-1" /></Hardware2Program>
  </Hardware2Programs></Hardware></Hardware>
  <Languages><Language Identifier="de-DE">
    <TranslationUnit RefId="M-0008_H-1_P-2"><TranslationElement RefId="M-0008_H-1_P-2">
      <Translation AttributeName="Text" Text="Raumtemperaturregler" />
    </TranslationElement></TranslationUnit>
  </Language></Languages>
</Manufacturer></ManufacturerData></KNX>''';

const _master = '''<?xml version="1.0" encoding="UTF-8"?>
<KNX xmlns="http://knx.org/xml/project/21"><MasterData><Manufacturers>
  <Manufacturer Id="M-0008" KnxManufacturerId="8" Name="GIRA Giersiepen" />
</Manufacturers></MasterData></KNX>''';

/// Applikation des Reglers: Objekt 12 (Anzeige) ohne Übertragen-Flag.
const _application = '''<KNX><ManufacturerData><Manufacturer RefId="M-0008"><ApplicationPrograms>
  <ApplicationProgram Id="M-0008_A-1"><Static><ComObjects>
    <ComObject Id="M-0008_A-1_O-12" Number="12" ReadFlag="Disabled" WriteFlag="Enabled" TransmitFlag="Enabled" />
  </ComObjects><ComObjectRefs>
    <ComObjectRef Id="M-0008_A-1_O-12_R-9" RefId="M-0008_A-1_O-12" TransmitFlag="Disabled" />
    <ComObject Id="M-0008_A-1_O-13" Number="13" WriteFlag="Enabled" TransmitFlag="Disabled" UpdateFlag="Disabled" />
    <ComObjectRef Id="M-0008_A-1_O-13_R-1" RefId="M-0008_A-1_O-13" TransmitFlag="Enabled" UpdateFlag="Enabled" />
  </ComObjectRefs></Static></ApplicationProgram>
</ApplicationPrograms></Manufacturer></ManufacturerData></KNX>''';

ArchiveFile _file(String name, String text) => ArchiveFile.bytes(name, utf8.encode(text));

/// Baut eine .knxproj wie ETS6: Projekt als verschlüsseltes P-XXXX.zip.
Uint8List _knxproj({
  String? password,
  String style = 'ThreeLevel',
  String project = _project,
  String application = _application,
}) {
  final inner = Archive()
    ..add(_file('0.xml', project))
    ..add(
      _file(
        'project.xml',
        '<KNX><Project><ProjectInformation Name="Testhaus" GroupAddressStyle="$style" /></Project></KNX>',
      ),
    );
  final innerBytes = ZipEncoder(password: password == null ? null : ets6ZipPassword(password)).encodeBytes(inner);
  final outer = Archive()
    ..add(_file('knx_master.xml', _master))
    ..add(_file('M-0008/Hardware.xml', _hardware))
    ..add(_file('M-0008/M-0008_A-1.xml', application))
    ..add(ArchiveFile.bytes('P-0ABC.zip', innerBytes));
  return ZipEncoder().encodeBytes(outer);
}

void main() {
  test('liest Gruppenadressen, Geräte, Orte und Verknüpfungen', () {
    final c = parseKnxproj(_knxproj());
    expect(c.projectName, 'Testhaus');
    expect(c.length, 3);

    final decke = c[parseGroup('1/1/1')!]!;
    expect(decke.name, 'Küche Decke');
    expect(decke.path, 'Licht › Schalten');
    expect(decke.dpt, const Dpt(1, 1));
    expect(decke.description, 'Spots');
    expect(decke.links.single.device, parseIndividual('1.1.5'));
    expect(decke.links.single.text, 'Kanal A – Schalten');
    expect(decke.links.single.sends, isTrue);

    final temp = c[parseGroup('2/0/0')!]!;
    expect(temp.path, 'Klima');
    expect(temp.links.map((l) => formatIndividual(l.device)), ['1.1.5', '1.1.18']);
    expect(temp.links.last.object, 12);
    // Erste Adresse, aber Ü-Flag aus (ComObjectRef überschreibt ComObject): hört nur.
    expect(temp.links.first.sends, isTrue);
    expect(temp.links.last.sends, isFalse);
    // Zustandseingang mit S + Ü + A (MDT-Glastaster): hört, sendet nicht.
    final alles = c[parseGroup('1/1/2')!]!.links;
    expect(alles.map((l) => (formatIndividual(l.device), l.sends)), [('1.1.5', false), ('1.1.18', false)]);

    final aktor = c.devices[parseIndividual('1.1.5')]!;
    expect(aktor.name, 'Aktor Licht EG');
    expect(aktor.product, 'Switch actuator 4-gang');
    expect(aktor.manufacturer, 'GIRA Giersiepen');
    expect(aktor.location, 'EG › Küche');
    expect(aktor.description, 'Verteiler EG');
    expect(aktor.serial, '000812345678');
    expect(c.manufacturers[8], 'GIRA Giersiepen');
    expect(c.devices[parseIndividual('1.1.6')]!.name, 'Aktor Licht EG · Tunnel 1');
    expect(c.devices[parseIndividual('1.1.7')]!.name, 'Aktor Licht EG · Visu');
    expect(c.devices[parseIndividual('1.1.6')]!.tunnelOf, parseIndividual('1.1.5'));
    expect(c.devices[parseIndividual('1.1.5')]!.isTunnel, isFalse);
    // Kennung übersteht JSON.
    final back = GroupCatalog.fromJson(c.toJson());
    expect(back.devices[parseIndividual('1.1.7')]!.tunnelOf, parseIndividual('1.1.5'));

    // Ohne Namen: Produktname, deutsche Übersetzung bevorzugt.
    expect(c.devices[parseIndividual('1.1.18')]!.name, 'Raumtemperaturregler');
    expect(c.style, GroupStyle.threeLevel);
  });

  // KNX RF (docs: Notion „KNX RF in Busclear“, öffentliches Issue KNX-Monitor #13): Das Medium steht
  // in ETS5 an der Linie, in ETS6 am Segment darin.
  test('Funklinie: Geräte auf KNX RF sind gekennzeichnet, die Linie zählt als Funk', () {
    final tp = parseKnxproj(_knxproj());
    expect(tp.devices.values.any((d) => d.rf), isFalse);
    expect(tp.rfLines, isEmpty);

    final ets5 = parseKnxproj(
      _knxproj(
        project: _project.replaceFirst(
          '<Line Id="P-0ABC-0_L-1" Name="Linie 1" Address="1">',
          '<Line Id="P-0ABC-0_L-1" Name="Linie 1" Address="1" MediumTypeRefId="MT-2">',
        ),
      ),
    );
    expect(ets5.devices.values.every((d) => d.rf || d.isTunnel), isTrue);
    expect(ets5.rfLines, {0x11});

    final ets6 = parseKnxproj(
      _knxproj(
        project: _project
            .replaceFirst(
              '<Line Id="P-0ABC-0_L-1" Name="Linie 1" Address="1">',
              '<Line Id="P-0ABC-0_L-1" Name="Linie 1" Address="1" MediumTypeRefId="MT-0">',
            )
            .replaceFirst(
              '<Segment Id="P-0ABC-0_S-1" Number="0">',
              '<Segment Id="P-0ABC-0_S-1" Number="0" MediumTypeRefId="MT-2">',
            ),
      ),
    );
    expect(ets6.rfLines, {0x11}, reason: 'das Segment zählt vor der Linie');

    // Reist im Übergabepaket mit: Beim Kunden bleibt die Funklinie eine Funklinie.
    expect(handoverCatalog(ets5).rfLines, {0x11});

    // Übersteht den Katalog auf der Platte; ältere Kataloge ohne das Feld sind TP.
    final back = GroupCatalog.fromJson(ets5.toJson());
    expect(back.rfLines, {0x11});
    expect(GroupCatalog.fromJson(tp.toJson()).rfLines, isEmpty);
  });

  test('Adressdarstellung aus dem Projekt (2-stufig, frei)', () {
    expect(parseKnxproj(_knxproj(style: 'TwoLevel')).style, GroupStyle.twoLevel);
    expect(parseKnxproj(_knxproj(style: 'Free')).style, GroupStyle.free);
  });

  test('Passwortschutz (ETS6-Ableitung)', () {
    final bytes = _knxproj(password: 'geheim');
    expect(
      () => parseKnxproj(bytes),
      throwsA(isA<KnxprojPasswordException>().having((e) => e.wrong, 'wrong', isFalse)),
    );
    expect(
      () => parseKnxproj(bytes, password: 'falsch'),
      throwsA(isA<KnxprojPasswordException>().having((e) => e.wrong, 'wrong', isTrue)),
    );
    expect(parseKnxproj(bytes, password: 'geheim').length, 3);
  });

  test('Katalog übersteht JSON-Hin-und-Rückweg', () {
    final c = parseKnxproj(_knxproj());
    final back = GroupCatalog.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
    expect(back.projectName, 'Testhaus');
    expect(back[parseGroup('2/0/0')!]!.links.length, 2);
    expect(back.devices[parseIndividual('1.1.5')]!.location, 'EG › Küche');
    expect(back[parseGroup('1/1/1')!]!.dpt, const Dpt(1, 1));
  });

  test('keine Projektdatei', () {
    expect(() => parseKnxproj(Uint8List.fromList([1, 2, 3])), throwsFormatException);
  });

  test('Datenpunkttyp über das Kommunikationsobjekt, wenn die Gruppenadresse keinen hat', () {
    final project = _project.replaceFirst(' DatapointType="DPST-9-1"', '');
    // Objekt im Applikationsprogramm nennt den Typ.
    final c = parseKnxproj(
      _knxproj(
        project: project,
        application: _application.replaceFirst('Number="12"', 'Number="12" DatapointType="DPST-9-1"'),
      ),
    );
    expect(c[parseGroup('2/0/0')!]!.dpt, const Dpt(9, 1));

    // Instanz überschreibt; widersprüchliche Objekte → lieber kein Typ.
    final conflicting = parseKnxproj(
      _knxproj(
        project: project.replaceFirst(
          'RefId="O-3_R-3" Links="GA-3"',
          'RefId="O-3_R-3" DatapointType="DPST-5-1" Links="GA-3"',
        ),
        application: _application.replaceFirst('Number="12"', 'Number="12" DatapointType="DPST-9-1"'),
      ),
    );
    expect(conflicting[parseGroup('2/0/0')!]!.dpt, isNull);

    // Liste erlaubter Typen ist keine Angabe.
    final list = parseKnxproj(
      _knxproj(
        project: project,
        application: _application.replaceFirst('Number="12"', 'Number="12" DatapointType="DPST-9-1 DPST-9-2"'),
      ),
    );
    expect(list[parseGroup('2/0/0')!]!.dpt, isNull);
  });

  test('Flags der Kommunikationsobjekte: Instanz vor ComObjectRef vor ComObject', () {
    final c = parseKnxproj(_knxproj());
    final temp = c[parseGroup('2/0/0')!]!.links;
    // Ohne Applikation und ohne Flags an der Instanz: unbekannt.
    expect(temp.first.flags, isNull);
    // ComObject K S Ü, ComObjectRef nimmt Ü weg.
    expect(temp.last.flags, const ComFlags(write: true));
    expect(temp.last.flags!.answersReads, isFalse);
    // ComObjectRef setzt Ü und A dazu.
    final alles = c[parseGroup('1/1/2')!]!.links.last;
    expect(alles.flags, const ComFlags(write: true, transmit: true, update: true));

    // Flags an der Instanz überschreiben die Applikation; ohne K sendet nichts.
    final own = parseKnxproj(
      _knxproj(
        project: _project
            .replaceFirst('RefId="O-12_R-9"', 'RefId="O-12_R-9" ReadFlag="Enabled" TransmitFlag="Enabled"')
            .replaceFirst(
              'RefId="O-3_R-3"',
              'RefId="O-3_R-3" CommunicationFlag="Disabled" ReadFlag="Enabled" WriteFlag="Disabled" '
                  'TransmitFlag="Enabled" UpdateFlag="Disabled"',
            ),
      ),
    );
    final links = own[parseGroup('2/0/0')!]!.links;
    expect(links.last.flags, const ComFlags(read: true, write: true, transmit: true));
    expect(links.last.sends, isTrue);
    // Alle Flags an der Instanz: auch ohne Applikation bekannt.
    expect(links.first.flags, const ComFlags(communication: false, read: true, transmit: true));
    expect(links.first.sends, isFalse);
  });

  test('Flags überstehen JSON, alte Kataloge ohne Flags laden weiter', () {
    final c = parseKnxproj(_knxproj());
    final back = GroupCatalog.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, Object?>);
    expect(back[parseGroup('1/1/2')!]!.links.last.flags, const ComFlags(write: true, transmit: true, update: true));
    expect(back[parseGroup('2/0/0')!]!.links.first.flags, isNull);
    expect(const ComFlags(communication: false).code, '');
    expect(ComFlags.fromCode('CRT'), const ComFlags(read: true, transmit: true));

    final old = GroupLink.fromJson({'d': 4357, 'o': 1, 't': null, 's': true});
    expect(old.flags, isNull);
    expect(old.sends, isTrue);
  });

  test('Flags und Nummern von Objekten aus Modulen (MD-…_M-…_MI-…)', () {
    final project = _project
        .replaceFirst('RefId="O-13_R-1" Links="GA-2"', 'RefId="MD-2_M-2_MI-1_O-2-25_R-1" Links="GA-2"')
        .replaceFirst(
          '</ComObjectInstanceRefs>\n                </DeviceInstance>\n              </Segment>',
          '</ComObjectInstanceRefs><ModuleInstances>'
              '<ModuleInstance Id="MD-2_M-2_MI-1" RefId="MD-2_M-2"><Arguments>'
              '<Argument RefId="MD-2_A-2" Value="87" /><Argument RefId="MD-2_A-3" Value="D" />'
              '</Arguments></ModuleInstance></ModuleInstances></DeviceInstance></Segment>',
        );
    String application({String base = ' BaseNumber="M-0008_A-1_MD-2_A-2"'}) => _application.replaceFirst(
      '</ComObjectRefs>',
      '<ComObject Id="M-0008_A-1_MD-2_O-2-25" Number="25" ReadFlag="Enabled" WriteFlag="Disabled" '
          'CommunicationFlag="Enabled" TransmitFlag="Enabled" UpdateFlag="Disabled"$base />'
          '<ComObjectRef Id="M-0008_A-1_MD-2_O-2-25_R-1" RefId="M-0008_A-1_MD-2_O-2-25" /></ComObjectRefs>',
    );
    final status = parseKnxproj(_knxproj(project: project, application: application())).groups[parseGroup('1/1/2')!]!;
    expect(status.links.last.flags, const ComFlags(read: true, transmit: true));
    expect(status.links.last.sends, isTrue);
    // Nummer im Modul (25) plus Basisnummer der Instanz (87) – nicht die „2“ aus „O-2-25“.
    expect(status.links.last.object, 112);

    // Basisnummer unbekannt: lieber keine Nummer als eine falsche.
    final unknown = parseKnxproj(
      _knxproj(
        project: project,
        application: application(base: ''),
      ),
    );
    expect(unknown[parseGroup('1/1/2')!]!.links.last.object, isNull);
  });

  test('letzter Download: nie programmierte Geräte, nur wenn das Projekt Downloads kennt', () {
    // Ohne LastDownload im ganzen Export: unbekannt, kein Befund.
    final unknown = parseKnxproj(_knxproj());
    expect(unknown.devices.values.where((d) => d.neverProgrammed), isEmpty);

    final project = _project.replaceFirst(
      'Address="5" Description',
      'Address="5" LastDownload="2026-10-17T14:24:40.5856424Z" IndividualAddressLoaded="true" '
          'ApplicationProgramLoaded="true" ParametersLoaded="true" MediumConfigLoaded="true" Description',
    );
    final c = parseKnxproj(_knxproj(project: project));
    expect(c.devices[parseIndividual('1.1.5')]!.neverProgrammed, isFalse);
    // Ohne CommunicationPartLoaded="true": Gruppenadressen noch nicht geladen.
    expect(c.devices[parseIndividual('1.1.5')]!.pendingDownload, [DownloadPart.groups]);
    expect(c.devices[parseIndividual('1.1.18')]!.pendingDownload, isEmpty);
    expect(c.devices[parseIndividual('1.1.18')]!.neverProgrammed, isTrue);
    // Tunnel sind keine Geräte.
    expect(c.devices[parseIndividual('1.1.6')]!.neverProgrammed, isFalse);
    final back = GroupCatalog.fromJson(c.toJson());
    expect(back.devices[parseIndividual('1.1.18')]!.neverProgrammed, isTrue);
  });

  test('Objekt-Referenz wie im XKNX Editor (Applikation + Instanz)', () {
    final c = parseKnxproj(_knxproj());
    final temp = c[parseGroup('2/0/0')!]!.links;
    // 1.1.18 hat eine Applikation, 1.1.5 nicht.
    expect(temp.firstWhere((l) => l.device == parseIndividual('1.1.18')).ref, 'M-0008_A-1_O-12_R-9');
    expect(temp.firstWhere((l) => l.device == parseIndividual('1.1.5')).ref, isNull);
    expect(GroupCatalog.fromJson(c.toJson())[parseGroup('2/0/0')!]!.links.last.ref, 'M-0008_A-1_O-12_R-9');
  });
}
