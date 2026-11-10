import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../model/telegram_log.dart';
import '../model/xknx_editor_handover.dart';
import '../model/xknx_editor_settings.dart';
import '../platform/addon.dart';
import '../platform/xknx_editor_client.dart';
import 'common.dart';
import 'ets_tasks_export.dart';

/// Hands the tasks of the project check over to the XKNX Editor: directly to its MCP server (not in
/// the browser, which cannot reach the editor on the user's computer) or as a file.
Future<void> showXknxEditorHandover(BuildContext context, {TelegramLog? log, Rect? origin}) async {
  final tasks = await currentEtsTasks(log: log);
  // With the add-on or box: datapoint types suggested from its long history.
  var suggestions = const <Map<String, Object?>>[];
  if (Addon.available) {
    try {
      suggestions = ((await Addon.projectEvidence(7))['dpt_suggestions'] as List? ?? const [])
          .cast<Map<String, Object?>>();
    } on Object {
      // Without the history the handover simply has no suggestions.
    }
  }
  final handover = XknxEditorHandover.of(tasks, CatalogStore.instance.project, dptSuggestions: suggestions);
  final endpoint = await XknxEditorSettings.endpoint();
  final token = await XknxEditorSettings.token();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _HandoverDialog(handover: handover, endpoint: endpoint, token: token, origin: origin),
  );
}

class _HandoverDialog extends StatefulWidget {
  const _HandoverDialog({required this.handover, required this.endpoint, required this.token, this.origin});

  final XknxEditorHandover handover;
  final Uri endpoint;
  final String? token;
  final Rect? origin;

  @override
  State<_HandoverDialog> createState() => _HandoverDialogState();
}

class _HandoverDialogState extends State<_HandoverDialog> {
  late final _endpoint = TextEditingController(text: '${widget.endpoint}');
  late final _token = TextEditingController(text: widget.token ?? '');
  var _busy = false;
  String? _error;
  XknxHandoverResult? _result;

  @override
  void dispose() {
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _saveFile() async {
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(widget.handover.toJson())));
    await shareFile(context, bytes, fileName(s.xknxEditorFile, 'json'), 'application/json', origin: widget.origin);
  }

  Future<void> _send() async {
    final endpoint = Uri.tryParse(_endpoint.text.trim());
    if (endpoint == null || !endpoint.hasScheme) {
      setState(() => _error = s.xknxEditorUnreachable(_endpoint.text));
      return;
    }
    await XknxEditorSettings.save(endpoint: endpoint, token: _token.text.trim());
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = XknxEditorClient(endpoint, token: _token.text.trim());
    try {
      final open = await client.openProject();
      if (open == null) {
        if (mounted) setState(() => _error = s.xknxEditorNoProject);
        return;
      }
      final own = widget.handover.projectName;
      if (own != null && own.isNotEmpty && open.name != own && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            content: Text(s.xknxEditorOtherProject(open.name, own)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(s.commonCancel)),
              FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(s.xknxEditorSend)),
            ],
          ),
        );
        if (go != true) return;
      }
      final result = await client.apply(widget.handover);
      if (mounted) setState(() => _result = result);
    } on XknxEditorException catch (e) {
      if (mounted) {
        setState(() => _error = xknxEditorErrorText(e));
      }
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = widget.handover;
    final result = _result;
    return AlertDialog(
      title: Text(s.xknxEditorTitle),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HzSpace.s12,
            children: [
              Text(s.xknxEditorText),
              Text(
                h.isEmpty ? s.xknxEditorNothing : s.xknxEditorSummary(h.operations.length, h.notes.length),
                style: theme.textTheme.titleSmall,
              ),
              if (!kIsWeb && result == null) ...[
                TextField(
                  controller: _endpoint,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: s.xknxEditorEndpoint, helperText: s.xknxEditorConnectionHint),
                ),
                TextField(
                  controller: _token,
                  autocorrect: false,
                  obscureText: true,
                  decoration: InputDecoration(labelText: s.xknxEditorToken),
                ),
              ],
              if (_error != null) HorizontNotice(HorizontStatus.critical, child: Text(_error!)),
              if (result != null) ...[
                HorizontNotice(
                  result.failed.isEmpty ? HorizontStatus.positive : HorizontStatus.warning,
                  child: Text(s.xknxEditorDone(result.applied, result.noted)),
                ),
                if (result.failed.isNotEmpty) ...[
                  Text(s.xknxEditorFailed, style: theme.textTheme.titleSmall),
                  for (final f in result.failed) Text(f, style: theme.textTheme.bodySmall),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.commonClose)),
        if (!h.isEmpty) OutlinedButton(onPressed: _busy ? null : _saveFile, child: Text(s.xknxEditorSaveFile)),
        if (!kIsWeb)
          TextButton(
            onPressed: _busy
                ? null
                : () => showDialog<void>(context: context, builder: (_) => const _CompareAllDialog()),
            child: Text(s.xknxEditorCompareAll),
          ),
        if (!kIsWeb && !h.isEmpty && result == null)
          FilledButton(
            onPressed: _busy ? null : _send,
            child: _busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.xknxEditorSend),
          ),
      ],
    );
  }
}

/// Message for an error of the editor connection.
String xknxEditorErrorText(XknxEditorException e) => switch (e.message) {
  '401' => s.xknxEditorUnauthorized,
  XknxEditorException.insecureToken => s.xknxEditorInsecure,
  _ => s.xknxEditorUnreachable(e.message),
};

/// Download preview of every device in the editor's project, one after the other, read-only.
class _CompareAllDialog extends StatefulWidget {
  const _CompareAllDialog();

  @override
  State<_CompareAllDialog> createState() => _CompareAllDialogState();
}

class _CompareAllDialogState extends State<_CompareAllDialog> {
  final _results = <(String, XknxDevicePreview?, String?)>[];
  var _running = false;
  var _stop = false;
  String? _current;
  var _total = 0;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _stop = false;
      _results.clear();
      _error = null;
    });
    final client = await XknxEditorSettings.client();
    try {
      final devices = await client.deviceAddresses();
      if (mounted) setState(() => _total = devices.length);
      for (final device in devices) {
        if (_stop || !mounted) break;
        setState(() => _current = device);
        try {
          final p = await client.previewDownload(device);
          if (mounted) setState(() => _results.add((device, p, null)));
        } on XknxEditorException catch (e) {
          // Not reachable or not programmed: noted, the rest goes on.
          if (mounted) setState(() => _results.add((device, null, e.message)));
        }
      }
    } on XknxEditorException catch (e) {
      if (mounted) setState(() => _error = xknxEditorErrorText(e));
    } finally {
      client.close();
      if (mounted) {
        setState(() {
          _running = false;
          _current = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final differ = _results.where((r) => (r.$2?.config ?? 0) > 0).toList();
    final failed = _results.where((r) => r.$3 != null).toList();
    final catalog = CatalogStore.instance;
    String label(String a) => [a, ?catalog.device(parseIndividual(a) ?? -1)?.name].join('  ');
    return AlertDialog(
      title: Text(s.xknxEditorCompareAll),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: HzSpace.s12,
            children: [
              Text(s.xknxEditorCompareAllHint),
              if (_error != null) HorizontNotice(HorizontStatus.critical, child: Text(_error!)),
              if (_current != null) ...[
                const LinearProgressIndicator(),
                Text(s.xknxEditorCompareProgress(_results.length + 1, _total, label(_current!))),
              ],
              if (_results.isNotEmpty && !_running)
                HorizontNotice(
                  differ.isEmpty && failed.isEmpty ? HorizontStatus.positive : HorizontStatus.warning,
                  child: Text(s.xknxEditorCompareResult(differ.length, _results.length, failed.length)),
                ),
              for (final (device, p, _) in differ)
                Text('${label(device)}: ${s.xknxEditorPreviewDiff(p!.config)}', style: theme.textTheme.bodySmall),
              for (final (device, _, error) in failed)
                Text('${label(device)}: $error', style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _running ? null : () => Navigator.pop(context), child: Text(s.commonClose)),
        if (_running)
          OutlinedButton(
            onPressed: _stop ? null : () => setState(() => _stop = true),
            child: Text(s.xknxEditorCompareStop),
          )
        else
          FilledButton(onPressed: _run, child: Text(s.xknxEditorCompareAll)),
      ],
    );
  }
}
