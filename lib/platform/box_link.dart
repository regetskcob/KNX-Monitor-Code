/// Pairing with a Busclear Box (Raspberry Pi with continuous recording, see docs/knx-box.md).
///
/// The box shows a QR code with the pairing link
/// `knxmonitor://box?url=http://knx-box.local/&code=…&name=KNX-Box-1A2B`. The `code` is a one-time
/// pairing code: valid for a few minutes, usable once. The app exchanges it for its device access
/// ([needsClaim], `POST /api/box/claim`), so the lasting secret is never part of a link. Links from
/// boxes up to 1.11.2 carry the device access itself (`key=…`) and keep working.
///
/// The box's sticker instead carries the setup link
/// `knxmonitor://box?url=http://10.42.0.1/&name=…&ssid=…&wifi=…&pw=…`: the box's Wi-Fi and the box
/// password. With it the app joins the Wi-Fi and pairs itself ([needsPairing]); the password is not
/// stored afterwards. The camera app opens the app directly with it; pasting works too. Also
/// accepted: the box's pairing page (`http://knx-box.local/pair?key=…`) and a bare address
/// (`10.42.0.1`; the box listens on port 80, a server in development mode e.g. on `:8765`).
final class BoxLink {
  BoxLink({
    required Uri url,
    this.key = '',
    this.name = '',
    this.ssid = '',
    this.wifi = '',
    this.password = '',
    this.code = '',
    this.fp = '',
  }) : url = _base(
         fp.isEmpty || url.scheme != 'http'
             ? url
             : Uri(
                 scheme: 'https',
                 host: url.host,
                 port: url.hasPort && url.port != 80 ? url.port : null,
                 path: url.path,
               ),
       );

  /// Base address of the box server, ends with "/".
  final Uri url;

  /// Device access (bearer token); empty as long as the box does not require one.
  final String key;

  /// Display name of the box (e.g. the Wi-Fi SSID).
  final String name;

  /// Wi-Fi of the box (SSID and WPA2 password), for joining from the app.
  final String ssid;
  final String wifi;

  /// Box password from the setup link; only for pairing, never stored.
  final String password;

  /// One-time pairing code from the box's pairing page; exchanged once for [key], never stored.
  final String code;

  /// Fingerprint of the box's certificate (SHA-256, base64url). With it the app speaks HTTPS and
  /// trusts only this certificate; the address in the link stays HTTP for older apps.
  final String fp;

  /// Whether the app speaks TLS with the box. Without it (no fingerprint, plain HTTP) everything the
  /// app sends there can be read in the network.
  bool get encrypted => url.scheme == 'https';

  /// Setup link: no device access yet, but the password for pairing.
  bool get needsPairing => key.isEmpty && password.isNotEmpty;

  /// Pairing link with a one-time code: no device access yet, the code is exchanged for it. A link
  /// that already carries the access needs nothing; the box password wins over a code.
  bool get needsClaim => key.isEmpty && password.isEmpty && code.isNotEmpty;

  /// Whether the link holds something secret that pairing would send to the box.
  bool get carriesSecret => key.isNotEmpty || password.isNotEmpty || code.isNotEmpty;

  /// Plain HTTP to an address outside the local network: whatever the app sends there crosses the
  /// internet readable for everyone on the way. Nothing secret goes over such a link: the app
  /// refuses before it sends (`addon_io.dart`).
  bool get plainOverInternet => !encrypted && !isLocal && !isHomeName(url.host);

  /// Whether [rawHost] is a name only the home network can resolve: a single label (`nas`,
  /// `busclear`) or one under a domain reserved for private use (`.home.arpa`, RFC 8375;
  /// `.internal`). The network the device is in answers such a name itself, as it does for a
  /// private address, so plain HTTP to it stays allowed. Not `.fritz.box` and the like: `.box` is a public top-level domain, and outside the
  /// home network such a name can belong to anyone.
  static bool isHomeName(String rawHost) {
    final host = rawHost.toLowerCase();
    if (host.isEmpty || host.contains(':')) return false;
    if (RegExp(r'^[0-9.]+$').hasMatch(host)) return false;
    return !host.contains('.') || host.endsWith('.home.arpa') || host.endsWith('.internal');
  }

  /// With the box password entered by hand (bare address on the desktop): pairs like the setup
  /// link. A link with device access, password or pairing code is kept.
  BoxLink withPassword(String password) => carriesSecret || password.isEmpty
      ? this
      : BoxLink(url: url, name: name, ssid: ssid, wifi: wifi, password: password, fp: fp);

  /// Copy with device access and without password or pairing code, for storing after pairing.
  BoxLink paired(String deviceKey) => BoxLink(url: url, key: deviceKey, name: name, ssid: ssid, wifi: wifi, fp: fp);

  static const scheme = 'knxmonitor';

  static final _keyPattern = RegExp(r'^[A-Za-z0-9_~.-]{1,128}$');

  /// Reads a pairing link; `null` if [text] is not one.
  ///
  /// Also accepts the route Flutter reports when opened via a link (Android only delivers path and
  /// query, e.g. "/?url=…").
  static BoxLink? parse(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://') && !t.startsWith('/') && !t.startsWith('?')) {
      final bare = Uri.tryParse('http://$t');
      if (bare == null || bare.host.isEmpty || bare.hasQuery || bare.userInfo.isNotEmpty) return null;
      t = '$bare';
    }
    final uri = Uri.tryParse(t);
    if (uri == null) return null;
    final query = uri.queryParameters;
    final Uri target;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      // Pairing page of the box: the base is everything before "pair".
      final path = uri.path.endsWith('/pair') ? uri.path.substring(0, uri.path.length - 4) : uri.path;
      target = Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: path);
    } else if (uri.scheme == scheme || uri.scheme.isEmpty) {
      final url = Uri.tryParse(query['url'] ?? '');
      if (url == null || !(url.scheme == 'http' || url.scheme == 'https')) return null;
      target = url;
    } else {
      return null;
    }
    if (target.host.isEmpty || target.userInfo.isNotEmpty) return null;
    final key = query['key'] ?? '';
    if (key.isNotEmpty && !_keyPattern.hasMatch(key)) return null;
    final code = query['code'] ?? '';
    if (code.isNotEmpty && !_keyPattern.hasMatch(code)) return null;
    final fp = query['fp'] ?? '';
    if (fp.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(fp)) return null;
    final name = (query['name'] ?? '').trim();
    final ssid = query['ssid'] ?? '';
    final wifi = query['wifi'] ?? '';
    final password = query['pw'] ?? '';
    // WPA2: SSID up to 32 bytes, password 8–63 characters.
    if (ssid.length > 32 || (wifi.isNotEmpty && (wifi.length < 8 || wifi.length > 63)) || password.length > 128) {
      return null;
    }
    return BoxLink(
      url: target,
      key: key,
      name: name.length > 64 ? name.substring(0, 64) : name,
      ssid: ssid,
      wifi: wifi,
      password: password,
      code: code,
      fp: fp,
    );
  }

  static Uri _base(Uri url) {
    final path = url.path.endsWith('/') ? url.path : '${url.path}/';
    return Uri(scheme: url.scheme, host: url.host, port: url.hasPort ? url.port : null, path: path);
  }

  /// The link for storing or for the QR code (counterpart to [parse]), without the box password
  /// and without a pairing code (both are only good for pairing).
  Uri toUri() => Uri(
    scheme: scheme,
    host: 'box',
    queryParameters: {
      'url': '$url',
      if (key.isNotEmpty) 'key': key,
      if (name.isNotEmpty) 'name': name,
      if (ssid.isNotEmpty) 'ssid': ssid,
      if (wifi.isNotEmpty) 'wifi': wifi,
      if (fp.isNotEmpty) 'fp': fp,
    },
  );

  /// Address without scheme for display, e.g. "knx-box.local" or "10.42.0.1:8765".
  String get address => url.hasPort ? '${url.host}:${url.port}' : url.host;

  String get label => name.isNotEmpty ? name : address;

  /// Whether the address is in the local network: private and link-local addresses, loopback,
  /// `.local`. Anything else may be a foreign server on the internet to which the app would hand
  /// project and keyring when connecting.
  bool get isLocal => isLocalHost(url.host);

  static bool isLocalHost(String rawHost) {
    final host = rawHost.toLowerCase();
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local')) return true;
    if (host.contains(':')) {
      final List<int> v6;
      try {
        v6 = Uri.parseIPv6Address(host.startsWith('[') ? host.substring(1, host.length - 1) : host);
      } on FormatException {
        return false;
      }
      final mapped = v6.take(10).every((b) => b == 0) && v6[10] == 0xff && v6[11] == 0xff;
      if (mapped) return _isLocalV4(v6.sublist(12));
      final loopback = v6.take(15).every((b) => b == 0) && v6[15] == 1;
      return loopback || (v6[0] == 0xfe && v6[1] & 0xc0 == 0x80) || v6[0] & 0xfe == 0xfc;
    }
    final parts = host.split('.');
    if (parts.length != 4 || !parts.every(RegExp(r'^[0-9]{1,3}$').hasMatch)) return false;
    final v4 = [for (final p in parts) int.parse(p)];
    return v4.every((b) => b < 256) && _isLocalV4(v4);
  }

  static bool _isLocalV4(List<int> ip) => switch (ip) {
    [10, _, _, _] || [127, _, _, _] || [192, 168, _, _] || [169, 254, _, _] => true,
    [172, final b, _, _] => b >= 16 && b < 32,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is BoxLink &&
      other.url == url &&
      other.key == key &&
      other.name == name &&
      other.ssid == ssid &&
      other.wifi == wifi &&
      other.password == password &&
      other.code == code &&
      other.fp == fp;

  @override
  int get hashCode => Object.hash(url, key, name, ssid, wifi, password, code, fp);

  @override
  String toString() => 'BoxLink($address)';
}
