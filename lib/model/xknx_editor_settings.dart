import 'package:shared_preferences/shared_preferences.dart';

import '../platform/key_vault.dart';
import '../platform/xknx_editor_client.dart';

/// Where Busclear reaches the XKNX Editor's MCP server: address (preferences) and the optional
/// bearer token (keychain). The editor shows both under Settings › AI/MCP.
class XknxEditorSettings {
  XknxEditorSettings._();

  static const _endpointKey = 'xknx_editor_endpoint';
  static const _tokenKey = 'xknx_editor_token';
  static KeyVault vault = SecureKeyVault();

  static Future<Uri> endpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return Uri.tryParse(prefs.getString(_endpointKey) ?? '') ?? xknxEditorDefaultEndpoint;
  }

  static Future<String?> token() async {
    try {
      return await vault.read(_tokenKey);
    } on Object {
      return null;
    }
  }

  static Future<void> save({required Uri endpoint, String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    if (endpoint == xknxEditorDefaultEndpoint) {
      await prefs.remove(_endpointKey);
    } else {
      await prefs.setString(_endpointKey, '$endpoint');
    }
    if (token == null || token.isEmpty) {
      await vault.delete(_tokenKey);
    } else {
      await vault.write(_tokenKey, token);
    }
  }

  static Future<XknxEditorClient> client() async => XknxEditorClient(await endpoint(), token: await token());
}
