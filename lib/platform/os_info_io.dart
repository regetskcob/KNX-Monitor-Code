import 'dart:io';

import 'os_info.dart';

String get operatingSystemVersion => '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';

String get issuePlatform => shortPlatform(Platform.operatingSystem, Platform.operatingSystemVersion);
