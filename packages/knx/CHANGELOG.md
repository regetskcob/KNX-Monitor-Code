# Changelog

## 0.1.0 (unreleased, internal)

- First version, taken out of the KNX Monitor app and its Home Assistant add-on server, which both
  use it now instead of their own copies: group and individual addresses, cEMI L_Data frames and
  group telegrams with the history's JSON line format, KNXnet/IP service identifiers and frame
  headers, datapoint type values and units.
- `package:knx/secure.dart`: KNX Secure building blocks, IP Secure session and Data Secure.
