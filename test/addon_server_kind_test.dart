import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knx_monitor/l10n/locale_controller.dart';
import 'package:knx_monitor/platform/addon.dart';
import 'package:knx_monitor/ui/weekly_report_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The web app served by a Busclear Box or Docker uses the box texts and the normal look, not
/// those of the Home Assistant add-on.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleController.instance.debugSetLocale(const Locale('de'));
  });
  tearDown(() => Addon.servedByBox = false);

  test('/api/box answers: box server, box texts', () async {
    await Addon.detectServer(info: () async => {'box': true, 'container': true});
    expect(Addon.servedByBox, isTrue);
    expect(Addon.onBox, isTrue);
    expect(Addon.inHomeAssistant, isFalse);
    expect(currentReport(null).basis.server, s.weekServerBox);
  });

  test('add-on (no /api/box) or no answer: add-on texts as before', () async {
    await Addon.detectServer(info: () async => throw const AddonException('Add-on: HTTP 404', status: 404));
    expect(Addon.servedByBox, isFalse);
    expect(Addon.onBox, isFalse);
    expect(currentReport(null).basis.server, s.weekServerAddon);

    await Addon.detectServer(
      info: () => Future.delayed(const Duration(seconds: 1), () => {'box': true}),
      timeout: const Duration(milliseconds: 10),
    );
    expect(Addon.servedByBox, isFalse);
  });
}
