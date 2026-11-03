import 'package:flutter/widgets.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_icons.dart';
import 'alarms.dart';

/// Section by measured quantity instead of ETS main group.
class _TypeSection {
  const _TypeSection(this.id, this.title, this.icon, this.matches);

  /// Language-independent identifier (for the saved collapsed state).
  final String id;
  final String Function() title;
  final IconData icon;
  final bool Function(GroupInfo info, Dpt? dpt, String text) matches;
}

bool _dpt(Dpt? d, int main, [List<int>? subs]) => d != null && d.main == main && (subs == null || subs.contains(d.sub));

final _weatherWords = RegExp(
  r'wetter|weather|wind|regen|rain|niederschlag|precipitation|sturm|storm|frost|dämmerung|daemmerung|twilight|'
  r'sonne|sun|azimut|azimuth|elevation',
);

/// "Außen" (outside) alone is not enough (outdoor light!) – only with temperature/humidity.
final _outdoorWords = RegExp(r'außen|aussen|outdoor|outside');
final _energyWords = RegExp(
  r'verbrauch|zähler|zaehler|energie|leistung|wirkleistung|strom|power|energy|consumption|meter|kwh|photovoltaik|\bpv\b|'
  r'solar|wallbox|einspeisung|bezug|grid|feed-in|voltage|spannung',
);

final _valveWords = RegExp(r'ventil|valve|stellgr|stellwert|stellantrieb|actuator|actuating');

/// Measured quantities with their own section – placed before the ETS main
/// groups. Order = priority: the first matching rule wins.
final _typeSections = [
  _TypeSection('alarms', () => s.boardAlarms, AppIcons.alarm, (info, d, text) => alarmKindOf(info) != null),
  _TypeSection(
    'brightness',
    () => s.boardBrightness,
    AppIcons.brightness,
    (info, d, text) => _dpt(d, 9, [4]) || _dpt(d, 7, [13]),
  ),
  _TypeSection(
    'weather',
    () => s.boardWeather,
    AppIcons.weather,
    (info, d, text) =>
        _dpt(d, 9, [5, 28]) ||
        (_weatherWords.hasMatch(text) && !_dpt(d, 3)) ||
        (_outdoorWords.hasMatch(text) && _dpt(d, 9, [1, 7])),
  ),
  _TypeSection(
    'energy',
    () => s.boardEnergy,
    AppIcons.energy,
    (info, d, text) =>
        _dpt(d, 13, [10, 11, 12, 13, 14, 15, 16]) ||
        _dpt(d, 14, [19, 27, 33, 56, 57]) ||
        _dpt(d, 9, [20, 21, 24]) ||
        ((_dpt(d, 12) || _dpt(d, 13) || _dpt(d, 14) || _dpt(d, 7)) && _energyWords.hasMatch(text)),
  ),
  // "Ventil-Zustand" (valve state) is often in the same main group as the
  // temperatures, but is a switching state or control value.
  _TypeSection(
    'valves',
    () => s.boardValves,
    AppIcons.valve,
    (info, d, text) => _valveWords.hasMatch(text) && (d == null || d.main == 1 || d.main == 5),
  ),
  _TypeSection(
    'datetime',
    () => s.boardDateTime,
    AppIcons.dateTime,
    (info, d, text) => _dpt(d, 10) || _dpt(d, 11) || _dpt(d, 19),
  ),
];

/// Section of the overview for a group address: measured quantity (brightness,
/// weather, energy, date & time) or ETS main group.
///
/// [id] is language-independent (for the saved collapsed state).
({String id, String title, IconData? icon}) sectionFor(int address) {
  // Remember the assignment per address – the rules (regex) are too expensive for every frame.
  final key = (CatalogStore.instance.catalog, LocaleController.instance.locale);
  if (!identical(_cacheKey?.$1, key.$1) || _cacheKey?.$2 != key.$2) {
    _cache.clear();
    _cacheKey = key;
  }
  return _cache[address] ??= _computeSection(address);
}

final _cache = <int, ({String id, String title, IconData? icon})>{};
(GroupCatalog, Locale)? _cacheKey;

({String id, String title, IconData? icon}) _computeSection(int address) {
  final info = CatalogStore.instance.info(address);
  if (info != null) {
    final text = '${info.name} ${info.path ?? ''}'.toLowerCase();
    for (final section in _typeSections) {
      if (section.matches(info, info.dpt, text)) {
        return (id: 'type:${section.id}', title: section.title(), icon: section.icon);
      }
    }
  }
  final main = (address >> 11) & 0x1F;
  return (id: 'main:$main', title: info?.path?.split(' › ').first ?? s.boardMainGroup(main), icon: null);
}

/// Order of the measured-quantity sections (before the ETS main groups).
List<String> get typeSectionIds => [for (final t in _typeSections) 'type:${t.id}'];
