import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizont/horizont.dart';
import 'package:horizont/testing.dart';
import 'package:knx_monitor/theme/product.dart';

Color _hex(Object? v) => Color(int.parse('FF${(v! as String).substring(1)}', radix: 16));

void main() {
  final json = jsonDecode(File('tool/horizont/horizont.product.json').readAsStringSync()) as Map<String, dynamic>;

  test('the product holds the guard rails of Horizont', () {
    // Busclear also runs embedded in Home Assistant, on its neutrals.
    expectProductHoldsContrast(busclear, hosts: HorizontHost.values);
  });

  test('product.dart and horizont.product.json say the same', () {
    expect(busclear.displayName, json['name']);
    expect(busclear.accentName, json['accentName']);
    for (final (mode, accent) in [('light', busclear.light), ('dark', busclear.dark)]) {
      final m = json[mode] as Map<String, dynamic>;
      expect(accent.accent, _hex(m['accent']), reason: '$mode accent');
      expect(accent.onAccent, _hex(m['on-accent']), reason: '$mode on-accent');
      expect(accent.accentTint, _hex(m['accent-tint']), reason: '$mode accent-tint');
      expect(accent.accentText, _hex(m['accent-text']), reason: '$mode accent-text');
    }
    expect(busclear.neutralDark, isNull);
    expect(json.containsKey('neutralDark'), isFalse);
    for (final (mode, soft) in [('light', busclear.softLight!), ('dark', busclear.softDark!)]) {
      final m = (json['soft'] as Map<String, dynamic>)[mode] as Map<String, dynamic>;
      Color? slot(String k) => m[k] == null ? null : _hex(m[k]);
      expect(
        [soft.bg, soft.surface, soft.line, soft.lineStrong, soft.accentTint, soft.accentText],
        [
          for (final k in ['bg', 'surface', 'line', 'line-strong', 'accent-tint', 'accent-text']) slot(k),
        ],
        reason: 'soft $mode',
      );
    }
  });

  testWidgets('the mark draws the glyph', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: HorizontMark(busclear, size: 48, color: const Color(0xFF000000))),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(busclear.mark, isNotNull);
    expect(find.bySemanticsLabel('Busclear'), findsOneWidget);
  });
}
