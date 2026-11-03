import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'storage.dart';

AppStorage createStorage() => _AddonStorage();

/// Storage in the data folder of the Home Assistant add-on ("api/files/…").
class _AddonStorage implements AppStorage {
  Uri _url(String path) => Uri.parse(web.document.baseURI).removeFragment().resolve('api/files/$path');

  static void _check(http.Response r) {
    if (r.statusCode >= 300) throw http.ClientException('${r.statusCode} ${r.body}', r.request?.url);
  }

  /// Reading failed (network, server): the store then holds an empty state. Until it works again it
  /// must not replace the file on the server.
  final _unread = <String>{};

  @override
  Future<String?> read(String path) async {
    try {
      final r = await http.get(_url(path));
      if (r.statusCode != 404) _check(r);
      _unread.remove(path);
      return r.statusCode == 404 ? null : utf8.decode(r.bodyBytes);
    } on Object {
      _unread.add(path);
      rethrow;
    }
  }

  @override
  Future<void> write(String path, String text) async {
    if (_unread.contains(path)) throw http.ClientException('$path wurde nicht gelesen, nicht überschrieben');
    _check(await http.put(_url(path), body: utf8.encode(text)));
  }

  @override
  Future<void> append(String path, String text) async => _check(await http.post(_url(path), body: utf8.encode(text)));

  @override
  Future<List<StoredFile>> list(String dir) async {
    final r = await http.get(_url('$dir/'));
    if (r.statusCode == 404) return [];
    _check(r);
    return [
      for (final e in jsonDecode(r.body) as List<Object?>)
        if (e case {'name': final String name, 'size': final int size}) (name: name, size: size),
    ];
  }

  @override
  Future<void> delete(String path) async {
    final r = await http.delete(_url(path));
    if (r.statusCode != 404) _check(r);
  }
}

Future<void> encryptExistingFiles() async {}

Future<List<String>> allStoredPaths() async => const [];

Future<StorageExtras> storageExtras() async => noStorageExtras;

Future<void> deleteQuarantinedFiles() async {}
