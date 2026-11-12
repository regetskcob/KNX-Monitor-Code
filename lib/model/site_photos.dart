import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../knx/demo_tunnel.dart';
import 'installation.dart';

/// Longest edge of a photo: labels in the distribution board stay readable.
const sitePhotoMaxEdge = 2000;

/// JPEG quality of the photos.
const sitePhotoQuality = 80;

/// Largest file accepted as a photo.
const sitePhotoMaxInput = 40 * 1024 * 1024;

/// Limit for all photos of an installation (base64 in storage).
const sitePhotoQuotaBytes = 300 * 1024 * 1024;

/// No more space for photos of this installation.
class SitePhotoQuotaExceeded implements Exception {
  const SitePhotoQuotaExceeded();
}

/// Normalizes a photo: upright, at most [sitePhotoMaxEdge], JPEG. Metadata
/// (location, device, time) is explicitly dropped; the photo should not reveal
/// where it was taken. Throws [FormatException] if it is not a readable
/// image.
Uint8List compressSitePhoto(Uint8List bytes) {
  if (bytes.length > sitePhotoMaxInput) throw const FormatException('photo too large');
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } on Object catch (e) {
    throw FormatException('$e');
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) throw const FormatException('image');
  final upright = img.bakeOrientation(decoded);
  final long = upright.width > upright.height ? upright.width : upright.height;
  final scaled = long <= sitePhotoMaxEdge
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? sitePhotoMaxEdge : null,
          height: upright.height > upright.width ? sitePhotoMaxEdge : null,
          interpolation: img.Interpolation.average,
        );
  scaled.exif = img.ExifData();
  scaled.iccProfile = null;
  return img.encodeJpg(scaled.convert(format: img.Format.uint8, numChannels: 3), quality: sitePhotoQuality);
}

/// A photo of an installation, e.g. of the distribution board.
@immutable
class SitePhoto {
  const SitePhoto({required this.id, required this.caption, required this.at});

  final String id;
  final String caption;
  final DateTime at;

  SitePhoto withCaption(String text) => SitePhoto(id: id, caption: text.trim(), at: at);

  Map<String, Object?> toJson() => {'id': id, 'caption': caption, 'at': at.toUtc().toIso8601String()};

  factory SitePhoto.fromJson(Map<Object?, Object?> j) => SitePhoto(
    id: j['id']! as String,
    caption: j['caption'] as String? ?? '',
    at: DateTime.parse(j['at']! as String).toLocal(),
  );
}

/// Photo documentation of the active installation: list in `site_photos.json`,
/// images as `site_photos/<id>.jpg.b64` in the installation's folder.
/// Deliberately separate from the comment screenshots: this way they are deleted
/// along with the installation and end up neither in the diagnostic package nor
/// in the handover package. Broken files are left alone; startup never depends on them.
class SitePhotoStore extends ChangeNotifier {
  SitePhotoStore._();

  static final instance = SitePhotoStore._();
  static const path = 'site_photos.json';
  static const dir = 'site_photos';
  static String _file(String id) => '$dir/$id.jpg.b64';

  /// Only IDs in our own format; they end up in a file path.
  static bool validId(String id) => RegExp(r'^[0-9a-z]{1,32}$').hasMatch(id);

  List<SitePhoto> _photos = [];
  String? _loadedFor;
  Future<void>? _loading;

  /// In the demo house in memory only.
  final _demo = <String, Uint8List>{};

  /// Newest first.
  List<SitePhoto> get photos => [..._photos]..sort((a, b) => b.at.compareTo(a.at));

  Future<void> load() {
    final id = InstallationStore.instance.active.id;
    if (_loadedFor == id && _loading != null) return _loading!;
    _loadedFor = id;
    return _loading = _load();
  }

  /// Reads the list again: files changed underneath (a customer file was taken over).
  Future<void> reload() {
    _loadedFor = null;
    return load();
  }

  Future<void> _load() async {
    _photos = [];
    _demo.clear();
    if (DemoTunnel.active) return notifyListeners();
    final storage = InstallationStore.instance.storage;
    try {
      final text = await storage.read(path);
      if (text != null) {
        try {
          for (final j in jsonDecode(text) as List) {
            try {
              final photo = SitePhoto.fromJson(j as Map);
              if (validId(photo.id)) _photos.add(photo);
            } on Object catch (e) {
              debugPrint('Foto übersprungen: $e');
            }
          }
        } on Object catch (e) {
          debugPrint('Fotoliste nicht lesbar: $e');
          await storage.write('$path.corrupt-${DateTime.now().millisecondsSinceEpoch}', text);
        }
      }
    } on Object catch (e) {
      debugPrint('Fotoliste nicht geladen: $e');
    }
    notifyListeners();
  }

  /// Stores [jpeg] (already passed through [compressSitePhoto]). Throws
  /// [SitePhotoQuotaExceeded] when the limit is reached.
  Future<SitePhoto> add(Uint8List jpeg, {String caption = '', DateTime? at}) async {
    await load();
    final now = at ?? DateTime.now();
    final photo = SitePhoto(id: now.microsecondsSinceEpoch.toRadixString(36), caption: caption.trim(), at: now);
    if (DemoTunnel.active) {
      _demo[photo.id] = jpeg;
    } else {
      final storage = InstallationStore.instance.storage;
      final used = (await storage.list(dir)).fold<int>(0, (n, f) => n + f.size);
      if (used + jpeg.length * 4 ~/ 3 > sitePhotoQuotaBytes) throw const SitePhotoQuotaExceeded();
      await storage.write(_file(photo.id), base64Encode(jpeg));
    }
    _photos.add(photo);
    await _changed();
    return photo;
  }

  Future<Uint8List?> read(String id) async {
    if (!validId(id)) return null;
    if (DemoTunnel.active) return _demo[id];
    final text = await InstallationStore.instance.storage.read(_file(id));
    if (text == null) return null;
    try {
      return base64Decode(text);
    } on FormatException catch (e) {
      debugPrint('Foto $id unlesbar: $e');
      return null;
    }
  }

  Future<void> setCaption(String id, String caption) async {
    _photos = [
      for (final p in _photos)
        if (p.id == id) p.withCaption(caption) else p,
    ];
    await _changed();
  }

  Future<void> remove(String id) async {
    _photos.removeWhere((p) => p.id == id);
    _demo.remove(id);
    if (validId(id) && !DemoTunnel.active) await InstallationStore.instance.storage.delete(_file(id));
    await _changed();
  }

  Future<void> _changed() async {
    notifyListeners();
    if (DemoTunnel.active) return;
    await InstallationStore.instance.storage.write(path, jsonEncode([for (final p in _photos) p.toJson()]));
  }

  @visibleForTesting
  void debugReset() {
    _photos = [];
    _demo.clear();
    _loadedFor = null;
    _loading = null;
  }
}
