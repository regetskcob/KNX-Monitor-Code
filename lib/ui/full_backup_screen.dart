import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../model/app_lock.dart';
import '../model/betrieb_mode.dart';
import '../model/customer.dart';
import '../model/full_backup.dart';
import '../model/installation.dart';
import '../platform/storage.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'telegram_row.dart' show formatDate;

/// Back up and restore everything, in every tier.
class FullBackupScreen extends StatefulWidget {
  const FullBackupScreen({super.key});

  @override
  State<FullBackupScreen> createState() => _FullBackupScreenState();
}

class _FullBackupScreenState extends State<FullBackupScreen> {
  late final Future<int> _estimate = FullBackup().estimateBytes();
  late final Future<StorageExtras> _extras = storageExtras();
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLast());
  }

  Future<void> _loadLast() async {
    final last = await BackupReminder.lastBackup();
    if (mounted) setState(() => _last = last);
  }

  /// Both tasks run as wizards: creating asks for the password after showing what goes in,
  /// restoring replaces what is on the device and says so before its last step.
  Future<void> _create() async {
    final done = await showHorizontWizard(context, _CreateWizard(estimate: _estimate));
    if (!done || !mounted) return;
    await _loadLast();
    if (mounted) showHorizontMessage(context, s.backupSaved, status: HorizontStatus.positive);
  }

  Future<void> _restore() => showHorizontWizard(context, const _RestoreWizard());

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return Scaffold(
      appBar: AppBar(title: Text(s.backupTitle)),
      body: ListView(
        padding: Gap.page,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Widths.reading),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.backupShort, style: muted),
                  SectionHead(s.backupDeviceHead),
                  _figures(),
                  SectionHead(s.handoverContents),
                  SectionCard(child: _BackupContents(muted: muted)),
                  const SizedBox(height: Gap.section),
                  Wrap(
                    spacing: Gap.item,
                    runSpacing: Gap.item,
                    children: [
                      FilledButton(onPressed: () => unawaited(_create()), child: Text(s.backupCreate)),
                      OutlinedButton(onPressed: () => unawaited(_restore()), child: Text(s.backupRestore)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// App storage, older versions and the date of the last backup.
  Widget _figures() => FutureBuilder(
    future: Future.wait<Object>([_estimate, _extras]),
    builder: (context, snapshot) {
      final bytes = snapshot.data?[0] as int?;
      final extras = snapshot.data?[1] as StorageExtras?;
      final side = extras == null ? 0 : extras.previousBytes + extras.corruptBytes;
      return RowCard(
        children: [
          if (bytes != null) _Figure(label: s.backupAppStorage, value: _size(bytes)),
          // Older and damaged versions only when they take up space.
          if (side > 0) _Figure(label: s.backupPrevious, value: _size(side)),
          _Figure(label: s.backupLastRow, value: _last == null ? s.backupNoneYet : formatDate(_last!)),
        ],
      );
    },
  );
}

String _size(int bytes) => '${localizeDecimal((bytes / 1024 / 1024).toStringAsFixed(1))} MB';

/// What went wrong, in the user's words.
String _backupError(Object e) {
  if (e is BackupException) {
    return switch (e.message) {
      'newer' => s.backupNewer,
      'tooLarge' => s.backupTooLarge(_size(e.bytes), _size(FullBackup.maxBytes)),
      _ => s.backupOpenFailed,
    };
  }
  debugPrint('Komplettsicherung: $e');
  return s.actionFailed;
}

/// What a backup holds and what it leaves out.
class _BackupContents extends StatelessWidget {
  const _BackupContents({required this.muted});

  final TextStyle? muted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(s.backupExplain),
      const SizedBox(height: Gap.inner),
      Text(Betrieb.enabled ? s.backupNotIncludedTeam : s.backupNotIncluded, style: muted),
    ],
  );
}

/// "Sicherung erstellen" (create backup): what goes in, then the password, then the file.
class _CreateWizard extends StatefulWidget {
  const _CreateWizard({required this.estimate});

  final Future<int> estimate;

  @override
  State<_CreateWizard> createState() => _CreateWizardState();
}

class _CreateWizardState extends State<_CreateWizard> {
  final _first = TextEditingController();
  final _second = TextEditingController();

  @override
  void initState() {
    super.initState();
    _first.addListener(_changed);
    _second.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<String?> _create() async {
    if (_first.text.length < FullBackup.minPassword) return s.backupTooShort(FullBackup.minPassword);
    if (_first.text != _second.text) return s.backupMismatch;
    try {
      final bytes = await FullBackup().create(_first.text);
      final saved = await FilePicker.saveFile(fileName: FullBackup.fileName, bytes: bytes);
      if (saved == null) return s.backupNotSaved;
      await BackupReminder.markDone();
      return null;
    } on Object catch (e) {
      return _backupError(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return HorizontWizard(
      title: s.backupCreate,
      // Short: the wizard's foot holds "Back" beside it, also on a narrow phone.
      finishLabel: s.backupCreateShort,
      stepOf: s.wizardStepOf,
      steps: [
        HorizontWizardStep(
          title: s.handoverContents,
          subtitle: s.backupShort,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BackupContents(muted: muted),
              const SizedBox(height: Gap.section),
              FutureBuilder(
                future: widget.estimate,
                builder: (context, snapshot) => switch (snapshot.data) {
                  final bytes? => RowCard(
                    children: [_Figure(label: s.backupAppStorage, value: _size(bytes))],
                  ),
                  null => const SizedBox.shrink(),
                },
              ),
            ],
          ),
        ),
        HorizontWizardStep(
          title: s.backupPassword,
          subtitle: s.backupPasswordHint,
          canContinue: _first.text.isNotEmpty && _second.text.isNotEmpty,
          onContinue: _create,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HorizontField(
                label: s.backupPassword,
                child: TextField(controller: _first, obscureText: true, autofocus: true),
              ),
              const SizedBox(height: Gap.inner),
              HorizontField(
                label: s.backupRepeat,
                child: TextField(controller: _second, obscureText: true),
              ),
              const SizedBox(height: Gap.inner),
              Text(s.backupSlow, style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Sicherung einspielen" (restore backup): the file, its password, then the step that replaces
/// what is on this device. The app ends after it.
class _RestoreWizard extends StatefulWidget {
  const _RestoreWizard();

  @override
  State<_RestoreWizard> createState() => _RestoreWizardState();
}

class _RestoreWizardState extends State<_RestoreWizard> {
  final _password = TextEditingController();
  PlatformFile? _file;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file != null && mounted) setState(() => _file = file);
  }

  Future<String?> _restore() async {
    try {
      try {
        await FullBackup().restore(await _file!.readAsBytes(), _password.text);
      } on BackupException catch (e) {
        if (e.message != 'partial') rethrow;
        // Part of the files is new already: continuing would save the old state
        // over them. Say so, then restart like after a complete restore.
        if (mounted) {
          await showAdaptiveDialog<void>(
            context: context,
            builder: (context) => AlertDialog.adaptive(
              title: Text(s.backupRestorePartialTitle),
              content: Text(s.backupRestorePartial(e.bytes)),
              actions: [
                horizontDialogAction(
                  context,
                  label: s.commonClose,
                  primary: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          );
        }
      }
      exit(0);
    } on Object catch (e) {
      return _backupError(e);
    }
  }

  @override
  Widget build(BuildContext context) => HorizontWizard(
    title: s.backupRestore,
    finishLabel: s.backupRestoreShort,
    stepOf: s.wizardStepOf,
    steps: [
      HorizontWizardStep(
        title: s.backupFileHead,
        subtitle: s.backupRestoreFileHint,
        canContinue: _file != null,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            OutlinedButton(onPressed: () => unawaited(_pick()), child: Text(s.backupPickFile)),
            if (_file case final file?) ...[
              const SizedBox(height: Gap.inner),
              HorizontStatusLine(HorizontStatus.positive, file.name),
            ],
          ],
        ),
      ),
      HorizontWizardStep(
        title: s.backupPassword,
        subtitle: s.backupRestorePasswordHint,
        canContinue: _password.text.isNotEmpty,
        content: HorizontField(
          label: s.backupPassword,
          child: TextField(controller: _password, obscureText: true, autofocus: true),
        ),
      ),
      HorizontWizardStep(
        title: s.backupRestoreTitle,
        subtitle: _file?.name,
        onContinue: _restore,
        content: HorizontNotice(HorizontStatus.warning, child: Text(s.backupRestoreBody)),
      ),
    ],
  );
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final figure = Text(
      value,
      style: context.figures(Theme.of(context).textTheme.bodyLarge).copyWith(fontWeight: FontWeight.w600),
    );
    // With large text label and value do not fit side by side on a phone: the value moves below.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 420 && MediaQuery.textScalerOf(context).scale(1) > 1.3
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.inner, vertical: Gap.item),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyLarge),
                  figure,
                ],
              ),
            )
          : CardRow(title: label, trailing: figure),
    );
  }
}

/// Unobtrusive backup reminder on the connect screen. No dialog, blocks
/// nothing, can be dismissed.
class BackupReminderNotice extends StatefulWidget {
  const BackupReminderNotice({super.key});

  @override
  State<BackupReminderNotice> createState() => _BackupReminderNoticeState();
}

class _BackupReminderNoticeState extends State<BackupReminderNotice> {
  bool _due = false;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  Future<void> _check() async {
    // Backup is offered wherever the menu offers it too.
    if (!AppLock.instance.available) return;
    try {
      final due = await BackupReminder.check(
        hasCustomerRecords: CustomerStore.instance.hasRecords,
        installations: InstallationStore.instance.list.length,
      );
      if (mounted) setState(() => _due = due);
    } on Object catch (e) {
      debugPrint('Sicherung: Erinnerung: $e');
    }
  }

  Future<void> _open() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const FullBackupScreen()));
    await _check();
  }

  Future<void> _dismiss() async {
    setState(() => _due = false);
    await BackupReminder.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (!_due) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.section),
      child: HorizontNotice(
        HorizontStatus.info,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.backupReminder),
            Wrap(
              spacing: Gap.item,
              children: [
                TextButton(onPressed: _open, child: Text(s.backupReminderOpen)),
                TextButton(onPressed: _dismiss, child: Text(s.backupReminderDismiss)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
