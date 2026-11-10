import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Keys that tell things apart across devices: installation, box, app instance. What each one
/// means, who creates it and where it travels is written down in docs/keys.md; a new kind of
/// key belongs there first.
///
/// A key names something, it never proves anything: whoever knows the key of an installation or
/// a box gets no access through it.

final _keyPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

/// Whether [value] has the form of a key (lower-case UUID). Everything from outside (box,
/// package, backup) is checked with it before it is stored.
bool isKey(Object? value) => value is String && _keyPattern.hasMatch(value);

String _format(List<int> b) {
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// A new random key (UUID version 4).
String newKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  return _format(b);
}

/// Namespace of the derived installation keys; never change it, or every installation from
/// before the keys existed would get another one.
const _installationNamespace = 'busclear:installation:';

final _randomId = RegExp(r'^[0-9a-f]{12}$');

/// Whether [id] is one the app generated at random (`InstallationStore.newId`). Only those are
/// unique beyond one device; `default` exists on every box and add-on.
bool isRandomInstallationId(String id) => _randomId.hasMatch(id);

/// Key of an installation that has none stored: derived from its id (UUID version 5 style,
/// SHA-1). Every device and every app version arrives at the same key for the same id without
/// talking to each other, also after an older version dropped the stored one.
///
/// For an id that is not random ([isRandomInstallationId]) the result is only a placeholder:
/// the real key comes from the box that manages the installation.
String derivedInstallationKey(String id) {
  final b = sha1.convert(utf8.encode('$_installationNamespace$id')).bytes.sublist(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50;
  b[8] = (b[8] & 0x3f) | 0x80;
  return _format(b);
}
