import 'dart:io';

/// Variables that may come from a file instead (`<NAME>_FILE`, as Docker and
/// Compose secrets provide them): a value in the environment stays visible in
/// `docker inspect`, in Portainer and in NAS support bundles.
const secretVariables = ['BOX_PASSWORD', 'MQTT_PASSWORD'];

/// [env] with every `<NAME>_FILE` of [secretVariables] read into `<NAME>`.
/// A value set directly wins. The file's trailing line break is dropped.
/// An unreadable file is a configuration error ([ContainerEnvException]):
/// starting without the password the user meant would be worse.
Map<String, String> withSecretFiles(Map<String, String> env) {
  final result = Map.of(env);
  for (final name in secretVariables) {
    final path = env['${name}_FILE'];
    if (path == null || path.isEmpty || (env[name] ?? '').isNotEmpty) continue;
    try {
      result[name] = File(path).readAsStringSync().replaceFirst(RegExp(r'\r?\n$'), '');
    } on FileSystemException catch (e) {
      throw ContainerEnvException('${name}_FILE: $path nicht lesbar (${e.osError?.message ?? e.message}).');
    }
  }
  return result;
}

/// Shortest first password the container accepts, as `/pair/password`.
const minPasswordLength = 8;

/// Why the server must not start with [env], or `null`.
///
/// - `ALLOW_ALL=1` turns off every access check. On a non-loopback `BIND`
///   every device on the network and every web page (DNS rebinding) could
///   write to the bus and use the UDP relay into the home network. The CI
///   needs exactly that inside its own runner, so it has to say so with
///   `ALLOW_ALL_EXPOSED=1`; a command copied from it without that fails.
/// - `BOX=1` in Docker: the first password must have at least
///   [minPasswordLength] characters ([firstStart]: no `access.json` yet;
///   later the stored password counts).
String? refuseToStart(Map<String, String> env, {required bool firstStart}) {
  final bind = env['BIND'];
  if (env['ALLOW_ALL'] == '1' && env['BOX'] != '1' && bind != null && bind.isNotEmpty) {
    final loopback = InternetAddress.tryParse(bind)?.isLoopback ?? false;
    if (!loopback && env['ALLOW_ALL_EXPOSED'] != '1') {
      return 'ALLOW_ALL=1 mit BIND=$bind schaltet jede Anmeldung ab und öffnet Bus und UDP-Relay für das '
          'ganze Netzwerk. Nur für Tests: zusätzlich ALLOW_ALL_EXPOSED=1. Für Docker BOX=1 und '
          'BOX_PASSWORD setzen.';
    }
  }
  final docker = env['BOX'] == '1' && env['BOX_STICKER'] != '1';
  if (docker && firstStart) {
    final password = env['BOX_PASSWORD'] ?? '';
    if (password.isEmpty) {
      return 'BOX_PASSWORD fehlt. Bitte ein eigenes Passwort setzen (mindestens $minPasswordLength Zeichen), '
          'z. B. in .env neben compose.yaml: BOX_PASSWORD=...';
    }
    if (password.length < minPasswordLength || password.length > 128) {
      return 'BOX_PASSWORD ist zu kurz oder zu lang: mindestens $minPasswordLength, höchstens 128 Zeichen.';
    }
  }
  return null;
}

/// A start option the user set but that cannot work, as [ContainerEnvException].
class ContainerEnvException implements Exception {
  const ContainerEnvException(this.message);
  final String message;
  @override
  String toString() => message;
}
