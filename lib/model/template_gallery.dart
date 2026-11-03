import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'template_rules.dart';

/// A gallery template: an ordinary template file ([TemplateRule]) with an
/// additional `gallery` block (texts in both languages, keywords). Roles instead
/// of addresses; it is applied to the project like any other.
@immutable
class GalleryTemplate {
  const GalleryTemplate({
    required this.id,
    required this.rule,
    required this.titles,
    required this.descriptions,
    this.tags = const [],
  });

  final String id;
  final TemplateRule rule;

  /// Language → text.
  final Map<String, String> titles;
  final Map<String, String> descriptions;
  final List<String> tags;

  /// Title in [language], or the template's name as a fallback.
  String title(String language) => titles[language] ?? rule.name;

  String description(String language) => descriptions[language] ?? '';

  /// The template under its title in [language], for adopting.
  TemplateRule ruleIn(String language) =>
      TemplateRule(name: title(language), series: rule.series, perRoom: rule.perRoom);

  bool matches(String query, String language) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [title(language), description(language), ...tags].any((text) => text.toLowerCase().contains(q));
  }

  /// `null` if the file is not a usable template.
  static GalleryTemplate? tryParse(String id, String text) {
    try {
      final json = jsonDecode(text);
      final rule = TemplateRule.fromJson(json);
      final gallery = (json as Map)['gallery'];
      Map<String, String> texts(Object? o) => {
        if (o is Map)
          for (final MapEntry(:key, :value) in o.entries)
            if (key is String && value is String) key: value,
      };
      return GalleryTemplate(
        id: id,
        rule: rule,
        titles: gallery is Map ? texts(gallery['title']) : const {},
        descriptions: gallery is Map ? texts(gallery['description']) : const {},
        tags: gallery is Map ? [...((gallery['tags'] as List?) ?? const []).whereType<String>()] : const [],
      );
    } on Object catch (e) {
      debugPrint('Galerie: $id übersprungen: $e');
      return null;
    }
  }
}

/// Folder of the bundled templates; `index.json` lists the files.
const galleryAssets = 'assets/templates';

/// Reads the gallery from the app's assets. There is deliberately no network
/// fetch: without an account and purchase the app transmits no data. Whatever
/// is missing or broken is dropped; at worst the gallery stays empty.
Future<List<GalleryTemplate>> loadTemplateGallery({AssetBundle? bundle}) async {
  final assets = bundle ?? rootBundle;
  try {
    final names = (jsonDecode(await assets.loadString('$galleryAssets/index.json')) as List).whereType<String>();
    return [for (final name in names) ?await _entry(assets, name)];
  } on Object catch (e) {
    debugPrint('Galerie nicht lesbar: $e');
    return const [];
  }
}

Future<GalleryTemplate?> _entry(AssetBundle assets, String name) async {
  try {
    return GalleryTemplate.tryParse(name.replaceFirst('.json', ''), await assets.loadString('$galleryAssets/$name'));
  } on Object catch (e) {
    debugPrint('Galerie: $name fehlt: $e');
    return null;
  }
}
