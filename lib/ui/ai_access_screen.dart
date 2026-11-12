import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../theme/app_icons.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'common.dart';
import 'figure_box.dart';
import 'form_columns.dart';

/// Talks to the server; replaceable in tests.
class AiAccessClient {
  const AiAccessClient();

  Future<Map<String, Object?>> settings() => Addon.mcpSettings();

  Future<Map<String, Object?>> configure({bool? enabled, bool renew = false}) =>
      Addon.configureMcp(enabled: enabled, renew: renew);

  /// Address of the MCP endpoint at [path] as an AI tool reaches it, `null` if unknown.
  Future<String?> endpoint(String path) async {
    if (Addon.box case final box?) return box.url.resolve(path.substring(1)).toString();
    // The add-on listens on its Ingress port in the host network.
    if (await Addon.lanAddress() case final ip?) return 'http://$ip:8765$path';
    return null;
  }
}

/// AI access (MCP server of the add-on or box): switch it on, see address and token, copy the
/// command for an AI tool, issue a new token. Admin only; the server enforces it as well.
class AiAccessScreen extends StatefulWidget {
  const AiAccessScreen({super.key, this.client = const AiAccessClient()});

  final AiAccessClient client;

  @override
  State<AiAccessScreen> createState() => _AiAccessScreenState();
}

class _AiAccessScreenState extends State<AiAccessScreen> {
  Map<String, Object?>? _settings;
  String? _endpoint;
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.client.settings();
      final endpoint = await widget.client.endpoint(settings['path'] as String? ?? '/api/mcp');
      if (mounted) {
        setState(() {
          _settings = settings;
          _endpoint = endpoint;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _change({bool? enabled, bool renew = false}) async {
    setState(() => _busy = true);
    try {
      final settings = await widget.client.configure(enabled: enabled, renew: renew);
      if (mounted) setState(() => _settings = settings);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    showHorizontMessage(context, s.aiAccessCopied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    final enabled = settings?['enabled'] == true;
    final token = settings?['token'] as String?;
    final endpoint = _endpoint;
    final command = endpoint == null || token == null
        ? null
        : 'claude mcp add --transport http busclear $endpoint --header "Authorization: Bearer $token"';
    return Scaffold(
      appBar: AppBar(title: Text(s.aiAccessTitle)),
      body: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth >= Breakpoints.expanded) return _wide(context, enabled, endpoint, token, command);
          return ListView(
            padding: Gap.page,
            children: [
              Text(s.aiAccessText),
              const SizedBox(height: Gap.section),
              if (_error != null) HorizontNotice(HorizontStatus.critical, child: Text(_error!)),
              if (settings == null && _error == null)
                const Center(child: CircularProgressIndicator.adaptive())
              else if (settings != null) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.aiAccessEnable),
                  subtitle: Text(s.aiAccessReadOnly),
                  value: enabled,
                  onChanged: _busy ? null : (on) => _change(enabled: on),
                ),
                if (enabled) ...[
                  const SizedBox(height: Gap.inner),
                  HorizontNotice(HorizontStatus.warning, child: Text(s.aiAccessPrivacy)),
                  const SizedBox(height: Gap.inner),
                  if (endpoint != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.aiAccessEndpoint),
                      subtitle: SelectableText(endpoint),
                      trailing: IconButton(icon: const Icon(AppIcons.copy), onPressed: () => _copy(endpoint)),
                    ),
                  if (token != null)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.aiAccessToken),
                      subtitle: Text('${token.substring(0, 6)}…'),
                      trailing: IconButton(icon: const Icon(AppIcons.copy), onPressed: () => _copy(token)),
                    ),
                  if (command != null) ...[
                    const SizedBox(height: Gap.inner),
                    Text(s.aiAccessCommand, style: theme.textTheme.titleSmall),
                    const SizedBox(height: Gap.item),
                    SelectableText(command, style: context.mono(theme.textTheme.bodySmall)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () => _copy(command), child: Text(s.aiAccessCopyCommand)),
                    ),
                  ],
                  const SizedBox(height: Gap.inner),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _change(renew: true),
                      child: Text(s.aiAccessRenew),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  /// From [Breakpoints.expanded]: the switch on the left; on the right what the token gives away
  /// and, while access is on, address, token and the command for an AI tool.
  Widget _wide(BuildContext context, bool enabled, String? endpoint, String? token, String? command) {
    final theme = Theme.of(context);
    Widget copy(String text) => IconButton(
      tooltip: MaterialLocalizations.of(context).copyButtonLabel,
      icon: const Icon(AppIcons.copy),
      onPressed: () => _copy(text),
    );
    return FormColumns(
      intro: [
        Text(s.aiAccessText),
        if (_error != null) ...[
          const SizedBox(height: Gap.inner),
          HorizontNotice(HorizontStatus.critical, child: Text(_error!)),
        ],
        if (_settings == null && _error == null) ...[
          const SizedBox(height: Gap.section),
          const Center(child: CircularProgressIndicator.adaptive()),
        ],
        const SizedBox(height: Gap.section),
      ],
      columns: [
        [
          if (_settings != null)
            RowCard(
              children: [
                SwitchRow(
                  title: s.aiAccessEnable,
                  meta: s.aiAccessReadOnly,
                  value: enabled,
                  onChanged: _busy ? null : (on) => _change(enabled: on),
                ),
              ],
            ),
        ],
        [
          // Before switching on as well: who allows access should know what the token opens.
          if (_settings != null) HorizontNotice(HorizontStatus.warning, child: Text(s.aiAccessPrivacy)),
          if (enabled) ...[
            SectionHead(s.factConnection),
            RowCard(
              children: [
                if (endpoint != null)
                  CardRow(title: s.aiAccessEndpoint, meta: endpoint, metaAddress: true, trailing: copy(endpoint)),
                if (token != null)
                  CardRow(
                    title: s.aiAccessToken,
                    meta: '${token.substring(0, 6)}…',
                    metaAddress: true,
                    trailing: copy(token),
                  ),
              ],
            ),
            const SizedBox(height: Gap.inner),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(onPressed: _busy ? null : () => _change(renew: true), child: Text(s.aiAccessRenew)),
            ),
            if (command != null) ...[
              SectionHead(s.aiAccessCommand),
              SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(command, style: context.mono(theme.textTheme.bodySmall)),
                    const SizedBox(height: Gap.inner),
                    OutlinedButton(onPressed: () => _copy(command), child: Text(s.aiAccessCopyCommand)),
                  ],
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }
}
