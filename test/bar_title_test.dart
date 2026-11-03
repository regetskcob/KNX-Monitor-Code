import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/theme/app_theme.dart';
import 'package:knx_monitor/ui/common.dart';

void main() {
  testWidgets('Titel neben Knöpfen bricht um statt abgeschnitten zu werden', (tester) async {
    tester.view.physicalSize = const Size(375, 667) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            title: const BarTitle('Unterschrift Kunde (Abnahme)'),
            actions: [
              for (final icon in [Icons.undo, Icons.clear]) IconButton(onPressed: () {}, icon: Icon(icon)),
            ],
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Unterschrift Kunde (Abnahme)'));
    expect(text.maxLines, 2);
    // Zwei Zeilen passen in die Kopfzeile.
    final paragraph = tester.renderObject<RenderParagraph>(find.text('Unterschrift Kunde (Abnahme)'));
    expect(paragraph.size.height, lessThanOrEqualTo(kToolbarHeight));
    expect(tester.takeException(), isNull);

    // Passt der Titel, bleibt er einzeilig in voller Größe.
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(appBar: AppBar(title: const BarTitle('Abnahme'))),
      ),
    );
    expect(tester.widget<Text>(find.text('Abnahme')).maxLines, 1);
  });

  testWidgets('Erklärung unter einem Schalter in Fließtext, nicht in der Datenschrift', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SwitchListTile(
            value: true,
            onChanged: (_) {},
            title: const Text('Durchklingeln'),
            subtitle: const SwitchHint('Taster drücken, der Eintrag hakt sich selbst ab.'),
          ),
        ),
      ),
    );
    final style = tester.renderObject<RenderParagraph>(find.textContaining('Taster drücken')).text.style;
    expect(style?.fontFamily ?? '', isNot(contains('Monaspace')));
  });

  testWidgets('„Inbetriebnahme“ neben drei Symbolen am A14 (360 dp) ganz lesbar', (tester) async {
    await tester.runAsync(() async {
      for (final file in ['MonaSans-Regular.ttf', 'MonaSans-Medium.ttf', 'MonaSans-SemiBold.ttf']) {
        await (FontLoader(
          'packages/horizont/MonaSans',
        )..addFont(rootBundle.load('packages/horizont/fonts/$file'))).load();
      }
    });
    tester.view.physicalSize = const Size(360, 800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            title: const BarTitle('Inbetriebnahme'),
            actions: [
              for (final icon in [Icons.picture_as_pdf, Icons.edit, Icons.delete])
                IconButton(onPressed: () {}, icon: Icon(icon)),
            ],
          ),
        ),
      ),
    );
    expect(tester.renderObject<RenderParagraph>(find.text('Inbetriebnahme')).didExceedMaxLines, isFalse);
  });
}
