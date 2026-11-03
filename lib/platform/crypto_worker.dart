import 'dart:async';
import 'dart:isolate';

/// Long-lived background isolate for encryption: even small files never run on the UI thread, and
/// not every call pays for starting an isolate. Jobs run in order. It ends after [_idle] without
/// work; the next job starts it again.
class CryptoWorker {
  static final instance = CryptoWorker();

  static const _idle = Duration(seconds: 30);

  Future<SendPort>? _port;
  ReceivePort? _replies;
  Timer? _idleTimer;
  var _nextId = 0;
  final _pending = <int, Completer<Object?>>{};

  /// Runs [job] in the worker. [job] must be a function without captured state; [argument] and
  /// result must be sendable. Errors arrive as text.
  Future<R> run<A, R>(R Function(A) job, A argument) async {
    _idleTimer?.cancel();
    final id = _nextId++;
    final done = Completer<Object?>();
    _pending[id] = done;
    try {
      final SendPort port = await (_port ??= Zone.root.run<Future<SendPort>>(_start));
      port.send((id, _Job<A, R>(job, argument)));
      return await done.future as R;
    } finally {
      _pending.remove(id);
      if (_pending.isEmpty) _idleTimer = Zone.root.createTimer(_idle, stop);
    }
  }

  Future<SendPort> _start() async {
    final replies = ReceivePort();
    _replies = replies;
    final ready = Completer<SendPort>();
    replies.listen((message) {
      switch (message) {
        case final SendPort port:
          ready.complete(port);
        case (final int id, final Object? value):
          _pending[id]?.complete(value);
        case (final int id, final Object error, final String stack):
          _pending[id]?.completeError(error, StackTrace.fromString(stack));
        default:
          // Isolate ended or crashed: nothing waiting may be left hanging.
          if (identical(_replies, replies)) _fail();
      }
    });
    await Isolate.spawn(_workerMain, replies.sendPort, onExit: replies.sendPort, onError: replies.sendPort);
    return ready.future;
  }

  void _fail() {
    _replies?.close();
    _replies = null;
    _port = null;
    final waiting = [..._pending.values];
    _pending.clear();
    for (final c in waiting) {
      if (!c.isCompleted) c.completeError(StateError('Verschlüsselung: Hintergrundprozess beendet'));
    }
  }

  /// Ends the isolate as soon as nothing is waiting any more.
  void stop() {
    if (_pending.isNotEmpty) return;
    final port = _port;
    _port = null;
    final replies = _replies;
    _replies = null;
    unawaited(port?.then((p) => p.send(null), onError: (Object _) {}));
    replies?.close();
  }
}

/// Keeps the job's types together.
class _Job<A, R> {
  const _Job(this.job, this.argument);
  final R Function(A) job;
  final A argument;
  Object? run() => job(argument);
}

void _workerMain(SendPort replies) {
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  requests.listen((message) {
    if (message == null) {
      requests.close();
      return;
    }
    final (id, job) = message as (int, _Job<dynamic, dynamic>);
    try {
      replies.send((id, job.run()));
    } on Object catch (e, st) {
      replies.send((id, '$e', '$st'));
    }
  });
}
