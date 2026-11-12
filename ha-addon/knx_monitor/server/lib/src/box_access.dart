import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:qr/qr.dart';

import 'atomic_file.dart';

/// Too many failed attempts at the box password (or too many checks at once); answer 429 with
/// `Retry-After` [retryAfter].
class TooManyAttemptsException implements Exception {
  const TooManyAttemptsException(this.retryAfter);
  final Duration retryAfter;
  @override
  String toString() => 'Zu viele Fehlversuche, bitte warten.';
}

/// Who makes a request to the box.
enum BoxRole {
  /// Box password (browser, HTTP Basic): everything, including pairing devices.
  admin,

  /// Paired device (app, bearer device token): monitor, history, sending.
  /// Devices paired in the app with the box password are [admin].
  device,

  /// Paired device that only looks: like [device], but sends nothing to the
  /// bus, not even read requests (a tablet in the hallway, a customer's view).
  viewer;

  /// Whether this role may put telegrams on the bus.
  bool get maySend => this != viewer;
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
    this.viewOnly = false,
    this.app,
  });

  final String id;

  /// Key of the app instance this access belongs to (docs/keys.md), if the app sent it when
  /// pairing. It says whose access this is (the owner's phone, the electrician's tablet); it grants
  /// nothing, the token does.
  final String? app;
  final String name;
  final String hash;
  final DateTime created;
  DateTime? lastUsed;

  /// May manage the box (devices, password): paired with the box password.
  final bool admin;

  /// Sends nothing to the bus ([BoxRole.viewer]); chosen when pairing.
  final bool viewOnly;

  BoxRole get role => admin ? BoxRole.admin : (viewOnly ? BoxRole.viewer : BoxRole.device);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'hash': hash,
    'created': created.millisecondsSinceEpoch,
    if (lastUsed != null) 'lastUsed': lastUsed!.millisecondsSinceEpoch,
    if (admin) 'admin': true,
    if (viewOnly) 'viewOnly': true,
    'app': ?app,
  };

  static final _appPattern = RegExp(r'^[0-9a-f]{16,64}$');

  /// [value] as an app instance key, or `null` if it is none.
  static String? appKey(Object? value) => value is String && _appPattern.hasMatch(value) ? value : null;

  static BoxDevice fromJson(Map<String, Object?> j) => BoxDevice(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    hash: j['hash'] as String,
    created: DateTime.fromMillisecondsSinceEpoch(j['created'] as int? ?? 0),
    lastUsed: j['lastUsed'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['lastUsed'] as int),
    admin: j['admin'] == true,
    viewOnly: j['viewOnly'] == true,
    app: appKey(j['app']),
  );
}

/// Access protection of the Busclear Box (`BOX=1`), see docs/knx-box.md and docs/security.md.
///
/// - **Browser:** the page `/login` asks for the password only and then sets
///   a session cookie ([sessionCookie]); `/logout` ends it. A browser without
///   a session is sent there instead of getting the browser's own login dialog
///   (which asks for a user name that does not matter). HTTP Basic with the
///   password (any user name) still works for tools such as curl, which get
///   the `WWW-Authenticate` challenge as before.
/// - **App:** device token as `Authorization: Bearer …`. The page `/pair` shows a QR code with a
///   one-time pairing code (`knxmonitor://box?url=…&code=…`, [createPairingCode]): valid for
///   [pairingCodeLifetime], usable once, kept only as a hash and only in memory. The app
///   exchanges it for its device token with `POST /api/box/claim` ([claimPath]); the device is
///   created at that moment, so the lasting secret never is in a link. Only on request the page
///   shows the device token itself (Home Assistant, ioBroker, apps up to 1.11.2, which do not
///   know the code).
///
/// - **Failed attempts:** wrong passwords, tokens and pairing codes count per sender; from the
///   fifth on the sender waits ([_fail]). Counts and running lockouts are kept in
///   `access-strikes.json` and survive a restart ([_loadStrikes]). No lockout lasts longer than
///   [_maxLockout], and a password reset on the device (`password-reset`, [_consumeReset]) clears
///   them all.
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
    this._strikesFile,
    this.name,
    this._iterations,
    this._clock,
    this._random,
    this._fromWlan,
    this.sticker,
    this._peerOf,
    this.container,
  );

  /// Opens `access.json` in [data]. If it does not exist yet, a password is
  /// set: [initialPassword] (on the box from `knx-box.txt`, see firstboot.sh)
  /// or a random one; then it is only available in [firstPassword]. It is
  /// never written to disk in plain text: the data folder is reachable via
  /// `/api/files/`.
  ///
  /// [initialLanAccess] applies as long as nothing else is set in the app.
  /// In a [container] (Docker) it applies on every start instead: there it
  /// comes from `LAN_ACCESS` in the container's settings, and the app cannot
  /// change it.
  /// [fromWlan] decides whether a sender is in the box Wi-Fi (default:
  /// [wlanPeer]).
  static Future<BoxAccess> open(
    Directory data, {
    String? initialPassword,
    String? name,
    bool initialLanAccess = false,
    bool Function(InternetAddress peer) fromWlan = wlanPeer,
    bool sticker = false,
    bool container = false,
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
      File('${data.path}/$strikesFileName'),
      (name == null || name.trim().isEmpty) ? Platform.localHostname : name.trim(),
      iterations,
      clock,
      random ?? Random.secure(),
      fromWlan,
      sticker,
      peerOf,
      container,
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
    // Docker: LAN_ACCESS from the container's settings wins over what the
    // first start stored, so changing it there and restarting takes effect.
    if (container && access._lanAccess != initialLanAccess) {
      access._lanAccess = initialLanAccess;
      await access._save();
    }
    await access._loadStrikes();
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
  /// Failed attempts and lockouts are cleared with it: the reset is the way back in, so nothing
  /// counted before may stand in its way.
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
        _strikes.clear();
        _strikesChanged();
        stdout.writeln('Busclear Box: Passwort von der SD-Karte übernommen');
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

  /// Failed attempts and lockouts across restarts, see [_loadStrikes].
  final File _strikesFile;

  /// Name of [_strikesFile] in the data folder.
  static const strikesFileName = 'access-strikes.json';

  /// Name of the box in the QR code (e.g. the Wi-Fi SSID).
  final String name;

  /// Real box with sticker and SD card (not Docker, see knx-box.service).
  final bool sticker;

  /// Docker container (`BOX=1` without the sticker of the real box): no box
  /// Wi-Fi, access from the network only via `LAN_ACCESS`, see [open].
  final bool container;

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

  /// Failed attempts per sender (address, or `device:<id>` for [confirmPassword]): how many, and
  /// until when the sender waits. Stored in [_strikesFile] whenever it changes.
  final _strikes = <String, ({int count, DateTime until})>{};

  /// The longest wait after failed attempts. Nothing locks longer, whatever count or clock say.
  static const _maxLockout = Duration(minutes: 15);

  /// How long a stored count is kept over a restart once its wait is over. While the server runs
  /// counts stay as before (until the password is entered correctly).
  static const _strikeMemory = Duration(hours: 24);

  /// At most this many senders in [_strikesFile].
  static const _maxStoredStrikes = 1024;

  /// Running password checks per sender: each one occupies a core for
  /// seconds, and a failed attempt only counts when it finishes. Without a
  /// limit, a hundred concurrent requests would stall the Pi before the
  /// throttling kicks in.
  final _verifying = <String, int>{};
  static const _maxVerifying = 3;

  /// The same over all senders: many addresses at once would otherwise still
  /// occupy every core of the Pi.
  static const _maxVerifyingTotal = 4;

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
        container
            ? 'Zugriff aus dem Netzwerk ist aus. Am Rechner mit dem Container über http://localhost öffnen, '
                  'oder LAN_ACCESS=yes setzen und den Container neu starten.'
            : 'Zugriff über das Kabel ist aus. Im WLAN der Box verbinden oder in den Box-Einstellungen freigeben.',
      );
    }
    // Docker without LAN access: only this machine, and only under a local
    // name. Otherwise a web page could rebind its own name to 127.0.0.1 and
    // ask for the password in the browser's login dialog (DNS rebinding).
    // A reverse proxy on the same host that passes its own host name lands
    // here too: it makes the container reachable from the network, so it
    // needs LAN_ACCESS=yes.
    if (container && !_lanAccess && !localHostName(request.headers.value(HttpHeaders.hostHeader))) {
      return _deny(
        response,
        HttpStatus.forbidden,
        'Nur über http://localhost erreichbar. Hinter einem Reverse-Proxy oder aus dem Netzwerk '
        'LAN_ACCESS=yes setzen und den Container neu starten.',
      );
    }
    final peer = _peerOf?.call(request) ?? address?.address ?? '';
    final now = _clock();
    if (request.uri.path == loginPath || request.uri.path == logoutPath) {
      await _loginOrLogout(request, peer, now);
      return null;
    }
    // The app hands in a pairing code: it has no access yet, the code is the credential.
    if (request.uri.path == claimPath) {
      await _claim(request, peer, now);
      return null;
    }
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    // A valid device token is checked first: a lockout of the sender (behind
    // a reverse proxy or NAT that is everyone) must not lock out paired apps.
    // Wrong tokens still count and are refused during the lockout.
    final bearer = auth.startsWith('Bearer ') ? _deviceFor(auth.substring(7).trim()) : null;
    final locked = _lockedFor(peer, now);
    if (bearer == null && locked != null) {
      response.headers.set(HttpHeaders.retryAfterHeader, '${locked.inSeconds + 1}');
      return _deny(response, HttpStatus.tooManyRequests, 'Zu viele Fehlversuche, bitte warten.');
    }
    // The browser loads the manifest without credentials; it only contains
    // the app's name, colours and icons.
    if (request.uri.path == '/manifest.json' && request.method == 'GET') return BoxRole.device;
    final session = _sessionOf(request, now);
    final BoxRole? role;
    if (auth.startsWith('Bearer ')) {
      role = bearer?.role;
    } else if (auth.startsWith('Basic ')) {
      final encoded = auth.substring(6).trim();
      final known = _acceptedBasic.contains(_sha256(utf8.encode(encoded)));
      if (!known && _tooManyChecks(peer)) {
        response.headers.set(HttpHeaders.retryAfterHeader, '5');
        return _deny(response, HttpStatus.tooManyRequests, 'Zu viele Anmeldungen auf einmal, bitte warten.');
      }
      role = await _counted(peer, () => _checkBasic(encoded)) ? BoxRole.admin : null;
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
      // A browser goes to the login page; its own dialog would ask for a user
      // name that does not matter. Pages are redirected, its other requests
      // (the web app's API calls) get 401 without the challenge, so that no
      // dialog pops up either. Tools without Sec-Fetch headers keep Basic.
      if (_isPage(request) && _isBrowser(request)) {
        final target = request.uri.hasQuery ? '${request.uri.path}?${request.uri.query}' : request.uri.path;
        return _redirect(response, target == '/' ? loginPath : '$loginPath?next=${Uri.encodeQueryComponent(target)}');
      }
      if (request.headers.value('sec-fetch-mode') == null) {
        response.headers.set(HttpHeaders.wwwAuthenticateHeader, 'Basic realm="$realm", charset="UTF-8"');
      }
      return _deny(response, HttpStatus.unauthorized, 'Anmeldung nötig.');
    }
    // Only the password itself clears the failed attempts: otherwise a valid device token
    // in between would allow unlimited further guessing.
    if (auth.startsWith('Basic ')) _forgive(peer);
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
    if (role != BoxRole.admin && (path == '/ws' || path == '/pair' || path.startsWith('/pair/'))) {
      return _deny(response, HttpStatus.forbidden, 'Nur mit dem $_passwordWord.');
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
  String get realm =>
      container ? 'Busclear: Benutzername beliebig, Passwort' : 'Busclear Box: Benutzername beliebig, Box-Passwort';

  /// "Box-Passwort", in Docker just "Passwort" (there is no box).
  String get _passwordWord => container ? 'Passwort' : 'Box-Passwort';

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
    final key = _sessionKeyOf(request, now);
    return key == null ? null : _sessions[key];
  }

  /// Stored key (hash) of the valid session in the cookie of [request].
  String? _sessionKeyOf(HttpRequest request, DateTime now) {
    _sessions.removeWhere((_, until) => !until.isAfter(now));
    for (final header in request.headers[HttpHeaders.cookieHeader] ?? const <String>[]) {
      for (final part in header.split(';')) {
        final eq = part.indexOf('=');
        if (eq < 0 || part.substring(0, eq).trim() != sessionCookie) continue;
        final value = part.substring(eq + 1).trim();
        if (value.isEmpty || value.length > 128) continue;
        final key = _sha256(utf8.encode(value));
        if (_sessions.containsKey(key)) return key;
      }
    }
    return null;
  }

  /// A browser: it sends fetch metadata (Sec-Fetch-*), older ones (Safari
  /// before 16.4) at least a browser user agent. curl or scripts asking for
  /// HTML keep the Basic challenge.
  static bool _isBrowser(HttpRequest request) =>
      request.headers.value('sec-fetch-mode') != null ||
      (request.headers.value(HttpHeaders.userAgentHeader) ?? '').startsWith('Mozilla/');

  /// A page the browser navigates to (not an API call or an asset).
  static bool _isPage(HttpRequest request) =>
      request.method == 'GET' && (request.headers.value(HttpHeaders.acceptHeader) ?? '').contains('text/html');

  /// Runs a password check of [peer] within the limits of concurrent checks
  /// (per sender and in total); the caller has checked them before.
  Future<bool> _counted(String peer, Future<bool> Function() check) async {
    _verifying[peer] = (_verifying[peer] ?? 0) + 1;
    try {
      return await check();
    } finally {
      final left = (_verifying[peer] ?? 1) - 1;
      if (left <= 0) {
        _verifying.remove(peer);
      } else {
        _verifying[peer] = left;
      }
    }
  }

  bool _tooManyChecks(String peer) =>
      (_verifying[peer] ?? 0) >= _maxVerifying || _verifying.values.fold(0, (a, b) => a + b) >= _maxVerifyingTotal;

  // --- Login page ---------------------------------------------------------------

  /// Login page: password only, then a session cookie.
  static const loginPath = '/login';

  /// Ends the browser's session (POST, from the button on `/pair`).
  static const logoutPath = '/logout';

  /// Where to go after logging in: a local path only (no `//host`, no
  /// backslash), never back to the login itself.
  static String safeNext(String? next) {
    if (next == null || next.length > 512) return '/';
    if (!RegExp(r'^/(?![/\\])[A-Za-z0-9/_.~%?=&+-]*$').hasMatch(next)) return '/';
    if (next.startsWith(loginPath) || next.startsWith(logoutPath)) return '/';
    return next;
  }

  /// A form sent by this box's own page: browsers send `Origin` with every
  /// form POST; a foreign page (login CSRF) has another one.
  bool _ownForm(HttpRequest request) {
    final origin = request.headers.value('origin');
    if (origin == null || !_sameOrigin(origin, request.headers.value(HttpHeaders.hostHeader))) return false;
    final site = request.headers.value('sec-fetch-site');
    return site == null || site == 'same-origin';
  }

  Future<void> _loginOrLogout(HttpRequest request, String peer, DateTime now) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    final secure = request.requestedUri.scheme == 'https';
    if (request.uri.path == logoutPath) {
      if (request.method != 'POST') {
        await _deny(response, HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
        return;
      }
      if (!_ownForm(request)) {
        await _deny(response, HttpStatus.forbidden, 'Fremde Herkunft.');
        return;
      }
      final key = _sessionKeyOf(request, now);
      if (key != null) _sessions.remove(key);
      response.headers.add(
        HttpHeaders.setCookieHeader,
        '$sessionCookie=; Max-Age=0; Path=/; HttpOnly; SameSite=Strict${secure ? '; Secure' : ''}',
      );
      await _redirect(response, loginPath);
      return;
    }
    if (request.method == 'GET') {
      final next = safeNext(request.uri.queryParameters['next']);
      if (_sessionOf(request, now) != null) {
        await _redirect(response, next);
        return;
      }
      await _loginAnswer(response, HttpStatus.ok, next: next);
      return;
    }
    if (request.method != 'POST') {
      await _deny(response, HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
      return;
    }
    if (!_ownForm(request)) {
      await _deny(response, HttpStatus.forbidden, 'Fremde Herkunft.');
      return;
    }
    final form = await _form(request);
    if (form == null) {
      await _deny(response, HttpStatus.requestEntityTooLarge, 'Zu groß.');
      return;
    }
    final next = safeNext(form['next']);
    final locked = _lockedFor(peer, now);
    if (locked != null) {
      final seconds = locked.inSeconds + 1;
      response.headers.set(HttpHeaders.retryAfterHeader, '$seconds');
      await _loginAnswer(
        response,
        HttpStatus.tooManyRequests,
        next: next,
        notice:
            'Zu viele Fehlversuche. Bitte ${seconds < 120 ? '$seconds Sekunden' : '${(seconds / 60).ceil()} Minuten'} warten.',
      );
      return;
    }
    final password = form['password'] ?? '';
    if (password.isEmpty || password.length > 128) {
      if (password.isNotEmpty) _fail(peer, now);
      await _loginAnswer(response, HttpStatus.unauthorized, next: next, notice: 'Bitte das Passwort eingeben.');
      return;
    }
    if (_tooManyChecks(peer)) {
      response.headers.set(HttpHeaders.retryAfterHeader, '5');
      await _loginAnswer(
        response,
        HttpStatus.tooManyRequests,
        next: next,
        notice: 'Zu viele Anmeldungen auf einmal. Bitte kurz warten.',
      );
      return;
    }
    if (!await _counted(peer, () => verifyPassword(password))) {
      _fail(peer, _clock());
      await _loginAnswer(response, HttpStatus.unauthorized, next: next, notice: 'Das Passwort stimmt nicht.');
      return;
    }
    unawaited(_rehash(password));
    _forgive(peer);
    _startSession(response, _clock(), secure: secure);
    // The sticker password is still valid: first set an own one.
    await _redirect(response, _mustChange ? '/pair' : next);
  }

  Future<void> _loginAnswer(HttpResponse response, int status, {required String next, String? notice}) async {
    const e = HtmlEscape(HtmlEscapeMode.attribute);
    response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write('<!doctype html><html lang="de"><head><meta charset="utf-8">')
      ..write('<meta name="viewport" content="width=device-width, initial-scale=1">')
      ..write('<title>${e.convert(name)} · Anmelden</title><style>$_css</style></head><body><main>')
      ..write('<h1>${e.convert(name)}</h1>');
    if (notice != null) response.write('<p class="notice" role="alert">${e.convert(notice)}</p>');
    response
      ..write('<form method="post" action="$loginPath">')
      ..write('<input type="hidden" name="next" value="${e.convert(next)}">')
      ..write('<label class="sr" for="password">$_passwordWord</label>')
      ..write('<input id="password" type="password" name="password" autocomplete="current-password" required ')
      ..write('autofocus placeholder="$_passwordWord"><button>Anmelden</button></form>')
      ..write(
        '<p class="hint">${container ? 'Das Passwort aus BOX_PASSWORD oder das zuletzt gesetzte.' : 'Das eigene Box-Passwort, bei einer neuen Box das vom Aufkleber.'}</p>',
      )
      ..write('</main></body></html>');
    await response.close();
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

  /// Changing the password and locking out all devices need the current
  /// password, also with an admin token or a session: a lost tablet or a
  /// borrowed browser must not be able to lock the owner out. A wrong one
  /// counts as a failed login. Not while the sticker password still has to be
  /// replaced: that one is printed on the box anyway.
  Future<bool> _confirmCurrent(HttpRequest request, Object? current) async {
    return confirmPassword(request, current);
  }

  /// [_confirmCurrent] for other services: restoring a box backup replaces everything on the box,
  /// so it asks for the current password like locking out all devices (box_backup.dart).
  ///
  /// Failed attempts count per sender and per paired device: the lockout in [guard] lets a valid
  /// device token through, so without the second key an admin token could guess the password
  /// without limit. During a lockout, and while too many checks run at once, it throws
  /// [TooManyAttemptsException] (the caller answers 429).
  Future<bool> confirmPassword(HttpRequest request, Object? current) async {
    if (_required) return true;
    final now = _clock();
    final peer = _peerAddress(request);
    final keys = [peer, if (_selfOf(request) case final id?) 'device:$id'];
    for (final key in keys) {
      if (_lockedFor(key, now) case final locked?) throw TooManyAttemptsException(locked);
    }
    if (current is! String || current.isEmpty || current.length > 128) {
      if (current is String && current.isNotEmpty) keys.forEach((k) => _fail(k, now));
      return false;
    }
    if (_tooManyChecks(peer)) throw const TooManyAttemptsException(Duration(seconds: 5));
    final ok = await _counted(peer, () => verifyPassword(current));
    for (final key in keys) {
      ok ? _forgive(key) : _fail(key, now);
    }
    return ok;
  }

  String _peerAddress(HttpRequest request) =>
      _peerOf?.call(request) ?? request.connectionInfo?.remoteAddress.address ?? '';

  /// `Host` of a request to this machine itself: localhost, 127.0.0.1 or
  /// [::1], with or without port.
  static bool localHostName(String? host) => host != null && _localHost.hasMatch(host);

  static final _localHost = RegExp(r'^(localhost|127\.0\.0\.1|\[::1\])(:\d{1,5})?$', caseSensitive: false);

  static bool _sameOrigin(String origin, String? host) => sameOrigin(origin, host);

  /// Whether the browser's `Origin` names the host the request was sent to (`Host`). Compared
  /// as parsed URIs: host without regard to case, port with the scheme's default (`http://box`
  /// equals `Host: box:80`). Anything that is not a plain `http`/`https` origin (`null`, a path,
  /// user info) never matches.
  static bool sameOrigin(String origin, String? host) {
    if (host == null || host.isEmpty) return false;
    final o = Uri.tryParse(origin);
    if (o == null || (o.scheme != 'http' && o.scheme != 'https') || o.host.isEmpty) return false;
    if (o.userInfo.isNotEmpty || o.path.isNotEmpty || o.hasQuery || o.hasFragment) return false;
    final h = Uri.tryParse('${o.scheme}://$host');
    if (h == null || h.host.isEmpty || h.userInfo.isNotEmpty || h.path.isNotEmpty || h.hasQuery) return false;
    return o.host.toLowerCase() == h.host.toLowerCase() && o.port == h.port;
  }

  /// Wait after the [count]th failed attempt: from the 5th 30 s, then doubled up to [_maxLockout].
  static Duration _waitAfter(int count) =>
      count < 5 ? Duration.zero : Duration(seconds: min(30 * (1 << min(count - 5, 10)), _maxLockout.inSeconds));

  /// How long [key] still waits after failed attempts, `null` if it does not.
  ///
  /// Never longer than [_maxLockout]: if the clock was set back in the meantime (a box without
  /// a battery starts with an old time), the end would lie far ahead and nobody could log in.
  /// Such an entry is shortened to the wait its count stands for, counted from now.
  Duration? _lockedFor(String key, DateTime now) {
    final strike = _strikes[key];
    if (strike == null || !strike.until.isAfter(now)) return null;
    final left = strike.until.difference(now);
    if (left <= _maxLockout) return left;
    final wait = _waitAfter(strike.count);
    _strikes[key] = (count: strike.count, until: now.add(wait));
    _strikesChanged();
    return wait > Duration.zero ? wait : null;
  }

  /// The right password: [key]'s failed attempts are forgotten. Writes only if there were any.
  void _forgive(String key) {
    if (_strikes.remove(key) != null) _strikesChanged();
  }

  void _fail(String peer, DateTime now) {
    final count = (_strikes[peer]?.count ?? 0) + 1;
    _strikes[peer] = (count: count, until: now.add(_waitAfter(count)));
    // There are only so many senders in a LAN; still, the list must not grow.
    // Expired entries go first; a running lockout only when the list is far
    // beyond that (many addresses), and then the one ending soonest, so that
    // a flood of new addresses cannot lift the lockout of the main attacker.
    if (_strikes.length > 1024) {
      _strikes.removeWhere((key, s) => key != peer && !s.until.isAfter(now));
      while (_strikes.length > 8192) {
        final soonest = _strikes.entries
            .where((e) => e.key != peer)
            .reduce((a, b) => a.value.until.isBefore(b.value.until) ? a : b)
            .key;
        _strikes.remove(soonest);
      }
    }
    _strikesChanged();
    stderr.writeln('Busclear Box: Fehlversuch $count von $peer');
  }

  // --- Failed attempts across restarts ---------------------------------------------------

  /// Reads [_strikesFile]: without it a restart (a power cut, an update, a crash someone
  /// provokes) would hand out fresh attempts.
  ///
  /// It can never lock anyone out for good: a wait that lies further ahead than its count allows
  /// (clock set back; at most [_maxLockout]) is shortened to that wait from now, counts whose
  /// wait ended more than [_strikeMemory] ago are dropped, and an unreadable file is deleted. A
  /// password reset on the device clears everything ([_consumeReset]); so does deleting the file
  /// while the server is stopped.
  Future<void> _loadStrikes() async {
    if (!await _strikesFile.exists()) return;
    final now = _clock();
    try {
      // Bounded: the file is the server's own, but nothing here may depend on that.
      if (await _strikesFile.length() > 512 * 1024) throw const FormatException('zu groß');
      final j = jsonDecode(await _strikesFile.readAsString());
      final stored = j is Map && j['strikes'] is Map ? j['strikes'] as Map : const <Object?, Object?>{};
      for (final MapEntry(:key, :value) in stored.entries) {
        if (_strikes.length >= _maxStoredStrikes) break;
        if (key is! String || key.isEmpty || key.length > 64 || value is! Map) continue;
        final count = value['count'];
        final until = value['until'];
        if (count is! int || count < 1 || until is! int) continue;
        var end = DateTime.fromMillisecondsSinceEpoch(until);
        if (!end.add(_strikeMemory).isAfter(now)) continue;
        final wait = _waitAfter(count);
        if (end.difference(now) > wait) end = now.add(wait);
        _strikes[key] = (count: min(count, 1 << 20), until: end);
      }
    } on Object catch (e) {
      stderr.writeln('$strikesFileName unlesbar, verworfen: $e');
      _strikes.clear();
      try {
        await _strikesFile.delete();
      } on FileSystemException {
        // The next change overwrites it.
      }
    }
  }

  bool _strikesDirty = false;
  Future<void>? _strikesWriting;

  /// Stores [_strikes] after a change. Changes while a write runs are collected into one more
  /// write, so a burst of failed attempts costs the SD card two writes, not one each. Requests
  /// that change nothing (a refused one during a lockout, a login without earlier failures)
  /// never get here.
  void _strikesChanged() {
    _strikesDirty = true;
    _strikesWriting ??= _writeStrikes();
  }

  Future<void> _writeStrikes() async {
    try {
      while (_strikesDirty) {
        _strikesDirty = false;
        final now = _clock();
        final keep = [
          for (final e in _strikes.entries)
            if (e.value.until.add(_strikeMemory).isAfter(now)) e,
        ];
        if (keep.isEmpty) {
          if (await _strikesFile.exists()) await _strikesFile.delete();
          continue;
        }
        // Too many: those that wait longest stay.
        if (keep.length > _maxStoredStrikes) {
          keep.sort((a, b) => b.value.until.compareTo(a.value.until));
          keep.length = _maxStoredStrikes;
        }
        await writeAtomic(
          _strikesFile,
          text: jsonEncode({
            'version': 1,
            'strikes': {
              for (final e in keep) e.key: {'count': e.value.count, 'until': e.value.until.millisecondsSinceEpoch},
            },
          }),
        );
      }
    } on Object catch (e) {
      stderr.writeln('$strikesFileName: $e');
    } finally {
      _strikesWriting = null;
    }
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
    _codes.clear();
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
  Future<String> pair(String deviceName, {bool admin = false, bool viewOnly = false, String? app}) async {
    final key = base64Url.encode(_bytes(32)).replaceAll('=', '');
    final name = deviceName.trim().isEmpty ? 'Gerät ${_devices.length + 1}' : deviceName.trim();
    _devices.add(
      BoxDevice(
        id: _hex(_bytes(6)),
        name: name.length > 40 ? name.substring(0, 40) : name,
        hash: _sha256(utf8.encode(key)),
        created: _clock(),
        admin: admin,
        viewOnly: viewOnly && !admin,
        app: app,
      ),
    );
    await _save();
    return key;
  }

  // --- One-time pairing codes -----------------------------------------------------------

  /// Where the app hands in a pairing code (`POST`, no other credentials), see [_claim].
  static const claimPath = '/api/box/claim';

  /// How long a pairing code from `/pair` can be handed in.
  static const pairingCodeLifetime = Duration(minutes: 10);

  /// Open and recently used codes; the oldest goes first.
  static const _maxCodes = 8;

  /// Pairing codes of this run, newest last. In memory only: a restart ends open codes.
  final _codes = <PairingCode>[];

  /// Codes that wait or were handed in during this run (for the page `/pair`).
  List<PairingCode> get pairingCodes {
    _pruneCodes(_clock());
    return List.unmodifiable(_codes);
  }

  /// Expired codes go, and used ones after a day; they are only kept to be shown.
  void _pruneCodes(DateTime now) => _codes.removeWhere(
    (c) => c.used == null ? !c.expires.isAfter(now) : now.difference(c.used!) > const Duration(hours: 24),
  );

  /// Creates a one-time pairing code for a device with the given rights and returns it in plain
  /// text (only this once; 256 random bits, of which only the SHA-256 is kept). Nothing is
  /// paired yet: the device comes into being when the app hands the code in ([claimPairing]).
  String createPairingCode(String deviceName, {bool admin = false, bool viewOnly = false}) {
    final now = _clock();
    _pruneCodes(now);
    while (_codes.length >= _maxCodes) {
      _codes.removeAt(0);
    }
    final code = base64Url.encode(_bytes(32)).replaceAll('=', '');
    final name = deviceName.trim();
    _codes.add(
      PairingCode._(
        id: _hex(_bytes(6)),
        hash: _sha256(utf8.encode(code)),
        name: name.length > 40 ? name.substring(0, 40) : name,
        admin: admin,
        viewOnly: viewOnly && !admin,
        created: now,
        expires: now.add(pairingCodeLifetime),
      ),
    );
    return code;
  }

  /// Withdraws the open code with [id] (button on `/pair`).
  void cancelPairingCode(String id) => _codes.removeWhere((c) => c.id == id && c.used == null);

  /// Exchanges [code] for a device token: `{key, id, name}` like `POST /api/box/pair`, or `null`
  /// if the code is unknown, already used or expired (the three are not told apart).
  ///
  /// The device gets the rights chosen on the page and the name given there; without one,
  /// [deviceName] as the app calls itself. The code is spent before anything is stored, so two
  /// requests at once cannot both win.
  Future<Map<String, Object?>?> claimPairing(String code, {String deviceName = '', String? app}) async {
    if (code.isEmpty || code.length > 128) return null;
    final now = _clock();
    _pruneCodes(now);
    final hash = _sha256(utf8.encode(code));
    PairingCode? found;
    for (final c in _codes) {
      if (c.used == null && _equal(c.hash, hash)) found = c;
    }
    if (found == null) return null;
    found.used = now;
    final key = await pair(
      found.name.isEmpty ? deviceName : found.name,
      admin: found.admin,
      viewOnly: found.viewOnly,
      app: app,
    );
    return {'key': key, 'id': _devices.last.id, 'name': name};
  }

  /// `POST /api/box/claim` `{code, name, app}` → `{key, id, name}`.
  ///
  /// The only request besides the login that works without credentials: the code is one. A
  /// wrong, used or expired code counts as a failed attempt like a wrong password, and during a
  /// lockout nothing is checked at all.
  Future<void> _claim(HttpRequest request, String peer, DateTime now) async {
    final response = request.response;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (request.method != 'POST') {
      await _deny(response, HttpStatus.methodNotAllowed, 'Nicht erlaubt.');
      return;
    }
    // The app sends no Origin; a web page has no business here.
    final origin = request.headers.value('origin');
    if (origin != null && !_sameOrigin(origin, request.headers.value(HttpHeaders.hostHeader))) {
      await _deny(response, HttpStatus.forbidden, 'Fremde Herkunft.');
      return;
    }
    if (_lockedFor(peer, now) case final locked?) {
      response.headers.set(HttpHeaders.retryAfterHeader, '${locked.inSeconds + 1}');
      await _deny(response, HttpStatus.tooManyRequests, 'Zu viele Fehlversuche, bitte warten.');
      return;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request) {
      builder.add(chunk);
      if (builder.length > 4096) {
        await _deny(response, HttpStatus.requestEntityTooLarge, 'Zu groß.');
        return;
      }
    }
    final Map<String, Object?> body;
    try {
      body = (jsonDecode(utf8.decode(builder.takeBytes())) as Map).cast<String, Object?>();
    } on Object {
      await _deny(response, HttpStatus.badRequest, 'Ungültige Anfrage.');
      return;
    }
    final code = body['code'];
    if (code is! String || code.isEmpty) {
      await _deny(response, HttpStatus.badRequest, 'Kopplungscode fehlt.');
      return;
    }
    final deviceName = body['name'];
    final result = await claimPairing(
      code,
      deviceName: deviceName is String ? deviceName : '',
      app: BoxDevice.appKey(body['app']),
    );
    if (result == null) {
      _fail(peer, _clock());
      await _deny(response, HttpStatus.forbidden, 'Kopplungscode ungültig, schon benutzt oder abgelaufen.');
      return;
    }
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(result));
    await response.close();
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

  /// Locks out everyone: devices, browser sessions, cached logins and open pairing codes (after
  /// an incident nothing logged in or handed out before may stay in).
  Future<void> revokeAll() async {
    _devices.clear();
    _sessions.clear();
    _acceptedBasic.clear();
    _codes.clear();
    await _save();
    onAccessChanged?.call();
  }

  /// Pairing link for the app, e.g. `knxmonitor://box?url=http://10.42.0.1:8765/&code=…`, with a
  /// one-time pairing [code] ([createPairingCode]). Only for apps that do not know the code yet
  /// and for integrations the link carries the device token itself ([key]).
  ///
  /// With a certificate, `fp` is added: newer apps then switch to HTTPS and pin
  /// exactly this certificate, older ones stay on the HTTP address. Only with an
  /// HTTPS port other than 443 (Docker) does the HTTPS address itself go into the link.
  Uri pairingLink(String host, {String? code, String? key}) {
    assert((code == null) != (key == null), 'either a pairing code or a device token');
    final fp = tlsFingerprint;
    final bare = host.split(':').first;
    return Uri(
      scheme: 'knxmonitor',
      host: 'box',
      queryParameters: {
        'url': fp != null && tlsPort != 443 ? 'https://$bare:$tlsPort/' : 'http://$host/',
        'code': ?code,
        'key': ?key,
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
  Future<void> flush() async {
    await (_saving ?? Future<void>.value()).catchError((Object _) {});
    await _strikesWriting;
  }

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
          if (container) 'container': true,
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
      try {
        await _handleApi(request, role);
      } on TooManyAttemptsException catch (e) {
        response.headers.set(HttpHeaders.retryAfterHeader, '${e.retryAfter.inSeconds + 1}');
        await _deny(response, HttpStatus.tooManyRequests, 'Zu viele Fehlversuche, bitte warten.');
      }
      return true;
    }
    if (path != '/pair' && !path.startsWith('/pair/')) return false;
    final host = request.headers.value(HttpHeaders.hostHeader) ?? '';
    if (!RegExp(r'^[A-Za-z0-9.-]+(:\d{1,5})?$').hasMatch(host)) {
      await _deny(response, HttpStatus.badRequest, 'Ungültige Adresse.');
      return true;
    }
    Uri? link;
    String? key;
    String? notice = request.method == 'GET' ? backupNotice(request.uri.queryParameters['backup']) : null;
    if (request.method == 'POST') {
      final form = await _form(request);
      if (form == null) {
        await _deny(response, HttpStatus.requestEntityTooLarge, 'Zu groß.');
        return true;
      }
      try {
        switch (path) {
          case '/pair':
            // The page itself needs the password, so it may also hand out a
            // device with admin rights (as POST /api/box/pair does): Home
            // Assistant and ioBroker need one for /api/ha/.
            final admin = form['admin'] == '1';
            final viewOnly = form['viewOnly'] == '1';
            if (form['direct'] == '1') {
              // Asked for explicitly: the device token itself, for what cannot hand in a code.
              key = await pair(form['name'] ?? '', admin: admin, viewOnly: viewOnly);
              link = pairingLink(host, key: key);
            } else {
              link = pairingLink(
                host,
                code: createPairingCode(form['name'] ?? '', admin: admin, viewOnly: viewOnly),
              );
            }
          case '/pair/cancel':
            cancelPairingCode(form['id'] ?? '');
            notice = 'Kopplungscode verworfen.';
          case '/pair/revoke':
            if (form['id'] == '*') {
              if (await _confirmCurrent(request, form['current'])) {
                await revokeAll();
                notice = 'Alle Geräte gesperrt.';
              } else {
                notice = 'Das aktuelle Passwort stimmt nicht.';
              }
            } else {
              await revoke(form['id'] ?? '');
              notice = 'Gerät gesperrt.';
            }
          case '/pair/lan':
            if (container) {
              notice = _containerLan;
            } else {
              await setLanAccess(form['enabled'] == '1');
              notice = lanAccess ? 'Zugriff über das Kabel ist frei.' : 'Zugriff über das Kabel ist aus.';
            }
          case '/pair/password':
            final next = form['password'] ?? '';
            if (next.length < 8) {
              notice = 'Das neue Passwort braucht mindestens 8 Zeichen.';
            } else if (!await _confirmCurrent(request, form['current'])) {
              notice = 'Das aktuelle Passwort stimmt nicht.';
            } else {
              try {
                await changePassword(next);
                notice = 'Passwort geändert. Bitte gleich mit dem neuen anmelden.';
              } on SamePasswordException {
                notice = 'Das ist das Passwort vom Aufkleber. Bitte ein eigenes wählen.';
              }
            }
        }
      } on TooManyAttemptsException {
        notice = 'Zu viele Fehlversuche, bitte warten.';
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
    response.write(_page(link, notice, key: key, plainLan: plainLan, host: host));
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
  /// password or a device paired with it). `POST /api/box/claim` is not among them: it takes a
  /// pairing code instead of credentials and is answered in [guard] ([_claim]).
  ///
  /// - `POST /api/box/pair` `{name}` → `{key, id, name}`: new device with
  ///   admin rights; this is how the app pairs with the sticker password.
  /// - `GET /api/box/devices` → devices (without hash), `self` on the requester.
  /// - `POST /api/box/devices/revoke` `{id}` or `{id: "*", current}`.
  /// - `POST /api/box/password` `{password, current}` (at least 8 characters),
  ///   not the one from the sticker.
  ///
  /// [current] is the box password as it is now (see [_confirmCurrent]).
  /// - `POST /api/box/wifi` `{password}`: Wi-Fi password of the box (real box only).
  /// - `POST /api/box/lan` `{enabled}`: access over the cable.
  Future<void> _handleApi(HttpRequest request, BoxRole role) async {
    final response = request.response;
    final path = request.uri.path;
    if (role != BoxRole.admin) {
      await _deny(response, HttpStatus.forbidden, 'Nur mit dem $_passwordWord.');
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
        // An admin token outlives a password change. Only with the password
        // itself (as the app pairs), not with a session or another token: a
        // borrowed browser or a lost tablet must not mint a lasting one.
        if (!(request.headers.value(HttpHeaders.authorizationHeader) ?? '').startsWith('Basic ')) {
          await _deny(response, HttpStatus.forbidden, 'Nur mit dem $_passwordWord.');
          return;
        }
        final key = await pair(body['name'] as String? ?? '', admin: true, app: BoxDevice.appKey(body['app']));
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
              if (d.viewOnly) 'viewOnly': true,
              'app': ?d.app,
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
          if (!await _confirmCurrent(request, body['current'])) {
            await _deny(response, HttpStatus.forbidden, 'Das aktuelle Passwort stimmt nicht.');
            return;
          }
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
        if (!await _confirmCurrent(request, body['current'])) {
          await _deny(response, HttpStatus.forbidden, 'Das aktuelle Passwort stimmt nicht.');
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
        if (container) {
          await _deny(response, HttpStatus.conflict, _containerLan);
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

  /// Id of the paired device that makes [request] (bearer token), otherwise
  /// `null` (box password, session cookie). The server marks what a device
  /// without admin rights stores with it (`charts.json`, `watch_rules.json`).
  String? deviceIdOf(HttpRequest request) => _selfOf(request);

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

  String _page(Uri? link, String? notice, {String? key, bool plainLan = false, String host = ''}) {
    const e = HtmlEscape(HtmlEscapeMode.attribute);
    final codes = pairingCodes.reversed.toList();
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
        ..write('<p><a class="button" href="${e.convert('$link')}">In der App öffnen</a></p>');
      if (key == null) {
        out
          ..write('<p class="hint">Der Code gilt ${pairingCodeLifetime.inMinutes} Minuten und nur einmal; er wird ')
          ..write('nur jetzt angezeigt. Das Gerät erscheint unten, sobald die App ihn eingelöst hat. Meldet die ')
          ..write('App „Zugang abgelehnt“, kennt sie den Code noch nicht (bis 1.11.2): App aktualisieren oder ')
          ..write('unten „Schlüssel direkt anzeigen“ wählen.</p></section>');
      } else {
        out
          ..write('<p class="hint">Schlüssel für Home Assistant und ioBroker:</p>')
          ..write('<p><code>${e.convert(key)}</code></p>')
          ..write('<p class="hint">Dieser Schlüssel gilt, bis das Gerät gesperrt wird, und steht so im Link und ')
          ..write('im QR-Code: nicht weitergeben, nicht fotografieren. Er wird nur jetzt angezeigt. Seite danach ')
          ..write('schließen.</p></section>');
      }
    }
    out
      ..write('<section><h2>Neues Gerät koppeln</h2><form class="stack" method="post" action="/pair">')
      ..write('<input name="name" maxlength="40" placeholder="z. B. iPad Bauleitung" autocomplete="off">')
      ..write('<label class="check"><input type="checkbox" name="viewOnly" value="1"> Nur ansehen: ')
      ..write('schaltet nichts und schickt nichts auf den Bus</label>')
      ..write('<label class="check"><input type="checkbox" name="admin" value="1"> Verwalten: darf alles wie mit ')
      ..write('dem Passwort, für Home Assistant und ioBroker</label>')
      ..write('<label class="check"><input type="checkbox" name="direct" value="1"> Schlüssel direkt anzeigen: ')
      ..write('nur für Home Assistant, ioBroker und Apps bis 1.11.2. Statt des Einmal-Codes steht dann der ')
      ..write('dauerhafte Schlüssel im Link</label>')
      ..write('<button>QR-Code erzeugen</button></form></section>');
    if (codes.isNotEmpty) {
      out.write('<section><h2>Kopplungscodes</h2><ul>');
      for (final c in codes) {
        final used = c.used;
        out
          ..write('<li><span><b>${c.name.isEmpty ? 'Ohne Namen' : e.convert(c.name)}</b>')
          ..write(c.admin ? ' <small>· verwalten</small>' : (c.viewOnly ? ' <small>· nur ansehen</small>' : ''))
          ..write('<br><small>')
          ..write(used == null ? 'wartet auf die App, gültig bis ${_date(c.expires)}' : 'eingelöst ${_date(used)}')
          ..write('</small></span>');
        if (used == null) {
          out
            ..write('<form method="post" action="/pair/cancel"><input type="hidden" name="id" ')
            ..write('value="${e.convert(c.id)}"><button class="quiet">Verwerfen</button></form>');
        }
        out.write('</li>');
      }
      out.write('</ul></section>');
    }
    out.write('<section><h2>Gekoppelte Geräte</h2>');
    if (devices.isEmpty) {
      out.write('<p class="hint">Noch keine.</p>');
    } else {
      out.write('<ul>');
      for (final d in devices) {
        out
          ..write('<li><span><b>${e.convert(d.name)}</b>')
          ..write(d.admin ? ' <small>· verwalten</small>' : (d.viewOnly ? ' <small>· nur ansehen</small>' : ''))
          ..write('<br><small>gekoppelt ${_date(d.created)}')
          ..write(d.lastUsed == null ? '' : ' · zuletzt ${_date(d.lastUsed!)}')
          ..write('</small></span><form method="post" action="/pair/revoke">')
          ..write('<input type="hidden" name="id" value="${e.convert(d.id)}"><button class="quiet">Sperren</button>')
          ..write('</form></li>');
      }
      out
        ..write('</ul><form method="post" action="/pair/revoke"><input type="hidden" name="id" value="*">')
        ..write('<input type="password" name="current" autocomplete="current-password" required ')
        ..write('placeholder="Aktuelles Passwort"><button class="quiet">Alle sperren</button></form>');
    }
    out
      ..write('</section><section><h2>$_passwordWord ändern</h2><form method="post" action="/pair/password">')
      ..write('<input type="password" name="current" autocomplete="current-password" required ')
      ..write('placeholder="Aktuelles Passwort">')
      ..write('<input type="password" name="password" minlength="8" autocomplete="new-password" ')
      ..write('placeholder="Neues Passwort"><button>Ändern</button></form></section>')
      ..write(container ? _containerLanSection() : _boxLanSection())
      ..write(_backupSection)
      ..write('<form method="post" action="$logoutPath" class="end"><a class="hint" href="/">Zum Monitor</a>')
      ..write('<button class="quiet">Abmelden</button></form></main></body></html>');
    return '$out';
  }

  /// Download of the whole backup (box_backup.dart, `POST /api/backup/form`). Restoring needs the
  /// app or the API (docs/backup-format.md): it asks back before it replaces anything.
  String get _backupSection =>
      '<section><h2>Sicherung</h2><p class="hint">Alle Anlagen mit Verlauf, Projekt, Wächtern und Prüfbuch '
      'in einer Datei. Mit Passwort (mindestens 12 Zeichen) kommen KNX-Secure-Schlüssel und Zugangsdaten '
      'verschlüsselt dazu, ohne bleiben sie draußen. Das Passwort getrennt notieren: Ohne es kommt beim '
      'Wiederherstellen alles außer den Schlüsseln zurück. $_passwordWord, gekoppelte Geräte und Zertifikat '
      'sind nie darin. Die Datei enthält den Verlauf im Klartext: sicher aufbewahren. Wiederherstellen in der '
      'App über das Zahnrad der Verbindung.</p><form method="post" action="/api/backup/form" class="stack">'
      '<label for="backup-password">Passwort für die Schlüssel (freiwillig)</label>'
      '<input type="password" id="backup-password" name="password" minlength="12" autocomplete="new-password">'
      '<label for="backup-password2">Passwort wiederholen</label>'
      '<input type="password" id="backup-password2" name="password2" autocomplete="new-password">'
      '<button>Sicherung herunterladen</button></form></section>';

  /// Notice on `/pair` after a failed backup download from the form (`?backup=<problem>`, set by
  /// box_backup.dart), so the browser shows text instead of the JSON error.
  static String? backupNotice(String? problem) => switch (problem) {
    'mismatch' => 'Sicherung: Die beiden Passwörter stimmen nicht überein.',
    'passwordShort' => 'Sicherung: Das Passwort braucht mindestens 12 Zeichen.',
    'busy' => 'Sicherung: Es läuft schon eine Sicherung, bitte gleich noch einmal versuchen.',
    null => null,
    _ => 'Sicherung: Das hat nicht geklappt, bitte noch einmal versuchen.',
  };

  /// Docker: why the switch is not here.
  static const _containerLan = 'Im Container über LAN_ACCESS einstellen (yes oder no) und den Container neu starten.';

  String _boxLanSection() =>
      '<section><h2>Zugriff über das Kabel</h2><p class="hint">'
      '${_lanAccess ? 'Frei: Auch Geräte im Netz am Kabel erreichen die Box (mit Passwort).' : 'Aus: Die Box ist nur im eigenen WLAN erreichbar.'}'
      '</p><form method="post" action="/pair/lan"><input type="hidden" name="enabled" '
      'value="${_lanAccess ? '0' : '1'}"><button class="quiet">${_lanAccess ? 'Sperren' : 'Freigeben'}</button>'
      '</form></section>';

  String _containerLanSection() =>
      '<section><h2>Zugriff aus dem Netzwerk</h2><p class="hint">'
      '${_lanAccess ? 'Frei: Geräte im Netzwerk erreichen Busclear (mit Passwort).' : 'Aus: Nur am Rechner mit dem Container selbst erreichbar.'} '
      '$_containerLan</p></section>';

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
      '.pair svg{width:min(100%,320px);height:auto;background:#fff;border-radius:12px}'
      'form.stack{flex-direction:column;align-items:stretch}form.stack label{color:var(--muted);font-size:14px}form.end{justify-content:space-between;align-items:center;margin-top:28px}'
      // The choices of a new device one below the other: three texts side by side became columns
      // a few words wide.
      'form.stack label.check{display:flex;gap:8px;align-items:flex-start;color:var(--fg);font-size:15px}'
      'input[type=checkbox]{flex:none;width:18px;height:18px;margin:2px 0 0;padding:0}'
      'code{word-break:break-all}.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}';

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

/// A one-time pairing code handed out on `/pair` ([BoxAccess.createPairingCode]): what the device
/// will be, until when the code can be handed in and when that happened. The code itself is not
/// in here, only its hash.
class PairingCode {
  PairingCode._({
    required this.id,
    required this.hash,
    required this.name,
    required this.admin,
    required this.viewOnly,
    required this.created,
    required this.expires,
  });

  /// Names the code on the page (to withdraw it); grants nothing.
  final String id;

  /// SHA-256 of the code.
  final String hash;

  /// Name for the device as entered on the page; empty: the app's own.
  final String name;
  final bool admin;
  final bool viewOnly;
  final DateTime created;
  final DateTime expires;

  /// When the code was handed in; `null` while it waits.
  DateTime? used;
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
