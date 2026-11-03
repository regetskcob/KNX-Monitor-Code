import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/theme/app_theme.dart';

void main() {
  testWidgets('Platzhalter im Suchfeld ist vertikal zentriert', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: TextField(
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  prefixIcon: Icon(AppIcons.search, size: 20),
                  hintText: 'Filter',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final field = tester.getRect(find.byType(TextField));
    final hint = tester.getRect(find.text('Filter'));
    expect((hint.center.dy - field.center.dy).abs(), lessThan(1.5));
  });
}
