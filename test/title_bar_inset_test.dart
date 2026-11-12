import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/platform/title_bar_inset.dart';

void main() {
  tearDown(() => TitleBarInset.value.value = 0);

  Future<(double, double)> tops(WidgetTester tester, {bool beside = true}) async {
    late double page;
    late double content;
    await tester.pumpWidget(
      MaterialApp(
        home: TitleBarPadding(
          child: Builder(
            builder: (context) {
              page = MediaQuery.paddingOf(context).top;
              return BesideTitleBar(
                active: beside,
                child: Builder(
                  builder: (context) {
                    content = MediaQuery.paddingOf(context).top;
                    return const SizedBox();
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    return (page, content);
  }

  testWidgets('ohne Fensterknöpfe (Telefon, Vollbild) bleibt der Abstand, wie er ist', (tester) async {
    expect(await tops(tester), (0.0, 0.0));
  });

  testWidgets('Mac: Seite beginnt unter den Fensterknöpfen, Inhalt neben der Seitenleiste etwas höher', (tester) async {
    TitleBarInset.value.value = 28;
    final (page, content) = await tops(tester);
    expect(page, 28);
    expect(content, lessThan(page));
    // The strip that drags the window stays free of controls: the content keeps most of it.
    expect(content, greaterThanOrEqualTo(16));
  });

  testWidgets('verschachtelt (Werkzeugseite mit eigener Seitenleiste): nur einmal höher', (tester) async {
    TitleBarInset.value.value = 28;
    late double once;
    late double twice;
    await tester.pumpWidget(
      MaterialApp(
        home: TitleBarPadding(
          child: BesideTitleBar(
            child: Builder(
              builder: (context) {
                once = MediaQuery.paddingOf(context).top;
                return BesideTitleBar(
                  child: Builder(
                    builder: (context) {
                      twice = MediaQuery.paddingOf(context).top;
                      return const SizedBox();
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(twice, once);
  });

  testWidgets('Seitenleiste eingeklappt: der Inhalt liegt wieder unter den Knöpfen', (tester) async {
    TitleBarInset.value.value = 28;
    final (page, content) = await tops(tester, beside: false);
    expect(content, page);
  });
}
