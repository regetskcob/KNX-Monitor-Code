import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/bus_activity.dart';

/// Four segments of a quarter hour, from [start] on.
class _Log extends TelegramLog {
  _Log(this.start);
  final DateTime start;

  @override
  List<int> get activityBins => const [3, 5, 2, 7];

  @override
  DateTime? activityTimeOf(int i) => start.add(Duration(minutes: 15 * i));
}

void main() {
  Future<void> hoverOver(WidgetTester tester, DateTime start, {required double fraction}) async {
    tester.view.physicalSize = const Size(1200, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: BusActivity(data: _Log(start))),
      ),
    );
    final bars = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_ActivityPainter',
    );
    final box = tester.getRect(bars);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(Offset(box.left + box.width * fraction, box.center.dy));
    await tester.pump();
  }

  testWidgets('today: only the time of the segment under the pointer', (tester) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 10);
    await hoverOver(tester, start, fraction: 0.6); // third segment
    expect(find.text('10:30'), findsOneWidget);
  });

  testWidgets('another day: date and time', (tester) async {
    await hoverOver(tester, DateTime(2026, 11, 3, 10), fraction: 0.1);
    expect(find.text('03.11.2026 10:00'), findsOneWidget);
  });
}
