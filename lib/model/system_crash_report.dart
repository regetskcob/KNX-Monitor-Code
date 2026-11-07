import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../platform/process_info.dart' as process;

/// The kind of error and the faulting module from the operating system's own
/// crash report of this app (public issue #4). Only these two fields are taken:
/// the report also names paths, the user name and memory contents.
@immutable
class SystemCrashReport {
  const SystemCrashReport({required this.system, required this.time, required this.kind, this.module});

  /// `macOS` or `Windows`.
  final String system;

  /// When the system wrote the report.
  final DateTime time;

  /// E.g. `EXC_BAD_ACCESS (SIGSEGV)` or `EXCEPTION_ACCESS_VIOLATION (0xc0000005)`.
  final String kind;

  /// File name of the faulting image or module (`FlutterMacOS`,
  /// `flutter_windows.dll`), without its folder.
  final String? module;

  /// For the diagnostics package.
  Map<String, Object?> toJson() => {
    'system': system,
    'time': time.toUtc().toIso8601String(),
    'kind': kind,
    'module': ?module,
  };

  @override
  bool operator ==(Object other) =>
      other is SystemCrashReport &&
      other.system == system &&
      other.time == time &&
      other.kind == kind &&
      other.module == module;

  @override
  int get hashCode => Object.hash(system, time, kind, module);

  /// Reads a macOS `.ips` report: a JSON header line, then the JSON body.
  /// `null` if it is not a crash report of [executable] or cannot be read.
  static SystemCrashReport? parseIps(String text, {String? executable}) {
    try {
      final newline = text.indexOf('\n');
      if (newline < 0) return null;
      final header = (jsonDecode(text.substring(0, newline)) as Map).cast<String, Object?>();
      final body = (jsonDecode(text.substring(newline + 1)) as Map).cast<String, Object?>();
      final name = body['procName'] ?? header['app_name'] ?? header['name'];
      if (executable != null && name != executable) return null;
      final exception = (body['exception'] as Map?)?.cast<String, Object?>();
      final type = exception?['type'];
      if (type is! String || type.isEmpty) return null;
      final signal = exception?['signal'];
      final time = parseIpsTime('${body['captureTime'] ?? header['timestamp'] ?? ''}');
      if (time == null) return null;
      return SystemCrashReport(
        system: 'macOS',
        time: time,
        kind: _clean(signal is String && signal.isNotEmpty ? '$type ($signal)' : type)!,
        module: _clean(_faultingImage(body)),
      );
    } on Object {
      return null;
    }
  }

  /// Image of the top frame of the faulting thread.
  static String? _faultingImage(Map<String, Object?> body) {
    final images = body['usedImages'];
    final threads = body['threads'];
    final index = body['faultingThread'];
    if (images is! List || threads is! List || index is! int || index < 0 || index >= threads.length) return null;
    final frames = (threads[index] as Map?)?['frames'];
    if (frames is! List || frames.isEmpty) return null;
    final image = (frames.first as Map?)?['imageIndex'];
    if (image is! int || image < 0 || image >= images.length) return null;
    final entry = (images[image] as Map?)?.cast<String, Object?>() ?? const {};
    // The name only; the path can contain the user name.
    final name = entry['name'];
    if (name is String && name.isNotEmpty) return name;
    final path = entry['path'];
    return path is String ? path.split('/').last : null;
  }

  /// `2026-11-06 14:32:07.00 +0100` (time of the `.ips` header).
  static DateTime? parseIpsTime(String text) {
    final m = RegExp(r'^(\d{4})-(\d\d)-(\d\d) (\d\d):(\d\d):(\d\d)(?:\.(\d+))? ([+-])(\d\d)(\d\d)')
        .firstMatch(text.trim());
    if (m == null) return null;
    int g(int i) => int.parse(m.group(i)!);
    final fraction = (m.group(7) ?? '0').padRight(3, '0').substring(0, 3);
    final local = DateTime.utc(g(1), g(2), g(3), g(4), g(5), g(6), int.parse(fraction));
    final offset = Duration(hours: g(9), minutes: g(10));
    return m.group(8) == '+' ? local.subtract(offset) : local.add(offset);
  }

  /// Reads "Application Error" events (ID 1000) as `wevtutil /f:xml` prints
  /// them, newest first. Only those of [executable]. The event data has a fixed
  /// order: application, its version and time stamp, module, its version and
  /// time stamp, exception code, …; the description text would be localised.
  static List<SystemCrashReport> parseWindowsEvents(String xml, {String? executable}) {
    final out = <SystemCrashReport>[];
    for (final event in RegExp(r'<Event[ >][\s\S]*?</Event>').allMatches(xml)) {
      final text = event.group(0)!;
      final time = RegExp(r'''<TimeCreated SystemTime=['"]([^'"]+)['"]''').firstMatch(text)?.group(1);
      final data = [
        for (final d in RegExp(r'<Data(?: [^>]*)?>([^<]*)</Data>|<Data(?: [^>]*)?/>').allMatches(text))
          _unescape(d.group(1) ?? ''),
      ];
      if (time == null || data.length < 7) continue;
      final at = DateTime.tryParse(time);
      if (at == null) continue;
      if (executable != null && data[0].toLowerCase() != executable.toLowerCase()) continue;
      final kind = windowsExceptionName(data[6]);
      if (kind == null) continue;
      out.add(
        SystemCrashReport(system: 'Windows', time: at.toUtc(), kind: kind, module: _clean(data[3].split(r'\').last)),
      );
    }
    return out;
  }

  /// `c0000005` → `EXCEPTION_ACCESS_VIOLATION (0xc0000005)`.
  static String? windowsExceptionName(String code) {
    final hex = code.trim().toLowerCase().replaceFirst('0x', '');
    if (!RegExp(r'^[0-9a-f]{1,8}$').hasMatch(hex)) return null;
    final name = const {
      'c0000005': 'EXCEPTION_ACCESS_VIOLATION',
      'c00000fd': 'EXCEPTION_STACK_OVERFLOW',
      'c0000409': 'STACK_BUFFER_OVERRUN',
      'c0000374': 'HEAP_CORRUPTION',
      'c000001d': 'EXCEPTION_ILLEGAL_INSTRUCTION',
      'c0000094': 'EXCEPTION_INT_DIVIDE_BY_ZERO',
      '80000003': 'EXCEPTION_BREAKPOINT',
      'e0434352': 'CLR_EXCEPTION',
    }[hex.padLeft(8, '0')];
    return name == null ? '0x$hex' : '$name (0x$hex)';
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');

  /// Short and without anything that could be a path or a sentence.
  static String? _clean(String? s) {
    if (s == null) return null;
    final t = s.replaceAll(RegExp(r'[^A-Za-z0-9._ ()+\-]'), '').trim();
    if (t.isEmpty) return null;
    return t.length > 80 ? t.substring(0, 80) : t;
  }
}

/// Looks for the system's crash report that belongs to an unexpected end
/// ([find]): macOS writes one per crash, Windows logs "Application Error".
/// Linux has no common place. Reads locally only; nothing leaves the device.
///
/// The macOS app runs in the App Sandbox: there the home folder points into
/// the container and the reports are out of reach, so [find] returns `null`.
class SystemCrashFinder {
  SystemCrashFinder({
    required this.platform,
    this.executable,
    Future<List<process.SystemReportFile>> Function(String executable)? macFiles,
    Future<String?> Function()? windowsEvents,
  }) : _macFiles = macFiles ?? process.macCrashReportFiles,
       _windowsEvents = windowsEvents ?? process.windowsApplicationErrors;

  /// For this device.
  factory SystemCrashFinder.forDevice() =>
      SystemCrashFinder(platform: kIsWeb ? null : defaultTargetPlatform, executable: process.executableName);

  final TargetPlatform? platform;
  final String? executable;
  final Future<List<process.SystemReportFile>> Function(String executable) _macFiles;
  final Future<String?> Function() _windowsEvents;

  /// The report may lie this far before the last sign of life (written at
  /// most once a minute) …
  static const before = Duration(minutes: 1);

  /// … and this far after it.
  static const after = Duration(minutes: 10);

  /// Report closest to [lastSeen] within the window; `null` if there is none
  /// or the system's reports cannot be read. Never throws.
  Future<SystemCrashReport?> find(DateTime lastSeen) async {
    try {
      final exe = executable;
      if (exe == null) return null;
      final from = lastSeen.subtract(before);
      final to = lastSeen.add(after);
      bool inWindow(DateTime t) => !t.isBefore(from) && !t.isAfter(to);
      final candidates = <SystemCrashReport>[];
      switch (platform) {
        case TargetPlatform.macOS:
          for (final f in await _macFiles(exe)) {
            // The file time first: reading every report would be slow.
            if (f.modified.isBefore(from) || f.modified.isAfter(to.add(const Duration(minutes: 1)))) continue;
            final report = SystemCrashReport.parseIps(await f.read(), executable: exe);
            if (report != null) candidates.add(report);
          }
        case TargetPlatform.windows:
          final xml = await _windowsEvents();
          if (xml != null) candidates.addAll(SystemCrashReport.parseWindowsEvents(xml, executable: exe));
        case _:
          return null;
      }
      SystemCrashReport? best;
      for (final r in candidates) {
        if (!inWindow(r.time)) continue;
        if (best == null || r.time.difference(lastSeen).abs() < best.time.difference(lastSeen).abs()) best = r;
      }
      return best;
    } on Object catch (e) {
      debugPrint('Absturzbericht des Systems nicht lesbar: $e');
      return null;
    }
  }
}
