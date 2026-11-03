import 'package:flutter/foundation.dart';

/// Compile-time switch for the company edition: `--dart-define=BETRIEB=true`.
const _compiled = bool.fromEnvironment('BETRIEB');

/// The company edition (standard, group address assistant, check, safe mode,
/// installation notes) is not ready yet and must not show publicly: without the
/// switch there are no menu entries and no changed behavior. In release builds
/// [enabled] is a constant, so the compiler drops everything behind it,
/// including texts, from the shipped app.
abstract final class Betrieb {
  /// For tests only; has no effect in release builds.
  @visibleForTesting
  static bool debugEnabled = false;

  static bool get enabled => _compiled || (!kReleaseMode && debugEnabled);
}
