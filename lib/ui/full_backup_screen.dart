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
import 'form_columns.dart';
import 'telegram_row.dart' show formatDate;

/// Back up and restore everything, in every tier.
class FullBackupScreen extends StatefulWidget {
  const FullBackupScreen({super.key});

  @override
  State<FullBackupScreen> createState() => _FullBackupScreenState();
}

class _FullBackupScreenState extends State<FullBackupScreen> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;
  bool _busy = false;
  late final Future<int> _estimate = FullBackup().estimateBytes();
  late final Future<StorageExtras> _extras = storageExtras();

  static String _size(int bytes) => '${localizeDecimal((bytes / 1024 / 1024).toStringAsFixed(1))} MB';
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

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on BackupException catch (e) {
      if (mounted) {
        setState(
          () => _error = switch (e.message) {
            'newer' => s.backupNewer,
            'tooLarge' => s.backupTooLarge(_size(e.bytes), _size(FullBackup.maxBytes)),
            _ => s.backupOpenFailed,
          },
        );
      }
    } on Object catch (e) {
      debugPrint('Komplettsicherung: $e');
      if (mounted) setState(() => _error = s.actionFailed);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _create() async {
    if (_first.text.length < FullBackup.minPassword) {
      setState(() => _error = s.backupTooShort(FullBackup.minPassword));
      return;
    }
    if (_first.text != _second.text) {
      setState(() => _error = s.backupMismatch);
      return;
    }
    await _run(() async {
      final bytes = await FullBackup().create(_first.text);
      final saved = await FilePicker.saveFile(fileName: FullBackup.fileName, bytes: bytes);
      if (saved == null) return;
      await BackupReminder.markDone();
      await _loadLast();
      if (mounted) showHorizontMessage(context, s.backupSaved, status: HorizontStatus.positive);
    });
  }

  Future<void> _restore() async {
    if (_first.text.isEmpty) {
      setState(() => _error = s.backupTooShort(FullBackup.minPassword));
      return;
    }
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null || !mounted) return;
    final sure =
        await showAdaptiveDialog<bool>(
          context: context,
          builder: (context) => AlertDialog.adaptive(
            title: Text(s.backupRestoreTitle),
            content: Text(s.backupRestoreBody),
            actions: [
              horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
              horizontDialogAction(
                context,
                label: s.backupRestore,
                destructive: true,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ==
        true;
    if (!sure) return;
    await _run(() async {
      try {
        await FullBackup().restore(await file.readAsBytes(), _first.text);
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(s.backupTitle),
        actions: [
          InfoAction(
            title: s.backupTitle,
            text: '${s.backupExplain}\n\n${Betrieb.enabled ? s.backupNotIncludedTeam : s.backupNotIncluded}',
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) => box.maxWidth < Breakpoints.expanded ? _narrow(context) : _wide(context),
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

  List<Widget> _progress(BuildContext context) => [
    if (_busy) ...[
      const LinearProgressIndicator(),
      const SizedBox(height: Gap.item),
      Text(s.backupSlow, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textFaint)),
      const SizedBox(height: Gap.item),
    ],
  ];

  /// Phone and narrow window: everything in one list.
  Widget _narrow(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return ListView(
      padding: Gap.page,
      children: [
        Text(s.backupShort, style: muted),
        const SizedBox(height: Gap.item),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HorizontField(
                label: s.backupPassword,
                child: TextField(controller: _first, obscureText: true),
              ),
              const SizedBox(height: Gap.inner),
              HorizontField(
                label: s.backupRepeat,
                child: TextField(
                  controller: _second,
                  obscureText: true,
                  decoration: InputDecoration(errorText: _error),
                ),
              ),
              const SizedBox(height: Gap.inner),
              ..._progress(context),
              FilledButton(onPressed: _busy ? null : () => unawaited(_create()), child: Text(s.backupCreate)),
            ],
          ),
        ),
        const SizedBox(height: Gap.item),
        OutlinedButton(onPressed: _busy ? null : () => unawaited(_restore()), child: Text(s.backupRestore)),
        const SizedBox(height: Gap.item),
        _figures(),
      ],
    );
  }

  /// From [Breakpoints.expanded]: the file with its password and both actions on the left, the
  /// state of this device and what a backup holds (otherwise behind the info symbol) on the right.
  Widget _wide(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium?.copyWith(color: context.hz.textMuted);
    return FormColumns(
      intro: [Text(s.backupShort, style: muted)],
      columns: [
        [
          SectionHead(s.backupFileHead),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HorizontField(
                  label: s.backupPassword,
                  child: TextField(controller: _first, obscureText: true),
                ),
                const SizedBox(height: Gap.inner),
                HorizontField(
                  label: s.backupRepeat,
                  child: TextField(
                    controller: _second,
                    obscureText: true,
                    decoration: InputDecoration(errorText: _error),
                  ),
                ),
                const SizedBox(height: Gap.inner),
                ..._progress(context),
                Wrap(
                  spacing: Gap.item,
                  runSpacing: Gap.item,
                  children: [
                    FilledButton(onPressed: _busy ? null : () => unawaited(_create()), child: Text(s.backupCreate)),
                    OutlinedButton(onPressed: _busy ? null : () => unawaited(_restore()), child: Text(s.backupRestore)),
                  ],
                ),
              ],
            ),
          ),
        ],
        [
          SectionHead(s.backupDeviceHead),
          _figures(),
          SectionHead(s.handoverContents),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.backupExplain),
                const SizedBox(height: Gap.inner),
                Text(Betrieb.enabled ? s.backupNotIncludedTeam : s.backupNotIncluded, style: muted),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Row with a label and a bold value.
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
