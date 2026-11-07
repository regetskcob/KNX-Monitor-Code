import 'process_info.dart';

int? get currentPid => null;

String? get executableName => null;

Future<bool?> processAlive(int pid, String? executable) async => null;

Future<List<SystemReportFile>> macCrashReportFiles(String executable) async => const [];

Future<String?> windowsApplicationErrors() async => null;
