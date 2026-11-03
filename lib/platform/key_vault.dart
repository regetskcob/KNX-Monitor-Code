import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage for keys in the keychain: app lock, device key and business key per generation. An
/// interface so tests run without a keychain.
abstract interface class KeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The system keychain; does not migrate to other devices via iCloud or backup (like the keyring in
/// `keyring_store.dart`).
class SecureKeyVault implements KeyVault {
  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      usesDataProtectionKeychain: false,
    ),
  );

  @override
  Future<String?> read(String key) => _vault.read(key: key);

  @override
  Future<void> write(String key, String value) => _vault.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _vault.delete(key: key);
}
