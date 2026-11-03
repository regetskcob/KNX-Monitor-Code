import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/ui/common.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  for (final (platform, expected) in const [
    (TargetPlatform.iOS, ScrollViewKeyboardDismissBehavior.onDrag),
    (TargetPlatform.android, ScrollViewKeyboardDismissBehavior.onDrag),
    (TargetPlatform.macOS, ScrollViewKeyboardDismissBehavior.manual),
  ]) {
    testWidgets('Tastatur beim Scrollen: $platform', (tester) async {
      late ScrollViewKeyboardDismissBehavior seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          scrollBehavior: const AppScrollBehavior(),
          home: Builder(
            builder: (context) {
              seen = ScrollConfiguration.of(context).getKeyboardDismissBehavior(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, expected);
    });
  }

  test('Scanner: fehlende Freigabe ist nicht „keine Kamera“', () {
    expect(
      scannerProblem(const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied)),
      s.scanCameraDenied,
    );
    expect(
      scannerProblem(const MobileScannerException(errorCode: MobileScannerErrorCode.genericError)),
      s.boxScanNoCamera,
    );
  });
}
