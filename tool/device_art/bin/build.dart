// Validates manufacturer device graphics and compiles them for the app.
//
//   cd tool/device_art && dart run bin/build.dart [<source> <target>]
//
// Reads src/<id>/manifest.json with the SVG next to it for each device,
// validates both against the specification and writes
// assets/device_art/<id>.vec (vector_graphics) and
// assets/device_art/index.json with all manifests. Aborts on errors without
// writing anything. With source and target it builds other graphics, such as
// the neutral sample devices for the manufacturer PDF.
import 'dart:convert';
import 'dart:io';

import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// Smallest tap target in mm (≈ 44 px at 8 px/mm).
const minArea = 6.0;

/// Largest SVG in bytes.
const maxSvg = 200 * 1024;

void main(List<String> args) {
  final tool = File(Platform.script.toFilePath()).parent.parent;
  final src = Directory(args.isNotEmpty ? args[0] : '${tool.path}/src');
  final out = Directory(args.length > 1 ? args[1] : '${tool.parent.parent.path}/assets/device_art');
  final errors = <String>[];
  final built = <String, (Map<String, Object?>, List<int>)>{};

  for (final dir in src.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path))) {
    final id = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
    void fail(String message) => errors.add('$id: $message');
    final file = File('${dir.path}/manifest.json');
    if (!file.existsSync()) {
      fail('manifest.json fehlt');
      continue;
    }
    final Map<String, Object?> manifest;
    try {
      manifest = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    } on FormatException catch (e) {
      fail('manifest.json ist kein JSON: ${e.message}');
      continue;
    }
    final svg = _check(manifest, dir, fail);
    if (svg == null) continue;
    try {
      // Optimizers need the engine's native PathOps library; not needed for
      // device fronts without masks.
      final bytes = encodeSvg(
        xml: svg,
        debugName: id,
        warningsAsErrors: true,
        enableMaskingOptimizer: false,
        enableClippingOptimizer: false,
        enableOverdrawOptimizer: false,
      );
      built[id] = (manifest, bytes);
    } on Object catch (e) {
      fail('SVG lässt sich nicht kompilieren: $e');
    }
  }

  if (errors.isNotEmpty) {
    stderr.writeln(errors.join('\n'));
    exit(1);
  }
  out.createSync(recursive: true);
  final index = <Map<String, Object?>>[];
  for (final MapEntry(key: id, value: (manifest, bytes)) in built.entries) {
    File('${out.path}/$id.vec').writeAsBytesSync(bytes);
    final image = {...manifest['image']! as Map<String, Object?>, 'file': '$id.vec'};
    index.add({'id': id, ...manifest, 'image': image});
    stdout.writeln('$id: ${bytes.length} B');
  }
  File('${out.path}/index.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(index)}\n');
}

/// Validates manifest and SVG; returns the SVG if everything is valid.
String? _check(Map<String, Object?> m, Directory dir, void Function(String) fail) {
  final before = _failures;
  void f(String message) {
    _failures++;
    fail(message);
  }

  if (m['schema'] != 1) f('schema muss 1 sein');
  if (m['manufacturer'] is! String) f('manufacturer fehlt');
  final orders = m['orderNumbers'];
  if (orders is! List || orders.isEmpty || orders.any((o) => o is! String)) f('orderNumbers fehlt');
  final image = m['image'];
  if (image is! Map) {
    f('image fehlt');
    return null;
  }
  final width = (image['width'] as num?)?.toDouble() ?? 0;
  final height = (image['height'] as num?)?.toDouble() ?? 0;
  if (width <= 0 || height <= 0) f('image.width/height in mm fehlen');
  final svgFile = File('${dir.path}/${image['file']}');
  if (!svgFile.existsSync()) {
    f('${image['file']} fehlt');
    return null;
  }
  final svg = svgFile.readAsStringSync();
  if (svgFile.lengthSync() > maxSvg) f('SVG größer als ${maxSvg ~/ 1024} KB');
  if (RegExp(r'<script|\bon\w+\s*=', caseSensitive: false).hasMatch(svg)) f('SVG enthält Skripte');
  if (RegExp(r'''href\s*=\s*["'](?!#)''').hasMatch(svg)) f('SVG verweist auf externe Dateien');
  if (RegExp(r'<text\b').hasMatch(svg)) f('Schrift muss in Pfade gewandelt sein');
  final viewBox = RegExp(r'viewBox\s*=\s*"([^"]+)"').firstMatch(svg)?.group(1)?.trim().split(RegExp(r'[\s,]+'));
  if (viewBox == null ||
      viewBox.length != 4 ||
      double.tryParse(viewBox[0]) != 0 ||
      double.tryParse(viewBox[1]) != 0 ||
      double.tryParse(viewBox[2]) != width ||
      double.tryParse(viewBox[3]) != height) {
    f('viewBox muss "0 0 $width $height" (mm) sein');
  }

  bool inside(Map r) {
    final (x, y, w, h) = _rect(r);
    return x >= 0 && y >= 0 && x + w <= width && y + h <= height;
  }

  final channels = m['channels'];
  final indicators = m['indicators'];
  if (indicators is List) {
    for (final i in indicators.cast<Map>()) {
      final led = i['led'];
      if (led is! Map || i['role'] is! String) {
        f('indicator ${i['key']}: led oder role fehlt');
      } else if (led['x'] is! num || led['y'] is! num) {
        f('indicator ${i['key']}: led.x/led.y müssen Zahlen sein');
      }
    }
  }
  // Channels may only be missing for devices with status LEDs (couplers, power supplies).
  if (channels is! List || (channels.isEmpty && indicators is! List)) {
    f('channels fehlt');
    return null;
  }
  final keys = <String>{};
  final areas = <(String, Map)>[];
  for (final c in channels.cast<Map>()) {
    final key = c['key'];
    if (key is! String || key.isEmpty) {
      f('Kanal ohne key');
      continue;
    }
    if (!keys.add(key)) f('Kanal $key doppelt');
    final area = c['area'];
    if (area is! Map) {
      f('Kanal $key: area fehlt');
      continue;
    }
    final (_, _, w, h) = _rect(area);
    if (!inside(area)) f('Kanal $key: area liegt außerhalb der Grafik');
    if (w < minArea || h < minArea) f('Kanal $key: area kleiner als $minArea mm');
    for (final (other, a) in areas) {
      if (_overlaps(area, a)) f('Kanal $key überlappt Kanal $other');
    }
    areas.add((key, area));
    if (c['label'] case final Map label when !inside(label)) f('Kanal $key: label liegt außerhalb der Grafik');
    if (c['led'] case final Map led) {
      final x = (led['x'] as num).toDouble(), y = (led['y'] as num).toDouble();
      final (ax, ay, aw, ah) = _rect(area);
      if (x < ax || x > ax + aw || y < ay || y > ay + ah) f('Kanal $key: led liegt nicht in area');
    }
  }
  return _failures == before ? svg : null;
}

var _failures = 0;

(double, double, double, double) _rect(Map r) => (
  (r['x'] as num? ?? -1).toDouble(),
  (r['y'] as num? ?? -1).toDouble(),
  (r['w'] as num? ?? 0).toDouble(),
  (r['h'] as num? ?? 0).toDouble(),
);

bool _overlaps(Map a, Map b) {
  final (ax, ay, aw, ah) = _rect(a);
  final (bx, by, bw, bh) = _rect(b);
  return ax < bx + bw && bx < ax + aw && ay < by + bh && by < ay + ah;
}
