import 'dart:typed_data';

import 'package:knx/knx.dart';

/// Group telegram from a cEMI frame as a history line (`Telegram.toJson()` of package:knx, the same
/// format the app reads). `null` for anything but group telegrams (L_Data.ind/.con,
/// read/response/write).
Map<String, Object?>? telegramJson(Uint8List c, DateTime time) => Telegram.fromCemi(c, time: time)?.toJson();
