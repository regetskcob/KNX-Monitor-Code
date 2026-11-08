# knx

KNX protocol building blocks in pure Dart, shared by the Busclear app (Flutter, also on the web)
and its Home Assistant add-on server (Dart VM). One implementation instead of two copies.

**Internal for now.** The package lives in the Busclear repository and is not published
(`publish_to: none`). It may be published on pub.dev later, with its own licence and a stable API;
until then names and signatures change whenever app and server need it.

## Contents

`package:knx/knx.dart`, without Flutter and without `dart:io`:

- Group and individual addresses: parse and format, 3-level, 2-level and free style.
- cEMI: L_Data frames (`CemiFrame`, `buildLData`, `isLDataRequest`), group telegrams (`Telegram`,
  `TelegramType`, `TelegramPriority`, `buildGroupRequest`) and the JSON line format of the
  recorded history (`Telegram.toJson`, `Telegram.fromJson`).
- KNXnet/IP: service identifiers (`KnxIpService`), status codes (`KnxIpStatus`), frame header,
  HPAI and tunnel CRI.
- Datapoint types: `Dpt`, DPT 9 float, numeric values for charts (`dptNumericValue`), units
  (`dptUnit`), encoding typed input (`encodeForDpt`). Texts stay with the caller.
- Hex helpers.

`package:knx/secure.dart`, KNX Secure after AN158/AN159 (needs `pointycastle`):

- AES-128-CCM in KNX block formatting, key derivation, X25519 (`cbcMac`, `ctr`, …).
- IP Secure session: handshake and secure wrapper (`IpSecureSession`).
- Data Secure for group telegrams (`DataSecure`, also from the add-on's `secure_keys.json`).

## Not in here

Everything with Flutter, texts and translations, storage or app models stays in the app;
connections (tunnel, routing, FT1.2, kBerry), the `.knxproj` parser and keyring storage stay
where they are and use this package. See `docs/architecture.md` in the repository.

## Checks

```sh
dart pub get && dart format --output=none --set-exit-if-changed lib test && dart analyze && dart test
```

`tool/release.sh verify` and the pull request CI (job `addon-server`) run them too.

## Licence

GPLv3 like the rest of the repository (`LICENSE`), for now. The KNX Secure code follows the
structure of xknx (MIT); its notice is in `NOTICE`.
