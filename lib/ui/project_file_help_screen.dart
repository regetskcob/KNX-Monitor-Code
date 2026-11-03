import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Opens the help on the project file, also without a connection (connect screen).
Future<void> openProjectFileHelp(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProjectFileHelpScreen()));

/// What a .knxproj, project password and keyring are, how to get them from the
/// electrician, with a sample request to copy.
class ProjectFileHelpScreen extends StatelessWidget {
  const ProjectFileHelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    Widget section(String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: Gap.section),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: HzSpace.s4),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(s.projectHelpTitle)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: ListView(
            padding: Gap.page,
            children: [
              section(s.projectHelpWhatTitle, s.projectHelpWhat),
              section(s.projectHelpPasswordTitle, s.projectHelpPassword),
              section(s.projectHelpKeyringTitle, s.projectHelpKeyring),
              section(s.projectHelpGetTitle, s.projectHelpGet),
              SectionCard(
                title: s.projectHelpTemplateTitle,
                soft: true,
                trailing: IconButton(
                  tooltip: s.projectHelpCopy,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copy(context),
                  icon: const Icon(AppIcons.copy, size: HzIconSize.row),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(s.projectHelpTemplate, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Gap.inner),
                    OutlinedButton.icon(
                      onPressed: () => _copy(context),
                      icon: const Icon(AppIcons.copy, size: 18),
                      label: Text(s.projectHelpCopy),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Gap.section),
              section(s.projectHelpNoneTitle, s.projectHelpNone),
              Text(s.projectHelpDisclaimer, style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: s.projectHelpTemplate));
    messenger.showSnackBar(SnackBar(content: Text(s.projectHelpCopied)));
  }
}
