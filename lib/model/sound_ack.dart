import 'package:flutter/foundation.dart';

import '../catalog_store.dart';
import '../knx/telegram.dart';
import '../l10n/locale_controller.dart';
import '../platform/native_bridge.dart';
import 'commissioning.dart';

/// Whose telegrams the sound acknowledgement makes audible.
sealed class AckTarget {
  const AckTarget();

  bool matches(Telegram t);

  /// Short form for the bar, e.g. "Linie 1.1" (line 1.1).
  String describe();
}

/// All addresses of the commissioning checklist (ring-through test).
final class AckChecklist extends AckTarget {
  const AckChecklist();

  @override
  bool matches(Telegram t) => Commissioning.instance.items.containsKey(t.destination);

  @override
  String describe() => s.ackTargetChecklist;
}

/// All senders of a line, e.g. 1.1.
final class AckLine extends AckTarget {
  const AckLine(this.area, this.line);
  final int area;
  final int line;

  @override
  bool matches(Telegram t) => t.source >> 12 == area && (t.source >> 8) & 0xF == line;

  @override
  String describe() => s.ackLine('$area.$line');

  @override
  bool operator ==(Object other) => other is AckLine && other.area == area && other.line == line;

  @override
  int get hashCode => Object.hash(area, line);
}

/// A device (individual address) as sender.
final class AckDevice extends AckTarget {
  const AckDevice(this.address);
  final int address;

  @override
  bool matches(Telegram t) => t.source == address;

  @override
  bool operator ==(Object other) => other is AckDevice && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String describe() => [formatIndividual(address), ?CatalogStore.instance.device(address)?.name].join(' ');
}

/// A group address as destination.
final class AckGroup extends AckTarget {
  const AckGroup(this.address);
  final int address;

  @override
  bool matches(Telegram t) => t.destination == address;

  @override
  bool operator ==(Object other) => other is AckGroup && other.address == address;

  @override
  int get hashCode => address.hashCode;

  @override
  String describe() => [formatGroup(address), ?CatalogStore.instance.info(address)?.name].join(' ');
}

/// Several group addresses as destinations under one label, e.g. the devices of a room.
final class AckGroups extends AckTarget {
  const AckGroups(this.addresses, this.label);
  final Set<int> addresses;
  final String label;

  @override
  bool matches(Telegram t) => addresses.contains(t.destination);

  @override
  String describe() => label;
}

/// Which tone: write, response, or a sender that according to the project does
/// not send there (or is not in the project at all).
enum AckSound { write, response, foreign }

/// Sound acknowledgement: a short tone per telegram of a target, so one person
/// can commission alone – press a push button, listen, move on. On Android the
/// app keeps listening with a foreground service even when the screen is locked;
/// iPhone and iPad only in the foreground with the screen awake.
class SoundAck extends ChangeNotifier {
  SoundAck._();

  static final instance = SoundAck._();

  /// At most this many tones per second; the acknowledgment swallows more, so a
  /// chatty line does not become a continuous tone.
  static const minGap = Duration(milliseconds: 120);

  AckTarget? _target;
  AckTarget? get target => _target;
  bool get active => _target != null;

  /// Telegrams since start.
  int count = 0;

  /// The acknowledgment remembers this many most recently heard telegrams.
  static const recentKeep = 8;

  /// Most recently heard telegrams since start, newest first.
  final recent = <Telegram>[];

  DateTime? _lastSound;

  /// Playback; replaceable in tests.
  @visibleForTesting
  void Function(AckSound sound) play = NativeBridge.ackSound;

  void start(AckTarget target) {
    _target = target;
    count = 0;
    recent.clear();
    _lastSound = null;
    notifyListeners();
  }

  void stop() {
    if (_target == null) return;
    _target = null;
    notifyListeners();
  }

  /// Telegram from the bus (from the monitor). Reads and telegrams sent by us stay
  /// silent: it is about what a device sends on its own.
  void check(Telegram t) {
    final target = _target;
    if (target == null || t.outgoing || t.type == TelegramType.read || !target.matches(t)) return;
    count++;
    recent.insert(0, t);
    if (recent.length > recentKeep) recent.removeLast();
    notifyListeners();
    final now = t.time;
    if (_lastSound case final last? when now.difference(last).abs() < minGap) return;
    _lastSound = now;
    play(soundFor(t));
  }

  /// Tone for [t]: foreign sender before response before write.
  static AckSound soundFor(Telegram t) {
    final catalog = CatalogStore.instance.catalog;
    final unknownDevice = catalog.devices.isNotEmpty && catalog.devices[t.source] == null;
    if (unknownDevice || isForeignSender(t.destination, t.source)) return AckSound.foreign;
    return t.type == TelegramType.response ? AckSound.response : AckSound.write;
  }

  @visibleForTesting
  void debugReset() {
    _target = null;
    count = 0;
    recent.clear();
    _lastSound = null;
    play = NativeBridge.ackSound;
  }
}
