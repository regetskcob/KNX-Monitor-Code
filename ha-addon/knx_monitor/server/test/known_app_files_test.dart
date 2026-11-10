import 'dart:io';

import 'package:knx_monitor_server/files.dart';
import 'package:test/test.dart';

/// File names in the app's code that do not go through the file API, so they need no entry in
/// [knownAppFiles]: names inside zip archives (backup, diagnostics, handover, team export), the
/// cloud vault in a folder of the user's choice, and files the server keeps for itself.
const _notThroughFileApi = {
  'audit.json', // team export (zip)
  'devices.json', // team export (zip)
  'diagnostics.json', // diagnostics bundle (zip)
  'handover.json', // handover package (zip)
  'installations.json', // the server's own, refused by the file API (_private)
  'keyrings.json', // full backup (zip)
  'log.txt', // diagnostics bundle (zip)
  'manifest.json', // backup / team export (zip)
  'members.json', // below team/
  'payload.json', // handover package (zip)
  'prefs.json', // full backup (zip)
  'project.json', // diagnostics bundle (zip)
  'readme.txt', // team export (zip)
  'recording.json', // diagnostics bundle (zip)
  'secure.json', // diagnostics bundle (zip)
  'shared_preferences.json', // local only, never synced
  'vault.json', // cloud sync, in a folder the user picks
};

void main() {
  // Security review 07.11.: the file API is to accept only what the app stores. A file name the
  // app starts using without an entry would be refused once the list is enforced, quietly, on
  // the add-on and box only (secure_sequence.json was such a case: Data Secure replay
  // protection would have been lost after each restart). This test sees every new name first.
  test('every file name in the app is in knownAppFiles or knowingly elsewhere', () {
    final names = <String>{};
    final literal = RegExp(r"'([a-z_]+\.(?:json|jsonl|yaml|b64|txt))'");
    for (final f in Directory('../../../lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('/l10n/')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        names.add(m.group(1)!);
      }
    }
    expect(names, isNotEmpty);
    final missing = names.difference(knownAppFiles).difference(_notThroughFileApi).toList()..sort();
    expect(
      missing,
      isEmpty,
      reason: 'add to knownAppFiles (lib/src/files.dart) or, if not stored through the file API, to _notThroughFileApi',
    );
  });

  test('the exceptions are not on the list as well', () {
    expect(_notThroughFileApi.intersection(knownAppFiles), isEmpty);
  });
}
