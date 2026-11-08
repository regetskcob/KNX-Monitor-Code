import 'process_info_io.dart' if (dart.library.js_interop) 'process_info_web.dart' as impl;

/// Process id of this app; `null` in the browser.
int? get currentPid => impl.currentPid;

/// File name of the running executable without its folder (e.g. `Busclear`,
/// `knx_monitor.exe`); `null` in the browser.
String? get executableName => impl.executableName;

/// Whether process [pid] still runs this app's executable [executable]: `true`
/// alive, `false` gone (or another program now has the id), `null` if it cannot
/// be told (no `ps`/`tasklist`, sandbox, browser). Never throws.
Future<bool?> processAlive(int pid, String? executable) => impl.processAlive(pid, executable);

/// The operating system's crash reports of this app (macOS
/// `~/Library/Logs/DiagnosticReports/*.ips`): name, modification time and a reader.
/// Empty where the folder is out of reach (the App Sandbox points the home
/// folder into the container) or on other systems. Never throws.
Future<List<SystemReportFile>> macCrashReportFiles(String executable) => impl.macCrashReportFiles(executable);

/// The latest "Application Error" events (ID 1000) from the Windows
/// application log as XML, via `wevtutil`; `null` where unavailable. Never throws.
Future<String?> windowsApplicationErrors() => impl.windowsApplicationErrors();

/// A crash report file of the system.
typedef SystemReportFile = ({String name, DateTime modified, Future<String> Function() read});
