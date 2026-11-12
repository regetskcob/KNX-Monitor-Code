import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/locale_controller.dart';
import '../model/box_connection.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'telegram_row.dart' show formatDate;

final _previousName = RegExp(r'^\d{8}-\d{6}(-\d{1,3})?$');
final _safeFileName = RegExp(r'^[A-Za-z0-9._-]{1,100}\.zip$');

/// File name of a box backup. The app makes it itself: a name from the box's answer could hold
/// `../` and write anywhere (security review 11.11.). [box] is the box's label, [previous] the
/// name of an earlier state.
String boxBackupFileName({String? box, String? previous, required DateTime now}) {
  String two(int v) => v.toString().padLeft(2, '0');
  if (previous != null && _previousName.hasMatch(previous)) return 'busclear-box-vorher-$previous.zip';
  final slug = (box ?? '')
      .replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  final short = slug.length > 30 ? slug.substring(0, 30) : slug;
  final name =
      'busclear-box-sicherung${short.isEmpty ? '' : '-$short'}-'
      '${now.year}-${two(now.month)}-${two(now.day)}-${two(now.hour)}${two(now.minute)}.zip';
  return _safeFileName.hasMatch(name) ? name : 'busclear-box-sicherung.zip';
}

/// Size for progress texts: "840 KB", "12,4 MB", "1,53 GB".
String backupSize(int bytes) {
  const mb = 1024 * 1024;
  if (bytes < mb) return '${(bytes / 1024).ceil()} KB';
  if (bytes < 1024 * mb) return '${localizeDecimal((bytes / mb).toStringAsFixed(1))} MB';
  return '${localizeDecimal((bytes / mb / 1024).toStringAsFixed(2))} GB';
}

/// What the backup screen does with the box and the device's files; replaced in tests.
class BoxBackupClient {
  const BoxBackupClient();

  Future<Map<String, Object?>> status() => Addon.backupStatus();

  Future<Map<String, Object?>> prepare({String? password, String? previous}) =>
      Addon.prepareBackup(password: password, previous: previous);

  Future<void> download(
    String ticket,
    String path, {
    void Function(int bytes)? onProgress,
    bool Function()? cancelled,
  }) => Addon.downloadBackup(ticket, path, onProgress: onProgress, cancelled: cancelled);

  /// Lets the user pick a backup and uploads it, streamed; `null` if nothing was picked.
  /// [onStart] runs once the file is chosen, before the upload.
  Future<Map<String, Object?>?> pickAndUpload({void Function()? onStart, void Function(int bytes)? onProgress}) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return null;
    onStart?.call();
    return Addon.uploadBackup(file.readAsByteStream(), await file.length(), onProgress: onProgress);
  }

  Future<Map<String, Object?>> apply({
    required String stage,
    String? password,
    bool withoutSecrets = false,
    String? current,
  }) => Addon.applyBackup(stage: stage, password: password, withoutSecrets: withoutSecrets, current: current);

  Future<void> discard() => Addon.discardBackup();

  Future<void> deletePrevious(String name) => Addon.deletePreviousState(name);

  /// Label of the connected box, for the file name.
  String? get boxLabel => BoxConnection.instance.saved?.label;

  /// Whether passwords and the file would go through a network in plain text: HTTP to anything
  /// but the box Wi-Fi's own address or this computer.
  bool get plainNetwork {
    final url = Addon.box?.url;
    return url != null &&
        url.scheme == 'http' &&
        !const {'10.42.0.1', 'localhost', '127.0.0.1', '::1', '[::1]'}.contains(url.host);
  }

  /// Where the download goes before it is handed on.
  Future<String> temporaryPath(String fileName) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/box-backup');
    // A backup left from earlier holds the history: remove it before the next one.
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    return '${dir.path}/$fileName';
  }

  /// Hands the downloaded [file] to the user: phones and tablets through the share sheet
  /// ("Save to Files", a drive), the desktop into a folder the user picks. The file is never read
  /// into memory, and removed afterwards. Returns where it went on the desktop, `''` after
  /// sharing, `null` if cancelled.
  Future<String?> deliver(File file, String name, {Rect? origin}) async {
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'application/zip', name: name)],
            sharePositionOrigin: origin,
          ),
        );
        return result.status == ShareResultStatus.dismissed ? null : '';
      }
      final dir = await FilePicker.getDirectoryPath(dialogTitle: s.boxBackupChooseFolder);
      if (dir == null) return null;
      var target = File('$dir/$name');
      for (var n = 2; await target.exists(); n++) {
        target = File('$dir/${name.replaceFirst(RegExp(r'\.zip$'), '')} ($n).zip');
      }
      await file.copy(target.path);
      return target.path;
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}

/// State of one section of the screen: what runs, what went wrong, what came out. Shown right
/// above the section's buttons, where the user tapped.
class _Status {
  String? progress;
  double? fraction;
  String? error;
  String? done;
  bool warn = false;

  /// A download is running and can be stopped.
  bool cancellable = false;

  void clear() {
    cancellable = false;
    progress = null;
    fraction = null;
    error = null;
    done = null;
    warn = false;
  }
}

/// Backup of the whole box and the way back (server `box_backup.dart`, docs/backup-format.md):
/// create a backup (optionally with the KNX Secure keys, encrypted), restore one on this box after
/// a confirmation, and manage the states a restore set aside. Admin only; the box checks that too.
class BoxBackupScreen extends StatefulWidget {
  const BoxBackupScreen({super.key, this.client = const BoxBackupClient()});

  final BoxBackupClient client;

  @override
  State<BoxBackupScreen> createState() => _BoxBackupScreenState();
}

class _BoxBackupScreenState extends State<BoxBackupScreen> {
  Map<String, Object?>? _status;
  Map<String, Object?>? _staged;
  String? _loadError;
  bool _tooOld = false;
  bool _withKeys = true;
  bool _cancel = false;
  bool _left = false;
  String? _passwordError;
  String? _restorePasswordError;
  String? _currentError;
  final _create = _Status();
  final _restore = _Status();
  final _previous = _Status();
  final _createKey = GlobalKey();
  final _restoreKey = GlobalKey();
  final _previousKey = GlobalKey();
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _restorePassword = TextEditingController();
  final _current = TextEditingController();

  BoxBackupClient get _client => widget.client;
  int get _min => (_status?['minPassword'] as num?)?.toInt() ?? 12;
  bool get _busy => _create.progress != null || _restore.progress != null || _previous.progress != null;
  bool get _readOnly => _status?['readOnly'] == true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    // A running download stops, and no share sheet opens after leaving.
    _left = true;
    for (final c in [_first, _second, _restorePassword, _current]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await _client.status();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadError = null;
        _staged = (status['staged'] as Map?)?.cast<String, Object?>() ?? _staged;
      });
    } on AddonException catch (e) {
      if (!mounted) return;
      setState(() {
        // An older box has no /api/backup.
        _tooOld = e.status == HttpStatus.notFound;
        _loadError = _tooOld ? s.boxBackupTooOld : _message(e);
      });
    }
  }

  String _message(AddonException e) => switch (e.problem) {
    'backupPassword' => s.boxBackupWrongPassword,
    'passwordShort' => s.boxBackupPasswordShort(_min),
    'passwordMissing' => s.boxBackupPasswordMissing,
    'mismatch' => s.boxBackupPasswordMismatch,
    'readOnly' => s.boxBackupReadOnly,
    'space' => s.boxBackupNoSpace,
    'tooLarge' => s.boxBackupTooLarge,
    'newer' => s.boxBackupNewer,
    'busy' => s.boxBackupBusy,
    'stage' => s.boxBackupStageGone,
    'ticket' => s.boxBackupTicket,
    'tampered' => s.boxBackupTampered,
    'tooMany' => s.boxTooManyAttempts,
    'invalid' => s.boxBackupInvalid,
    'cancelled' => s.boxBackupCancelled,
    _ => e.message,
  };

  void _show(GlobalKey key) => WidgetsBinding.instance.addPostFrameCallback((_) {
    final target = key.currentContext;
    if (target != null && target.mounted) unawaited(Scrollable.ensureVisible(target, alignment: 0.3));
  });

  /// Runs [job] for the section [status] ([key]); errors end up there, and the section scrolls
  /// into view when it is done.
  Future<void> _run(_Status status, GlobalKey key, String progress, Future<void> Function() job) async {
    setState(() {
      for (final st in [_create, _restore, _previous]) {
        st.clear();
      }
      status.progress = progress;
    });
    try {
      await job();
    } on AddonException catch (e) {
      if (mounted) setState(() => status.error = _message(e));
    } on Object catch (e) {
      debugPrint('Box-Sicherung: $e');
      if (mounted) setState(() => status.error = s.actionFailed);
    }
    if (!mounted) return;
    setState(() {
      status
        ..progress = null
        ..fraction = null
        ..cancellable = false;
    });
    _show(key);
  }

  Future<bool> _ask(String title, String body, String action, {bool destructive = false}) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(title),
          content: Text(body),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: action,
              destructive: destructive,
              primary: !destructive,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ==
      true;

  /// On plain HTTP outside the box Wi-Fi: ask before passwords or keys go over the network.
  Future<bool> _plainOk() async =>
      !_client.plainNetwork || await _ask(s.boxBackupPlainTitle, s.boxBackupPlainBody, s.boxBackupPlainGo);

  Future<void> _download({
    String? password,
    String? previous,
    Rect? origin,
    required _Status status,
    required GlobalKey key,
  }) async {
    if (password != null && !await _plainOk()) return;
    if (!mounted) return;
    _cancel = false;
    await _run(status, key, s.boxBackupPreparing, () async {
      final ticket = await _client.prepare(password: password, previous: previous);
      final name = boxBackupFileName(box: _client.boxLabel, previous: previous, now: DateTime.now());
      final total = (ticket['bytes'] as num?)?.toInt() ?? 0;
      final path = await _client.temporaryPath(name);
      void progress(int bytes) {
        if (!mounted) return;
        setState(() {
          status
            ..progress = total > 0
                ? s.boxBackupDownloadingOf(backupSize(bytes), backupSize(total))
                : s.boxBackupDownloading(backupSize(bytes))
            ..fraction = total > 0 ? (bytes / total).clamp(0, 1).toDouble() : null
            ..cancellable = true;
        });
      }

      progress(0);
      await _client.download(
        ticket['ticket']! as String,
        path,
        onProgress: progress,
        cancelled: () => _cancel || _left,
      );
      if (!mounted || _left) {
        final left = File(path);
        if (await left.exists()) await left.delete();
        return;
      }
      setState(() {
        status
          ..progress = null
          ..fraction = null
          ..cancellable = false;
      });
      final where = await _client.deliver(File(path), name, origin: origin);
      if (where == null || !mounted) return;
      final withheld = (ticket['withheld'] as List?)?.isNotEmpty ?? false;
      setState(() {
        status.done = where.isEmpty ? s.boxBackupSaved : s.boxBackupSavedTo(where);
        if (withheld) {
          status
            ..done = '${status.done} ${s.boxBackupWithheld}'
            ..warn = true;
        }
      });
    });
  }

  Future<void> _createBackup({Rect? origin}) async {
    final password = _withKeys ? _first.text : null;
    setState(() => _passwordError = null);
    if (password != null && password.length < _min) {
      setState(() => _passwordError = s.boxBackupPasswordShort(_min));
      return;
    }
    if (password != null && password != _second.text) {
      setState(() => _passwordError = s.boxBackupPasswordMismatch);
      return;
    }
    await _download(password: password, origin: origin, status: _create, key: _createKey);
  }

  /// An earlier state: its own small password dialog, independent of the fields above.
  Future<void> _downloadPrevious(String name, {Rect? origin}) async {
    final password = await showAdaptiveDialog<String>(
      context: context,
      builder: (_) => _PreviousPasswordDialog(minimum: _min),
    );
    if (password == null || !mounted) return;
    await _download(
      password: password.isEmpty ? null : password,
      previous: name,
      origin: origin,
      status: _previous,
      key: _previousKey,
    );
  }

  Future<void> _pick() async {
    if (!await _plainOk() || !mounted) return;
    setState(() {
      for (final st in [_create, _restore, _previous]) {
        st.clear();
      }
    });
    try {
      final summary = await _client.pickAndUpload(
        onStart: () {
          if (mounted) setState(() => _restore.progress = s.boxBackupUploading(backupSize(0)));
        },
        onProgress: (bytes) {
          if (mounted) setState(() => _restore.progress = s.boxBackupUploading(backupSize(bytes)));
        },
      );
      if (mounted && summary != null) setState(() => _staged = summary);
    } on AddonException catch (e) {
      if (mounted) setState(() => _restore.error = _message(e));
    } on Object catch (e) {
      debugPrint('Box-Sicherung: $e');
      if (mounted) setState(() => _restore.error = s.actionFailed);
    }
    if (!mounted) return;
    setState(() => _restore.progress = null);
    _show(_restoreKey);
  }

  Future<void> _discard() => _run(_restore, _restoreKey, s.boxBackupDiscard, () async {
    await _client.discard();
    if (mounted) setState(() => _staged = null);
  });

  Future<void> _apply() async {
    final staged = _staged;
    if (staged == null) return;
    final needsCurrent = _status?['needsCurrent'] == true;
    setState(() {
      _currentError = null;
      _restorePasswordError = null;
    });
    if (needsCurrent && _current.text.isEmpty) {
      setState(() => _currentError = s.boxBackupCurrentMissing);
      return;
    }
    final password = _restorePassword.text;
    var withoutSecrets = false;
    if (staged['secrets'] == true && password.isEmpty) {
      if (!await _ask(s.boxBackupWithoutKeysTitle, s.boxBackupWithoutKeysBody, s.boxBackupWithoutKeys)) return;
      withoutSecrets = true;
    }
    final count = (staged['installations'] as List?)?.length ?? 0;
    if (!mounted ||
        !await _ask(
          s.boxBackupConfirmTitle,
          s.boxBackupConfirmBody(count, _date(staged['created'])),
          s.boxBackupApply,
          destructive: true,
        )) {
      return;
    }
    await _run(_restore, _restoreKey, s.boxBackupRestoring, () async {
      try {
        final result = await _client.apply(
          stage: staged['stage']! as String,
          password: password.isEmpty ? null : password,
          withoutSecrets: withoutSecrets,
          current: needsCurrent ? _current.text : null,
        );
        _restorePassword.clear();
        _current.clear();
        if (!mounted) return;
        setState(() {
          _staged = null;
          _restore.done = s.boxBackupRestored((result['installations'] as num?)?.toInt() ?? count);
          if (result['secretsSkipped'] == true) {
            _restore
              ..done = '${_restore.done} ${s.boxBackupKeysSkipped}'
              ..warn = true;
          }
        });
      } on AddonException catch (e) {
        // Errors that belong to a field go there.
        if (e.problem == 'backupPassword') {
          if (mounted) setState(() => _restorePasswordError = s.boxBackupWrongPassword);
        } else if (e.status == HttpStatus.forbidden) {
          if (mounted) setState(() => _currentError = s.boxPasswordCurrentWrong);
        } else {
          rethrow;
        }
      }
    });
    await _load();
  }

  Future<void> _deletePrevious(String name, String date) async {
    if (!await _ask(
      s.boxBackupPreviousDeleteTitle,
      s.boxBackupPreviousDeleteBody(date),
      s.commonDelete,
      destructive: true,
    )) {
      return;
    }
    await _run(_previous, _previousKey, s.commonDelete, () => _client.deletePrevious(name));
    await _load();
  }

  static String _date(Object? iso) {
    final t = DateTime.tryParse('$iso')?.toLocal();
    if (t == null) return '';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${formatDate(t)} ${two(t.hour)}:${two(t.minute)}';
  }

  Widget _password(
    TextEditingController controller,
    String label, {
    String? help,
    String? error,
    bool current = false,
  }) => HorizontField(
    label: label,
    help: help,
    child: TextField(
      style: context.hzTheme.field,
      controller: controller,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      enabled: !_busy,
      autofillHints: [current ? AutofillHints.password : AutofillHints.newPassword],
      decoration: InputDecoration(errorText: error),
    ),
  );

  /// Progress, error and result of a section, right above its buttons.
  List<Widget> _statusOf(_Status status) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    return [
      if (status.progress case final progress?) ...[
        LinearProgressIndicator(value: status.fraction),
        const SizedBox(height: Gap.item),
        Row(
          children: [
            Expanded(child: Text(progress, style: muted)),
            if (status.cancellable)
              TextButton(onPressed: () => setState(() => _cancel = true), child: Text(s.commonCancel)),
          ],
        ),
        const SizedBox(height: Gap.item),
      ],
      if (status.error case final error?) ...[
        HorizontStatusLine(HorizontStatus.critical, error),
        const SizedBox(height: Gap.item),
      ],
      if (status.done case final done?) ...[
        HorizontStatusLine(status.warn ? HorizontStatus.warning : HorizontStatus.positive, done),
        const SizedBox(height: Gap.item),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted);
    final staged = _staged;
    final ready = _status != null;
    final previous = [for (final p in (_status?['previous'] as List?) ?? const []) (p as Map).cast<String, Object?>()];
    return Scaffold(
      appBar: AppBar(title: Text(s.boxBackupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.reading),
          child: RefreshIndicator.adaptive(
            onRefresh: _load,
            child: ListView(
              padding: Gap.page,
              children: [
                Text(s.boxBackupIntro, style: muted),
                if (_loadError case final error?) ...[
                  const SizedBox(height: Gap.section),
                  HorizontStatusLine(_tooOld ? HorizontStatus.warning : HorizontStatus.critical, error),
                ],
                if (!ready && _loadError == null) ...[
                  const SizedBox(height: Gap.section),
                  const LinearProgressIndicator(),
                ],
                if (ready && _client.plainNetwork) ...[
                  const SizedBox(height: Gap.section),
                  HorizontStatusLine(HorizontStatus.warning, s.boxBackupPlainNetwork),
                ],
                if (ready) ...[
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxBackupCreate, key: _createKey),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.boxBackupWithKeys),
                    subtitle: SwitchHint(s.boxBackupWithKeysHint),
                    value: _withKeys,
                    onChanged: _busy ? null : (v) => setState(() => _withKeys = v),
                  ),
                  if (_withKeys) ...[
                    _password(_first, s.boxBackupPassword, help: s.boxBackupPasswordHelp(_min), error: _passwordError),
                    const SizedBox(height: Gap.item),
                    _password(_second, s.boxBackupPasswordRepeat),
                    const SizedBox(height: Gap.item),
                  ],
                  Text(s.boxBackupPlain, style: muted),
                  const SizedBox(height: Gap.inner),
                  ..._statusOf(_create),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Builder(
                      builder: (button) => FilledButton.icon(
                        icon: Icon(AppIcons.share, size: 18),
                        label: Text(s.boxBackupCreate),
                        onPressed: _busy ? null : () => unawaited(_createBackup(origin: rectOf(button))),
                      ),
                    ),
                  ),
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxBackupRestore, key: _restoreKey),
                  const SizedBox(height: Gap.item),
                  Text(s.boxBackupRestoreHint, style: muted),
                  const SizedBox(height: Gap.inner),
                  ..._statusOf(_restore),
                  if (_readOnly)
                    HorizontStatusLine(HorizontStatus.warning, s.boxBackupReadOnly)
                  else if (staged == null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => unawaited(_pick()),
                        child: Text(s.boxBackupPick),
                      ),
                    )
                  else
                    ..._stagedSection(staged, muted),
                  const SizedBox(height: Gap.section),
                  Kennung(s.boxBackupPrevious, count: previous.length, key: _previousKey),
                  const SizedBox(height: Gap.item),
                  Text(s.boxBackupPreviousHint, style: muted),
                  const SizedBox(height: Gap.item),
                  ..._statusOf(_previous),
                  if (previous.isEmpty) Text(s.boxBackupPreviousNone, style: muted),
                  for (final p in previous) _previousEntry(p, muted),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One earlier state: text above, buttons below, so large text keeps its width.
  Widget _previousEntry(Map<String, Object?> p, TextStyle? muted) {
    final name = p['name']! as String;
    final date = _date(p['created']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(date, style: Theme.of(context).textTheme.bodyLarge),
          Text([for (final n in (p['installations'] as List?) ?? const []) '$n'].join(' · '), style: muted),
          Wrap(
            spacing: Gap.inner,
            children: [
              Builder(
                builder: (button) => TextButton(
                  onPressed: _busy ? null : () => unawaited(_downloadPrevious(name, origin: rectOf(button))),
                  child: Text(s.boxBackupDownload),
                ),
              ),
              TextButton.icon(
                icon: const Icon(AppIcons.delete, size: 18),
                label: Text(s.commonDelete),
                onPressed: _busy ? null : () => unawaited(_deletePrevious(name, date)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _stagedSection(Map<String, Object?> staged, TextStyle? muted) {
    final installations = [for (final i in (staged['installations'] as List?) ?? const []) (i as Map)['name']];
    final hasKeys = staged['secrets'] == true;
    final from = (staged['box'] as Map?)?['name'];
    return [
      HorizontStatusLine(
        HorizontStatus.info,
        s.boxBackupSummary(
          _date(staged['created']),
          installations.length,
          backupSize((staged['bytes'] as num?)?.toInt() ?? 0),
        ),
      ),
      const SizedBox(height: Gap.item),
      Text([if (from is String && from.isNotEmpty) from, ...installations.map((n) => '$n')].join(' · '), style: muted),
      const SizedBox(height: Gap.item),
      HorizontStatusLine(
        hasKeys ? HorizontStatus.positive : HorizontStatus.warning,
        hasKeys ? s.boxBackupHasKeys : s.boxBackupNoKeys,
      ),
      const SizedBox(height: Gap.inner),
      if (hasKeys) ...[
        _password(
          _restorePassword,
          s.boxBackupPassword,
          current: true,
          help: s.boxBackupWithoutKeysBody,
          error: _restorePasswordError,
        ),
        const SizedBox(height: Gap.item),
      ],
      if (_status?['needsCurrent'] == true) ...[
        _password(_current, s.boxBackupCurrent, current: true, help: s.boxBackupCurrentHint, error: _currentError),
        const SizedBox(height: Gap.item),
      ],
      Wrap(
        spacing: Gap.inner,
        runSpacing: Gap.item,
        children: [
          FilledButton(onPressed: _busy ? null : () => unawaited(_apply()), child: Text(s.boxBackupApply)),
          OutlinedButton(onPressed: _busy ? null : () => unawaited(_discard()), child: Text(s.boxBackupDiscard)),
        ],
      ),
    ];
  }
}

/// Password for downloading an earlier state, independent of the fields of the screen. Empty:
/// without the keys.
class _PreviousPasswordDialog extends StatefulWidget {
  const _PreviousPasswordDialog({required this.minimum});
  final int minimum;

  @override
  State<_PreviousPasswordDialog> createState() => _PreviousPasswordDialogState();
}

class _PreviousPasswordDialogState extends State<_PreviousPasswordDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text;
    if (text.isNotEmpty && text.length < widget.minimum) {
      setState(() => _error = s.boxBackupPasswordShort(widget.minimum));
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: Text(s.boxBackupPreviousTitle),
    content: Material(
      type: MaterialType.transparency,
      // A fixed width: the dialog measures its content, which a text field cannot answer.
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.boxBackupPreviousBody),
            const SizedBox(height: Gap.item),
            TextField(
              controller: _controller,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: s.boxBackupPassword, errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
    ),
    actions: [
      horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
      horizontDialogAction(context, label: s.boxBackupDownload, primary: true, onPressed: _submit),
    ],
  );
}
