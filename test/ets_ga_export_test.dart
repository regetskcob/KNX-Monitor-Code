import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/export/ets_ga_export.dart';
import 'package:knx_monitor/knx/group_catalog.dart';
import 'package:knx_monitor/knx/telegram.dart';

int ga(int main, int middle, int sub) => (main << 11) | (middle << 8) | sub;

void main() {
  final catalog = GroupCatalog({
    ga(1, 0, 5): GroupInfo(
      address: ga(1, 0, 5),
      name: 'HWR Decke',
      path: 'Beleuchtung › Untergeschoss',
      dpt: const Dpt(1, 1),
    ),
    ga(1, 1, 0): GroupInfo(
      address: ga(1, 1, 0),
      name: 'Flur "Spots" & Garderobe',
      path: 'Beleuchtung › Erdgeschoss',
      description: 'mit Garderobe',
    ),
    ga(4, 0, 2): GroupInfo(address: ga(4, 0, 2), name: 'Helligkeit Süd', path: 'Wetter › Station'),
  });

  test('nur geänderte Typen, mit Name, Beschreibung und Gruppenbereichen aus dem Projekt', () {
    final xml = etsGroupAddressXml(catalog, {
      ga(1, 0, 5): const Dpt(1, 1), // unverändert: nicht in der Datei
      ga(1, 1, 0): const Dpt(1, 1),
      ga(4, 0, 2): const Dpt(9, 4),
    })!;
    expect(xml, contains('<GroupAddress-Export xmlns="http://knx.org/xml/ga-export/01">'));
    expect(xml, isNot(contains('1/0/5')));
    expect(xml, contains('<GroupRange Name="Beleuchtung" RangeStart="2048" RangeEnd="4095">'));
    expect(xml, contains('<GroupRange Name="Erdgeschoss" RangeStart="2304" RangeEnd="2559">'));
    expect(
      xml,
      contains(
        '<GroupAddress Name="Flur &quot;Spots&quot; &amp; Garderobe" Address="1/1/0" '
        'Description="mit Garderobe" DPTs="DPST-1-1" />',
      ),
    );
    expect(xml, contains('<GroupAddress Name="Helligkeit Süd" Address="4/0/2" DPTs="DPST-9-4" />'));
    // Bereiche sauber geschlossen.
    expect('<GroupRange '.allMatches(xml).length, '</GroupRange>'.allMatches(xml).length);
  });

  test('nichts geändert oder nicht dreistufig: keine Datei', () {
    expect(etsGroupAddressXml(catalog, {ga(1, 0, 5): const Dpt(1, 1)}), isNull);
    final twoLevel = GroupCatalog(catalog.groups, style: GroupStyle.twoLevel);
    expect(etsGroupAddressXml(twoLevel, {ga(4, 0, 2): const Dpt(9, 4)}), isNull);
  });

  test('Kennung ohne Subtyp', () {
    expect(etsDptId(const Dpt(9)), 'DPT-9');
    expect(etsDptId(const Dpt(5, 1)), 'DPST-5-1');
  });

  test('neue Adresse ohne Datentyp: ohne DPTs-Attribut, Bereichsnamen als Zahl', () {
    final xml = etsImportXml([
      (address: ga(5, 2, 7), name: 'Garten & Terrasse', dpt: null, description: null, path: null),
    ], GroupStyle.threeLevel)!;
    expect(xml, contains('<GroupAddress Name="Garten &amp; Terrasse" Address="5/2/7" />'));
    expect(xml, contains('<GroupRange Name="5" RangeStart="10240" RangeEnd="12287">'));
    expect(etsImportXml(const [], GroupStyle.threeLevel), isNull);
  });

  test('CSV: Namen, die eine Tabelle als Formel liest, bekommen ein Apostroph, „+“ und „-“ nur als Formel', () {
    final csv = etsImportCsv([
      (address: ga(1, 0, 1), name: '=HYPERLINK("http://x")', dpt: null, description: '@SUM(A1)', path: '=Licht › @OG'),
      (address: ga(1, 0, 2), name: '-1 Keller', dpt: null, description: '+ Zentral', path: 'Licht › @OG'),
      (address: ga(1, 0, 3), name: '+SUM(A1)', dpt: null, description: '-1+1', path: 'Licht › @OG'),
    ], GroupStyle.threeLevel)!;
    final lines = csv.split('\r\n');
    expect(lines[1], startsWith('''"'=Licht"'''));
    expect(lines[2], startsWith('''"","'@OG"'''));
    expect(lines[3], contains('''"'=HYPERLINK(""http://x"")"'''));
    expect(lines[3], contains('''"'@SUM(A1)"'''));
    expect(lines[4], contains('"-1 Keller"'));
    expect(lines[4], contains('"+ Zentral"'));
    // Formula-shaped + and - are escaped as well.
    expect(lines[5], contains('''"'+SUM(A1)"'''));
    expect(lines[5], contains('''"'-1+1"'''));
  });
}
