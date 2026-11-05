import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/secure/keyring.dart';
import '../knx/secure/keyring_store.dart';
import '../l10n/locale_controller.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'handover_screen.dart' show openPackageFile;
import 'project_file_help_screen.dart';

/// Imports an ETS project (.knxproj) or a group address CSV and reports the
/// result in a snackbar. Asks for the project password if needed.
Future<void> importCatalog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  final navigator = Navigator.of(context);
  final store = CatalogStore.instance;
  // Progress as a dialog while a step is running; closed during the password
  // prompt.
  var progress = false;
  void follow() {
    final running = store.phase.value != null;
    if (running && !progress) {
      progress = true;
      showAdaptiveDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(canPop: false, child: _ImportProgress(phase: store.phase)),
      );
    } else if (!running && progress) {
      progress = false;
      navigator.pop();
    }
  }

  store.phase.addListener(follow);
  try {
    final bool ok;
    try {
      ok = await store.pickAndImport(askPassword: ({required bool wrong}) => _askPassword(context, wrong: wrong));
    } finally {
      store.phase.removeListener(follow);
      if (progress) navigator.pop();
    }
    if (!ok) return;
    final c = store.catalog;
    messenger.showSnackBar(
      horizontMessageSnackBar(
        colors,
        s.catalogImportedSnack(
          [s.groupAddressCount(c.length), if (c.devices.isNotEmpty) s.deviceCount(c.devices.length)].join(' · '),
        ),
        status: HorizontStatus.positive,
      ),
    );
  } on PackageFileChosen catch (e) {
    if (context.mounted) await openPackageFile(context, e.bytes);
  } on FormatException catch (e) {
    messenger.showSnackBar(
      horizontMessageSnackBar(colors, s.catalogImportFailed(e.message), status: HorizontStatus.critical),
    );
  } on Object catch (e) {
    // Unexpectedly structured file: better a message than a silent abort. The
    // FormatExceptions above carry a sentence for the user, this one does not.
    debugPrint('Import fehlgeschlagen: $e');
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.actionFailed, status: HorizontStatus.critical));
  }
}

/// Shows the state of the imported group addresses with an import action.
class CatalogTile extends StatelessWidget {
  const CatalogTile({super.key, this.removable = false, this.onDismiss, this.onTeachIn});

  /// Also offers "Remove" (project menu in the monitor).
  final bool removable;

  /// Close button, e.g. for the hint above the overview.
  final VoidCallback? onDismiss;

  /// Offers "Anlernen" (learn addresses; only when connected).
  final VoidCallback? onTeachIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = CatalogStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, store.busy, LocaleController.instance]),
      builder: (context, _) {
        final loaded = !store.catalog.isEmpty;
        final hasProject = !store.project.isEmpty;
        final learned = store.learned.length;
        final c = store.catalog;
        final info = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project name on top, below it one figure per line.
              Text(
                hasProject
                    ? c.projectName ?? store.fileName ?? s.catalogImported
                    : (loaded ? s.learnSource : s.catalogNone),
                style: theme.textTheme.titleSmall,
              ),
              if (loaded) ...[
                if (c.devices.isNotEmpty)
                  Text(
                    s.deviceCount(c.devices.length),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                  ),
                Text(s.groupAddressCount(c.length), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
                if (hasProject && learned > 0)
                  Text(s.learnCount(learned), style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted)),
              ] else
                Text(
                  onDismiss != null ? s.projectHintRaw : s.catalogHint,
                  style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                ),
            ],
          ),
        );
        final actions = <Widget>[
          if (store.busy.value)
            const Padding(
              padding: EdgeInsets.all(Gap.inner),
              child: SizedBox.square(
                dimension: HzSpace.s24,
                child: CircularProgressIndicator.adaptive(strokeWidth: Lines.selection),
              ),
            )
          else ...[
            if (removable && hasProject) TextButton(onPressed: store.clear, child: Text(s.projectRemove)),
            if (!hasProject)
              IconButton(
                tooltip: s.projectHelpTitle,
                onPressed: () => openProjectFileHelp(context),
                icon: const Icon(AppIcons.help, size: HzIconSize.row),
              ),
            if (onTeachIn != null) TextButton(onPressed: onTeachIn, child: Text(s.learnTitle)),
            TextButton(
              onPressed: () => importCatalog(context),
              child: Text(hasProject ? s.catalogReplace : s.catalogImport),
            ),
          ],
        ];
        final close = onDismiss == null
            ? null
            : IconButton(tooltip: s.commonDismiss, onPressed: onDismiss, icon: const Icon(AppIcons.close, size: 18));
        final icon = Icon(loaded ? AppIcons.project : AppIcons.noProject, color: loaded ? hz.text : hz.textMuted);
        return _TileFrame(
          child: LayoutBuilder(
            // Narrow (phone, card in the installation): buttons below the text,
            // otherwise the title wraps and the hint turns into a column.
            builder: (context, box) => box.maxWidth < 360
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          icon,
                          const SizedBox(width: Gap.inner),
                          info,
                          ?close,
                        ],
                      ),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
                    ],
                  )
                : Row(
                    children: [
                      icon,
                      const SizedBox(width: Gap.inner),
                      info,
                      ...actions,
                      ?close,
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Project menu in the monitor: state, replace, remove.
Future<void> showProjectSheet(BuildContext context, {VoidCallback? onTeachIn}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Gap.gutter, 0, Gap.gutter, Gap.gutter),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.projectTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Gap.inner),
          CatalogTile(
            removable: true,
            onTeachIn: onTeachIn == null
                ? null
                : () {
                    Navigator.pop(context);
                    onTeachIn();
                  },
          ),
          const SizedBox(height: Gap.inner),
          const KeyringTile(),
        ],
      ),
    ),
  ),
);

Future<String?> _askPassword(BuildContext context, {required bool wrong, bool keyring = false}) {
  if (!context.mounted) return Future.value();
  return showAdaptiveDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(wrong: wrong, keyring: keyring),
  );
}

/// Imports an ETS keyring (.knxkeys) for KNX Secure.
Future<void> importKeyring(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final colors = context.hz;
  final file = await FilePicker.pickFile(type: FileType.any);
  if (file == null || !context.mounted) return;
  final String text;
  try {
    text = utf8.decode(await file.readAsBytes());
  } on FormatException {
    messenger.showSnackBar(horizontMessageSnackBar(colors, s.keyringInvalid, status: HorizontStatus.critical));
    return;
  }
  var wrong = false;
  while (true) {
    if (!context.mounted) return;
    final password = await _askPassword(context, wrong: wrong, keyring: true);
    if (password == null) return;
    try {
      await KeyringStore.instance.import(text, password);
      final k = KeyringStore.instance;
      messenger.showSnackBar(
        horizontMessageSnackBar(
          colors,
          s.keyringLoaded(k.project ?? '', k.groupKeyCount, k.tunnels.length),
          status: HorizontStatus.positive,
        ),
      );
      return;
    } on KeyringException catch (e) {
      if (!e.wrongPassword) {
        messenger.showSnackBar(horizontMessageSnackBar(colors, s.keyringInvalid, status: HorizontStatus.critical));
        return;
      }
      wrong = true;
    }
  }
}

/// State of the keyring (KNX Secure) with import/remove.
class KeyringTile extends StatelessWidget {
  const KeyringTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hz = context.hz;
    final store = KeyringStore.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([store, LocaleController.instance]),
      builder: (context, _) => _TileFrame(
        child: Row(
          children: [
            Icon(AppIcons.secure, color: store.loaded ? hz.text : hz.textMuted),
            const SizedBox(width: Gap.inner),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.keyringTitle, style: theme.textTheme.titleSmall),
                  Text(
                    store.loaded
                        ? s.keyringLoaded(store.project ?? '', store.groupKeyCount, store.tunnels.length)
                        // Phone: keep it short so the installations stay
                        // visible.
                        : (MediaQuery.sizeOf(context).width < Breakpoints.medium ? s.keyringNoneShort : s.keyringNone),
                    style: theme.textTheme.bodySmall?.copyWith(color: hz.textMuted),
                  ),
                ],
              ),
            ),
            if (store.loaded) TextButton(onPressed: store.clear, child: Text(s.keyringRemove)),
            TextButton(onPressed: () => importKeyring(context), child: Text(s.catalogImport)),
          ],
        ),
      ),
    );
  }
}

/// Frame of the project and keyring tile: surface with hairline, radius 6 like
/// the fields and buttons next to it.
class _TileFrame extends StatelessWidget {
  const _TileFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hz = context.hz;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: hz.surface,
        border: Border.all(color: hz.line, width: Lines.hairline),
        borderRadius: Radii.tile,
      ),
      child: Padding(padding: const EdgeInsets.fromLTRB(Gap.card, Gap.inner, HzSpace.s8, Gap.inner), child: child),
    );
  }
}

/// Running import: current step and a hint that large projects take a while.
class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.phase});

  final ValueListenable<ImportPhase?> phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: phase,
      builder: (context, p, _) => AlertDialog.adaptive(
        content: Row(
          children: [
            const CircularProgressIndicator.adaptive(),
            const SizedBox(width: Gap.section),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (p) {
                    ImportPhase.reading || null => s.importReading,
                    ImportPhase.opening => s.importOpening,
                    ImportPhase.decrypting => s.importDecrypting,
                    ImportPhase.saving => s.importSaving,
                  }, style: theme.textTheme.titleSmall),
                  const SizedBox(height: HzSpace.s4),
                  Text(s.importSlowHint, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.wrong, this.keyring = false});

  final bool wrong;
  final bool keyring;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: Text(widget.keyring ? s.keyringPassword : s.passwordTitle),
      // Material for the text field in the Cupertino dialog.
      content: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.wrong)
              // Error with icon and word, not just red.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(HorizontStatus.critical.icon, size: 18, color: context.hz.critical),
                  const SizedBox(width: HzSpace.s8),
                  Expanded(
                    child: Text(s.passwordWrong, style: TextStyle(color: context.hz.critical)),
                  ),
                ],
              )
            else
              Text(widget.keyring ? s.keyringPasswordHint : s.passwordPrompt),
            const SizedBox(height: Gap.section),
            HorizontField(
              label: s.passwordLabel,
              child: TextField(
                style: context.hzTheme.field,
                controller: _controller,
                autofocus: true,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  suffixIcon: HorizontFieldIconButton(
                    tooltip: _obscure ? s.passwordShow : s.passwordHide,
                    icon: Icon(_obscure ? AppIcons.show : AppIcons.hide),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
        horizontDialogAction(context, label: s.passwordOpen, primary: true, onPressed: _submit),
      ],
    );
  }
}
