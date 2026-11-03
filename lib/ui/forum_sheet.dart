import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../catalog_store.dart';
import '../export/forum_package.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Text snippet for the KNX-User-Forum from a selection: BBCode or Markdown,
/// names replaced on request, copied to the clipboard.
Future<void> showForumSheet(BuildContext context, List<Telegram> telegrams, {String? connection}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (context, controller) =>
            ForumPanel(telegrams: telegrams, connection: connection, scrollController: controller),
      ),
    );

class ForumPanel extends StatefulWidget {
  const ForumPanel({super.key, required this.telegrams, this.connection, this.scrollController});

  final List<Telegram> telegrams;
  final String? connection;
  final ScrollController? scrollController;

  @override
  State<ForumPanel> createState() => _ForumPanelState();
}

class _ForumPanelState extends State<ForumPanel> {
  ForumFormat _format = ForumFormat.bbcode;
  bool _pseudonymize = true;
  String? _version;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _version = p.version);
    }, onError: (Object _) {});
  }

  String _text() {
    final store = CatalogStore.instance;
    return ForumPackage.build(
      telegrams: widget.telegrams,
      catalog: store.catalog,
      format: _format,
      pseudonymize: _pseudonymize,
      connection: widget.connection,
      appVersion: _version,
      value: store.value,
      dptOf: store.dptOf,
    );
  }

  void _copy() {
    final messenger = ScaffoldMessenger.of(context);
    Clipboard.setData(ClipboardData(text: _text()));
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(s.forumCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final text = _text();
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.bottom),
      children: [
        Text(s.forumTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: HzSpace.s4),
        Text(s.forumExplain(widget.telegrams.length), style: theme.textTheme.bodyMedium?.copyWith(color: hz.textMuted)),
        const SizedBox(height: Gap.inner),
        SegmentedButton<ForumFormat>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ForumFormat.bbcode, label: Text('BBCode')),
            ButtonSegment(value: ForumFormat.markdown, label: Text('Markdown')),
          ],
          selected: {_format},
          onSelectionChanged: (v) => setState(() => _format = v.first),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(s.forumPseudonymize),
          subtitle: SwitchHint(s.forumPseudonymizeHint),
          value: _pseudonymize,
          onChanged: (v) => setState(() => _pseudonymize = v),
        ),
        const SizedBox(height: Gap.item),
        FilledButton.icon(onPressed: _copy, icon: const Icon(AppIcons.copy, size: 18), label: Text(s.forumCopy)),
        const SizedBox(height: Gap.inner),
        Kennung(s.forumPreview),
        const SizedBox(height: Gap.item),
        SectionCard(soft: true, child: SelectableText(text, style: context.hzTheme.data.copyWith(fontSize: 12))),
      ],
    );
  }
}
