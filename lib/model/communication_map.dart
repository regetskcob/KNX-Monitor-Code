import '../catalog_store.dart';
import 'telegram_log.dart';

/// Node of the communication map: device (individual address) or group address.
class MapNode {
  const MapNode.device(this.address) : isGroup = false;
  const MapNode.group(this.address) : isGroup = true;

  final int address;
  final bool isGroup;

  @override
  bool operator ==(Object other) => other is MapNode && other.address == address && other.isGroup == isGroup;

  @override
  int get hashCode => Object.hash(address, isGroup);
}

/// Neighbor of a node with the observed count and the origin of the edge.
class MapNeighbor {
  const MapNeighbor(this.node, {this.observed = 0, this.inProject = false});

  final MapNode node;

  /// Telegrams observed over this edge.
  final int observed;

  /// Whether the edge is associated in the ETS project.
  final bool inProject;
}

/// Two devices connected through shared group addresses.
class DeviceLink {
  DeviceLink(this.a, this.b);

  final int a;
  final int b;

  /// Telegrams observed over the shared addresses.
  int observed = 0;
  final groups = <int>{};
}

/// Who talks to whom: observed edges (sender → group address) from the history,
/// supplemented by the associations from the project.
class CommunicationMap {
  CommunicationMap.of(TelegramLog log) {
    for (final t in log.log) {
      if (t.outgoing) continue;
      final key = (t.source, t.destination);
      _observed[key] = (_observed[key] ?? 0) + 1;
      _groupTraffic[t.destination] = (_groupTraffic[t.destination] ?? 0) + 1;
      _deviceTraffic[t.source] = (_deviceTraffic[t.source] ?? 0) + 1;
    }
  }

  final _deviceTraffic = <int, int>{};

  /// Observed telegrams of a node (group address: received, device: sent).
  int traffic(MapNode node) => (node.isGroup ? _groupTraffic : _deviceTraffic)[node.address] ?? 0;

  /// All known nodes of one kind (project + observed), most active first.
  List<MapNode> nodes({required bool groups}) {
    final store = CatalogStore.instance;
    final addresses = groups
        ? {...store.catalog.groups.keys, ..._groupTraffic.keys}
        : {
            for (final d in store.catalog.devices.values)
              if (!d.isTunnel || _deviceTraffic.containsKey(d.address)) d.address,
            ..._deviceTraffic.keys,
          };
    final list = [for (final a in addresses) groups ? MapNode.group(a) : MapNode.device(a)];
    list.sort((a, b) {
      final t = traffic(b).compareTo(traffic(a));
      return t != 0 ? t : a.address.compareTo(b.address);
    });
    return list;
  }

  final _observed = <(int, int), int>{};
  final _groupTraffic = <int, int>{};

  /// Group address with the most traffic – a good starting point.
  MapNode? get busiest {
    if (_groupTraffic.isEmpty) return null;
    return MapNode.group(_groupTraffic.entries.reduce((a, b) => a.value >= b.value ? a : b).key);
  }

  /// Group addresses by traffic, most active first (search suggestions).
  List<MapNode> busiestGroups(int count) {
    final sorted = _groupTraffic.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(count)) MapNode.group(e.key)];
  }

  /// Devices around a node: for a device its partners, for a group address its
  /// senders and receivers.
  Set<int> scopeOf(MapNode node) {
    if (node.isGroup) {
      return {
        for (final n in [..._senders(node.address), ..._receivers(node.address)]) n.node.address,
      };
    }
    return {
      node.address,
      for (final l in deviceLinks())
        if (l.a == node.address || l.b == node.address) ...[l.a, l.b],
    };
  }

  /// Device pairs: sender and receiver of an address. Without known receivers
  /// (no project), the senders of the same address count as connected.
  List<DeviceLink> deviceLinks() {
    final links = <(int, int), DeviceLink>{};
    final groups = {...CatalogStore.instance.catalog.groups.keys, ..._groupTraffic.keys};
    for (final ga in groups) {
      final senders = _senders(ga);
      final receivers = _receivers(ga);
      final others = receivers.isEmpty ? senders : receivers;
      for (final from in senders) {
        for (final to in others) {
          final x = from.node.address;
          final y = to.node.address;
          if (x == y) continue;
          final key = x < y ? (x, y) : (y, x);
          (links[key] ??= DeviceLink(key.$1, key.$2))
            ..observed += from.observed
            ..groups.add(ga);
        }
      }
    }
    return links.values.toList();
  }

  /// Left column: for group addresses the senders, for devices the addresses they listen to.
  List<MapNeighbor> inputs(MapNode node) => node.isGroup ? _senders(node.address) : _listened(node.address);

  /// Right column: for group addresses the receivers, for devices the addresses they send.
  List<MapNeighbor> outputs(MapNode node) => node.isGroup ? _receivers(node.address) : _sent(node.address);

  List<MapNeighbor> _senders(int ga) {
    final links = CatalogStore.instance.info(ga)?.links ?? const [];
    final projectSenders = {
      for (final l in links)
        if (l.sends) l.device,
    };
    final result = <int, MapNeighbor>{};
    for (final MapEntry(key: (src, dst), value: count) in _observed.entries) {
      if (dst == ga) {
        result[src] = MapNeighbor(MapNode.device(src), observed: count, inProject: projectSenders.contains(src));
      }
    }
    for (final pa in projectSenders) {
      result.putIfAbsent(pa, () => MapNeighbor(MapNode.device(pa), inProject: true));
    }
    return _sorted(result.values);
  }

  List<MapNeighbor> _receivers(int ga) {
    final links = CatalogStore.instance.info(ga)?.links ?? const [];
    return _sorted(
      {
        for (final l in links)
          if (!l.sends) l.device: MapNeighbor(MapNode.device(l.device), inProject: true),
      }.values,
    );
  }

  List<MapNeighbor> _sent(int pa) {
    final result = <int, MapNeighbor>{};
    for (final MapEntry(key: (src, dst), value: count) in _observed.entries) {
      if (src == pa) result[dst] = MapNeighbor(MapNode.group(dst), observed: count);
    }
    for (final g in CatalogStore.instance.catalog.groups.values) {
      if (g.links.any((l) => l.device == pa && l.sends)) {
        final seen = result[g.address];
        result[g.address] = MapNeighbor(MapNode.group(g.address), observed: seen?.observed ?? 0, inProject: true);
      }
    }
    return _sorted(result.values);
  }

  List<MapNeighbor> _listened(int pa) => _sorted([
    for (final g in CatalogStore.instance.catalog.groups.values)
      if (g.links.any((l) => l.device == pa && !l.sends))
        MapNeighbor(MapNode.group(g.address), observed: _groupTraffic[g.address] ?? 0, inProject: true),
  ]);

  static List<MapNeighbor> _sorted(Iterable<MapNeighbor> items) => items.toList()
    ..sort((a, b) {
      final byCount = b.observed.compareTo(a.observed);
      return byCount != 0 ? byCount : a.node.address.compareTo(b.node.address);
    });
}
