import 'dart:io';

import 'process_info.dart';

int? get currentPid => pid;

String? get executableName {
  try {
    return File(Platform.resolvedExecutable).uri.pathSegments.last;
  } on Object {
    return null;
  }
}

Future<bool?> processAlive(int id, String? executable) async {
  try {
    if (Platform.isWindows) {
      // CSV without header: "knx_monitor.exe","4188","Console","1","120.000 K"
      final result = await Process.run('tasklist', ['/FI', 'PID eq $id', '/FO', 'CSV', '/NH']);
      if (result.exitCode != 0) return null;
      return tasklistMatches('${result.stdout}', id, executable);
    }
    if (Platform.isMacOS || Platform.isLinux) {
      // Exit code 1 without such a process; otherwise its command name.
      final result = await Process.run('ps', ['-p', '$id', '-o', 'comm=']);
      final out = '${result.stdout}'.trim();
      if (result.exitCode != 0) return out.isEmpty && '${result.stderr}'.trim().isEmpty ? false : null;
      return out.isEmpty ? false : commandMatches(out, executable);
    }
  } on Object {
    // No such tool, or the sandbox refuses it.
  }
  return null;
}

/// Whether the `ps -o comm=` output [command] is [executable]: macOS prints the
/// full path, Linux the name cut to 15 characters.
bool commandMatches(String command, String? executable) {
  if (executable == null) return true;
  final name = command.split('/').last;
  return name == executable || (name.length >= 15 && executable.startsWith(name));
}

/// Whether the `tasklist /FO CSV /NH` output lists [id] with [executable].
bool tasklistMatches(String output, int id, String? executable) {
  for (final line in output.split('\n')) {
    final cells = RegExp(r'"([^"]*)"').allMatches(line).map((m) => m.group(1)!).toList();
    if (cells.length < 2 || cells[1] != '$id') continue;
    return executable == null || cells[0].toLowerCase() == executable.toLowerCase();
  }
  return false;
}

Future<List<SystemReportFile>> macCrashReportFiles(String executable) async {
  if (!Platform.isMacOS) return const [];
  try {
    final home = Platform.environment['HOME'];
    if (home == null) return const [];
    final dir = Directory('$home/Library/Logs/DiagnosticReports');
    if (!await dir.exists()) return const [];
    return [
      await for (final f in dir.list())
        if (f is File && f.uri.pathSegments.last.startsWith(executable) && f.path.endsWith('.ips'))
          (name: f.uri.pathSegments.last, modified: await f.lastModified(), read: () => _readCapped(f)),
    ];
  } on Object {
    // Sandbox: no access outside the container.
    return const [];
  }
}

/// Crash reports are some 100 KB; anything far larger is not one of them.
Future<String> _readCapped(File f) async {
  if (await f.length() > 4 * 1024 * 1024) return '';
  return f.readAsString();
}

Future<String?> windowsApplicationErrors() async {
  if (!Platform.isWindows) return null;
  try {
    final result = await Process.run('wevtutil', [
      'qe',
      'Application',
      "/q:*[System[Provider[@Name='Application Error'] and (EventID=1000)]]",
      '/c:10',
      '/rd:true',
      '/f:xml',
    ]);
    return result.exitCode == 0 ? '${result.stdout}' : null;
  } on Object {
    return null;
  }
}
