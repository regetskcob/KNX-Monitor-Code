import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Result of an outbound request. [code] is a short reason without address
/// and without credentials: `network`, `timeout`, `http<Status>`, `invalid`,
/// `blocked`. Only this ends up in log and status; the messages of
/// `HttpClient` contain the address otherwise, which may hold a secret
/// (webhook URLs).
class OutboundResult {
  const OutboundResult.ok() : ok = true, code = null;
  const OutboundResult.failed(String this.code) : ok = false;

  final bool ok;
  final String? code;
}

/// Checks a user-defined target: only http(s), with host, without credentials
/// in the address (that is what the token field is for, which is never shown).
Uri? parseOutboundTarget(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null || !const {'http', 'https'}.contains(uri.scheme) || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return null;
  }
  // Reject already when saving, not only when sending. postOutbound checks names.
  final literal = InternetAddress.tryParse(uri.host);
  if (literal != null && isForbiddenOutboundAddress(literal)) return null;
  return uri;
}

/// Targets that never receive notifications or metrics: cloud metadata
/// (169.254.169.254 and the like), link-local in general, the unspecified
/// address and multicast. Private networks and loopback remain allowed: ntfy
/// and InfluxDB often run there, and only an admin sets the target.
bool isForbiddenOutboundAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return (b[0] == 169 && b[1] == 254) || b[0] == 0 || (b[0] >= 224 && b[0] < 240) || b.every((x) => x == 255);
  }
  // IPv4 in IPv6 (::ffff:169.254.169.254).
  if (b.take(10).every((x) => x == 0) && b[10] == 0xFF && b[11] == 0xFF) {
    return isForbiddenOutboundAddress(InternetAddress.fromRawAddress(b.sublist(12)));
  }
  return address.isLinkLocal ||
      address.isMulticast ||
      b.every((x) => x == 0) ||
      // fd00:ec2::254: AWS metadata over IPv6.
      (b[0] == 0xFD && b[1] == 0x00 && b[2] == 0x0E && b[3] == 0xC2);
}

/// Sends a POST and reports the result; never throws. Redirects are not
/// followed, otherwise the token would go to a target the user never set.
/// Forbidden targets ([isForbiddenOutboundAddress]) report `blocked`; every
/// resolved address is checked, and only one of them is connected to.
Future<OutboundResult> postOutbound(
  Uri url, {
  Map<String, String> headers = const {},
  required List<int> body,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final response = await () async {
      final literal = InternetAddress.tryParse(url.host);
      final addresses = literal != null ? [literal] : await InternetAddress.lookup(url.host);
      if (addresses.isEmpty || addresses.any(isForbiddenOutboundAddress)) return null;
      // Connect exactly to the checked address: the client would otherwise resolve
      // the name again (DNS rebinding). Addresses from lookup keep the name for SNI and certificate.
      final target = addresses.firstWhere((a) => a.type == InternetAddressType.IPv4, orElse: () => addresses.first);
      client.connectionFactory = (uri, _, _) =>
          uri.scheme == 'https' ? SecureSocket.startConnect(target, uri.port) : Socket.startConnect(target, uri.port);
      final request = await client.postUrl(url);
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.add(body);
      return request.close();
    }().timeout(timeout);
    if (response == null) return const OutboundResult.failed('blocked');
    await response.drain<void>().timeout(timeout);
    return response.statusCode >= 200 && response.statusCode < 300
        ? const OutboundResult.ok()
        : OutboundResult.failed('http${response.statusCode}');
  } on TimeoutException {
    return const OutboundResult.failed('timeout');
  } on Object {
    return const OutboundResult.failed('network');
  } finally {
    client.close(force: true);
  }
}

/// Outbound notification: opt-in only and only a summary, never addresses,
/// names or values of the installation.
class OutboundMessage {
  const OutboundMessage({required this.kind, required this.title, required this.message, this.period});

  /// `ready`, `urgent`, `maintenance` or `test`.
  final String kind;
  final String title;
  final String message;
  final String? period;
}

/// Sends [message] to the chosen target: `ntfy` ([url] + [topic]) or
/// `webhook` ([url], JSON). The token only goes out as Authorization header.
Future<OutboundResult> sendOutbound({
  required String kind,
  required String url,
  String topic = '',
  String token = '',
  required OutboundMessage message,
}) async {
  final target = parseOutboundTarget(url);
  if (target == null) return const OutboundResult.failed('invalid');
  final auth = token.isEmpty ? const <String, String>{} : {HttpHeaders.authorizationHeader: 'Bearer $token'};
  switch (kind) {
    case 'ntfy':
      if (topic.isEmpty || !validNtfyTopic(topic)) return const OutboundResult.failed('invalid');
      final segments = [...target.pathSegments.where((s) => s.isNotEmpty), topic];
      return postOutbound(
        target.replace(pathSegments: segments),
        headers: {
          ...auth,
          // Headers are ASCII; the text is in the body.
          'Title': message.title.codeUnits.every((c) => c < 128) ? message.title : 'KNX Monitor',
          'Priority': message.kind == 'urgent' ? '4' : '3',
          'Tags': message.kind == 'urgent' ? 'warning' : 'house',
          HttpHeaders.contentTypeHeader: 'text/plain; charset=utf-8',
        },
        body: utf8.encode(message.message),
      );
    case 'webhook':
      return postOutbound(
        target,
        headers: {...auth, HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8'},
        body: utf8.encode(
          jsonEncode({
            'source': 'knx_monitor',
            'kind': message.kind,
            'title': message.title,
            'message': message.message,
            'period': ?message.period,
          }),
        ),
      );
    default:
      return const OutboundResult.failed('invalid');
  }
}

/// ntfy topic names: letters, digits, `_` and `-`.
bool validNtfyTopic(String topic) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(topic);
