import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizont/horizont.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/locale_controller.dart';
import '../model/site_photos.dart';
import '../theme/app_icons.dart';

/// Camera only on phone and tablet, as in the photo documentation: the desktop
/// apps have no camera permission, and in the add-on images are chosen as files.
bool get _hasCamera => !kIsWeb && const {TargetPlatform.android, TargetPlatform.iOS}.contains(defaultTargetPlatform);

/// Replaces camera and file dialog in tests: returns the raw image.
@visibleForTesting
Future<Uint8List?> Function()? debugPhotoSource;

/// Lets the user take a photo or choose an image (camera or gallery on phone
/// and tablet, a file elsewhere) and returns it normalized like every site
/// photo ([compressSitePhoto]: upright, limited size, JPEG, no metadata).
/// `null` if nothing was chosen or the image is unreadable; the reason is shown.
Future<Uint8List?> pickSitePhoto(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final Uint8List? bytes;
  try {
    if (debugPhotoSource case final source?) {
      bytes = await source();
    } else {
      // `true` camera, `false` gallery or file; closing the sheet chooses nothing.
      final camera = _hasCamera ? await _askCamera(context) : false;
      if (camera == null) return null;
      bytes = camera
          ? await (await ImagePicker().pickImage(source: ImageSource.camera))?.readAsBytes()
          : await (await FilePicker.pickFile(type: FileType.image))?.readAsBytes();
    }
  } on PlatformException catch (e) {
    // Camera denied or not available.
    debugPrint('Kamera: $e');
    messenger.showSnackBar(SnackBar(content: Text(s.boxScanNoCamera)));
    return null;
  }
  if (bytes == null) return null;
  try {
    return await compute(compressSitePhoto, bytes);
  } on FormatException {
    messenger.showSnackBar(SnackBar(content: Text(s.siteDocsUnreadable)));
    return null;
  }
}

Future<bool?> _askCamera(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  showDragHandle: true,
  builder: (sheet) => SafeArea(
    top: false,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(AppIcons.image),
          title: Text(s.siteDocsTakePhoto),
          onTap: () => Navigator.pop(sheet, true),
        ),
        ListTile(
          leading: const Icon(AppIcons.import),
          title: Text(s.siteDocsPickPhoto),
          onTap: () => Navigator.pop(sheet, false),
        ),
        const SizedBox(height: HzSpace.s8),
      ],
    ),
  ),
);
