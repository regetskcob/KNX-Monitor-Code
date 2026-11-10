import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';

import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import '../theme/tokens.dart';

/// AI access (MCP server of the add-on or box): switch it on, see address and token, copy the
/// command for an AI tool, issue a new token. Admin only; the server enforces it as well.
class AiAccessScreen extends StatefulWidget {
  const AiAccessScreen({super.key});

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
      final settings = await Addon.mcpSettings();
      final path = settings['path'] as String? ?? '/api/mcp';
      String? endpoint;
      if (Addon.box case final box?) {
        endpoint = box.url.resolve(path.substring(1)).toString();
      } else if (await Addon.lanAddress() case final ip?) {
        // The add-on listens on its Ingress port in the host network.
        endpoint = 'http://$ip:8765$path';
      }
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
      final settings = await Addon.configureMcp(enabled: enabled, renew: renew);
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
      body: ListView(
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
                  trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(endpoint)),
                ),
              if (token != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.aiAccessToken),
                  subtitle: Text('${token.substring(0, 6)}…'),
                  trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () => _copy(token)),
                ),
              if (command != null) ...[
                const SizedBox(height: Gap.inner),
                Text(s.aiAccessCommand, style: theme.textTheme.titleSmall),
                const SizedBox(height: Gap.item),
                SelectableText(command, style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')),
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
      ),
    );
  }
}
