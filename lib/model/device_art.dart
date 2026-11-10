import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import 'device_channels.dart';
import 'device_shapes.dart';

/// Manufacturer artwork of a device: compiled front view (vector_graphics) and
/// a manifest with the areas on which the app overlays its values. All
/// dimensions in mm, origin at the top left.
class DeviceArt {
  const DeviceArt({
    required this.id,
    required this.manufacturer,
    this.manufacturerName,
    required this.orderNumbers,
    this.asset,
    required this.size,
    required this.channels,
    this.indicators = const [],
    this.product,
    this.bus,
    this.busPlusRight = false,
    this.lineBuses = const [],
    this.address,
    this.objectStride,
    this.objectOffset = 0,
    this.attribution,
    this.channelKinds = const [],
  });

  final String id;
  final String manufacturer;

  /// Manufacturer name as in the ETS project (prototype mapping, until the
  /// catalog stores the manufacturer ID).
  final String? manufacturerName;
  final List<String> orderNumbers;
  final String? product;

  /// Asset of the compiled artwork; `null` = generic actuator that the app draws
  /// itself ([DeviceArt.generic]).
  final String? asset;

  bool get generic => asset == null;

  /// Device dimensions in mm.
  final Size size;
  final List<ArtChannel> channels;

  /// Status LEDs without a channel (coupler, power supply).
  final List<ArtIndicator> indicators;

  /// Bus terminal in mm; the app attaches the bus cable there.
  final Rect? bus;

  /// Red wire (+) on the right of the bus terminal instead of the left.
  final bool busPlusRight;

  /// Bus terminals of a coupler: main line (`false`) and subline (`true`).
  /// If the list is not empty, [bus] does not apply.
  final List<(Rect, bool)> lineBuses;

  /// Field for the individual address; the app writes it in.
  final Rect? address;

  /// Object layout: [objectStride] objects per channel starting at [objectOffset],
  /// for projects without a channel in the object texts.
  final int? objectStride;
  final int objectOffset;

  /// Source attribution below the artwork.
  final String? attribution;

  /// Kind per channel (like [channels]); only for the generic actuator, which then
  /// draws relays, buttons or arrows on the front.
  final List<ChannelKind> channelKinds;

  factory DeviceArt.fromJson(Map<String, Object?> j) {
    final image = j['image']! as Map<String, Object?>;
    return DeviceArt(
      id: j['id']! as String,
      manufacturer: j['manufacturer']! as String,
      manufacturerName: j['manufacturerName'] as String?,
      orderNumbers: [for (final o in j['orderNumbers']! as List) o as String],
      product: j['product'] as String?,
      asset: '${DeviceArtCatalog.folder}/${image['file']}',
      size: Size((image['width']! as num).toDouble(), (image['height']! as num).toDouble()),
      channels: [for (final c in (j['channels'] as List?) ?? const []) ArtChannel.fromJson(c as Map<String, Object?>)],
      indicators: [
        for (final i in (j['indicators'] as List?) ?? const []) ArtIndicator.fromJson(i as Map<String, Object?>),
      ],
      bus: _rect(j['bus']),
      busPlusRight: ((j['bus'] ?? (j['lineBuses'] as List?)?.firstOrNull) as Map?)?['plus'] == 'right',
      lineBuses: [
        for (final b in (j['lineBuses'] as List?) ?? const [])
          if (_rect(b) case final r?) (r, (b as Map)['line'] == 'sub'),
      ],
      address: _rect(j['address']),
      objectStride: (j['objects'] as Map?)?['stride'] as int?,
      objectOffset: ((j['objects'] as Map?)?['offset'] as int?) ?? 0,
      attribution: (j['license'] as Map<String, Object?>?)?['attribution'] as String?,
    );
  }

  /// Channel of the artwork for the short name from the object texts ("A", "1").
  ArtChannel? channel(String label) {
    final l = label.toLowerCase();
    for (final c in channels) {
      if (c.key.toLowerCase() == l || c.aliases.any((a) => a.toLowerCase() == l)) return c;
    }
    return null;
  }
}

/// Channel on the artwork: tap area, LED and label field in mm.
class ArtChannel {
  const ArtChannel({
    required this.key,
    required this.area,
    this.aliases = const [],
    this.led,
    this.label,
    this.contact,
  });

  /// Label as printed on the device.
  final String key;
  final List<String> aliases;
  final Rect area;

  /// Center and radius of the LED.
  final (Offset, double)? led;
  final Rect? label;

  /// Switch rocker of the relay symbol: pivot, open end, closed end.
  final (Offset, Offset, Offset)? contact;

  factory ArtChannel.fromJson(Map<String, Object?> j) {
    final led = j['led'];
    return ArtChannel(
      key: j['key']! as String,
      aliases: [for (final a in (j['aliases'] as List?) ?? const []) a as String],
      area: _rect(j['area'])!,
      led: led is Map
          ? (Offset((led['x']! as num).toDouble(), (led['y']! as num).toDouble()), (led['r'] as num? ?? 1).toDouble())
          : null,
      label: _rect(j['label']),
      contact: switch (j['contact']) {
        final Map<Object?, Object?> c => (
          Offset((c['x']! as num).toDouble(), (c['y']! as num).toDouble()),
          Offset((c['openX']! as num).toDouble(), (c['openY']! as num).toDouble()),
          Offset((c['closedX']! as num).toDouble(), (c['closedY']! as num).toDouble()),
        ),
        _ => null,
      },
    );
  }
}

/// When a status LED lights up.
enum IndicatorRole {
  /// Steady light while the device is running (RUN, BusState).
  on,

  /// Flashes on every telegram (Traffic).
  traffic,

  /// Flashes on telegrams from the device's line (Traffic Sub on a coupler).
  trafficLine,

  /// Flashes on telegrams from other lines (Traffic Main on a coupler).
  trafficOther,
}

/// Status LED on the artwork: center and radius in mm, role, color.
class ArtIndicator {
  const ArtIndicator({required this.key, required this.center, required this.radius, required this.role, this.color});

  final String key;
  final Offset center;
  final double radius;
  final IndicatorRole role;

  /// LED color as 0xAARRGGBB; green if not specified.
  final int? color;

  factory ArtIndicator.fromJson(Map<String, Object?> j) {
    final led = j['led']! as Map;
    return ArtIndicator(
      key: j['key']! as String,
      center: Offset((led['x']! as num).toDouble(), (led['y']! as num).toDouble()),
      radius: (led['r'] as num? ?? 1).toDouble(),
      role: IndicatorRole.values.byName(j['role']! as String),
      color: switch (j['color']) {
        final String hex => int.parse('FF${hex.replaceFirst('#', '')}', radix: 16),
        _ => null,
      },
    );
  }
}

/// Rectangle from `{x, y, w, h}` in mm.
Rect? _rect(Object? r) => r is Map
    ? Rect.fromLTWH(
        (r['x']! as num).toDouble(),
        (r['y']! as num).toDouble(),
        (r['w']! as num).toDouble(),
        (r['h']! as num).toDouble(),
      )
    : null;

/// All bundled artworks from `assets/device_art/index.json`, loaded once. If the
/// file is missing or broken, there are no artworks – the app then shows the
/// drawn view.
class DeviceArtCatalog {
  DeviceArtCatalog._();

  static final instance = DeviceArtCatalog._();

  static const folder = 'assets/device_art';

  List<DeviceArt>? _all;
  Future<void>? _loading;

  /// Loads the index on the first call; ready immediately afterwards.
  Future<void> load([AssetBundle? bundle]) => _loading ??= () async {
    try {
      final json = jsonDecode(await (bundle ?? rootBundle).loadString('$folder/index.json')) as List;
      _all = [for (final j in json) DeviceArt.fromJson(j as Map<String, Object?>)];
    } on Object catch (e, stack) {
      debugPrint('Herstellergrafiken nicht geladen: $e\n$stack');
      _all = const [];
    }
  }();

  /// Artwork for the device once [load] has finished. Matched by manufacturer and
  /// order number; as long as the catalog does not store both, by manufacturer
  /// name and the product text, which starts with the order number
  /// (prototype).
  DeviceArt? of(DeviceInfo? device) {
    final product = device?.product;
    if (product == null) return null;
    for (final a in _all ?? const <DeviceArt>[]) {
      final maker = device!.manufacturer;
      if (maker != a.manufacturer && maker != a.manufacturerName) continue;
      // ETS product texts usually start with the order number.
      if (a.product == product || a.orderNumbers.any((o) => product == o || product.startsWith('$o '))) return a;
    }
    return null;
  }

  @visibleForTesting
  void debugReset() {
    _all = null;
    _loading = null;
  }
}

/// Channels of the device; with manufacturer artwork, also via its object layout.
List<DeviceChannel> deviceChannels(int address) {
  final catalog = CatalogStore.instance.catalog;
  final art = DeviceArtCatalog.instance.of(catalog.devices[address]);
  // Device without channels on the front (power supply): each object on its own,
  // so it gets its own card on the artwork.
  if (art != null && art.channels.isEmpty) {
    return [
      for (final o in objectsOf(address, catalog)) DeviceChannel('', [o], title: catalog[o.address]?.name ?? o.text),
    ];
  }
  if (art?.objectStride case final stride?) {
    return channelsOf(
      address,
      catalog,
      keys: [for (final c in art!.channels) c.key],
      stride: stride,
      offset: art.objectOffset,
    );
  }
  return channelsOf(address, catalog);
}

/// Manufacturer artwork or, for actuators without artwork, a generic actuator
/// with the channels from the project; otherwise `null`.
DeviceArt? artFor(int address) {
  final catalog = CatalogStore.instance.catalog;
  final device = catalog.devices[address];
  if (DeviceArtCatalog.instance.of(device) case final art?) return art;
  // Only DIN rail devices that switch, dim, move or heat – push buttons, sensors,
  // meters and gateways keep their own representation.
  if (device == null || shapeOf(address, catalog) != DeviceShape.din) return null;
  final channels = [
    for (final c in channelsOf(address, catalog))
      if (c.label.isNotEmpty) c,
  ];
  const actuating = {ChannelKind.switching, ChannelKind.dimming, ChannelKind.blind, ChannelKind.heating};
  // An actuator receives commands; channels that only send are inputs.
  if (!channels.any((c) => actuating.contains(c.kind) && c.objects.any((o) => !o.sends))) return null;
  return genericArt([for (final c in channels) c.label], [for (final c in channels) c.kind]);
}

final _generic = <String, DeviceArt>{};

/// Generic actuator in the neutral style "A" (light gray, like the sample
/// devices in the manufacturer PDF): channels in up to two rows of 15.5 mm,
/// each with a number, LED, a control by kind and a label field the app fills
/// with the name. Width in modules by channel count (at least 2 modules),
/// height 90 mm like the manufacturer artworks.
DeviceArt genericArt(List<String> keys, [List<ChannelKind> kinds = const []]) =>
    _generic.putIfAbsent('${keys.join(',')}|${kinds.map((k) => k.name).join(',')}', () {
      const pitch = 15.5;
      final rows = keys.length > 4 ? 2 : 1;
      final cols = (keys.length / rows).ceil();
      final te = ((cols * pitch + 4) / 18).ceil().clamp(2, 24);
      final width = te * 18.0;
      final x0 = (width - cols * pitch) / 2 + 0.75;
      final channels = <ArtChannel>[];
      for (final (i, key) in keys.indexed) {
        final x = x0 + (i % cols) * pitch;
        final y = rows == 1 ? 30.0 : (i < cols ? 25.0 : 45.0);
        final kind = i < kinds.length ? kinds[i] : ChannelKind.switching;
        final py = y + 5.6;
        channels.add(
          ArtChannel(
            key: key,
            area: Rect.fromLTWH(x, y, 14, 17),
            led: (Offset(x + 10.5, y + 2.2), 1.0),
            label: Rect.fromLTWH(x + 1, y + 12, 12, 4.2),
            // Relay symbol only for switching channels; the app paints the rocker.
            contact: kind == ChannelKind.switching
                ? (Offset(x + 3.4, py), Offset(x + 7.2, py - 1.6), Offset(x + 7.6, py))
                : null,
          ),
        );
      }
      return DeviceArt(
        id: 'generic-${keys.length}',
        manufacturer: '',
        orderNumbers: const [],
        size: Size(width, 90),
        channels: channels,
        channelKinds: [for (var i = 0; i < keys.length; i++) i < kinds.length ? kinds[i] : ChannelKind.switching],
        address: Rect.fromLTWH(4, 66.6, math.min(16, width - 26), 4.6),
        bus: Rect.fromLTWH(width - 14.5, 79.4, 10, 6.4),
      );
    });
