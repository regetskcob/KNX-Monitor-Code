import 'os_info_io.dart' if (dart.library.js_interop) 'os_info_web.dart' as impl;

/// Operating system version or browser identification (for the diagnostics package).
String get operatingSystemVersion => impl.operatingSystemVersion;
