/// Event channel `/ws/events`: the server's events for clients without
/// Supervisor (the Busclear integration with a box or Docker, a future
/// ioBroker adapter). Format and rules in `docs/event-channel.md`.
///
/// It carries exactly what the add-on fires on Home Assistant's event bus
/// ([HomeAssistant.watcherEvent], [HomeAssistant.alarmEvent],
/// [HomeAssistant.busEvent]): [serverEventSink] hands every event of a
/// [BusService] to both, so the two ways cannot drift apart.
///
/// Text messages only, JSON, each with `"v": 1` ([formatVersion]):
///
/// - `hello` once after connecting: `seq` (last sequence number), `epoch`
///   (changes with every server start), `server` (version), `heartbeat_s`,
///   `resumed` (see below).
/// - `event` per event: `seq`, `time` (UTC), `event` (`knx_monitor_…`), `data`.
/// - `heartbeat` every [heartbeat] with the current `seq`, also when nothing
///   happens, so a client notices a dead connection and missed events.
///
/// No history: only a small ring of the last [ringSize] events. A client that
/// reconnects with `?since=<seq>&epoch=<epoch>` gets the events after `since`
/// that are still in the ring, right after the hello; `resumed` says whether
/// nothing in between is missing.
///
/// Each connection has a bounded queue ([maxQueuedBytes]): a client that
/// stops reading is disconnected instead of holding back the others or
/// filling the memory. Messages from the client are ignored (a large one ends
/// the connection). At most [maxClients] connect at once, at most
/// [maxPerOwner] with the same device (or from the same address), and the
/// last [reservedForAdmin] places only with admin rights: a viewer cannot take
/// every place and lock out the Home Assistant integration.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:pointycastle/digests/sha1.dart';

import 'bus.dart';
import 'ha.dart';

/// Path of the event channel.
const eventsPath = '/ws/events';

/// Event sink for [BusService.event]: every event goes to the event channel,
/// to [others] (the MQTT device) and to Home Assistant through the Supervisor
/// (does nothing without one), in that order and with the same data.
Future<void> Function(String type, Map<String, Object?> data) serverEventSink({
  required EventChannel channel,
  required HomeAssistant homeAssistant,
  void Function(String type, Map<String, Object?> data)? others,
}) => (type, data) async {
  channel.publish(type, data);
  others?.call(type, data);
  await homeAssistant.fire(type, data);
};

class EventChannel {
  EventChannel({
    this.server = 'dev',
    this.maxClients = 8,
    this.maxPerOwner = 2,
    this.reservedForAdmin = 1,
    this.ringSize = 64,
    this.heartbeat = const Duration(seconds: 30),
    this.ping = webSocketPing,
    this.maxQueuedBytes = 256 * 1024,
    DateTime Function() clock = DateTime.now,
    String? epoch,
  }) : _clock = clock,
       epoch = epoch ?? _newEpoch();

  /// Version of the message format; a client ignores messages with another one.
  /// The integration learns from `events` in `/api/ha/state` that the channel exists.
  static const formatVersion = 1;

  /// Version of the server, in the hello.
  final String server;
  final int maxClients;

  /// Connections of one device or address (a reconnect while the old one is
  /// not yet noticed as gone still fits).
  final int maxPerOwner;

  /// Places kept free for admin devices (the Home Assistant integration).
  final int reservedForAdmin;
  final int ringSize;
  final Duration heartbeat;

  /// WebSocket ping: a client that answers none is closed after two intervals.
  final Duration ping;

  /// Bytes waiting for one client before it counts as too slow and is disconnected.
  final int maxQueuedBytes;
  final DateTime Function() _clock;

  /// Changes with every start: sequence numbers count from 1 again.
  final String epoch;

  /// Largest message a client may send; it has nothing to say anyway.
  static const maxClientMessage = 1024;

  var _seq = 0;
  final _ring = Queue<({int seq, String text})>();
  final _clients = <_EventClient>{};

  /// Taken places, from the check until the connection ends (also during the upgrade).
  final _places = <({String? owner, bool admin})>[];
  Timer? _beat;

  /// Sequence number of the last event (0 before the first).
  int get seq => _seq;

  int get clientCount => _clients.length;

  /// Whether another client of [owner] fits (checked before the upgrade).
  /// [owner] `null`: no limit per owner (add-on, where only Ingress gets in).
  bool acceptsClient({String? owner, bool admin = true}) {
    if (_places.length >= (admin ? maxClients : maxClients - reservedForAdmin)) return false;
    return owner == null || _places.where((p) => p.owner == owner).length < maxPerOwner;
  }

  /// Clients disconnected for not reading (since start).
  int dropped = 0;

  static String _newEpoch() {
    final random = Random.secure();
    return [for (var i = 0; i < 8; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  String _now() => _clock().toUtc().toIso8601String();

  /// Sends an event to every client and keeps it in the ring. Never throws:
  /// an event that cannot be encoded (a NaN value) is only logged.
  void publish(String type, Map<String, Object?> data) {
    final String text;
    try {
      text = jsonEncode({
        'v': formatVersion,
        'type': 'event',
        'seq': _seq + 1,
        'time': _now(),
        'event': type,
        'data': data,
      });
    } on Object catch (e) {
      stderr.writeln('Ereigniskanal: $type nicht kodierbar: $e');
      return;
    }
    _seq++;
    _ring.add((seq: _seq, text: text));
    while (_ring.length > ringSize) {
      _ring.removeFirst();
    }
    for (final client in _clients.toList()) {
      client.send(text);
    }
  }

  String _heartbeat() => jsonEncode({'v': formatVersion, 'type': 'heartbeat', 'seq': _seq, 'time': _now()});

  void _startBeat() => _beat ??= Timer.periodic(heartbeat, (_) {
    final text = _heartbeat();
    for (final client in _clients.toList()) {
      client.send(text);
    }
  });

  void _stopBeatIfIdle() {
    if (_clients.isNotEmpty) return;
    _beat?.cancel();
    _beat = null;
  }

  /// Answers [request] for [eventsPath]; the caller checked the access.
  /// [owner]: the paired device's id or the sender's address (box, Docker);
  /// [admin]: whether it has admin rights (see [reservedForAdmin]).
  Future<void> serve(HttpRequest request, {String? owner, bool admin = true}) async {
    final response = request.response;
    if (request.method != 'GET' || !WebSocketTransformer.isUpgradeRequest(request)) {
      response
        ..statusCode = HttpStatus.upgradeRequired
        ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
        ..write('WebSocket erwartet.');
      return response.close();
    }
    if (!acceptsClient(owner: owner, admin: admin)) {
      response
        ..statusCode = HttpStatus.serviceUnavailable
        ..headers.set(HttpHeaders.retryAfterHeader, '10');
      return response.close();
    }
    final place = (owner: owner, admin: admin);
    _places.add(place);
    try {
      await _serve(request);
    } finally {
      _places.remove(place);
    }
  }

  Future<void> _serve(HttpRequest request) async {
    // Not closed: its socket is detached for the WebSocket below.
    // ignore: close_sinks
    final response = request.response;
    final q = request.uri.queryParameters;
    final since = int.tryParse(q['since'] ?? '');
    final sameEpoch = q['epoch'] == epoch;
    // The upgrade by hand (as WebSocketTransformer does it) to keep the
    // socket: a client that stops reading is cut off with destroy().
    final key = request.headers.value('sec-websocket-key')!.trim();
    response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('Sec-WebSocket-Accept', acceptKey(key))
      ..headers.contentLength = 0;
    // Both end with the connection: the WebSocket closes the socket, and
    // _EventClient closes or destroys them (close, closeClients, too slow).
    // ignore: close_sinks
    final socket = await response.detachSocket();
    // ignore: close_sinks
    final ws = WebSocket.fromUpgradedSocket(
      socket,
      serverSide: true,
      compression: webSocketCompression,
      // dart:io refuses larger frames (1002) before assembling them, so a client cannot make
      // the server hold more than maxClientMessage per message.
      maxPayloadLength: maxClientMessage,
    )..pingInterval = ping;
    final client = _EventClient(ws, socket, maxQueuedBytes: maxQueuedBytes, onDrop: () => dropped++);
    _clients.add(client);
    _startBeat();
    final missing = sameEpoch && since != null && since >= 0 && since <= _seq
        ? [
            for (final e in _ring)
              if (e.seq > since) e,
          ]
        : const <({int seq, String text})>[];
    // Resumed: nothing after `since` fell out of the ring (or nothing happened).
    final resumed =
        sameEpoch &&
        since != null &&
        since >= 0 &&
        since <= _seq &&
        (since == _seq || missing.firstOrNull?.seq == since + 1);
    client.send(
      jsonEncode({
        'v': formatVersion,
        'type': 'hello',
        'seq': _seq,
        'epoch': epoch,
        'server': server,
        'heartbeat_s': heartbeat.inSeconds,
        'resumed': resumed,
      }),
    );
    for (final e in missing) {
      client.send(e.text);
    }
    try {
      await for (final message in ws) {
        final length = message is String ? message.length : (message is List<int> ? message.length : 0);
        if (length > maxClientMessage) {
          await client.close(WebSocketStatus.messageTooBig, 'too big');
          break;
        }
      }
    } on Object {
      // Connection gone.
    } finally {
      client.dispose();
      _clients.remove(client);
      _stopBeatIfIdle();
    }
  }

  /// Closes every connection (access changed: revoked devices must not keep
  /// listening); clients reconnect and are checked again.
  Future<void> closeClients({int code = WebSocketStatus.policyViolation, String reason = 'access changed'}) async {
    final clients = _clients.toList();
    _clients.clear();
    _stopBeatIfIdle();
    await Future.wait([for (final c in clients) c.close(code, reason)]);
  }

  /// Stops the heartbeat and closes every connection (shutdown, tests).
  Future<void> close() => closeClients(code: WebSocketStatus.goingAway, reason: 'shutdown');

  /// `Sec-WebSocket-Accept` for [key] (RFC 6455, section 4.2.2).
  static String acceptKey(String key) =>
      base64.encode(SHA1Digest().process(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')));
}

/// One connection: messages go through its own queue into the WebSocket,
/// which pauses while the socket cannot write ([StreamController.isPaused]).
class _EventClient {
  _EventClient(this.ws, this.socket, {required this.maxQueuedBytes, required this.onDrop}) {
    _out = StreamController<String>(sync: true, onResume: _pump);
    _added = ws.addStream(_out.stream).catchError((Object _) => null);
  }

  final WebSocket ws;
  final Socket socket;
  final int maxQueuedBytes;
  final void Function() onDrop;
  late final StreamController<String> _out;
  late final Future<Object?> _added;
  // Each message with its UTF-8 size: the limit is in bytes, not characters.
  final _queue = Queue<(String, int)>();
  var _queued = 0;
  var _closed = false;

  void send(String text) {
    if (_closed) return;
    final bytes = utf8.encode(text).length;
    _queue.add((text, bytes));
    _queued += bytes;
    if (_queued > maxQueuedBytes) {
      // Not reading: cut off, it reconnects once it reads again.
      onDrop();
      _closed = true;
      _queue.clear();
      socket.destroy();
      return;
    }
    _pump();
  }

  void _pump() {
    while (!_closed && !_out.isPaused && !_out.isClosed && _queue.isNotEmpty) {
      final (text, bytes) = _queue.removeFirst();
      _queued -= bytes;
      _out.add(text);
    }
  }

  Future<void> close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _queue.clear();
    // Not awaited: the done event waits behind data a stalled client never reads.
    unawaited(_out.close());
    try {
      // A client that does not read would keep both waiting.
      await _added.timeout(const Duration(seconds: 2));
      await ws.close(code, reason).timeout(const Duration(seconds: 2));
    } on Object {
      socket.destroy();
    }
  }

  void dispose() {
    _closed = true;
    _queue.clear();
    if (!_out.isClosed) unawaited(_out.close());
  }
}
