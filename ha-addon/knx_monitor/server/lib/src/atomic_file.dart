import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Running and queued writes per target path (see [writeAtomic]).
final _queues = <String, Future<void>>{};

final _random = Random.secure();

/// Writes [bytes] (or [text]) to [target] atomically: into a temporary file
/// with a random name next to it, then renamed over the target.
///
/// Writes to the same path run one after another, so two requests at once
/// can neither share a temporary file (one would rename the other's half
/// written file) nor overtake each other. The temporary name ends in `.tmp`,
/// which `/api/files/` never serves.
Future<void> writeAtomic(File target, {List<int>? bytes, String? text}) =>
    serialized(target, () => writeAtomicNow(target, bytes: bytes, text: text));

/// Runs [action] after all earlier actions for [target] have finished, also
/// failed ones. For read-modify-write cycles that must not interleave.
Future<T> serialized<T>(File target, Future<T> Function() action) {
  final key = target.absolute.path;
  final previous = _queues[key] ?? Future<void>.value();
  final next = previous.then((_) => action());
  final tail = next.then<void>((_) {}, onError: (Object _) {});
  _queues[key] = tail;
  // Forget the path once nothing is queued behind this write.
  unawaited(tail.whenComplete(() => identical(_queues[key], tail) ? _queues.remove(key) : null));
  return next;
}

/// [writeAtomic] without waiting for the queue: only inside [serialized] for
/// the same [target] (waiting there would wait for itself).
Future<void> writeAtomicNow(File target, {List<int>? bytes, String? text}) async {
  final suffix = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  final tmp = File('${target.path}.$suffix.tmp');
  try {
    if (bytes != null) {
      await tmp.writeAsBytes(bytes, flush: true);
    } else {
      await tmp.writeAsString(text ?? '', flush: true);
    }
    await tmp.rename(target.path);
  } on Object {
    try {
      if (await tmp.exists()) await tmp.delete();
    } on Object {
      // Nothing left to clean up.
    }
    rethrow;
  }
}
