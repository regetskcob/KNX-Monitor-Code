/// KNX protocol building blocks without Flutter and without `dart:io`, so they run in the app (also on
/// the web) and in the add-on server: group and individual addresses, cEMI L_Data frames and group
/// telegrams, KNXnet/IP service identifiers and frame headers, datapoint types (values and units; texts
/// are up to the caller).
library;

export 'src/address.dart';
export 'src/cemi.dart';
export 'src/dpt.dart';
export 'src/hex.dart';
export 'src/knxip.dart';
export 'src/telegram.dart';
