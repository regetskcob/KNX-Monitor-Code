import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'box_clock.dart';
import 'bus.dart';
import 'files.dart';
import 'http.dart';
import 'recorder.dart';

/// An installation (customer, construction site, home) with its own bus connection,
/// ETS catalog, keyring and long-term history under `installations/<id>/`.
class Installation {
  Installation({required this.id, required this.name, required this.created});

  final String id;
  String name;
  final DateTime created;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'created': created.millisecondsSinceEpoch};

  factory Installation.fromJson(Map<String, Object?> j) => Installation(
    id: j['id']! as String,
    name: j['name'] as String? ?? '',
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
  );
}

/// Error while managing installations (status for the HTTP response).
class InstallationException implements Exception {
  InstallationException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Directory of the installations in the data folder (`installations.json`).
///
/// Only the server's own files stay in the root (`access.json`,
/// `time-request.json`); everything that belongs to an installation lives under
/// `installations/<id>/`. Switching happens via [InstallationService].
class Installations {
  Installations._(this.data);

  final Directory data;
  final _list = <Installation>[];
  late String _active;

  /// Ids as they come from the app (12 hex characters, UUIDs) – they end up in the file path.
  static final validId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// Name used when none can be derived (as in the app).
  static const defaultName = 'Installation';

  /// What lay in the root before installations existed and belongs to the
  /// installation. Not "everything except …": on the box the data folder is
  /// a separate file system (lost+found).
  static const migrated = [
    'server.json',
    'catalog.json',
    'dpt_overrides.json',
    'secure_keys.json',
    'health.json',
    'commissioning.json',
    'diagnostics.json',
    'availability.json',
    'history',
    'status',
    'recordings',
    'charts',
  ];

  File get _index => File('${data.path}/installations.json');

  List<Installation> get list => List.unmodifiable(_list);
  String get activeId => _active;
  Installation get active => byId(_active)!;

  /// Folder of the active installation.
  Directory get root => rootOf(_active);

  Directory rootOf(String id) => Directory('${data.path}/installations/$id');

  Installation? byId(String? id) => _list.where((i) => i.id == id).firstOrNull;

  /// Opens the directory; if it is missing, the previous data folder becomes
  /// the installation `default` (even if the data folder is empty).
  static Future<Installations> open(Directory data) async {
    final result = Installations._(data);
    await data.create(recursive: true);
    final existed = await result._index.exists();
    // First the index, then its backup; each entry individually, so that a
    // broken one (or one from a newer version) does not take all others with it.
    for (final (index, file) in [result._index, result._backup].indexed) {
      if (!existed || result._list.isNotEmpty || !await file.exists()) continue;
      try {
        result._read(jsonDecode(await file.readAsString()) as Map<String, Object?>);
      } on Object catch (e) {
        stderr.writeln('${file.uri.pathSegments.last}: $e');
      }
      if (result._list.isNotEmpty && index == 1) {
        // Set the broken index aside and write the recovered state, instead of
        // reading past it again on every start.
        stderr.writeln('installations.json unlesbar – Sicherung übernommen');
        await result._index.rename('${result._index.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        if (result.byId(result._active) == null) result._active = result._list.first.id;
        await result._save();
      }
    }
    if (result._list.isEmpty && existed) {
      // Index broken: do not overwrite it, set it aside and rebuild the list
      // from the existing folders.
      await result._index.rename('${result._index.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      await result._rebuild();
    }
    if (result._list.isEmpty) {
      await result._migrate();
    } else if (result.byId(result._active) == null) {
      result._active = result._list.first.id;
      await result._save();
    }
    await result.root.create(recursive: true);
    return result;
  }

  File get _backup => File('${_index.path}.bak');

  void _read(Map<String, Object?> j) {
    for (final e in (j['list'] as List? ?? const [])) {
      try {
        final i = Installation.fromJson((e as Map).cast<String, Object?>());
        if (validId.hasMatch(i.id) && byId(i.id) == null) _list.add(i);
      } on Object catch (error) {
        stderr.writeln('installations.json: Eintrag übersprungen: $error');
      }
    }
    final active = j['active'];
    _active = active is String ? active : '';
  }

  /// List built from the folders under `installations/` (name from the project).
  Future<void> _rebuild() async {
    final dir = Directory('${data.path}/installations');
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final id = e.uri.pathSegments.where((p) => p.isNotEmpty).last;
      if (e is! Directory || !validId.hasMatch(id)) continue;
      _list.add(Installation(id: id, name: await _projectName(e) ?? defaultName, created: (await e.stat()).modified));
    }
    if (_list.isEmpty) return;
    _active = _list.first.id;
    stderr.writeln('Installationen: Liste aus ${_list.length} Ordnern wiederhergestellt');
    await _save();
  }

  /// Moves the previous files from the root to `installations/default/`. Can be
  /// repeated after an abort: the directory is only created at the end.
  Future<void> _migrate() async {
    const id = 'default';
    final target = rootOf(id);
    await target.create(recursive: true);
    final names = [
      ...migrated,
      // Recording without a confirmed time, in case it was ever in the root.
      await for (final e in data.list())
        if (e is File && RegExp(r'^unsynced-\d+\.ndjson$').hasMatch(e.uri.pathSegments.last)) e.uri.pathSegments.last,
    ];
    var moved = 0;
    for (final name in names) {
      final source = '${data.path}/$name';
      final type = await FileSystemEntity.type(source);
      if (type == FileSystemEntityType.notFound) continue;
      final destination = '${target.path}/$name';
      if (await FileSystemEntity.type(destination) != FileSystemEntityType.notFound) {
        stderr.writeln('Installationen: $name liegt schon in $id, bleibt im Root');
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        await Directory(source).rename(destination);
      } else {
        await File(source).rename(destination);
      }
      moved++;
    }
    _list
      ..clear()
      ..add(Installation(id: id, name: await _projectName(target) ?? defaultName, created: DateTime.now()));
    _active = id;
    await _save();
    if (moved > 0) stdout.writeln('Installationen: $moved Einträge nach installations/$id verschoben');
  }

  static Future<String?> _projectName(Directory root) async {
    try {
      final file = File('${root.path}/catalog.json');
      if (!await file.exists()) return null;
      final name = (jsonDecode(await file.readAsString()) as Map<String, Object?>)['project'] as String?;
      return name == null || name.trim().isEmpty ? null : name.trim();
    } on Object {
      return null;
    }
  }

  Future<void> _save() async {
    // Keep the last readable state as a backup.
    if (await _index.exists()) {
      try {
        jsonDecode(await _index.readAsString());
        await _index.copy(_backup.path);
      } on Object {
        // Do not take over unreadable data as a backup.
      }
    }
    final tmp = File('${_index.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'active': _active,
        'list': [for (final i in _list) i.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_index.path);
  }

  static String _cleanName(Object? name) {
    final text = name is String ? name.trim() : '';
    if (text.isEmpty) throw InstallationException(HttpStatus.badRequest, 'Name fehlt.');
    return text.length > 80 ? text.substring(0, 80) : text;
  }

  /// Creates an installation. The app sends its own [id] so that box and app
  /// use the same one; otherwise one is generated.
  Future<Installation> create({String? id, required Object? name}) async {
    final clean = _cleanName(name);
    final newId = id ?? _newId();
    if (!validId.hasMatch(newId)) throw InstallationException(HttpStatus.badRequest, 'Ungültige Id.');
    if (byId(newId) != null) throw InstallationException(HttpStatus.conflict, 'Id gibt es schon.');
    await rootOf(newId).create(recursive: true);
    final installation = Installation(id: newId, name: clean, created: DateTime.now());
    _list.add(installation);
    await _save();
    return installation;
  }

  Future<Installation> rename(String id, Object? name) async {
    final installation = _require(id);
    installation.name = _cleanName(name);
    await _save();
    return installation;
  }

  /// Deletes an installation including its history; not the active one.
  Future<void> delete(String id) async {
    final installation = _require(id);
    if (id == _active) throw InstallationException(HttpStatus.conflict, 'Die aktive Installation bleibt.');
    _list.remove(installation);
    await _save();
    final dir = rootOf(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Remembers the active installation ([InstallationService] switches the services).
  Future<void> setActive(String id) async {
    _require(id);
    _active = id;
    await rootOf(id).create(recursive: true);
    await _save();
  }

  Installation _require(String id) =>
      byId(id) ?? (throw InstallationException(HttpStatus.notFound, 'Installation unbekannt.'));

  static String _newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  Map<String, Object?> toJson() => {
    'active': _active,
    'list': [
      for (final i in _list) {...i.toJson(), 'active': i.id == _active},
    ],
  };
}

/// Holds the bus connection of the active installation and switches it at
/// runtime: write the history, disconnect, close open views (the app
/// reconnects), and start a new [BusService] in the folder of the other
/// installation. Alarm and catalog state start over with it.
class InstallationService {
  InstallationService(this.installations, this._createBus, {this.clock});

  final Installations installations;
  final BusService Function(Directory root, Map<String, Object?> installation) _createBus;
  final BoxClock? clock;

  late BusService bus;
  Future<void> _switching = Future.value();

  /// Recorders of previous installations with rows without a confirmed time;
  /// they are converted as soon as the clock is set.
  final _unsynced = <Recorder>[];

  Map<String, Object?> get info => {'id': installations.activeId, 'name': installations.active.name};

  Future<void> start() async {
    bus = _createBus(installations.root, info);
    await bus.start();
    _chainClock();
  }

  void _chainClock() {
    final clock = this.clock;
    if (clock == null) return;
    final inner = clock.onSet;
    clock.onSet = (time, mono) {
      inner?.call(time, mono);
      for (final r in _unsynced) {
        unawaited(r.retime(time, mono));
      }
      _unsynced.clear();
    };
  }

  /// Switches the active installation; switches run one after another.
  Future<void> activate(String id) {
    final next = _switching.then((_) => _activate(id));
    _switching = next.catchError((Object _) {});
    return next;
  }

  Future<void> _activate(String id) async {
    if (installations.byId(id) == null) throw InstallationException(HttpStatus.notFound, 'Installation unbekannt.');
    if (id == installations.activeId) return;
    final old = bus;
    await old.shutdown();
    await old.closeClients();
    if (clock?.synced == false) _unsynced.add(old.recorder);
    await installations.setActive(id);
    stdout.writeln('Installation gewechselt: ${installations.active.name} ($id)');
    await start();
  }

  /// Renames; for the active one also in the bus status.
  Future<Installation> rename(String id, Object? name) async {
    final result = await installations.rename(id, name);
    if (id == installations.activeId) bus.installation = info;
    return result;
  }

  /// History of an installation (active: the running recorder).
  Recorder recorderOf(String id) =>
      id == installations.activeId ? bus.recorder : Recorder(installations.rootOf(id), retentionDays: 1);

  Availability availabilityOf(String id) =>
      id == installations.activeId ? bus.availability : Availability(installations.rootOf(id));

  /// When the server shuts down.
  Future<void> shutdown() async {
    await _switching;
    await bus.shutdown();
  }
}

/// `/api/installations…`; `true` if [request] has been answered by it.
///
/// - `GET /api/installations` → `{active, list: [{id, name, created, active}]}`
/// - `POST /api/installations` `{id?, name}` → new installation (201)
/// - `POST /api/installations/active` `{id}` → switches, response like GET
/// - `PATCH /api/installations/<id>` `{name}` → renamed
/// - `DELETE /api/installations/<id>` → deleted (not the active one: 409)
/// - `GET /api/installations/<id>/files/<rel>` → files of any installation,
///   read-only (also for device access)
///
/// Managing requires [admin] (box password or Ingress); anyone who gets past
/// the server's access check may read.
Future<bool> serveInstallations(HttpRequest request, InstallationService service, {required bool admin}) async {
  final path = request.uri.path;
  if (path != '/api/installations' && !path.startsWith('/api/installations/')) return false;
  final response = request.response;
  final installations = service.installations;
  final rest = path == '/api/installations' ? <String>[] : path.substring('/api/installations/'.length).split('/');
  final method = request.method;

  Future<void> deny(int status, String text) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(text);
    await response.close();
  }

  // Files of any installation, read-only.
  if (rest.length >= 3 && rest[1] == 'files') {
    if (installations.byId(rest[0]) == null) {
      await deny(HttpStatus.notFound, 'Installation unbekannt.');
      return true;
    }
    final prefix = '/api/installations/${rest[0]}/files/';
    await serveFile(
      request,
      installations.rootOf(rest[0]),
      path.substring(prefix.length),
      readOnly: true,
      admin: admin,
    );
    return true;
  }

  if (method == 'GET' && rest.isEmpty) {
    await sendJson(response, installations.toJson());
    return true;
  }
  if (!admin) {
    await deny(HttpStatus.forbidden, 'Nur mit dem Box-Passwort.');
    return true;
  }

  Map<String, Object?> body = const {};
  if (method == 'POST' || method == 'PATCH') {
    final raw = await readBody(request, 4096);
    if (raw == null) {
      await deny(HttpStatus.requestEntityTooLarge, 'Zu groß.');
      return true;
    }
    try {
      body = raw.isEmpty ? const {} : (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>();
    } on Object {
      await deny(HttpStatus.badRequest, 'Ungültige Anfrage.');
      return true;
    }
  }

  try {
    switch ((method, rest)) {
      case ('POST', []):
        final id = body['id'];
        if (id != null && id is! String) throw InstallationException(HttpStatus.badRequest, 'Ungültige Id.');
        final created = await installations.create(id: id as String?, name: body['name']);
        response.statusCode = HttpStatus.created;
        await sendJson(response, {...created.toJson(), 'active': false});
      case ('POST', ['active']):
        final id = body['id'];
        if (id is! String) throw InstallationException(HttpStatus.badRequest, 'Id fehlt.');
        await service.activate(id);
        await sendJson(response, installations.toJson());
      case ('PATCH', [final id]):
        final renamed = await service.rename(id, body['name']);
        await sendJson(response, {...renamed.toJson(), 'active': id == installations.activeId});
      case ('DELETE', [final id]):
        await installations.delete(id);
        response.statusCode = HttpStatus.noContent;
        await response.close();
      default:
        await deny(HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
    }
  } on InstallationException catch (e) {
    await deny(e.status, e.message);
  }
  return true;
}
