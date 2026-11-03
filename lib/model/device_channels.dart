import '../catalog_store.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'object_groups.dart';

/// A communication object of a device with its group address.
class DeviceObject {
  const DeviceObject({required this.address, this.number, this.text, this.sends = false});

  final int address;
  final int? number;
  final String? text;

  /// Whether the object sends (status/feedback) instead of only receiving.
  final bool sends;
}

/// What a channel is – determines how it is drawn.
enum ChannelKind { switching, dimming, blind, heating, sensor, other }

/// Channel of a device (output A, channel 3 …) with its objects.
class DeviceChannel {
  DeviceChannel(this.label, this.objects, {this.title});

  /// Short name, e.g. "A", "3" – empty for general objects.
  final String label;

  /// Label if the channel is derived from the group address names
  /// (e.g. "Küche Deckenlicht", kitchen ceiling light).
  final String? title;
  final List<DeviceObject> objects;

  /// Type from the datapoint types and object texts.
  ChannelKind get kind {
    final store = CatalogStore.instance;
    final dpts = [for (final o in objects) store.dptOf(o.address)];
    // Object texts and group address names (projects without object texts).
    final text = objects.map((o) => '${o.text ?? ''} ${store.info(o.address)?.name ?? ''}').join(' ').toLowerCase();
    if (dpts.any((d) => d?.main == 1 && (d?.sub == 8 || d?.sub == 7)) ||
        RegExp(r'jalousie|rollladen|rolladen|blind|shutter|lamelle|slat|auf/ab|auf/zu|up/down|position')
            .hasMatch(text)) {
      return ChannelKind.blind;
    }
    if (RegExp(r'heiz|ventil|stellwert|valve|heat').hasMatch(text)) {
      return ChannelKind.heating;
    }
    if (dpts.any((d) => d?.main == 5 && d?.sub == 1) || RegExp(r'dimm').hasMatch(text)) return ChannelKind.dimming;
    if (dpts.any((d) => d?.main == 1)) return ChannelKind.switching;
    if (dpts.any((d) => d?.main == 9 || d?.main == 14)) return ChannelKind.sensor;
    return ChannelKind.other;
  }
}

/// Channel number from an object text: "Kanal A – Schalten", "Ausgang 3: Status",
/// "Channel 2 Switch", "A1 Schalten", "K4 Dimmen".
String? channelLabel(String? text) {
  if (text == null || text.isEmpty) return null;
  final named = RegExp(
    r'\b(?:kanal|channel|ausgang|output|eingang|input|kreis|circuit|zone|taste|button|wippe|rocker|ch|k)\s*[.:]?\s*([a-z]{1,2}\d{0,2}|\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(text);
  if (named != null) return named[1]!.toUpperCase();
  final leading = RegExp(r'^\s*([A-Z]\d{0,2}|\d{1,3})\s*[:\-–.]\s', caseSensitive: false).firstMatch(text);
  return leading?[1]?.toUpperCase();
}

/// Channels of a device from the associations in the ETS project, in natural
/// order (A, B … or 1, 2 … 10); general objects last.
///
/// If the object texts name no channel but the device's object layout is known
/// ([keys] per [stride] objects starting at [offset], from a manufacturer
/// artwork), the channels follow from the object numbers.
List<DeviceChannel> channelsOf(int device, GroupCatalog catalog, {List<String>? keys, int? stride, int offset = 0}) {
  final byChannel = <String, List<DeviceObject>>{};
  for (final g in catalog.groups.values) {
    for (final l in g.links) {
      if (l.device != device) continue;
      final o = DeviceObject(address: g.address, number: l.object, text: l.text, sends: l.sends);
      (byChannel[channelLabel(l.text) ?? ''] ??= []).add(o);
    }
  }
  for (final list in byChannel.values) {
    list.sort((a, b) => (a.number ?? 1 << 20).compareTo(b.number ?? 1 << 20));
  }
  int order(String label) {
    final n = int.tryParse(label);
    if (n != null) return n;
    final m = RegExp(r'^([A-Z]+)(\d*)$').firstMatch(label);
    if (m == null) return 1 << 20;
    final letters = m[1]!.codeUnits.fold(0, (a, c) => a * 26 + (c - 64));
    return letters * 1000 + (int.tryParse(m[2]!) ?? 0);
  }

  if (keys != null && stride != null && byChannel.length == 1 && byChannel.containsKey('')) {
    final index = ObjectIndex.of(catalog);
    final byKey = <String, List<DeviceObject>>{};
    for (final o in byChannel['']!) {
      final slot = o.number == null ? -1 : (o.number! - offset) ~/ stride;
      (byKey[slot >= 0 && slot < keys.length ? keys[slot] : ''] ??= []).add(o);
    }
    String? titleOf(List<DeviceObject> objects) {
      final o = objects.firstWhere((o) => !o.sends, orElse: () => objects.first);
      final group = index.objectOf(o.address);
      final room = group?.room;
      final title = group?.title;
      if (title == null) return null;
      return room == null || title.startsWith(room) ? title : '$room $title';
    }

    return [
      for (final k in keys)
        if (byKey[k] case final objects?) DeviceChannel(k, objects, title: titleOf(objects)),
      if (byKey[''] case final general?) DeviceChannel('', general),
    ];
  }

  // Projects without channel info in the object texts: derive channels from the
  // objects of the overview (switch + status of a light = one channel).
  if (byChannel.length == 1 && byChannel.containsKey('') && byChannel['']!.length > 1) {
    final index = ObjectIndex.of(catalog);
    final byObject = <String, List<DeviceObject>>{};
    final titles = <String, String>{};
    final general = <DeviceObject>[];
    for (final o in byChannel['']!) {
      // Inputs sent by another device (wind, rain …) are not channels.
      final sentByOther = catalog[o.address]?.links.any((l) => l.sends && l.device != device) ?? false;
      if (!o.sends && sentByOther && (catalog[o.address]?.links.where((l) => l.device == device).length ?? 0) == 1) {
        final group = index.objectOf(o.address);
        if (group == null || group.members.every((m) => m.address == o.address)) {
          general.add(o);
          continue;
        }
      }
      final group = index.objectOf(o.address);
      final key = group?.key ?? 'ga:${o.address}';
      (byObject[key] ??= []).add(o);
      final title = group?.title ?? catalog[o.address]?.name ?? formatGroup(o.address);
      final room = group?.room;
      titles[key] = room == null || title.startsWith(room) ? title : '$room $title';
    }
    final keys = byObject.keys.toList()
      ..sort(
        (a, b) => byObject[a]!
            .map((o) => o.address)
            .reduce((x, y) => x < y ? x : y)
            .compareTo(byObject[b]!.map((o) => o.address).reduce((x, y) => x < y ? x : y)),
      );
    return [
      for (final (i, k) in keys.indexed) DeviceChannel('${i + 1}', byObject[k]!, title: titles[k]),
      if (general.isNotEmpty) DeviceChannel('', general),
    ];
  }

  final labels = byChannel.keys.toList()
    ..sort((a, b) {
      if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
      return order(a).compareTo(order(b));
    });
  return [for (final l in labels) DeviceChannel(l, byChannel[l]!)];
}

/// Main value of a channel for display: preferably a status feedback (sending
/// object), otherwise the most recently written object.
Telegram? primaryValue(DeviceChannel channel, Map<int, Telegram> latest) {
  final store = CatalogStore.instance;
  Telegram? pick(bool Function(DeviceObject) where) {
    Telegram? best;
    for (final o in channel.objects.where(where)) {
      final t = latest[o.address];
      if (t != null && (best == null || t.time.isAfter(best.time))) best = t;
    }
    return best;
  }

  bool interesting(DeviceObject o) {
    final d = store.dptOf(o.address);
    return d == null || d.main == 1 || d.main == 5 || d.main == 9 || d.main == 14;
  }

  return pick((o) => o.sends && interesting(o)) ?? pick(interesting) ?? pick((_) => true);
}
