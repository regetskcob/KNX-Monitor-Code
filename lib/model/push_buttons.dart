import '../catalog_store.dart';
import '../knx/dpt_codec.dart';
import '../knx/group_catalog.dart';
import '../knx/telegram.dart';
import 'device_channels.dart';

/// Form factor of a push button – determines the drawing.
enum PanelStyle {
  /// 55 × 55 mm frame (switch range), buttons as rocker surfaces.
  frame55,

  /// Glass push button (MDT Glastaster II, 92 × 92 mm): sensor surfaces left and
  /// right, display in the middle, pages.
  glass,
}

/// Assignment of a button or button pair ("T1: Licht", "T5/6: Rollladen").
class ButtonFunction {
  ButtonFunction({required this.first, this.second, required this.channel, required this.status});

  /// Number of the first button (1 …); for pairs, the one for on/up/brighter.
  final int first;

  /// Second button of a pair (off/down/darker), otherwise `null`.
  final int? second;

  /// Objects of the function – for the object list on tap.
  final DeviceChannel channel;

  /// Group addresses whose value keeps the status LED lit (status feedback the
  /// device receives).
  final List<int> status;

  String get label => second == null ? 'T$first' : 'T$first/$second';

  List<int> get keys => [first, ?second];
}

/// Push button with its functions.
class PushButton {
  PushButton({
    required this.address,
    required this.style,
    required this.keysPerPage,
    required this.functions,
    this.temperature,
  });

  final int address;
  final PanelStyle style;

  /// Sensor surfaces or buttons visible at the same time.
  final int keysPerPage;
  final List<ButtonFunction> functions;

  /// Room temperature sent by the push button (built-in sensor).
  final int? temperature;

  int get pages {
    final last = functions.expand((f) => f.keys).fold(1, (a, k) => k > a ? k : a);
    return ((last - 1) ~/ keysPerPage) + 1;
  }

  /// Page (0 …) and slot (0 … [keysPerPage]-1) of a button.
  (int, int) slotOf(int key) => ((key - 1) ~/ keysPerPage, (key - 1) % keysPerPage);

  ButtonFunction? functionOf(int key) => functions.where((f) => f.keys.contains(key)).firstOrNull;
}

final _buttonWords = RegExp(r'taster|tastsensor|push.?button|tastenmodul|wippe|rocker', caseSensitive: false);
final _notButton = RegExp(
  r'interface|schnittstelle|binär|binary|eingang|input|rauch|smoke|aktor|actuator',
  caseSensitive: false,
);
final _glassWords = RegExp(r'glas|glass|\bGT\s?\d|BE-GT', caseSensitive: false);
final _gangs = RegExp(r'(\d{1,2})\s*-?\s*(?:fach|fold|gang|kanal)', caseSensitive: false);
final _feedbackWords = RegExp(r'rückmeld|ruckmeld|status|feedback|zustand|geöffnet|geschlossen', caseSensitive: false);

/// Buttons from an object text: "T1: …", "T5/6: …", "Taste 3 …",
/// "Tasten 5/6", "Wippe 2" (= buttons 3/4). `null` if no button is named.
(int, int?)? keysOf(String? text) {
  if (text == null) return null;
  final m = RegExp(
    r'^\s*(?:(T)|tasten?|keys?|buttons?|(wippe|rocker))\s*(\d{1,2})(?:\s*[/+&]\s*(\d{1,2}))?\s*(?:[:\-–.]|\s|$)',
    caseSensitive: false,
  ).firstMatch(text);
  if (m == null) return null;
  final a = int.parse(m[3]!);
  if (a == 0) return null;
  if (m[2] != null) return (a * 2 - 1, a * 2);
  final b = m[4] == null ? null : int.parse(m[4]!);
  return (a, b);
}

/// Push button from the project – `null` if the device is not one or its
/// buttons are not recognizable (then the device shows the actuator drawing).
PushButton? pushButtonOf(int device, GroupCatalog catalog) {
  final info = catalog.devices[device];
  if (info == null) return null;
  final name = '${info.product ?? ''} ${info.name}';
  if (!_buttonWords.hasMatch(name) || _notButton.hasMatch(name)) return null;
  final style = _glassWords.hasMatch(name) ? PanelStyle.glass : PanelStyle.frame55;

  final byKeys = <(int, int?), List<DeviceObject>>{};
  final titles = <(int, int?), String>{};
  int? temperature;
  for (final g in catalog.groups.values) {
    for (final l in g.links) {
      if (l.device != device) continue;
      final keys = keysOf(l.text);
      if (keys == null) {
        if (l.sends && g.dpt?.main == 9 && g.dpt?.sub == 1) temperature ??= g.address;
        continue;
      }
      (byKeys[keys] ??= []).add(DeviceObject(address: g.address, number: l.object, text: l.text, sends: l.sends));
      final title = l.text!.replaceFirst(RegExp(r'^[^:]*:\s*'), '').trim();
      if (title.isNotEmpty && title != l.text) titles[keys] ??= title;
    }
  }
  if (byKeys.isEmpty) return null;

  final functions = <ButtonFunction>[];
  for (final MapEntry(key: keys, value: objects) in byKeys.entries) {
    objects.sort((a, b) => (a.number ?? 1 << 20).compareTo(b.number ?? 1 << 20));
    // The same object can be associated via several addresses – once is enough.
    final seen = <int>{};
    final unique = [
      for (final o in objects)
        if (seen.add(o.address)) o,
    ];
    final label = keys.$2 == null ? 'T${keys.$1}' : 'T${keys.$1}/${keys.$2}';
    final channel = DeviceChannel(label, unique, title: titles[keys]);
    functions.add(
      ButtonFunction(first: keys.$1, second: keys.$2, channel: channel, status: _statusAddresses(channel, catalog)),
    );
  }
  functions.sort((a, b) => a.first.compareTo(b.first));

  final last = functions.expand((f) => f.keys).reduce((a, b) => a > b ? a : b);
  final int perPage;
  if (style == PanelStyle.glass) {
    perPage = 6;
  } else {
    final gangs = int.tryParse(_gangs.firstMatch(name)?[1] ?? '') ?? 0;
    final n = (gangs > last ? gangs : last).clamp(2, 8);
    perPage = n.isOdd ? n + 1 : n;
  }
  return PushButton(
    address: device,
    style: style,
    keysPerPage: perPage,
    functions: functions,
    temperature: temperature,
  );
}

/// Addresses that report the state behind a button: status feedback (received
/// by the push button or named as such) with DPT 1 – for dimming buttons also
/// the brightness value. Move, step and pulse objects do not count.
List<int> _statusAddresses(DeviceChannel channel, GroupCatalog catalog) {
  final store = CatalogStore.instance;
  // Shutters have no on/off status feedback (position, weather …).
  if (channel.kind == ChannelKind.blind) return const [];
  final dims = channel.kind == ChannelKind.dimming;
  return [
    for (final o in channel.objects)
      if (store.dptOf(o.address) case final d?)
        if ((d.main == 1 && !const {7, 8, 9, 10, 17}.contains(d.sub)) || (dims && d.main == 5 && d.sub == 1))
          if (!o.sends || _feedbackWords.hasMatch('${o.text ?? ''} ${catalog[o.address]?.name ?? ''}')) o.address,
  ];
}

/// Which button a telegram from the push button pressed: the number, or `0`
/// for "the function as a whole" (single button, toggle), `null` if it is not a
/// button press (another sender, read, dimming stop).
/// [previous] is the previous value of the address – for setpoint ±.
int? pressedKey(ButtonFunction f, int device, Telegram t, {Telegram? previous}) {
  if (t.source != device || t.type != TelegramType.write || t.data.isEmpty) return null;
  if (!f.channel.objects.any((o) => o.address == t.destination)) return null;
  final dpt = CatalogStore.instance.dptOf(t.destination);
  // A dimming or blind stop comes on release – not a new press.
  if (dpt?.main == 3 && t.data.last & 0x07 == 0) return null;
  final second = f.second;
  if (second == null) return 0;
  final bit = t.data.last & 1 == 1;
  switch ((dpt?.main, dpt?.sub)) {
    case (1, 17):
      return 0;
    // Up/down, step/stop: 0 = up (first button) – even if the project only says
    // DPT 1.x.
    case (1, 7 || 8 || 10):
    case (1, _) when f.channel.kind == ChannelKind.blind:
      return bit ? second : f.first;
    case (1, _) || (null, _) when t.isSmall:
      return bit ? f.first : second;
    case (3, final sub):
      final up = t.data.last & 0x08 != 0;
      // 3.008 blinds: set = down; 3.007 dimming: set = brighter.
      return (sub == 8 ? !up : up) ? f.first : second;
  }
  final now = numericValue(dpt, t);
  final before = previous == null ? null : numericValue(dpt, previous);
  if (now == null || before == null || now == before) return 0;
  return now > before ? f.first : second;
}

/// Whether the status feedback of a function reports "on"; `null` without
/// status feedback or as long as none is known.
bool? statusOf(ButtonFunction f, Map<int, Telegram> latest) {
  Telegram? best;
  for (final a in f.status) {
    final t = latest[a];
    if (t == null || t.type == TelegramType.read || t.data.isEmpty) continue;
    if (best == null || t.time.isAfter(best.time)) best = t;
  }
  if (best == null) return null;
  final v = numericValue(CatalogStore.instance.dptOf(best.destination), best);
  return v != null && v > 0;
}

/// How long a pressed button lights up.
const pressGlow = Duration(milliseconds: 1500);

/// Then briefly off before the status LED lights up permanently.
const pressGap = Duration(milliseconds: 300);

/// Brightness of a button's LED (0 … 1): after a press, on for [pressGlow]; if
/// the status feedback stays on afterwards, off for [pressGap] and then
/// permanently on until the feedback reports off. Without a press the LED
/// follows the status feedback. [fade] makes fading in and out smooth.
double ledLevel({Duration? sincePress, required bool status, bool fade = true}) {
  const fadeIn = Duration(milliseconds: 90);
  if (sincePress != null && sincePress >= Duration.zero) {
    if (sincePress < pressGlow) {
      return fade && sincePress < fadeIn ? sincePress.inMicroseconds / fadeIn.inMicroseconds : 1;
    }
    if (sincePress < pressGlow + pressGap) {
      if (status || !fade) return 0;
      return 1 - (sincePress - pressGlow).inMicroseconds / pressGap.inMicroseconds;
    }
  }
  return status ? 1 : 0;
}
