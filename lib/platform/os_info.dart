import 'os_info_io.dart' if (dart.library.js_interop) 'os_info_web.dart' as impl;

/// Operating system version or browser identification (for the diagnostics package).
String get operatingSystemVersion => impl.operatingSystemVersion;

/// System and version for a public issue, e.g. `macOS 15.1` ([shortPlatform]).
String get issuePlatform => impl.issuePlatform;

/// Short name of the system with its version, from `Platform.operatingSystem`
/// and `Platform.operatingSystemVersion` (e.g. `macOS 15.1`,
/// `Windows 11 Pro (Build 26100)`). Leaves out the kernel strings of Linux and
/// Android: they say little about a crash and can be long and specific.
String shortPlatform(String os, String version) {
  String? number() => RegExp(r'Version ([0-9.]+)').firstMatch(version)?.group(1);
  return switch (os) {
    'macos' => ['macOS', ?number()].join(' '),
    'ios' => ['iOS', ?number()].join(' '),
    'windows' => switch (RegExp(r'"([^"]+)"').firstMatch(version)?.group(1)) {
      final name? => [name, ?RegExp(r'\(Build \d+\)').firstMatch(version)?.group(0)].join(' '),
      null => 'Windows',
    },
    'android' => 'Android',
    'linux' => 'Linux',
    'web' => 'Browser',
    _ => os,
  };
}
