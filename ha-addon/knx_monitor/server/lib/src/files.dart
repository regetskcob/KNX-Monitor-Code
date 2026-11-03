import 'dart:io';

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
};

/// The installation's keyring (KNX Secure): only the server reads it and uses it
/// to record secured telegrams; the app only compares ([admin]). A paired device
/// without admin rights does not need it: its keyring lives in its own keychain,
/// and this file would give it all group keys.
const _adminOnly = 'secure_keys.json';

/// What a device without admin rights may store: its own charts and watchers.
/// Everything else (project, fault hunt, history) changes the installation for everyone.
const _deviceWritable = {'charts.json', 'watch_rules.json'};

/// Upper limit per upload without admin rights.
const _maxDeviceUpload = 1024 * 1024;

bool _isKeyring(String name) => name == _adminOnly || name.startsWith('$_adminOnly.');

/// Whether [name] belongs to the server. Backups and set-aside copies
/// (`access.json.bak`, `installations.json.corrupt-…`) contain the same
/// secrets too.
bool _isPrivate(String name) => _private.any((p) => name == p || name.startsWith('$p.'));

bool _deviceMayWrite(HttpRequest request, String relative) =>
    request.method == 'PUT' && _deviceWritable.contains(relative);

/// Upper limit per upload. Generous for catalogs of large projects, but prevents
/// a single request from filling the add-on's memory.
const _maxUpload = 64 * 1024 * 1024;

/// `/api/files/<relative>` in the data folder [data]: read (GET, with a trailing
/// `/` the listing), write (PUT), append (POST), delete (DELETE). With
/// [readOnly] read only (installations that are not currently active). Without
/// [admin] (device from `/pair`) no keyring and hardly any write access.
Future<void> serveFile(
  HttpRequest request,
  Directory data,
  String relative, {
  bool readOnly = false,
  bool admin = true,
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
  if (_isPrivate(relative.split('/').first) || relative.endsWith('.tmp')) {
    response.statusCode = HttpStatus.forbidden;
    return response.close();
  }
  if (!admin &&
      (relative.split('/').any(_isKeyring) || (request.method != 'GET' && !_deviceMayWrite(request, relative)))) {
    response
      ..statusCode = HttpStatus.forbidden
      ..headers.contentType = ContentType.text
      ..write('Nur mit dem Box-Passwort.');
    return response.close();
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
      await response.addStream(exists ? file.openRead() : packed.openRead().transform(gzip.decoder));
    case 'PUT' || 'POST':
      // Receive completely first, then write (no half catalog on abort).
      final bytes = await readBody(request, admin ? _maxUpload : _maxDeviceUpload);
      if (bytes == null) {
        response.statusCode = HttpStatus.requestEntityTooLarge;
        break;
      }
      await file.parent.create(recursive: true);
      if (request.method == 'PUT') {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
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
