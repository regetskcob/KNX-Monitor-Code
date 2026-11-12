import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../export/pdf_export.dart';
import '../l10n/locale_controller.dart';
import '../model/account.dart';
import '../model/betrieb_mode.dart';
import '../model/app_lock.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'form_columns.dart';

/// Puts the lock over the whole app. Whatever runs underneath keeps its state
/// but takes neither focus nor input and is not read out.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    return ListenableBuilder(
      listenable: lock,
      child: child,
      builder: (context, app) {
        final blocked = lock.locked || lock.needsSetup;
        return Stack(
          fit: StackFit.expand,
          children: [
            ExcludeFocus(
              excluding: blocked,
              child: ExcludeSemantics(
                excluding: blocked,
                child: Offstage(offstage: blocked, child: app),
              ),
            ),
            if (blocked)
              // Own navigator: text fields and dialogs need an overlay.
              HeroControllerScope.none(
                child: Navigator(
                  key: ValueKey(lock.needsSetup),
                  onGenerateRoute: (_) => PageRouteBuilder<void>(
                    pageBuilder: (_, _, _) => lock.needsSetup ? const _RequiredSetup() : const _LockView(),
                  ),
                ),
              )
            else if (lock.covered)
              ColoredBox(color: Theme.of(context).colorScheme.surface),
          ],
        );
      },
    );
  }
}

class _LockView extends StatefulWidget {
  const _LockView();

  @override
  State<_LockView> createState() => _LockViewState();
}

class _LockViewState extends State<_LockView> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _wrong = false;

  AppLock get _lock => AppLock.instance;

  @override
  void initState() {
    super.initState();
    if (_lock.mode == AppLockMode.system) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_system()));
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _system() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _lock.unlockWithSystem(s.appLockReason);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _wrong = false;
    });
    final ok = await _lock.unlockWithPassword(_password.text);
    if (!mounted) return;
    _password.clear();
    setState(() {
      _busy = false;
      _wrong = !ok;
    });
  }

  String _wrongText() {
    if (_lock.restartRequired) return s.appLockRestart;
    final wait = _lock.waitUntil;
    if (wait == null || !DateTime.now().isBefore(wait)) return s.appLockWrong;
    return s.appLockWait(wait.difference(DateTime.now()).inSeconds + 1);
  }

  Future<void> _recover() async {
    final field = TextEditingController();
    final code = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.recoveryUse),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: field,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: s.recoveryTitle),
          ),
        ),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
          horizontDialogAction(context, label: s.appLockUnlock, onPressed: () => Navigator.pop(context, field.text)),
        ],
      ),
    );
    disposeAfterDialog(field);
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    final ok = await _lock.unlockWithRecovery(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wrong = !ok;
    });
  }

  Future<void> _forgot() async {
    final body = Betrieb.enabled ? s.appLockForgotBodyTeam : s.appLockForgotBody;
    if (!await _sure(s.appLockForgotTitle, body, s.appLockForgotContinue) || !mounted) return;
    final sure = Betrieb.enabled ? s.appLockForgotSureBodyTeam : s.appLockForgotSureBody;
    if (!await _sure(s.appLockForgotSureTitle, sure, s.appLockForgotConfirm)) return;
    await _lock.wipeAndExit();
  }

  Future<bool> _sure(String title, String body, String confirm) async =>
      await showAdaptiveDialog<bool>(
        context: context,
        builder: (context) => AlertDialog.adaptive(
          title: Text(title),
          content: Text(body),
          actions: [
            horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context, false)),
            horizontDialogAction(
              context,
              label: confirm,
              destructive: true,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    final password = _lock.mode == AppLockMode.password;
    return _LockFrame(
      title: s.appLockTitle,
      text: password ? s.appLockPasswordHint : s.appLockSystemHint,
      children: [
        if (password) ...[
          TextField(
            controller: _password,
            autofocus: true,
            obscureText: true,
            enabled: !_busy,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => unawaited(_submit()),
            decoration: InputDecoration(labelText: s.appLockPassword, errorText: _wrong ? _wrongText() : null),
          ),
          const SizedBox(height: Gap.item),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(s.appLockUnlock)),
          const SizedBox(height: Gap.item),
          TextButton(onPressed: _busy ? null : _recover, child: Text(s.recoveryUse)),
          TextButton(onPressed: _busy ? null : _forgot, child: Text(s.appLockForgot)),
        ] else
          FilledButton(onPressed: _busy ? null : _system, child: Text(s.appLockUnlock)),
      ],
    );
  }
}

/// A company requires the lock, but it is not set up yet.
class _RequiredSetup extends StatelessWidget {
  const _RequiredSetup();

  @override
  Widget build(BuildContext context) => _LockFrame(
    title: s.appLockRequiredTitle,
    text: AppLock.instance.mustReset ? s.recoveryResetBody : s.appLockRequiredBody,
    children: const [_LockSetup()],
  );
}

class _LockFrame extends StatelessWidget {
  const _LockFrame({required this.title, required this.text, required this.children});

  final String title;
  final String text;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(AppIcons.locked, color: context.hz.textMuted),
                  const SizedBox(height: Gap.item),
                  Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleLarge),
                  const SizedBox(height: Gap.item),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: context.hz.textMuted),
                  ),
                  const SizedBox(height: Gap.section),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Setup: device lock if available, otherwise or optionally an app password.
class _LockSetup extends StatefulWidget {
  const _LockSetup();

  @override
  State<_LockSetup> createState() => _LockSetupState();
}

class _LockSetupState extends State<_LockSetup> {
  late final Future<bool> _supported = AppLock.instance.systemSupported();
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _useSystem() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppLock.instance.enableSystem(s.appLockReason);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = s.appLockSystemFailed;
    });
  }

  Future<void> _usePassword() async {
    if (_first.text.length < AppLock.minPasswordLength) {
      setState(() => _error = s.appLockTooShort(AppLock.minPasswordLength));
      return;
    }
    if (_first.text != _second.text) {
      setState(() => _error = s.appLockMismatch);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    // Key first, then the lock: otherwise you'd be locked out before the PDF is
    // saved.
    final code = AppLock.newRecoveryCode();
    if (await showRecoveryKey(context, code)) await AppLock.instance.enablePassword(_first.text, recovery: code);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _supported,
    builder: (context, snap) {
      if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (snap.data == true) ...[
            FilledButton(onPressed: _busy ? null : _useSystem, child: Text(s.appLockUseSystem)),
            const SizedBox(height: Gap.section),
          ],
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _first,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  inputFormatters: [LengthLimitingTextInputFormatter(128)],
                  decoration: InputDecoration(labelText: s.appLockNewPassword),
                ),
                const SizedBox(height: Gap.item),
                TextField(
                  controller: _second,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  inputFormatters: [LengthLimitingTextInputFormatter(128)],
                  decoration: InputDecoration(labelText: s.appLockRepeatPassword, errorText: _error),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.item),
          if (_busy) const LinearProgressIndicator(),
          OutlinedButton(onPressed: _busy ? null : _usePassword, child: Text(s.appLockUsePassword)),
          const SizedBox(height: Gap.item),
          Text(
            s.appLockPasswordWarning,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.hz.textMuted),
          ),
        ],
      );
    },
  );
}

/// Shows the emergency key; `true` once it has been saved.
Future<bool> showRecoveryKey(BuildContext context, String code) async {
  Future<void> savePdf(BuildContext dialog) async {
    final bytes = await buildRecoveryKeyPdf(code, email: Account.instance.email);
    final saved = await FilePicker.saveFile(fileName: 'knx-monitor-notfallschluessel.pdf', bytes: bytes);
    if (saved != null && dialog.mounted) Navigator.pop(dialog, true);
  }

  return await showAdaptiveDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog.adaptive(
          title: Text(s.recoveryTitle),
          content: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.recoveryExplain),
                const SizedBox(height: Gap.item),
                SelectableText(code, style: dialog.mono(Theme.of(dialog).textTheme.bodyMedium)),
              ],
            ),
          ),
          actions: [
            horizontDialogAction(dialog, label: s.commonCancel, onPressed: () => Navigator.pop(dialog, false)),
            horizontDialogAction(dialog, label: s.recoveryNoted, onPressed: () => Navigator.pop(dialog, true)),
            horizontDialogAction(dialog, label: s.recoverySavePdf, primary: true, onPressed: () => savePdf(dialog)),
          ],
        ),
      ) ==
      true;
}

/// Lock settings.
class AppLockSettingsScreen extends StatelessWidget {
  const AppLockSettingsScreen({super.key});

  Future<bool> _confirm(BuildContext context) async {
    final lock = AppLock.instance;
    if (lock.mode == AppLockMode.system) return lock.confirmSystem(s.appLockReason);
    final field = TextEditingController();
    final entered = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.appLockPassword),
        content: Material(
          type: MaterialType.transparency,
          child: TextField(controller: field, autofocus: true, obscureText: true),
        ),
        actions: [
          horizontDialogAction(context, label: s.commonCancel, onPressed: () => Navigator.pop(context)),
          horizontDialogAction(context, label: s.appLockUnlock, onPressed: () => Navigator.pop(context, field.text)),
        ],
      ),
    );
    disposeAfterDialog(field);
    return entered != null && await lock.checkPassword(entered);
  }

  /// Choice of timeout, as shown by the "Sperren nach" (lock after) row.
  static String _timeoutLabel(int minutes) => minutes == 0 ? s.appLockTimeoutNow : s.appLockTimeoutMinutes(minutes);

  Future<void> _pickTimeout(BuildContext context) async {
    final lock = AppLock.instance;
    final picked = await showAdaptiveDialog<int>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(s.appLockTimeout),
        children: [
          for (final m in AppLock.timeouts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, m),
              child: Text(
                _timeoutLabel(m),
                style: m == lock.timeoutMinutes
                    ? TextStyle(color: dialog.hz.accentText, fontWeight: FontWeight.w600)
                    : null,
              ),
            ),
        ],
      ),
    );
    if (picked != null) await lock.setTimeout(picked);
  }

  @override
  Widget build(BuildContext context) {
    final lock = AppLock.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.appLockSettings),
        actions: [InfoAction(title: s.appLockSettings, text: s.appLockExplain)],
      ),
      body: ListenableBuilder(
        listenable: lock,
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final settings = RowCard(
              children: [
                SwitchRow(
                  title: s.appLockSettings,
                  meta: lock.mode == AppLockMode.system ? s.appLockMethodSystem : s.appLockMethodPassword,
                  value: true,
                  // Turn off only after confirmation; if the company requires
                  // the lock, it stays on.
                  onChanged: lock.required
                      ? null
                      : (_) async {
                          if (await _confirm(context)) await lock.disable();
                        },
                ),
                CardRow(
                  title: s.appLockTimeout,
                  value: _timeoutLabel(lock.timeoutMinutes),
                  onTap: () => unawaited(_pickTimeout(context)),
                ),
                if (Theme.of(context).platform == TargetPlatform.android)
                  SwitchRow(
                    title: s.appLockHideTitle,
                    meta: s.appLockHideHint,
                    value: lock.hideScreen,
                    onChanged: (v) => unawaited(lock.setHideScreen(v)),
                  ),
              ],
            );
            final recovery = RowCard(
              children: [
                CardRow(
                  title: s.recoveryTitle,
                  meta: s.recoveryRenew,
                  onTap: () async {
                    if (!await _confirm(context) || !context.mounted) return;
                    final code = AppLock.newRecoveryCode();
                    if (await showRecoveryKey(context, code)) await lock.setRecovery(code);
                  },
                ),
              ],
            );
            final note = Text(
              s.appLockRequiredNote,
              style: theme.textTheme.bodySmall?.copyWith(color: context.hz.textFaint),
            );
            if (box.maxWidth >= Breakpoints.expanded) {
              // Little content, so no more than two columns of cards: the lock (or its setup) on
              // the left; on the right what it is for (otherwise behind the info symbol) and the
              // emergency key.
              return FormColumns(
                columns: [
                  [if (!lock.enabled) SectionCard(child: const _LockSetup()) else settings],
                  [
                    SectionCard(child: Text(s.appLockExplain)),
                    if (lock.enabled && lock.mode == AppLockMode.password) ...[
                      const SizedBox(height: Gap.section),
                      recovery,
                    ],
                    if (lock.enabled && lock.required) ...[const SizedBox(height: Gap.item), note],
                  ],
                ],
              );
            }
            return ListView(
              padding: Gap.page,
              children: [
                if (!lock.enabled)
                  SectionCard(child: const _LockSetup())
                else ...[
                  settings,
                  if (lock.mode == AppLockMode.password) ...[const SizedBox(height: Gap.item), recovery],
                  if (lock.required) ...[const SizedBox(height: Gap.item), note],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
