import 'pbkdf2_io.dart' if (dart.library.js_interop) 'pbkdf2_web.dart' as impl;

/// PBKDF2-HMAC-SHA256 via the browser's cryptography (Web Crypto) – orders of magnitude faster than
/// pure Dart in the browser. `null` if unavailable (native, or a page without HTTPS); then the
/// parser computes it itself.
Future<List<int>?> nativePbkdf2Sha256(List<int> password, List<int> salt, int iterations, int bytes) =>
    impl.nativePbkdf2Sha256(password, salt, iterations, bytes);
