import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knx_monitor/model/installation.dart';
import 'package:knx_monitor/model/site_photos.dart';
import 'package:knx_monitor/model/telegram_log.dart';
import 'package:knx_monitor/platform/storage.dart';
import 'package:knx_monitor/theme/app_icons.dart';
import 'package:knx_monitor/ui/site_docs_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_storage.dart';
import 'window.dart';

void main() {
  final photos = SitePhotoStore.instance;

  Future<void> fill(WidgetTester tester) => tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    AppStorage.instance = MemoryStorage();
    InstallationStore.instance.debugReset();
    photos.debugReset();
    await photos.load();
    final jpeg = img.encodeJpg(img.Image(width: 8, height: 6));
    for (var i = 0; i < 4; i++) {
      await photos.add(jpeg, caption: 'Feld $i', at: DateTime(2026, 11, i + 1));
    }
  });

  testWidgets('breites Fenster: Fotos als Kachelraster, Etiketten rechts daneben', (tester) async {
    await fill(tester);
    await pumpWindow(tester, SiteDocsScreen(log: TelegramLog()), wideWindow);
    final photosTitle = tester.getTopLeft(find.text('Fotos'));
    final labelsTitle = tester.getTopLeft(find.text('Etiketten'));
    expect(labelsTitle.dy, photosTitle.dy);
    expect(labelsTitle.dx, greaterThan(wideWindow.width / 2));
    // Zeilenweise, neuestes zuerst: das zweite Foto steht rechts neben dem ersten.
    expect(columnsOf(tester, find.byIcon(AppIcons.delete)), hasLength(3));
    final first = tester.getTopLeft(find.text('Feld 3'));
    final second = tester.getTopLeft(find.text('Feld 2'));
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('Telefon und schmales Fenster: Karten untereinander, Fotos als Liste', (tester) async {
    await fill(tester);
    for (final (size, scale) in [(phoneWindow, 1.0), (phoneWindow, 2.0), (const Size(800, 1000), 1.0)]) {
      await pumpWindow(tester, SiteDocsScreen(log: TelegramLog()), size, textScale: scale);
      expect(columnsOf(tester, find.byIcon(AppIcons.delete)), hasLength(1), reason: '$size, Schrift $scale');
      await tester.dragUntilVisible(find.text('Etiketten'), find.byType(ListView), const Offset(0, -200));
      expect(tester.getTopLeft(find.text('Etiketten')).dx, lessThan(size.width / 2));
    }
    await pumpWindow(tester, SiteDocsScreen(log: TelegramLog()), wideWindow, textScale: 2);
  });
}
