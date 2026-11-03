import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plan.dart';

/// Chapters of the introduction, one for the features of each tier.
enum TourChapter {
  /// Connect, ETS project, overview, objects, live, health …
  basics(Tier.free),

  /// History, charts, statistics, watchers, export.
  analysis(Tier.plus),

  /// Expert mode with its tools.
  expert(Tier.pro);

  const TourChapter(this.tier);

  /// Tier from which the chapter's features are unlocked.
  final Tier tier;
}

/// Which chapters the introduction shows and which have already been seen.
///
/// Without a purchase channel (Home Assistant add-on, box, Linux) everything is
/// free: the three chapters run as one introduction. In the store apps it shows
/// the chapters up to the user's own tier; above that, a card with what would be
/// added. After an upgrade the new chapter is unseen, the button is highlighted
/// and the introduction starts there.
class TourProgress extends ChangeNotifier {
  TourProgress._();

  static final instance = TourProgress._();
  static const _key = 'tour_seen';

  final _seen = <TourChapter>{};

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _seen
      ..clear()
      ..addAll([
        for (final name in prefs.getStringList(_key) ?? const <String>[]) ?TourChapter.values.asNameMap()[name],
      ]);
    notifyListeners();
  }

  /// Chapters that belong to [tier] (all without a purchase channel).
  static List<TourChapter> chaptersFor(Tier tier, {required bool purchasable}) => [
    for (final c in TourChapter.values)
      if (!purchasable || tier.covers(c.tier)) c,
  ];

  /// Whether there are further chapters above that a higher tier unlocks.
  static bool hasMore(Tier tier, {required bool purchasable}) => purchasable && tier != Tier.pro;

  bool seen(TourChapter chapter) => _seen.contains(chapter);

  /// Chapters of the current tier that have not been seen yet.
  List<TourChapter> unseen(Tier tier, {required bool purchasable}) => [
    for (final c in chaptersFor(tier, purchasable: purchasable))
      if (!_seen.contains(c)) c,
  ];

  /// Marks [chapter] as seen to the end.
  Future<void> markSeen(TourChapter chapter) async {
    if (!_seen.add(chapter)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final c in _seen) c.name]);
  }

  /// For tests: everything unseen again.
  @visibleForTesting
  void reset() {
    _seen.clear();
    notifyListeners();
  }
}
