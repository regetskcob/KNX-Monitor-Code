import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:qr/qr.dart';

/// Who makes a request to the box.
enum BoxRole {
  /// Box password (browser, HTTP Basic): everything, including pairing devices.
  admin,

  /// Paired device (app, bearer device token): monitor, history, sending.
  /// Devices paired in the app with the box password are [admin].
  device,
}

/// A paired device; of its token only the hash is stored.
class BoxDevice {
  BoxDevice({
    required this.id,
    required this.name,
    required this.hash,
    required this.created,
    this.lastUsed,
    this.admin = false,
  });

  final String id;
  final String name;
  final String hash;
  final DateTime created;
  DateTime? lastUsed;

  /// May manage the box (devices, password): paired with the box password.
  final bool admin;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hash': hash,
    'created': created.millisecondsSinceEpoch,
    if (lastUsed != null) 'lastUsed': lastUsed!.millisecondsSinceEpoch,
    if (admin) 'admin': true,
  };

  static BoxDevice fromJson(Map<String, Object?> j) => BoxDevice(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    hash: j['hash'] as String,
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    lastUsed: j['lastUsed'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastUsed'] as int),
    admin: j['admin'] == true,
  );
}

/// Access protection of the KNX box (`BOX=1`), see docs/knx-box.md and docs/security.md.
///
/// - **Browser:** HTTP Basic with the box password (any user name).
///   After the first valid login the box sets a session cookie
///   ([sessionCookie]): Safari/WebKit does not send the Basic credentials with
///   the WebSocket handshake, but it does send the cookie.
/// - **App:** device token as `Authorization: Bearer …`, created on `/pair`
///   and shown there as a QR code (`knxmonitor://box?url=…&key=…`).
///
/// - **Network:** by default only from the box Wi-Fi. Over the cable (the
///   network at the gateway, at the customer's site their LAN) only after
///   enabling it ([lanAccess]): `LAN_ACCESS=yes` in `knx-box.txt` or in the
///   app's box settings. This is enforced in the firewall per interface
///   (`box/files/lan-access.sh` reads the file `lan-access`); checking the
///   sender address here is only a second layer, because a customer network
///   may itself use `10.42.0.0/24`.
///
/// - **Sticker:** on the real box ([sticker], `BOX_STICKER=1`) the initial
///   password is printed in plain text on the sticker and stored on the SD
///   card. As long as it is valid, [mustChangePassword] is set. A new box then
///   only allows pairing and changing it ([changeRequired]); a box updated from
///   1.9.1 only asks, so nobody gets locked out. After the change,
///   `box/files/secrets.sh` removes the passwords from the boot partition.
///
/// Stored in `access.json`: the password as PBKDF2-HMAC-SHA256, device tokens
/// as SHA-256 (32 random bytes need no key stretching).
class BoxAccess {
  BoxAccess._(
    this._file,
    this._lanFile,
    this.name,
    this._iterations,
    this._clock,
    this._random,
    this._fromWlan,
    this.sticker,
    this._peerOf,
  );

  /// Opens `access.json` in [data]. If it does not exist yet, a password is
  /// set: [initialPassword] (on the box from `knx-box.txt`, see firstboot.sh)
  /// or a random one; then it is only available in [firstPassword]. It is
  /// never written to disk in plain text: the data folder is reachable via
  /// `/api/files/`.
  ///
  /// [initialLanAccess] applies as long as nothing else is set in the app.
  /// [fromWlan] decides whether a sender is in the box Wi-Fi (default:
  /// [wlanPeer]).
  static Future<BoxAccess> open(
    Directory data, {
    String? initialPassword,
    String? name,
    bool initialLanAccess = false,
    bool Function(InternetAddress peer) fromWlan = wlanPeer,
    bool sticker = false,
    String Function(HttpRequest request)? peerOf,
    // 200,000 rounds took over 30 seconds per first login on the Pi 4; the password is on
    // the SD card anyway, and online attempts are slowed by the lockout after failures.
    int iterations = 40000,
    DateTime Function() clock = DateTime.now,
    Random? random,
  }) async {
    final access = BoxAccess._(
      File('${data.path}/access.json'),
      File('${data.path}/lan-access'),
      (name == null || name.trim().isEmpty) ? Platform.localHostname : name.trim(),
      iterations,
      clock,
      random ?? Random.secure(),
      fromWlan,
      sticker,
      peerOf,
    );
    access._lanAccess = initialLanAccess;
    // Older versions stored the initial password in plain text.
    final plain = File('${data.path}/box-password.txt');
    if (await plain.exists()) await plain.delete();
    // Unreadable (power failure while writing, broken card): try the backup
    // first, otherwise move the file aside and start fresh – the box must stay
    // reachable, and devices can be paired again. If the file is missing
    // entirely, that counts as a fresh start as before (password from the
    // sticker), even if a backup exists.
    var loaded = false;
    final candidates = [access._file, access._backup];
    final existed = await access._file.exists();
    for (final (index, file) in candidates.indexed) {
      if (loaded || !existed || !await file.exists()) continue;
      try {
        access._load(jsonDecode(await file.readAsString()) as Map<String, Object?>);
        loaded = true;
        if (index == 1) {
          stderr.writeln('access.json unlesbar – Sicherung access.json.bak übernommen');
          await access._save();
        }
      } on Object catch (e) {
        stderr.writeln('${file.uri.pathSegments.last} unlesbar: $e');
        await file.rename('${file.path}.corrupt-${clock().millisecondsSinceEpoch}');
      }
    }
    if (!loaded) {
      final password = (initialPassword == null || initialPassword.isEmpty)
          ? access._randomPassword()
          : initialPassword;
      access._setPassword(password);
      // New box: the password is on the sticker and on the SD card.
      if (sticker) {
        access._mustChange = true;
        access._required = true;
        access._stickerChecked = true;
      }
      await access._save();
      access.firstPassword = password;
    }
    await access._consumeReset();
    // Box from 1.9.1: is the sticker password still valid? In the background, the old
    // 200,000 rounds took longer on the Pi than the startup check of setup.sh.
    if (sticker && !access._stickerChecked) access.settled = access._checkOldSticker(initialPassword);
    await access._writeLanChoice();
    return access;
  }

  /// Completes when the check of an updated box is done (tests).
  Future<void> settled = Future.value();

  Future<void> _checkOldSticker(String? initial) async {
    try {
      final current = _password;
      final same = initial != null && initial.isNotEmpty && await verifyPassword(initial);
      if (!identical(current, _password)) return;
      _stickerChecked = true;
      _mustChange = same;
      _required = false;
      await _save();
      // Already changed: the card only holds an old password. Remove it.
      if (!same) await _requestScrub('box');
    } on Object catch (e) {
      stderr.writeln('access.json: $e');
    }
  }

  /// New password from the SD card (`knx-box-reset.txt`, see secrets.sh):
  /// whoever has the card in hand can get back into the box this way, without
  /// the passwords having to stay there permanently. Paired devices are kept.
  Future<void> _consumeReset() async {
    final file = File('${_file.parent.path}/password-reset');
    if (!await file.exists()) return;
    try {
      final next = (await file.readAsString()).trim();
      if (next.length >= 8 && next.length <= 128) {
        _setPassword(next);
        _mustChange = false;
        _required = false;
        _stickerChecked = true;
        await _save();
        stdout.writeln('KNX-Box: Passwort von der SD-Karte übernommen');
      }
    } on Object catch (e) {
      stderr.writeln('password-reset: $e');
    } finally {
      await file.delete();
    }
  }

  final File _file;

  /// Choice for the firewall (`yes`/`no`), see knx-box-lan.path.
  final File _lanFile;

  /// Name of the box in the QR code (e.g. the Wi-Fi SSID).
  final String name;

  /// Real box with sticker and SD card (not Docker, see knx-box.service).
  final bool sticker;

  /// Tests only: sender for lockout and counters instead of the real address.
  final String Function(HttpRequest request)? _peerOf;

  bool _mustChange = false;
  bool _required = false;
  bool _stickerChecked = false;

  /// The sticker password is still valid.
  bool get mustChangePassword => _mustChange;

  /// Until then nothing works except pairing and changing it (new boxes only).
  bool get changeRequired => _required;

  /// Self-signed certificate: SHA-256 (base64url), see box_tls.dart.
  /// `null` without TLS.
  String? tlsFingerprint;

  /// HTTPS port; 443 on the box.
  int tlsPort = 443;
  final int _iterations;
  final DateTime Function() _clock;
  final Random _random;

  /// Password generated on first start, otherwise `null`.
  String? firstPassword;

  /// Additional fields for `/api/box`, such as the clock (set by the server).
  Map<String, Object?> Function()? status;

  final bool Function(InternetAddress peer) _fromWlan;
  bool _lanAccess = false;

  /// Access over the cable too, not only from the box Wi-Fi.
  bool get lanAccess => _lanAccess;

  /// Sender in the box Wi-Fi (hotspot `10.42.0.0/24`, see firstboot.sh) or
  /// the box itself.
  static bool wlanPeer(InternetAddress peer) {
    if (peer.isLoopback) return true;
    final b = peer.rawAddress;
    return peer.type == InternetAddressType.IPv4 && b[0] == 10 && b[1] == 42 && b[2] == 0;
  }

  late Map<String, Object?> _password;
  final _devices = <BoxDevice>[];

  /// Basic credentials already verified (SHA-256 of the header), so that not
  /// every request costs 200,000 PBKDF2 rounds.
  final _acceptedBasic = <String>{};

  final _strikes = <String, ({int count, DateTime until})>{};

  /// Running password checks per sender: each one occupies a core for
  /// seconds, and a failed attempt only counts when it finishes. Without a
  /// limit, a hundred concurrent requests would stall the Pi before the
  /// throttling kicks in.
  final _verifying = <String, int>{};
  static const _maxVerifying = 3;

  /// Name of the session cookie for the browser.
  static const sessionCookie = 'knx_box_session';

  /// How long a session is valid after creation. As long as the browser still
  /// sends the Basic credentials, it gets a new one before that.
  static const sessionLifetime = Duration(hours: 12);

  /// Sessions (SHA-256 of the cookie → expiry). In memory only: after a
  /// restart the browser logs in again with the remembered Basic credentials.
  final _sessions = <String, DateTime>{};

  /// At most this many sessions; the oldest one is dropped first.
  static const _maxSessions = 32;

  List<BoxDevice> get devices => List.unmodifiable(_devices);

  // --- Checking ---------------------------------------------------------------

  /// Checks [request]. On `null` the response (401, 403, 429) has already been sent.
  Future<BoxRole?> guard(HttpRequest request) async {
    final response = request.response;
    // "no-referrer" would make browsers send "Origin: null" on POST/PUT; the
    // origin check needs the real one.
    response.headers.set('Referrer-Policy', 'same-origin');
    final address = request.connectionInfo?.remoteAddress;
    // Over the cable only once enabled; does not count as a failed attempt.
    if (!_lanAccess && (address == null || !_fromWlan(address))) {
      return _deny(
        response,
        HttpStatus.forbidden,
        'Zugriff über das Kabel ist aus. Im WLAN der Box verbinden oder in den Box-Einstellungen freigeben.',
      );
    }
    final peer = _peerOf?.call(request) ?? address?.address ?? '';
    final now = _clock();
    final strike = _strikes[peer];
    if (strike != null && strike.until.isAfter(now)) {
      response.headers.set(HttpHeaders.retryAfterHeader, '${strike.until.difference(now).inSeconds + 1}');
      return _deny(response, HttpStatus.tooManyRequests, 'Zu viele Fehlversuche, bitte warten.');
    }
    // The browser loads the manifest without credentials; it only contains
    // the app's name, colours and icons.
    if (request.uri.path == '/manifest.json' && request.method == 'GET') return BoxRole.device;
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final session = _sessionOf(request, now);
    final BoxRole? role;
    if (auth.startsWith('Bearer ')) {
      final device = _deviceFor(auth.substring(7).trim());
      role = device == null ? null : (device.admin ? BoxRole.admin : BoxRole.device);
    } else if (auth.startsWith('Basic ')) {
      final encoded = auth.substring(6).trim();
      final known = _acceptedBasic.contains(_sha256(utf8.encode(encoded)));
      final running = _verifying[peer] ?? 0;
      if (!known && running >= _maxVerifying) {
        response.headers.set(HttpHeaders.retryAfterHeader, '5');
        return _deny(response, HttpStatus.tooManyRequests, 'Zu viele Anmeldungen auf einmal, bitte warten.');
      }
      _verifying[peer] = running + 1;
      try {
        role = await _checkBasic(encoded) ? BoxRole.admin : null;
      } finally {
        final left = (_verifying[peer] ?? 1) - 1;
        if (left <= 0) {
          _verifying.remove(peer);
        } else {
          _verifying[peer] = left;
        }
      }
    } else if (auth.isEmpty) {
      role = session == null ? null : BoxRole.admin;
    } else {
      // Unknown scheme: do not fall back to the cookie, otherwise the request
      // would escape the origin check for cookie requests.
      role = null;
    }
    if (role == null) {
      // A browser's first request always comes without; only wrong ones count.
      // An expired cookie is not a failed attempt.
      if (auth.isNotEmpty) _fail(peer, now);
      response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="$realm", charset="UTF-8"');
      return _deny(response, HttpStatus.unauthorized, 'Anmeldung nötig.');
    }
    // Only the password itself clears the failed attempts: otherwise a valid device token
    // in between would allow unlimited further guessing.
    if (auth.startsWith('Basic ')) _strikes.remove(peer);
    // Foreign pages in the same browser (CSRF, cross-site WebSocket). The app
    // does not send an Origin.
    final origin = request.headers.value('origin');
    if (origin != null && !_sameOrigin(origin, request.headers.value(HttpHeaders.hostHeader))) {
      return _deny(response, HttpStatus.forbidden, 'Fremde Herkunft.');
    }
    if (auth.isEmpty && !_ownSite(request, origin)) {
      return _deny(response, HttpStatus.forbidden, 'Fremde Herkunft.');
    }
    if (auth.startsWith('Basic ') && (session == null || session.difference(now) < sessionLifetime ~/ 2)) {
      _startSession(response, now, secure: request.requestedUri.scheme == 'https');
    }
    final path = request.uri.path;
    final page =
        request.method == 'GET' && (request.headers.value(HttpHeaders.acceptHeader) ?? '').contains('text/html');
    if (_required && !_allowedBeforeChange(request.method, path)) {
      if (page) return _redirect(response, '/pair');
      return _deny(response, HttpStatus.preconditionRequired, 'Erst ein eigenes Box-Passwort setzen (/pair).');
    }
    // Updated from 1.9.1: ask once on browser login, do not lock.
    if (_mustChange && !_required && page && path == '/' && session == null) return _redirect(response, '/pair');
    // The raw relay can send arbitrary KNXnet/IP packets; pairing devices
    // requires the password.
    if (role == BoxRole.device && (path == '/ws' || path == '/pair' || path.startsWith('/pair/'))) {
      return _deny(response, HttpStatus.forbidden, 'Nur mit dem Box-Passwort.');
    }
    return role;
  }

  /// As long as the sticker password is valid: nothing beyond pairing and
  /// changing it. Devices paired this way are afterwards either kept or
  /// revoked (see [changePassword]).
  static bool _allowedBeforeChange(String method, String path) =>
      path == '/api/box' ||
      path == '/api/box/pair' ||
      path == '/api/box/password' ||
      (path == '/pair' && method == 'GET') ||
      path == '/pair/password';

  Future<BoxRole?> _redirect(HttpResponse response, String to) async {
    response
      ..statusCode = HttpStatus.seeOther
      ..headers.set(HttpHeaders.locationHeader, to)
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    await response.close();
    return null;
  }

  Future<BoxRole?> _deny(HttpResponse response, int status, String text) async {
    response
      ..statusCode = status
      ..headers.contentType = ContentType.text
      ..write(text);
    await response.close();
    return null;
  }

  /// Text in the browser's login dialog (if it shows one).
  static const realm = 'KNX-Box: Benutzername beliebig, Box-Passwort';

  /// Logged in by cookie only: modifying requests and WebSockets must state
  /// their origin (browsers always do), and requests from foreign pages do
  /// not count, even though `SameSite=Strict` should already send them
  /// without the cookie.
  static bool _ownSite(HttpRequest request, String? origin) {
    final site = request.headers.value('sec-fetch-site');
    if (site != null && site != 'same-origin' && site != 'none') return false;
    final safe = request.method == 'GET' || request.method == 'HEAD';
    final upgrade = WebSocketTransformer.isUpgradeRequest(request);
    return origin != null || (safe && !upgrade);
  }

  /// Session expiry from the cookie of [request], otherwise `null`.
  DateTime? _sessionOf(HttpRequest request, DateTime now) {
    _sessions.removeWhere((_, until) => !until.isAfter(now));
    for (final header in request.headers[HttpHeaders.cookieHeader] ?? const <String>[]) {
      for (final part in header.split(';')) {
        final eq = part.indexOf('=');
        if (eq < 0 || part.substring(0, eq).trim() != sessionCookie) continue;
        final value = part.substring(eq + 1).trim();
        if (value.isEmpty || value.length > 128) continue;
        final until = _sessions[_sha256(utf8.encode(value))];
        if (until != null) return until;
      }
    }
    return null;
  }

  void _startSession(HttpResponse response, DateTime now, {required bool secure}) {
    final token = base64Url.encode(_bytes(32)).replaceAll('=', '');
    while (_sessions.length >= _maxSessions) {
      _sessions.remove(_sessions.entries.reduce((a, b) => a.value.isBefore(b.value) ? a : b).key);
    }
    _sessions[_sha256(utf8.encode(token))] = now.add(sessionLifetime);
    // `Secure` only over HTTPS: in the box Wi-Fi the browser stays on HTTP.
    response.headers.add(
      HttpHeaders.setCookieHeader,
      '$sessionCookie=$token; Max-Age=${sessionLifetime.inSeconds}; Path=/; HttpOnly; SameSite=Strict'
      '${secure ? '; Secure' : ''}',
    );
  }

  static bool _sameOrigin(String origin, String? host) {
    if (host == null) return false;
    return origin == 'http://$host' || origin == 'https://$host';
  }

  void _fail(String peer, DateTime now) {
    final count = (_strikes[peer]?.count ?? 0) + 1;
    // From the 5th failed attempt 30 s, then doubled up to 15 min.
    final wait = count < 5 ? Duration.zero : Duration(seconds: min(30 * (1 << min(count - 5, 10)), 15 * 60));
    _strikes[peer] = (count: count, until: now.add(wait));
    // There are only so many senders in a LAN; still, the list must not grow.
    if (_strikes.length > 1024) {
      _strikes.removeWhere((key, s) => key != peer && !s.until.isAfter(now));
      while (_strikes.length > 1024) {
        _strikes.remove(_strikes.keys.firstWhere((key) => key != peer));
      }
    }
    stderr.writeln('KNX-Box: Fehlversuch $count von $peer');
  }

  /// Concurrent logins with the same credentials are computed only once.
  final _checking = <String, Future<bool>>{};

  Future<bool> _checkBasic(String encoded) async {
    final key = _sha256(utf8.encode(encoded));
    if (_acceptedBasic.contains(key)) return true;
    final String decoded;
    try {
      decoded = utf8.decode(base64.decode(encoded));
    } on FormatException {
      return false;
    }
    final colon = decoded.indexOf(':');
    if (colon < 0) return false;
    final check = _checking[key] ??= verifyPassword(decoded.substring(colon + 1)).whenComplete(() {
      // Block instead of arrow: remove returns this future, and awaiting it would deadlock.
      _checking.remove(key);
    });
    if (!await check) return false;
    unawaited(_rehash(decoded.substring(colon + 1)));
    if (_acceptedBasic.length > 64) _acceptedBasic.clear();
    _acceptedBasic.add(key);
    return true;
  }

  BoxDevice? _deviceFor(String key) {
    if (key.isEmpty || key.length > 128) return null;
    final hash = _sha256(utf8.encode(key));
    for (final d in _devices) {
      if (_equal(d.hash, hash)) {
        final now = _clock();
        final last = d.lastUsed;
        d.lastUsed = now;
        // Do not write to the SD card on every request.
        if (last == null || now.difference(last) > const Duration(hours: 1)) {
          unawaited(_save().catchError((Object e) => stderr.writeln('access.json: $e')));
        }
        return d;
      }
    }
    return null;
  }

  // --- Password and devices -------------------------------------------------------

  bool checkPassword(String password) {
    final salt = base64.decode(_password['salt'] as String);
    final iterations = _password['iterations'] as int;
    return _equal(base64.encode(_pbkdf2(password, salt, iterations)), _password['hash'] as String);
  }

  /// Like [checkPassword], but in a separate isolate: on the Pi 4 the derivation takes
  /// many seconds, during which the server and the recording would otherwise stall.
  Future<bool> verifyPassword(String password) async {
    final current = _password;
    final salt = base64.decode(current['salt'] as String);
    final iterations = current['iterations'] as int;
    final derived = await _deriveInIsolate(password, salt, iterations);
    // Changed in the meantime: the result no longer applies.
    return identical(current, _password) && _equal(derived, current['hash'] as String);
  }

  /// Older boxes stored more rounds: migrate after a successful login.
  Future<void> _rehash(String password) async {
    final current = _password;
    if ((current['iterations'] as int) <= _iterations) return;
    try {
      final salt = _bytes(16);
      final hash = await _deriveInIsolate(password, salt, _iterations);
      if (!identical(current, _password)) return;
      _password = {...current, 'salt': base64.encode(salt), 'iterations': _iterations, 'hash': hash};
      await _save();
    } on Object catch (e) {
      stderr.writeln('access.json: $e');
    }
  }

  /// Separate function: the closure must not capture anything from the object, or the isolate fails.
  static Future<String> _deriveInIsolate(String password, List<int> salt, int iterations) =>
      Isolate.run(() => base64.encode(_pbkdf2(password, salt, iterations)));

  /// Access revoked or password changed: open connections were only checked when they
  /// were established. The server closes them; whoever is still allowed reconnects.
  void Function()? onAccessChanged;

  /// Sets a new password. The sticker password does not count as new: the box
  /// then cleans up the boot partition, and it would still be on the sticker.
  ///
  /// If the change was mandatory ([changeRequired]), previously paired devices
  /// except [keepDevice] are revoked: they only got into the box with the
  /// sticker, and whoever photographed it should not keep access.
  Future<void> changePassword(String password, {String? keepDevice}) async {
    if (_mustChange && await verifyPassword(password)) throw const SamePasswordException();
    final wasSticker = _mustChange;
    if (_required) _devices.removeWhere((d) => d.id != keepDevice);
    _setPassword(password);
    _mustChange = false;
    _required = false;
    _stickerChecked = true;
    _acceptedBasic.clear();
    _sessions.clear();
    await _save();
    onAccessChanged?.call();
    if (wasSticker) await _requestScrub('box');
  }

  /// Wi-Fi password: 8–63 printable characters without spaces and without `" ' \ \$ \``
  /// (as in firstboot.sh; it ends up in a keyfile line).
  static bool validWifiPassword(String password) =>
      password.length >= 8 &&
      password.length <= 63 &&
      password.codeUnits.every((c) => c > 0x20 && c < 0x7F && !const [0x22, 0x27, 0x5C, 0x24, 0x60].contains(c));

  /// Asks the host to change the Wi-Fi password (knx-box-secrets.path); the
  /// server itself is not allowed to. `false` without a real box.
  Future<bool> changeWifiPassword(String password) async {
    if (!sticker) return false;
    final file = File('${_file.parent.path}/wifi-request');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString('$password\n', flush: true);
    await tmp.rename(file.path);
    return true;
  }

  /// Asks the host to remove passwords from the boot partition (`box`/`wifi`).
  Future<void> _requestScrub(String kind) async {
    if (!sticker) return;
    await File('${_file.parent.path}/sticker-scrub').writeAsString('$kind\n', mode: FileMode.append, flush: true);
  }

  /// Pairs a new device; returns the token in plain text (only this once).
  Future<String> pair(String deviceName, {bool admin = false}) async {
    final key = base64Url.encode(_bytes(32)).replaceAll('=', '');
    final name = deviceName.trim().isEmpty ? 'Gerät ${_devices.length + 1}' : deviceName.trim();
    _devices.add(
      BoxDevice(
        id: _hex(_bytes(6)),
        name: name.length > 40 ? name.substring(0, 40) : name,
        hash: _sha256(utf8.encode(key)),
        created: _clock(),
        admin: admin,
      ),
    );
    await _save();
    return key;
  }

  /// Enables or disables access over the cable.
  Future<void> setLanAccess(bool enabled) async {
    _lanAccess = enabled;
    await _save();
    await _writeLanChoice();
  }

  /// Writes only on change: every change reconfigures the firewall.
  Future<void> _writeLanChoice() async {
    final choice = _lanAccess ? 'yes\n' : 'no\n';
    if (await _lanFile.exists() && await _lanFile.readAsString() == choice) return;
    await _lanFile.writeAsString(choice, flush: true);
  }

  Future<void> revoke(String id) async {
    _devices.removeWhere((d) => d.id == id);
    await _save();
    onAccessChanged?.call();
  }

  Future<void> revokeAll() async {
    _devices.clear();
    await _save();
    onAccessChanged?.call();
  }

  /// Pairing link for the app, e.g. `knxmonitor://box?url=http://10.42.0.1:8765/&key=…`.
  ///
  /// With a certificate, `fp` is added: newer apps then switch to HTTPS and pin
  /// exactly this certificate, older ones stay on the HTTP address. Only with an
  /// HTTPS port other than 443 (Docker) does the HTTPS address itself go into the link.
  Uri pairingLink(String host, String key) {
    final fp = tlsFingerprint;
    final bare = host.split(':').first;
    return Uri(
      scheme: 'knxmonitor',
      host: 'box',
      queryParameters: {
        'url': fp != null && tlsPort != 443 ? 'https://$bare:$tlsPort/' : 'http://$host/',
        'key': key,
        'name': name,
        'fp': ?fp,
      },
    );
  }

  void _setPassword(String password) {
    final salt = _bytes(16);
    _password = {
      'salt': base64.encode(salt),
      'iterations': _iterations,
      'hash': base64.encode(_pbkdf2(password, salt, _iterations)),
    };
  }

  void _load(Map<String, Object?> j) {
    _password = (j['password'] as Map).cast<String, Object?>();
    _mustChange = j['mustChangePassword'] == true;
    _required = j['changeRequired'] == true;
    _stickerChecked = j['stickerChecked'] == true;
    // If the field is missing (older box), the value from knx-box.txt applies.
    if (j['lanAccess'] case final bool lan) _lanAccess = lan;
    _devices
      ..clear()
      ..addAll([for (final d in (j['devices'] as List?) ?? const []) BoxDevice.fromJson((d as Map).cast())]);
  }

  Future<void>? _saving;

  /// Waits until pending saves have finished (shutdown, tests).
  Future<void> flush() => (_saving ?? Future<void>.value()).catchError((Object _) {});

  /// Writes sequentially: two concurrent saves would otherwise share the temp
  /// file.
  Future<void> _save() {
    final previous = _saving ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) => _write());
    _saving = next;
    return next;
  }

  /// Last readable state before the most recent save.
  File get _backup => File('${_file.path}.bak');

  Future<void> _write() async {
    if (await _file.exists()) {
      try {
        jsonDecode(await _file.readAsString());
        await _file.copy(_backup.path);
      } on Object {
        // Do not take over an unreadable file as the backup.
      }
    }
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'version': 1,
        'password': _password,
        if (_mustChange) 'mustChangePassword': true,
        if (_required) 'changeRequired': true,
        if (_stickerChecked) 'stickerChecked': true,
        'lanAccess': _lanAccess,
        'devices': [for (final d in _devices) d.toJson()],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  // --- Pages ------------------------------------------------------------------

  /// Box-specific paths: `/pair` (pairing, devices, password) and `/api/box`.
  /// `true` if [request] has been answered by them.
  Future<bool> handle(HttpRequest request, BoxRole role) async {
    final path = request.uri.path;
    final response = request.response;
    if (path == '/api/box') {
      response.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.cacheControlHeader, 'no-store');
      response.write(
        jsonEncode({
          'box': true,
          'name': name,
          'role': role.name,
          'lanAccess': _lanAccess,
          if (sticker) 'wifiChange': true,
          if (_mustChange) 'mustChangePassword': true,
          if (_required) 'passwordChangeRequired': true,
          if (tlsFingerprint case final fp?) 'tls': {'port': tlsPort, 'fingerprint': fp},
          ...?status?.call(),
        }),
      );
      await response.close();
      return true;
    }
    if (path.startsWith('/api/box/') && _api.contains(path)) {
      await _handleApi(request, role);
      return true;
    }
    if (path != '/pair' && !path.startsWith('/pair/')) return false;
    final host = request.headers.value(HttpHeaders.hostHeader) ?? '';
    if (!RegExp(r'^[A-Za-z0-9.-]+(:\d{1,5})?$').hasMatch(host)) {
      await _deny(response, HttpStatus.badRequest, 'Ungültige Adresse.');
      return true;
    }
    String? key;
    String? notice;
    if (request.method == 'POST') {
      final form = await _form(request);
      if (form == null) {
        await _deny(response, HttpStatus.requestEntityTooLarge, 'Zu groß.');
        return true;
      }
      switch (path) {
        case '/pair':
          key = await pair(form['name'] ?? '');
        case '/pair/revoke':
          if (form['id'] == '*') {
            await revokeAll();
          } else {
            await revoke(form['id'] ?? '');
          }
          notice = 'Gerät gesperrt.';
        case '/pair/lan':
          await setLanAccess(form['enabled'] == '1');
          notice = lanAccess ? 'Zugriff über das Kabel ist frei.' : 'Zugriff über das Kabel ist aus.';
        case '/pair/password':
          final next = form['password'] ?? '';
          if (next.length < 8) {
            notice = 'Das neue Passwort braucht mindestens 8 Zeichen.';
          } else {
            try {
              await changePassword(next);
              notice = 'Passwort geändert. Der Browser fragt gleich neu danach.';
            } on SamePasswordException {
              notice = 'Das ist das Passwort vom Aufkleber. Bitte ein eigenes wählen.';
            }
          }
      }
    } else if (request.method != 'GET' || path != '/pair') {
      await _deny(response, HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
      return true;
    }
    response.headers
      ..contentType = ContentType.html
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    final peer = request.connectionInfo?.remoteAddress;
    final plainLan = request.requestedUri.scheme != 'https' && !(peer != null && _fromWlan(peer));
    response.write(_page(key == null ? null : pairingLink(host, key), notice, plainLan: plainLan, host: host));
    await response.close();
    return true;
  }

  static const _api = {
    '/api/box/pair',
    '/api/box/devices',
    '/api/box/devices/revoke',
    '/api/box/password',
    '/api/box/wifi',
    '/api/box/lan',
  };

  /// Management from the app, without a browser (admin rights only: box
  /// password or a device paired with it):
  ///
  /// - `POST /api/box/pair` `{name}` → `{key, id, name}`: new device with
  ///   admin rights; this is how the app pairs with the sticker password.
  /// - `GET /api/box/devices` → devices (without hash), `self` on the requester.
  /// - `POST /api/box/devices/revoke` `{id}` or `{id: "*"}`.
  /// - `POST /api/box/password` `{password}` (at least 8 characters), not the
  ///   one from the sticker.
  /// - `POST /api/box/wifi` `{password}`: Wi-Fi password of the box (real box only).
  /// - `POST /api/box/lan` `{enabled}`: access over the cable.
  Future<void> _handleApi(HttpRequest request, BoxRole role) async {
    final response = request.response;
    final path = request.uri.path;
    if (role != BoxRole.admin) {
      await _deny(response, HttpStatus.forbidden, 'Nur mit dem Box-Passwort.');
      return;
    }
    final post = request.method == 'POST';
    if (post != (path != '/api/box/devices') || (!post && request.method != 'GET')) {
      await _deny(response, HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
      return;
    }
    Map<String, Object?> body = const {};
    if (post) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in request) {
        builder.add(chunk);
        if (builder.length > 4096) {
          await _deny(response, HttpStatus.requestEntityTooLarge, 'Zu groß.');
          return;
        }
      }
      try {
        final raw = builder.takeBytes();
        body = raw.isEmpty ? const {} : (jsonDecode(utf8.decode(raw)) as Map).cast<String, Object?>();
      } on Object {
        await _deny(response, HttpStatus.badRequest, 'Ungültige Anfrage.');
        return;
      }
    }
    Object? result;
    switch (path) {
      case '/api/box/pair':
        final key = await pair(body['name'] as String? ?? '', admin: true);
        result = {'key': key, 'id': _devices.last.id, 'name': name};
      case '/api/box/devices':
        final self = _selfOf(request);
        result = [
          for (final d in _devices)
            {
              'id': d.id,
              'name': d.name,
              'created': d.created.millisecondsSinceEpoch,
              if (d.lastUsed != null) 'lastUsed': d.lastUsed!.millisecondsSinceEpoch,
              'admin': d.admin,
              if (d.id == self) 'self': true,
            },
        ];
      case '/api/box/devices/revoke':
        final id = body['id'];
        if (id is! String) {
          await _deny(response, HttpStatus.badRequest, 'Gerät fehlt.');
          return;
        }
        if (id == '*') {
          await revokeAll();
        } else {
          await revoke(id);
        }
        result = {'ok': true};
      case '/api/box/password':
        final next = body['password'] as String? ?? '';
        if (next.length < 8 || next.length > 128) {
          await _deny(response, HttpStatus.badRequest, 'Das Passwort braucht 8 bis 128 Zeichen.');
          return;
        }
        try {
          await changePassword(next, keepDevice: _selfOf(request));
        } on SamePasswordException {
          await _deny(response, HttpStatus.badRequest, 'Das ist das Passwort vom Aufkleber. Bitte ein eigenes wählen.');
          return;
        }
        result = {'ok': true};
      case '/api/box/wifi':
        final next = body['password'];
        if (next is! String || !validWifiPassword(next)) {
          await _deny(
            response,
            HttpStatus.badRequest,
            'Das Passwort braucht 8 bis 63 Zeichen ohne Leerzeichen und " \' \\ \$ `.',
          );
          return;
        }
        if (!await changeWifiPassword(next)) {
          await _deny(response, HttpStatus.conflict, 'Das WLAN gehört hier nicht zur Box.');
          return;
        }
        result = {'ok': true};
      case '/api/box/lan':
        final enabled = body['enabled'];
        if (enabled is! bool) {
          await _deny(response, HttpStatus.badRequest, 'Ungültige Anfrage.');
          return;
        }
        await setLanAccess(enabled);
        result = {'ok': true, 'lanAccess': enabled};
    }
    response.headers
      ..contentType = ContentType.json
      ..set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(result));
    await response.close();
  }

  /// Id of the requesting device (bearer), otherwise `null`.
  String? _selfOf(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!auth.startsWith('Bearer ')) return null;
    final hash = _sha256(utf8.encode(auth.substring(7).trim()));
    for (final d in _devices) {
      if (_equal(d.hash, hash)) return d.id;
    }
    return null;
  }

  static Future<Map<String, String>?> _form(HttpRequest request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > 4096) return null;
    }
    try {
      return Uri.splitQueryString(utf8.decode(builder.takeBytes()));
    } on FormatException {
      return const {};
    }
  }

  String _page(Uri? link, String? notice, {bool plainLan = false, String host = ''}) {
    const e = HtmlEscape(HtmlEscapeMode.attribute);
    final devices = [..._devices]..sort((a, b) => b.created.compareTo(a.created));
    final out = StringBuffer()
      ..write('<!doctype html><html lang="de"><head><meta charset="utf-8">')
      ..write('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..write('<title>${e.convert(name)} · Geräte koppeln</title><style>$_css</style></head><body><main>')
      ..write('<h1>${e.convert(name)}</h1>');
    if (notice != null) out.write('<p class="notice">${e.convert(notice)}</p>');
    if (plainLan) {
      final https = tlsFingerprint == null
          ? ''
          : ' Sicherer: <a href="https://${e.convert(host.split(':').first)}:$tlsPort/pair">HTTPS</a> '
                '(der Browser warnt einmal vor dem eigenen Zertifikat der Box).';
      out.write(
        '<p class="notice"><b>Unverschlüsselt.</b> Passwort und Daten gehen im Klartext durch dieses Netz.$https</p>',
      );
    }
    if (_mustChange) {
      out.write(
        '<p class="notice"><b>Bitte ein eigenes Passwort setzen.</b> Das bisherige steht auf dem Aufkleber und auf '
        'der SD-Karte; wer es hat, kann die Box steuern und den Keyring lesen. Danach verschwindet es von der Karte.</p>',
      );
    }
    if (_required) {
      out
        ..write('<section><h2>Eigenes Box-Passwort</h2><form method="post" action="/pair/password">')
        ..write('<input type="password" name="password" minlength="8" autocomplete="new-password" ')
        ..write('placeholder="Neues Passwort"><button>Setzen</button></form></section></main></body></html>');
      return '$out';
    }
    if (link != null) {
      out
        ..write('<section class="pair"><h2>Mit der Kamera scannen</h2>')
        ..write(qrSvg('$link'))
        ..write('<p><a class="button" href="${e.convert('$link')}">In der App öffnen</a></p>')
        ..write('<p class="hint">Der Code gilt, bis das Gerät gesperrt wird, und wird nur jetzt angezeigt. ')
        ..write('Seite danach schließen.</p></section>');
    }
    out
      ..write('<section><h2>Neues Gerät koppeln</h2><form method="post" action="/pair">')
      ..write('<input name="name" maxlength="40" placeholder="z. B. iPad Bauleitung" autocomplete="off">')
      ..write('<button>QR-Code erzeugen</button></form></section>')
      ..write('<section><h2>Gekoppelte Geräte</h2>');
    if (devices.isEmpty) {
      out.write('<p class="hint">Noch keine.</p>');
    } else {
      out.write('<ul>');
      for (final d in devices) {
        out
          ..write('<li><span><b>${e.convert(d.name)}</b><br><small>gekoppelt ${_date(d.created)}')
          ..write(d.lastUsed == null ? '' : ' · zuletzt ${_date(d.lastUsed!)}')
          ..write('</small></span><form method="post" action="/pair/revoke">')
          ..write('<input type="hidden" name="id" value="${e.convert(d.id)}"><button class="quiet">Sperren</button>')
          ..write('</form></li>');
      }
      out
        ..write('</ul><form method="post" action="/pair/revoke"><input type="hidden" name="id" value="*">')
        ..write('<button class="quiet">Alle sperren</button></form>');
    }
    out
      ..write('</section><section><h2>Box-Passwort ändern</h2><form method="post" action="/pair/password">')
      ..write('<input type="password" name="password" minlength="8" autocomplete="new-password" ')
      ..write('placeholder="Neues Passwort"><button>Ändern</button></form></section>')
      ..write('<section><h2>Zugriff über das Kabel</h2><p class="hint">')
      ..write(
        _lanAccess
            ? 'Frei: Auch Geräte im Netz am Kabel erreichen die Box (mit Passwort).'
            : 'Aus: Die Box ist nur im eigenen WLAN erreichbar.',
      )
      ..write('</p><form method="post" action="/pair/lan"><input type="hidden" name="enabled" ')
      ..write(
        'value="${_lanAccess ? '0' : '1'}"><button class="quiet">${_lanAccess ? 'Sperren' : 'Freigeben'}</button>',
      )
      ..write('</form></section>')
      ..write('<p class="hint"><a href="/">Zum Monitor</a></p></main></body></html>');
    return '$out';
  }

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static const _css =
      ':root{color-scheme:light dark;--fg:#1b1f1d;--muted:#5b6560;--line:#d5dbd8;--bg:#f7f9f8;--accent:#1f7a4d}'
      '@media(prefers-color-scheme:dark){:root{--fg:#e6ebe8;--muted:#9aa5a0;--line:#38413d;--bg:#141816;'
      '--accent:#5cc28f}}body{margin:0;background:var(--bg);color:var(--fg);font:16px/1.45 -apple-system,'
      'system-ui,sans-serif}main{max-width:520px;margin:0 auto;padding:24px 16px}h1{font-size:22px}'
      'h2{font-size:16px;margin:28px 0 8px}form{display:flex;gap:8px}input{flex:1;min-width:0;font:inherit;'
      'padding:10px;border:1px solid var(--line);border-radius:10px;background:transparent;color:inherit}'
      'button,.button{font:inherit;padding:10px 14px;border:0;border-radius:10px;background:var(--accent);'
      'color:#fff;text-decoration:none;display:inline-block}button.quiet{background:transparent;'
      'color:var(--accent);border:1px solid var(--line)}ul{list-style:none;padding:0;margin:0}'
      'li{display:flex;justify-content:space-between;align-items:center;gap:8px;padding:10px 0;'
      'border-bottom:1px solid var(--line)}small,.hint{color:var(--muted)}.notice{padding:10px;'
      'border:1px solid var(--line);border-radius:10px}.pair{text-align:center}'
      '.pair svg{width:min(100%,320px);height:auto;background:#fff;border-radius:12px}';

  // --- Helpers ------------------------------------------------------------------

  Uint8List _bytes(int n) => Uint8List.fromList([for (var i = 0; i < n; i++) _random.nextInt(256)]);

  /// 10 characters without easily confused ones (0/O, 1/l/I).
  String _randomPassword() {
    const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
    return [for (var i = 0; i < 10; i++) alphabet[_random.nextInt(alphabet.length)]].join();
  }

  static Uint8List _pbkdf2(String password, List<int> salt, int iterations) =>
      (PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, 32)))
          .process(Uint8List.fromList(utf8.encode(password)));

  static String _sha256(List<int> data) => base64.encode(SHA256Digest().process(Uint8List.fromList(data)));

  static String _hex(List<int> bytes) => [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  /// Comparison without early exit (no timing attack on the hash).
  static bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// The new password is the one printed on the sticker.
class SamePasswordException implements Exception {
  const SamePasswordException();
}

/// QR code as SVG (black on white, 4-module quiet zone).
String qrSvg(String data) {
  final image = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));
  final n = image.moduleCount;
  final path = StringBuffer();
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      if (image.isDark(row, col)) path.write('M${col + 4} ${row + 4}h1v1h-1z');
    }
  }
  final size = n + 8;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" shape-rendering="crispEdges" '
      'role="img" aria-label="QR-Code"><rect width="$size" height="$size" fill="#fff"/>'
      '<path fill="#000" d="$path"/></svg>';
}
