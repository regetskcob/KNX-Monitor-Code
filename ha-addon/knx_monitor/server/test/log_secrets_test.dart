import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:knx_monitor_server/bus.dart';
import 'package:test/test.dart';

/// What goes to the log never contains a credential (code review, issue KNX-Monitor-Code#3): the
/// add-on's log is readable for every Home Assistant admin and ends up in bug reports.
void main() {
  /// Runs [body] and returns everything it wrote to stdout and stderr.
  Future<String> logOf(Future<void> Function() body) async {
    // In-memory stand-ins for the process's streams: nothing to close.
    // ignore: close_sinks
    final out = _Capture();
    // ignore: close_sinks
    final err = _Capture();
    await IOOverrides.runZoned(body, stdout: () => out, stderr: () => err);
    return '${out.text}\n${err.text}';
  }

  test('Home Assistant unreachable or refusing: the log names the event, not the token', () async {
    const token = 'tok_3f9a-SUPERVISOR-secret';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      // Echoing the header back would be the worst case for a careless log line.
      request.response
        ..statusCode = HttpStatus.unauthorized
        ..write(request.headers.value(HttpHeaders.authorizationHeader));
      await request.response.close();
    });
    final refusing = HomeAssistant(token: token, base: Uri.parse('http://127.0.0.1:${server.port}/core/'));
    final port = server.port;
    final log = await logOf(() async {
      await refusing.fire(HomeAssistant.busEvent, {'connected': false});
      await refusing.refreshKnx();
      await server.close(force: true);
      // Nothing listens any more: connection errors carry the address, never the header.
      final gone = HomeAssistant(token: token, base: Uri.parse('http://127.0.0.1:$port/core/'));
      await gone.fire(HomeAssistant.watcherEvent, {'watcher_id': 'w1'});
      await gone.refreshKnx();
    });
    expect(log, contains('Ereignis'), reason: 'the failures are logged at all');
    expect(log, isNot(contains(token)));
    expect(log.toLowerCase(), isNot(contains('bearer')));
  });

  test('no log line in the server prints a credential variable', () {
    // A line that writes to the log and interpolates something named like a secret. Counted, so
    // a new one has to be looked at; today there is none.
    final secret = RegExp(r'\$\{?[A-Za-z_.]*(token|password|passwort|secret|credential)', caseSensitive: false);
    final hits = <String>[];
    for (final dir in ['lib', 'bin']) {
      for (final file in Directory(dir).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!RegExp(r'(stdout|stderr)\.write|print\(').hasMatch(lines[i])) continue;
          // The statement may span lines: look until its semicolon.
          final statement = StringBuffer();
          for (var j = i; j < lines.length && j < i + 12; j++) {
            statement.writeln(lines[j]);
            if (lines[j].trimRight().endsWith(';')) break;
          }
          if (secret.hasMatch('$statement')) hits.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(hits, isEmpty, reason: 'log statements that interpolate a credential');
  });
}

class _Capture implements Stdout {
  final _buffer = StringBuffer();
  String get text => '$_buffer';

  @override
  void writeln([Object? object = '']) => _buffer.writeln(object);
  @override
  void write(Object? object) => _buffer.write(object);
  @override
  void writeAll(Iterable<dynamic> objects, [String sep = '']) => _buffer.writeAll(objects, sep);
  @override
  void writeCharCode(int charCode) => _buffer.writeCharCode(charCode);
  @override
  void add(List<int> data) => _buffer.write(utf8.decode(data, allowMalformed: true));
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding value) {}
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> get done async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
