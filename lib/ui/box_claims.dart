import 'package:flutter/material.dart';
import 'package:horizont/horizont.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/locale_controller.dart';
import '../model/box_connection.dart';
import '../model/installation.dart';
import '../theme/palette.dart';

/// Installations the paired box names by their key without this app ever having connected them
/// ([InstallationStore.boxClaims]), e.g. a home owner's box that holds the installation an
/// electrician got back by handover. The key travels in files people pass around, so it proves
/// nothing: the user decides, once per box and installation. A "not now" is remembered; the box
/// settings list the claim again ([BoxClaimList]).
abstract final class BoxClaims {
  static const _declinedKey = 'box_claims_declined';

  static String _mark(String box, String id) => '$box:$id';

  /// Claims of the paired box the user has not answered yet.
  static Future<List<String>> unanswered() async {
    final store = InstallationStore.instance;
    final box = store.boxKey;
    if (box == null || store.boxClaims.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final declined = prefs.getStringList(_declinedKey) ?? const [];
    return [
      for (final id in store.boxClaims.keys)
        if (store.byId(id) != null && !declined.contains(_mark(box, id))) id,
    ];
  }

  static Future<void> _decline(String id) async {
    final box = InstallationStore.instance.boxKey;
    if (box == null) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_declinedKey) ?? const [];
    final mark = _mark(box, id);
    if (!list.contains(mark)) await prefs.setStringList(_declinedKey, [...list, mark]);
  }

  /// Asks for every unanswered claim of the paired box. Returns whether one was connected.
  static Future<bool> offer(BuildContext context) async {
    var connected = false;
    for (final id in await unanswered()) {
      if (!context.mounted) break;
      final yes = await ask(context, id);
      if (yes == null) break;
      if (yes) {
        await InstallationStore.instance.acceptBoxClaim(id);
        connected = true;
      } else {
        await _decline(id);
      }
    }
    return connected;
  }

  /// The question for installation [id]: `true` connect, `false` not now, `null` dismissed.
  static Future<bool?> ask(BuildContext context, String id) {
    final name = InstallationStore.instance.byId(id)?.name ?? id;
    final box = BoxConnection.instance.saved?.label ?? s.boxClaimThisBox;
    return showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(s.boxClaimTitle),
        content: Text(s.boxClaimBody(box, name)),
        actions: [
          horizontDialogAction(context, label: s.boxClaimNotNow, onPressed: () => Navigator.pop(context, false)),
          horizontDialogAction(context, label: s.boxClaimConnect, onPressed: () => Navigator.pop(context, true)),
        ],
      ),
    );
  }
}

/// Box settings: the installations the box names that are not connected here, each with
/// "Verbinden" (connect). Nothing when there are none.
class BoxClaimList extends StatelessWidget {
  const BoxClaimList({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: InstallationStore.instance,
    builder: (context, _) {
      final store = InstallationStore.instance;
      final ids = [
        for (final id in store.boxClaims.keys)
          if (store.byId(id) != null) id,
      ];
      if (ids.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kennung(s.boxClaimSection),
          Text(s.boxClaimSectionHint, style: TextStyle(color: context.hz.textMuted)),
          for (final id in ids)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(store.byId(id)!.name),
              trailing: TextButton(
                onPressed: () async {
                  if (await BoxClaims.ask(context, id) == true) await store.acceptBoxClaim(id);
                },
                child: Text(s.boxClaimConnect),
              ),
            ),
        ],
      );
    },
  );
}
