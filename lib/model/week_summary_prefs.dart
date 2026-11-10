import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the card "Last 7 days" appears in the overview, per device: shown at all, collapsed to
/// its headline, or put away for the current week. Stored on the device, not on the server:
/// hiding it on a tablet must not hide it for everyone else on the same add-on.
class WeekSummaryPrefs extends ChangeNotifier {
  WeekSummaryPrefs._();

  static final instance = WeekSummaryPrefs._();

  static const _showKey = 'week_summary_show';
  static const _collapsedKey = 'week_summary_collapsed';
  static const _hiddenWeekKey = 'week_summary_hidden_week';

  bool _loaded = false;
  bool _show = true;
  bool _collapsed = false;
  String? _hiddenWeek;

  /// Tests: the time the week is taken from.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// The general switch (menu "More").
  bool get show => _show;

  /// Only title and headline.
  bool get collapsed => _collapsed;

  /// Whether the card appears now: switched on, and not put away for this week.
  bool get visible => _show && _hiddenWeek != weekOf(clock());

  /// The week [time] lies in, named by its Monday (`2026-11-09`): a new week brings the card back.
  static String weekOf(DateTime time) {
    final monday = DateTime(time.year, time.month, time.day - (time.weekday - DateTime.monday));
    String two(int n) => n.toString().padLeft(2, '0');
    return '${monday.year}-${two(monday.month)}-${two(monday.day)}';
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _show = prefs.getBool(_showKey) ?? true;
    _collapsed = prefs.getBool(_collapsedKey) ?? false;
    _hiddenWeek = prefs.getString(_hiddenWeekKey);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setShow(bool on) async {
    _show = on;
    // Switched on again means: now, also if it was put away for this week.
    if (on) _hiddenWeek = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showKey, on);
    if (on) await prefs.remove(_hiddenWeekKey);
  }

  Future<void> setCollapsed(bool on) async {
    _collapsed = on;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setBool(_collapsedKey, on);
  }

  /// Away until next Monday.
  Future<void> hideThisWeek() async {
    _hiddenWeek = weekOf(clock());
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(_hiddenWeekKey, _hiddenWeek!);
  }

  @visibleForTesting
  void debugReset() {
    _loaded = false;
    _show = true;
    _collapsed = false;
    _hiddenWeek = null;
    clock = DateTime.now;
  }
}
