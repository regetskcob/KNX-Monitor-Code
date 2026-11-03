import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// Hält die gewählte App-Sprache (Deutsch/Englisch) und speichert sie lokal.
///
/// Ohne [load] bleibt Deutsch aktiv – so sind Tests unabhängig von der
/// Systemsprache.
class LocaleController extends ChangeNotifier {
  LocaleController._();

  static final instance = LocaleController._();

  static const _key = 'app_language';
  static const supported = ['de', 'en'];

  Locale _locale = const Locale('de');

  Locale get locale => _locale;

  /// Gespeicherte Wahl, sonst Systemsprache, falls Englisch, sonst Deutsch.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    final system = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    final code = supported.contains(saved) ? saved! : (system == 'en' ? 'en' : 'de');
    _apply(Locale(code));
  }

  /// Wechselt die Sprache und merkt sie sich.
  Future<void> setLocale(Locale locale) async {
    final code = supported.contains(locale.languageCode) ? locale.languageCode : 'de';
    _apply(Locale(code));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, code);
  }

  /// Setzt die Sprache ohne zu speichern (Tests, Hintergrund-Isolates).
  void debugSetLocale(Locale locale) => _apply(locale);

  void _apply(Locale locale) {
    if (locale == _locale) return;
    _locale = locale;
    notifyListeners();
  }
}

final _cache = <String, AppLocalizations>{};

/// Übersetzte Texte der aktuellen Sprache – auch außerhalb von Widgets
/// (Modelle, PDF-Export, DPT-Dekodierung, Fehlermeldungen).
AppLocalizations get s {
  final locale = LocaleController.instance.locale;
  return _cache[locale.languageCode] ??= lookupAppLocalizations(locale);
}

/// Dezimaltrennzeichen der aktuellen Sprache („,“ bzw. „.“).
String get decimalSeparator => s.localeName.startsWith('de') ? ',' : '.';

/// Tausendertrennzeichen der aktuellen Sprache („.“ bzw. „,“).
String get thousandsSeparator => s.localeName.startsWith('de') ? '.' : ',';

final _plainNumber = RegExp(r'^(-?)(\d+)(\.\d+)?$');

/// Ersetzt den Dezimalpunkt von [formatted] durch das Trennzeichen der Sprache
/// und gruppiert reine Zahlen ab 1000 in Tausender („14.612,48“).
String localizeDecimal(String formatted) {
  final m = _plainNumber.firstMatch(formatted);
  if (m == null) return formatted.replaceAll('.', decimalSeparator);
  final fraction = m.group(3)?.replaceFirst('.', decimalSeparator) ?? '';
  return '${m.group(1)}${_group(m.group(2)!)}$fraction';
}

/// Ganzzahl mit Tausendertrennzeichen („1.524“).
String formatInt(int v) => v < 0 ? '-${_group('${-v}')}' : _group('$v');

String _group(String digits) {
  if (digits.length <= 3) return digits;
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(thousandsSeparator);
    out.write(digits[i]);
  }
  return out.toString();
}
