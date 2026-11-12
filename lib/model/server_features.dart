import 'package:flutter/foundation.dart';

/// What the add-on server or box the app is connected to can do beyond the basics, as it reports
/// in its status (`features`). Empty without a server and for older servers: the app then does the
/// work itself.
class ServerFeatures extends ValueNotifier<Set<String>> {
  ServerFeatures._() : super(const {});

  static final instance = ServerFeatures._();

  /// The server checks watchers of the kind `bits` (flags of a datapoint, e.g. DALI diagnostics).
  bool get bitsCheck => value.contains('bitsCheck');

  /// The server reports DALI faults per luminaire and keeps the emergency lighting log.
  bool get dali => value.contains('dali');

  /// Whether a server status arrived (on a server's tunnel: before it, nothing is known).
  bool known = false;

  /// Takes the features from a server status; `null` = no server.
  void update(Map<String, Object?>? status) {
    known = status != null;
    final features = status?['features'];
    final next = {
      if (features is List)
        for (final f in features.take(64))
          if (f is String) f,
    };
    if (!setEquals(next, value)) value = next;
  }
}
