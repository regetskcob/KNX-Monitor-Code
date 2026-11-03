import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'package:knx/secure.dart';

/// Wrong password or damaged file.
class KeyringException implements Exception {
  const KeyringException(this.wrongPassword);
  final bool wrongPassword;
}

/// Tunnel credentials from the keyring.
class KeyringTunnel {
  const KeyringTunnel({required this.address, this.host, this.userId, this.password, this.secureGroups = const {}});

  /// Tunnel address (individual).
  final int address;

  /// Individual address of the interface the tunnel belongs to.
  final int? host;
  final int? userId;
  final String? password;

  /// Data Secure group addresses of this tunnel → permitted sources.
  final Map<int, List<int>> secureGroups;
}

/// Content of an ETS keyring file (`.knxkeys`): keys for Data Secure and credentials for IP Secure
/// tunnels – decrypted.
class Keyring {
  const Keyring({
    required this.project,
    this.tunnels = const [],
    this.groupKeys = const {},
    this.sequenceNumbers = const {},
    this.deviceAuthentication = const {},
    this.backboneKey,
  });

  final String project;
  final List<KeyringTunnel> tunnels;

  /// Group address → AES key (Data Secure).
  final Map<int, Uint8List> groupKeys;

  /// Individual address → last known sequence number (sources of Data Secure telegrams).
  final Map<int, int> sequenceNumbers;

  /// Individual address of an interface → device authentication code.
  final Map<int, String> deviceAuthentication;
  final Uint8List? backboneKey;

  /// Reads and decrypts a `.knxkeys` file, verifying the signature (wrong password →
  /// [KeyringException]).
  static Keyring parse(String text, String password) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(text.startsWith('﻿') ? text.substring(1) : text);
    } on XmlException {
      throw const KeyringException(false);
    }
    final root = doc.rootElement;
    if (root.localName != 'Keyring') throw const KeyringException(false);
    final hash = deriveKeyringPassword(password);
    final signature = base64.decode(root.getAttribute('Signature') ?? '');
    if (!bytesEqual(_signature(root, hash), signature)) throw const KeyringException(true);

    final iv = sha256(utf8.encode(root.getAttribute('Created') ?? '')).sublist(0, 16);
    Uint8List? key(String? b64) => b64 == null ? null : aesCbcDecrypt(base64.decode(b64), hash, iv);
    String? secret(String? b64) {
      final data = key(b64);
      if (data == null || data.isEmpty) return null;
      final pad = data.last;
      if (pad > data.length - 8) return null;
      return utf8.decode(data.sublist(8, data.length - pad), allowMalformed: true);
    }

    final tunnels = <KeyringTunnel>[];
    for (final i in root.findElements('Interface')) {
      final address = parseIndividualAddress(i.getAttribute('IndividualAddress'));
      if (address == null || i.getAttribute('Type') != 'Tunneling') continue;
      tunnels.add(
        KeyringTunnel(
          address: address,
          host: parseIndividualAddress(i.getAttribute('Host')),
          userId: int.tryParse(i.getAttribute('UserID') ?? ''),
          password: secret(i.getAttribute('Password')),
          secureGroups: {
            for (final g in i.findElements('Group'))
              ?parseGroupAddress(g.getAttribute('Address')): [
                for (final s in (g.getAttribute('Senders') ?? '').split(' ')) ?parseIndividualAddress(s),
              ],
          },
        ),
      );
    }
    final groupKeys = <int, Uint8List>{
      for (final g in root.findElements('GroupAddresses').expand((e) => e.findElements('Group')))
        if ((parseGroupAddress(g.getAttribute('Address')), key(g.getAttribute('Key'))) case (final ga?, final k?))
          ga: k,
    };
    final sequence = <int, int>{};
    final deviceAuth = <int, String>{};
    for (final d in root.findElements('Devices').expand((e) => e.findElements('Device'))) {
      final address = parseIndividualAddress(d.getAttribute('IndividualAddress'));
      if (address == null) continue;
      sequence[address] = int.tryParse(d.getAttribute('SequenceNumber') ?? '') ?? 0;
      final auth = secret(d.getAttribute('Authentication'));
      if (auth != null) deviceAuth[address] = auth;
    }
    // Source according to the tunnel mapping, even without its own Device element.
    for (final t in tunnels) {
      for (final senders in t.secureGroups.values) {
        for (final s in senders) {
          sequence.putIfAbsent(s, () => 0);
        }
      }
    }
    return Keyring(
      project: root.getAttribute('Project') ?? '',
      tunnels: tunnels,
      groupKeys: groupKeys,
      sequenceNumbers: sequence,
      deviceAuthentication: deviceAuth,
      backboneKey: key(root.findElements('Backbone').firstOrNull?.getAttribute('Key')),
    );
  }

  /// Signature as in the ETS: element tree as a byte sequence (names, sorted attributes without
  /// `xmlns`/`Signature`) plus Base64 of the password hash.
  static Uint8List _signature(XmlElement root, Uint8List hash) {
    final out = BytesBuilder();
    void str(String v) {
      final b = utf8.encode(v);
      out
        ..addByte(b.length)
        ..add(b);
    }

    void element(XmlElement e) {
      out.addByte(1);
      str(e.name.qualified);
      final attrs = [
        for (final a in e.attributes)
          if (a.name.qualified != 'xmlns' && a.name.qualified != 'Signature') a,
      ]..sort((a, b) => a.name.qualified.compareTo(b.name.qualified));
      for (final a in attrs) {
        str(a.name.qualified);
        str(a.value);
      }
      for (final child in e.childElements) {
        element(child);
      }
      out.addByte(2);
    }

    element(root);
    str(base64.encode(hash));
    return sha256(out.takeBytes()).sublist(0, 16);
  }

  /// Credentials for a tunnel: matching the requested tunnel address, otherwise the first one with
  /// a user ID.
  KeyringTunnel? tunnelFor({int? address}) =>
      tunnels.where((t) => t.userId != null && (address == null || t.address == address)).firstOrNull;

  Map<String, Object?> toJson() => {
    'project': project,
    'groupKeys': {for (final MapEntry(:key, :value) in groupKeys.entries) '$key': base64.encode(value)},
    'sequence': {for (final MapEntry(:key, :value) in sequenceNumbers.entries) '$key': value},
  };

  /// Only the Data Secure parts (for the add-on server and restarts).
  factory Keyring.fromJson(Map<String, Object?> j) => Keyring(
    project: j['project'] as String? ?? '',
    groupKeys: {
      for (final MapEntry(:key, :value) in ((j['groupKeys'] as Map?) ?? const {}).entries)
        int.parse('$key'): base64.decode('$value'),
    },
    sequenceNumbers: {
      for (final MapEntry(:key, :value) in ((j['sequence'] as Map?) ?? const {}).entries)
        int.parse('$key'): value as int,
    },
  );
}

int? parseIndividualAddress(String? s) {
  final p = (s ?? '').trim().split('.').map(int.tryParse).toList();
  return switch (p) {
    [final a?, final l?, final d?] when a <= 15 && l <= 15 && d <= 255 => (a << 12) | (l << 8) | d,
    _ => null,
  };
}

/// Group address in the keyring: number ("2049") or "1/0/1".
int? parseGroupAddress(String? s) {
  final text = (s ?? '').trim();
  final raw = int.tryParse(text);
  if (raw != null) return raw >= 0 && raw <= 0xFFFF ? raw : null;
  final p = text.split('/').map(int.tryParse).toList();
  return switch (p) {
    [final m?, final mi?, final sub?] when m <= 31 && mi <= 7 && sub <= 255 => (m << 11) | (mi << 8) | sub,
    [final m?, final sub?] when m <= 31 && sub <= 2047 => (m << 11) | sub,
    _ => null,
  };
}
