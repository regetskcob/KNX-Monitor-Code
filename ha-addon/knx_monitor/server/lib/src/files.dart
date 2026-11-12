import 'dart:convert';
import 'dart:io';

import 'atomic_file.dart';
import 'dali.dart' show emergencyLogMaxBytes;
import 'http.dart';

final _safePath = RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*/?$');

/// The server's own files, never via `/api/files/`: box access, the bus
/// connection with IP Secure passwords, the plain-text password of older box
/// versions, and the time request to the host (which then sets the clock).
/// The web app never reads or writes them directly (`/api/bus`, `/api/box/time`).
/// Also the directory of installations (`/api/installations`): the storage
/// points into the active installation, so its `server.json` is locked as well.
/// Likewise the settings of notifications and data export: they contain
/// credentials for third-party services (`/api/report`, `/api/export`).
const _private = {
  'access.json',
  // Failed attempts and lockouts (BoxAccess): deleting it would hand out fresh attempts.
  'access-strikes.json',
  'server.json',
  'report_settings.json',
  'export.json',
  'box-password.txt',
  'time-request.json',
  'lan-access',
  'installations.json',
  'installations',
  'wifi-request',
  'sticker-scrub',
  'password-reset',
  // Data Secure sequence numbers (BusService): lowering them would let replays through.
  'secure_sequence.json',
};

/// The installation's keyring (KNX Secure): only the server reads it and uses it
/// to record secured telegrams; the app only compares ([admin]). A paired device
/// without admin rights does not need it: its keyring lives in its own keychain,
/// and this file would give it all group keys.
const _adminOnly = 'secure_keys.json';

/// What a device without admin rights may store: its own charts and watchers,
/// as a list under the given key whose entries are told apart by the given
/// field. Everything else (project, fault hunt, history) changes the
/// installation for everyone. See [mergeDeviceEntries].
/// Folder whose files may only be appended to (the emergency lighting log).
const _appendOnly = 'dali_tests';

const _deviceWritable = {'charts.json': ('charts', 'name'), 'watch_rules.json': ('rules', 'id')};

/// Field in which the server notes which paired device created an entry of a
/// [_deviceWritable] file. Entries without it belong to the admin.
const ownerField = 'owner';

/// What the app stores through this API, by first path segment (files and folders of
/// `AppStorage` in the app, plus what the server writes for it, such as `hunts/`). Anything else
/// is refused (security review 07.11.: allowlist instead of the blocklist [_private]; enforced
/// since 11.11., after the logs of 1.11 stayed quiet). `test/known_app_files_test.dart` checks
/// every file and folder name in the app's code against it.
const knownAppFiles = {
  'annotations.json',
  'assets',
  'betrieb_standards.json',
  'catalog.json',
  'charts.json',
  'cloud_sync',
  'commissioning.json',
  'company.json',
  'company_logo.png.b64',
  'crash',
  'crash_log.txt',
  'customer.json',
  'dali.json',
  'dali_state.json',
  'dali_tests',
  'dpt_overrides.json',
  'exports',
  'fault_hunt.json',
  'fault_report.json',
  'floor_view.json',
  'floor_view_images',
  'ga_plan.json',
  'handover_origin.json',
  'health.json',
  'history',
  'hunts',
  'home_plan.json',
  'home_plan_exchange.json',
  'home_plan_images',
  'home_plan_live.json',
  'home_plan_previous.json',
  'home_plan_previous_images',
  'knx.yaml',
  'learned.json',
  'name_overrides.json',
  'project_states.json',
  'protocols',
  'recordings',
  'secure_keys.json',
  'secure_sequence.json',
  'service_reports',
  'shots',
  'site_notes.json',
  'site_photos',
  'site_photos.json',
  'site_survey.json',
  'team',
  'visits.json',
  'watch_rules.json',
};

final _reportedUnknown = <String>{};

/// Whether the first path segment of [relative] is not in [knownAppFiles] (and not
/// `.bak`/`.corrupt-…` of a known one); such a request is refused. Logged once per name, so a
/// file the app starts using without an entry shows up in the logs.
bool reportUnknownFile(String relative) {
  final top = relative.split('/').first;
  final base = top.replaceFirst(RegExp(r'\.(bak|corrupt-\d+)$'), '');
  if (top.isEmpty || knownAppFiles.contains(base)) return false;
  if (_reportedUnknown.add(top)) {
    stderr.writeln('Datei-API: "$top" steht nicht auf der Positivliste, abgewiesen (siehe knownAppFiles)');
  }
  return true;
}

/// Upper limit of a merged file: each device brings at most [_maxDeviceUpload].
const _maxMerged = 8 * 1024 * 1024;

/// Upper limit per upload without admin rights.
const _maxDeviceUpload = 1024 * 1024;

// Compared in lower case: on a case-insensitive data folder (Docker Desktop
// on macOS or Windows, some NAS shares) `Secure_Keys.json` is the keyring.
bool _isKeyring(String name) {
  final n = name.toLowerCase();
  return n == _adminOnly || n.startsWith('$_adminOnly.');
}

/// Whether [name] belongs to the server. Backups and set-aside copies
/// (`access.json.bak`, `installations.json.corrupt-…`) contain the same
/// secrets too.
bool _isPrivate(String name) {
  final n = name.toLowerCase();
  return _private.any((p) => n == p || n.startsWith('$p.'));
}

bool _deviceMayWrite(HttpRequest request, String relative) =>
    request.method == 'PUT' && _deviceWritable.containsKey(relative);

/// Upper limit per upload. Generous for catalogs of large projects, but prevents
/// a single request from filling the add-on's memory.
const _maxUpload = 64 * 1024 * 1024;

/// `/api/files/<relative>` in the data folder [data]: read (GET, with a trailing
/// `/` the listing), write (PUT), append (POST), delete (DELETE). With
/// [readOnly] read only (installations that are not currently active). Without
/// [admin] (device from `/pair`) no keyring and hardly any write access: a
/// [viewOnly] device writes nothing, any other one only its own entries in
/// `charts.json` and `watch_rules.json`, identified by [owner] (its device id).
Future<void> serveFile(
  HttpRequest request,
  Directory data,
  String relative, {
  bool readOnly = false,
  bool admin = true,
  bool viewOnly = false,
  String? owner,
}) async {
  final response = request.response;
  relative = Uri.decodeComponent(relative);
  if (!_safePath.hasMatch(relative) || relative.split('/').any((p) => p.startsWith('.'))) {
    response.statusCode = HttpStatus.badRequest;
    return response.close();
  }
  if (readOnly && request.method != 'GET') {
    response.statusCode = HttpStatus.methodNotAllowed;
    return response.close();
  }
  if (reportUnknownFile(relative)) {
    response
      ..statusCode = HttpStatus.forbidden
      ..headers.contentType = ContentType.text
      ..write('Diese Datei gehört nicht zur App.');
    return response.close();
  }
  if (_isPrivate(relative.split('/').first) || relative.toLowerCase().endsWith('.tmp')) {
    response.statusCode = HttpStatus.forbidden;
    return response.close();
  }
  if (!admin &&
      (relative.split('/').any(_isKeyring) ||
          (request.method != 'GET' && (viewOnly || owner == null || !_deviceMayWrite(request, relative))))) {
    response
      ..statusCode = HttpStatus.forbidden
      ..headers.contentType = ContentType.text
      ..write('Nur mit dem Box-Passwort.');
    return response.close();
  }
  // The emergency lighting log is append only: nobody rewrites or deletes a year through the file
  // API (it goes with the installation), and appending stops at the year's limit.
  if (relative.startsWith('$_appendOnly/') && !relative.endsWith('/')) {
    if (request.method == 'PUT' || request.method == 'DELETE') {
      response
        ..statusCode = HttpStatus.methodNotAllowed
        ..headers.contentType = ContentType.text
        ..write('Prüfbuch: nur anhängen.');
      return response.close();
    }
    if (request.method == 'POST') {
      // The body counts as it really is (chunked requests have no length), and check plus append
      // run in one step per file, so two requests at once cannot both pass the limit. The server's
      // own recorder (dali_watch.dart) appends through the same queue.
      final file = File('${data.path}/$relative');
      final size = await file.exists() ? await file.length() : 0;
      final room = emergencyLogMaxBytes - size;
      final bytes = room <= 0 ? null : await readBody(request, room);
      if (bytes == null) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        return response.close();
      }
      await file.parent.create(recursive: true);
      response.statusCode = await serialized(file, () async {
        final now = await file.exists() ? await file.length() : 0;
        if (now + bytes.length > emergencyLogMaxBytes) return HttpStatus.requestEntityTooLarge;
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        return HttpStatus.noContent;
      });
      return response.close();
    }
  }
  if (relative.endsWith('/')) {
    final dir = Directory('${data.path}/$relative');
    if (!await dir.exists()) return sendJson(response, []);
    return sendJson(response, [
      await for (final f in dir.list())
        if (f is File &&
            !f.path.endsWith('.tmp') &&
            !_isPrivate(f.uri.pathSegments.last) &&
            (admin || !_isKeyring(f.uri.pathSegments.last)))
          {'name': f.uri.pathSegments.last.replaceFirst(RegExp(r'\.ndjson\.gz$'), '.ndjson'), 'size': await f.length()},
    ]);
  }
  final file = File('${data.path}/$relative');
  // The server compresses completed history days; the app keeps asking for
  // "….ndjson" and gets them decompressed.
  final packed = File('${file.path}.gz');
  switch (request.method) {
    case 'GET':
      final exists = await file.exists();
      if (!exists && !await packed.exists()) {
        response.statusCode = HttpStatus.notFound;
        return response.close();
      }
      response.headers
        ..contentType = ContentType('application', 'octet-stream')
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      // A client that takes gzip (browsers, dart:io) gets the packed day as it
      // is: a quarter of the transfer, and the Pi does not unpack it.
      final gzipOk = (request.headers.value(HttpHeaders.acceptEncodingHeader) ?? '').contains('gzip');
      if (!exists && gzipOk) {
        response.headers
          ..set(HttpHeaders.contentEncodingHeader, 'gzip')
          ..set(HttpHeaders.varyHeader, 'Accept-Encoding');
        await response.addStream(packed.openRead());
      } else {
        await response.addStream(exists ? file.openRead() : packed.openRead().transform(gzip.decoder));
      }
    case 'PUT' || 'POST':
      // Receive completely first, then write (no half catalog on abort).
      final bytes = await readBody(request, admin ? _maxUpload : _maxDeviceUpload);
      if (bytes == null) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        break;
      }
      await file.parent.create(recursive: true);
      if (!admin) {
        final (list, key) = _deviceWritable[relative]!;
        final Object? incoming;
        try {
          incoming = jsonDecode(utf8.decode(bytes));
        } on FormatException {
          response.statusCode = HttpStatus.badRequest;
          break;
        }
        // Read, merge and write without another request in between.
        response.statusCode = await serialized(file, () async {
          final merged = mergeDeviceEntries(await _readJson(file), incoming, list: list, key: key, owner: owner!);
          if (merged == null) return HttpStatus.badRequest;
          final encoded = utf8.encode(jsonEncode(merged));
          if (encoded.length > _maxMerged) return HttpStatus.requestEntityTooLarge;
          await writeAtomicNow(file, bytes: encoded);
          return HttpStatus.noContent;
        });
        break;
      }
      if (request.method == 'PUT') {
        await writeAtomic(file, bytes: bytes);
      } else {
        await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
      }
      response.statusCode = HttpStatus.noContent;
    case 'DELETE':
      final found = [
        for (final f in [file, packed])
          if (await f.exists()) f,
      ];
      if (found.isEmpty) response.statusCode = HttpStatus.notFound;
      for (final f in found) {
        await f.delete();
      }
    default:
      response.statusCode = HttpStatus.methodNotAllowed;
  }
  await response.close();
}

Future<Object?> _readJson(File file) async {
  try {
    return await file.exists() ? jsonDecode(await file.readAsString()) : null;
  } on Object {
    // Unreadable: the device's entries replace it, like a write by the admin would.
    return null;
  }
}

/// What a device without admin rights ([owner]) may change in a file with a
/// list of entries under [list] (`charts`, `rules`), told apart by [key]
/// (`name`, `id`): its own entries. Entries of others, including the admin's
/// (without [ownerField]), stay as they are, also when [incoming] leaves them
/// out or brings an entry with the same key. The device's entries are marked
/// with its id. All other fields (such as `allowed`, the unlock of the
/// dashboard card) keep their stored value; `allowed` is `false` as long as
/// none is stored, so a device cannot unlock the card.
///
/// `null` if [incoming] is not an object, or its list is not a list of
/// objects with a text [key].
Map<String, Object?>? mergeDeviceEntries(
  Object? stored,
  Object? incoming, {
  required String list,
  required String key,
  required String owner,
}) {
  // Without the list: the device has no entries (any more).
  if (incoming is! Map || (incoming[list] != null && incoming[list] is! List)) return null;
  final entries = <Map<String, Object?>>[];
  for (final e in incoming[list] as List? ?? const []) {
    if (e is! Map || e[key] is! String) return null;
    entries.add({...e.cast<String, Object?>(), ownerField: owner});
  }
  final before = stored is Map ? stored.cast<String, Object?>() : const <String, Object?>{};
  final others = [
    for (final e in before[list] is List ? before[list] as List : const [])
      if (e is Map && e[ownerField] != owner) e.cast<String, Object?>(),
  ];
  final taken = {for (final e in others) e[key]};
  return {
    for (final MapEntry(key: field, :value) in incoming.cast<String, Object?>().entries)
      if (field != list && field != 'allowed') field: value,
    for (final MapEntry(key: field, :value) in before.entries)
      if (field != list && field != 'allowed') field: value,
    if (list == 'charts') 'allowed': before['allowed'] == true,
    if (list != 'charts' && before.containsKey('allowed')) 'allowed': before['allowed'],
    list: [
      ...others,
      for (final e in entries)
        if (!taken.contains(e[key])) e,
    ],
  };
}
