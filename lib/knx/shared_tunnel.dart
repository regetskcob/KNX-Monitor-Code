import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';
import '../platform/addon.dart';
import 'gateway_info.dart';
import 'knx_tunnel.dart';
import '../model/tap_points.dart';
import 'telegram.dart';

/// The shared tunnel of the Home Assistant add-on or the Busclear Box.
///
/// The add-on server holds the bus connection permanently, records and distributes the frames to
/// all open views; this class is one of them. To the outside a perfectly normal [KnxTunnel]:
/// disconnecting only closes the view, the server stays connected.
class SharedTunnel extends KnxTunnel {
  SharedTunnel({String host = '', int port = 3671, Future<AddonSocket> Function()? open})
    : _open = open ?? Addon.openBus,
      super(host, port: port);

  final Future<AddonSocket> Function() _open;

  /// Last status of the server (connection, recording, settings).
  final status = ValueNotifier<Map<String, Object?>>(const {});

  final _watchHits = StreamController<({List<String> ids, Telegram telegram})>.broadcast();

  /// Watchers that the server checked and that triggered.
  Stream<({List<String> ids, Telegram telegram})> get watchHits => _watchHits.stream;

  AddonSocket? _socket;
  StreamSubscription<Uint8List>? _sub;
  final _pending = <int, Completer<(int, String)>>{};
  int _nextId = 1;
  Completer<void>? _connected;
  Completer<void>? _released;

  /// "Connecting to the bus", depending on whether the server runs in the add-on or on the box.
  static String get _connecting => Addon.box != null ? s.boxConnecting : s.addonConnecting;

  /// Whether the connection to the add-on server is up (the bus itself may not be yet).
  bool get attached => _socket != null;

  /// Whether the server runs read-only and sends nothing to the bus.
  bool get readOnly => status.value['readOnly'] == true;

  /// This device is paired with the box for viewing only (implies [readOnly]).
  bool get viewOnly => status.value['viewOnly'] == true;

  @override
  bool get supportsBusMonitor =>
      _config['mode'] == 'hat' ? serverBusMonitor : !const {'routing', 'ha', 'secure'}.contains(_config['mode']);

  /// KNX HAT in bus monitor mode: the raw frames including acknowledgements come from the server
  /// over this connection ([busmon]), no separate bus monitor tunnel.
  bool get serverBusMonitor => _config['mode'] == 'hat' && _config['hatBusmonitor'] == true;

  Map<String, Object?> get _config => (status.value['config'] as Map?)?.cast<String, Object?>() ?? const {};

  @override
  String get kind {
    final via = Addon.box == null ? 'Add-on' : 'Box';
    return switch (_config['mode']) {
      'tcp' => '$via · TCP',
      'routing' => '$via · Routing',
      'secure' => '$via · IP Secure',
      'ha' => '$via · Home Assistant',
      'hat' => '$via · KNX-HAT',
      _ => '$via · UDP',
    };
  }

  /// Gateway according to the server (for titles and reports).
  String get gateway => switch (_config['mode']) {
    'routing' => 'Routing',
    'ha' => 'Home Assistant',
    'hat' => 'KNX-HAT',
    _ => _config['host'] as String? ?? host,
  };

  @override
  Future<void> connect({Duration timeout = const Duration(seconds: 10)}) async {
    if (state.value == TunnelState.connected) return;
    try {
      if (_socket == null) {
        _socket = await _open();
        _sub = _socket!.messages.listen(_onMessage, onError: (Object e) => _closed('$e'), onDone: () => _closed(null));
      }
      if (status.value['state'] == 'connected') return;
      state.value = TunnelState.connecting;
      _connected = Completer();
      await _connected!.future.timeout(timeout);
    } on AddonException catch (e) {
      _drop();
      throw KnxException(e.message, connectProblemNamed(e.problem));
    } on TimeoutException {
      // The server keeps trying; the view shows why it fails – with a reason, also the connection
      // help as in the app.
      state.value = TunnelState.disconnected;
      final reason = status.value['error'] as String?;
      error.value = reason ?? _connecting;
      throw KnxException(reason ?? _connecting, connectProblemNamed(status.value['problem'] as String?));
    }
  }

  void _onMessage(Uint8List m) {
    if (m.isEmpty) return;
    switch (m[0]) {
      case 0x01:
        receiveCemi(Uint8List.sublistView(m, 1));
      // Frame from a further tap point of the server (issue #8): tap number, then cEMI.
      case 0x04 when m.length > 2:
        receiveCemiAt(m[1], Uint8List.sublistView(m, 2));
      case 0x02:
        _onStatus(jsonDecode(utf8.decode(m.sublist(1))) as Map<String, Object?>);
      case 0x03:
        final j = jsonDecode(utf8.decode(m.sublist(1))) as Map<String, Object?>;
        _watchHits.add((
          ids: (j['ids'] as List? ?? const []).cast<String>(),
          telegram: Telegram.fromJson((j['line']! as Map).cast<String, Object?>()),
        ));
      case 0x11 when m.length >= 4:
        _pending.remove((m[1] << 8) | m[2])?.complete((m[3], utf8.decode(m.sublist(4), allowMalformed: true)));
    }
  }

  /// Releases the server's tunnel slot for the bus monitor ([release]) or gives it back. The view
  /// stays connected; if it disconnects, the server reconnects on its own. When releasing, returns
  /// only once the server has closed its tunnel.
  Future<void> releaseTunnel(bool release) async {
    final socket = _socket;
    if (socket == null) return;
    final released = _released = release ? Completer<void>() : null;
    socket.send([0x12, release ? 1 : 0]);
    if (released != null && status.value['state'] != 'yielded') {
      await released.future.timeout(const Duration(seconds: 5), onTimeout: () {});
    }
  }

  void _onStatus(Map<String, Object?> j) {
    status.value = j;
    _followTaps(j);
    if (j['state'] == 'yielded') {
      // The bus monitor has the slot – no error, no automatic reconnect.
      if (!(_released?.isCompleted ?? true)) _released!.complete();
      error.value = null;
      state.value = TunnelState.disconnected;
      return;
    }
    final description = j['description'] as String?;
    if (description == null && j['state'] == 'connected' && gatewayInfo.value != null) {
      // Connected without a gateway (KNX HAT, routing, Home Assistant): do not leave the previous
      // gateway's description in place.
      gatewayInfo.value = null;
      deviceName.value = null;
    } else if (description != null && gatewayInfo.value == null) {
      final info = GatewayInfo.parse(Uint8List.fromList(parseHex(description) ?? const []));
      if (info != null) {
        gatewayInfo.value = info;
        if (info.name.isNotEmpty) deviceName.value = info.name;
      }
    }
    tunnelAddress = j['address'] as int?;
    if (j['state'] == 'connected') {
      error.value = null;
      state.value = TunnelState.connected;
      if (!(_connected?.isCompleted ?? true)) _connected!.complete();
    } else if (state.value == TunnelState.connected) {
      // The server lost the bus and reconnects itself.
      error.value = (j['error'] as String?) ?? _connecting;
      state.value = TunnelState.disconnected;
    }
  }

  /// Tap points of the server (status `taps`, issue #8): labels for the chips, state for the banner,
  /// merging of the `0x04` frames. Without the key (older server, single tap point) nothing changes.
  void _followTaps(Map<String, Object?> j) {
    final taps = j['taps'];
    if (taps is! List || taps.isEmpty) {
      if (tapPoints.value.isNotEmpty) {
        tapPoints.value = const [];
        tapLabels.value = const [];
        useTaps(1);
      }
      return;
    }
    final mainState = j['state'] == 'connected' ? TunnelState.connected : TunnelState.disconnected;
    final list = <TapStatus>[
      TapStatus(
        index: 0,
        name: (j['link'] as String?) ?? host,
        label: tapLabel(j['address'] as int?, '1'),
        state: mainState,
        error: j['error'] as String?,
        autoWindow: switch (j['autoWindowMs']) {
          final int ms => Duration(milliseconds: ms),
          _ => null,
        },
      ),
      for (final (i, raw) in taps.indexed)
        if (raw is Map)
          TapStatus(
            index: i + 1,
            name: raw['name'] as String? ?? '${i + 2}',
            label: tapLabel(raw['address'] as int?, raw['name'] as String? ?? '${i + 2}'),
            state: raw['state'] == 'connected' ? TunnelState.connected : TunnelState.disconnected,
            error: raw['error'] as String?,
            paused: raw['paused'] == true,
            silent: raw['silent'] == true,
            autoWindow: switch (raw['autoWindowMs']) {
              final int ms => Duration(milliseconds: ms),
              _ => null,
            },
          ),
    ];
    tapPoints.value = list;
    tapLabels.value = [for (final p in list) p.label];
    useTaps(
      list.where((p) => p.connected).length,
      windows: {
        for (final (i, raw) in taps.indexed)
          if (raw is Map && raw['windowMs'] is int) i + 1: Duration(milliseconds: raw['windowMs']! as int),
      },
    );
  }

  void _closed(String? reason) {
    _drop();
    if (state.value != TunnelState.disconnected) {
      error.value = Addon.box != null ? s.boxConnectionLost : s.addonConnectionLost;
      state.value = TunnelState.disconnected;
    }
  }

  void _drop() {
    _sub?.cancel();
    _sub = null;
    _socket?.close();
    _socket = null;
    for (final p in _pending.values) {
      if (!p.isCompleted) p.complete((1, ''));
    }
    _pending.clear();
  }

  @override
  Future<void> disconnect() async {
    _drop();
    error.value = null;
    state.value = TunnelState.disconnected;
  }

  @override
  @protected
  Future<void> transmit(Uint8List cemi) async {
    final socket = _socket;
    if (socket == null || state.value != TunnelState.connected) throw KnxException(s.errorNotConnected);
    final id = _nextId;
    _nextId = (_nextId % 0xFFFF) + 1;
    final done = Completer<(int, String)>();
    _pending[id] = done;
    socket.send([0x10, id >> 8, id & 0xFF, ...cemi]);
    final (result, text) = await done.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pending.remove(id);
        return (2, s.errorNoAck);
      },
    );
    switch (result) {
      case 0:
        return;
      case 1:
        throw KnxException(s.errorNotConnected);
      case 4:
        throw KnxException(s.addonDeviceBusy);
      case 6:
        throw KnxException(s.addonReadOnly);
      default:
        throw KnxException(text.isEmpty ? s.errorNoAck : text);
    }
  }

  @override
  void dispose() {
    _drop();
    _watchHits.close();
    super.dispose();
  }
}
