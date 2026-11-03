import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../export/telegram_files.dart' show utf8Bytes;
import '../l10n/locale_controller.dart';
import '../model/saved_charts.dart';
import '../model/template_gallery.dart';
import '../model/template_rules.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Gallery of shared templates: shipped with the app and searchable.
/// Adopting puts the template into your own library, where it is applied to the
/// project like any imported one. Nothing is fetched or uploaded; submitting
/// means sharing the file yourself.
class TemplateGalleryScreen extends StatefulWidget {
  const TemplateGalleryScreen({super.key, this.bundle});

  /// Source of the templates; tests set their own.
  final AssetBundle? bundle;

  @override
  State<TemplateGalleryScreen> createState() => _TemplateGalleryScreenState();
}

class _TemplateGalleryScreenState extends State<TemplateGalleryScreen> {
  late final Future<List<GalleryTemplate>> _gallery = loadTemplateGallery(bundle: widget.bundle);
  final _search = TextEditingController();

  String get _language => s.localeName.startsWith('de') ? 'de' : 'en';

  @override
  void initState() {
    super.initState();
    unawaited(CustomTemplates.instance.load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _adopt(GalleryTemplate template) async {
    final messenger = ScaffoldMessenger.of(context);
    final rule = template.ruleIn(_language);
    await CustomTemplates.instance.add(rule);
    messenger.showSnackBar(SnackBar(content: Text(s.galleryAdopted(rule.name))));
  }

  /// Submitting: your own charts as a template file via the share menu. Only
  /// roles and the name are included, no addresses and no room.
  Future<void> _submit(Rect? origin) async {
    final store = CatalogStore.instance;
    final charts = SavedCharts.instance.charts;
    final rules = [
      for (final MapEntry(key: name, value: ids) in charts.entries)
        ?ruleFromChart(name, ids, store.catalog.groups, store.catalog.devices, dptOf: store.dptOf).rule,
    ];
    final picked = await showModalBottomSheet<TemplateRule>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: Gap.page,
          children: [
            Text(s.gallerySubmitHint, style: Theme.of(sheet).textTheme.bodyMedium),
            const SizedBox(height: Gap.item),
            if (rules.isEmpty) Text(s.gallerySubmitNone, style: Theme.of(sheet).textTheme.bodyMedium),
            for (final r in rules)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(r.name),
                trailing: Icon(AppIcons.share),
                onTap: () => Navigator.pop(sheet, r),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final json = const JsonEncoder.withIndent('  ').convert(picked.toJson());
    await shareFile(context, utf8Bytes(json), fileName(picked.name, 'json'), 'application/json', origin: origin);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(s.galleryTitle)),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Widths.reading),
        child: FutureBuilder(
          future: _gallery,
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator.adaptive());
            return ListenableBuilder(
              listenable: Listenable.merge([_search, CustomTemplates.instance, CatalogStore.instance]),
              builder: (context, _) => _list(context, snapshot.data!),
            );
          },
        ),
      ),
    ),
  );

  Widget _list(BuildContext context, List<GalleryTemplate> gallery) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final shown = [
      for (final t in gallery)
        if (t.matches(_search.text, _language)) t,
    ];
    return ListView(
      padding: Gap.page,
      children: [
        Text(s.galleryIntro, style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
        const SizedBox(height: Gap.item),
        TextField(
          controller: _search,
          decoration: InputDecoration(labelText: s.gallerySearch, prefixIcon: const Icon(AppIcons.search)),
        ),
        const SizedBox(height: Gap.section),
        if (shown.isEmpty)
          HorizontEmptyHint(icon: AppIcons.search, text: s.galleryNoMatch)
        else
          for (final t in shown) ...[_card(context, t), const SizedBox(height: Gap.item)],
        const SizedBox(height: Gap.item),
        Builder(
          builder: (button) => OutlinedButton.icon(
            onPressed: () => _submit(rectOf(button)),
            icon: Icon(AppIcons.share, size: 18),
            label: Text(s.gallerySubmit),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, GalleryTemplate t) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    final rule = t.ruleIn(_language);
    final matches = applyRule(rule, store.catalog.groups, store.catalog.devices, dptOf: store.dptOf);
    final adopted = CustomTemplates.instance.rules.any((r) => r.name == rule.name);
    return SectionCard(
      title: rule.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t.description(_language), style: theme.textTheme.bodyMedium),
          const SizedBox(height: HzSpace.s4),
          Text(
            matches.isEmpty ? s.galleryFitsNothing : s.galleryFits(matches.length),
            style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
          ),
          const SizedBox(height: Gap.item),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: adopted
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: HzSpace.s4,
                    children: [
                      Icon(AppIcons.check, size: HzIconSize.inline, color: hz.textMuted),
                      Text(s.chartTemplateAdopted, style: theme.textTheme.labelLarge?.copyWith(color: hz.textMuted)),
                    ],
                  )
                : TextButton.icon(
                    onPressed: () => _adopt(t),
                    icon: const Icon(AppIcons.add),
                    label: Text(s.chartTemplateAdopt),
                  ),
          ),
        ],
      ),
    );
  }
}
