// Remembered statement passwords, one per account (a bank's statement password
// rarely changes). Stored via flutter_secure_storage — Android Keystore-backed,
// encrypted at rest, on-device only, never transmitted. All failures degrade
// gracefully to "no remembered password" so a locked keystore never blocks an
// import.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PasswordStore {
  PasswordStore._();
  static final PasswordStore instance = PasswordStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _key(String accountId) => 'import_pw_$accountId';

  Future<String?> get(String accountId) async {
    try {
      return await _storage.read(key: _key(accountId));
    } catch (_) {
      return null;
    }
  }

  Future<void> set(String accountId, String password) async {
    try {
      await _storage.write(key: _key(accountId), value: password);
    } catch (_) {
      // Best-effort; a failed save just means we prompt again next time.
    }
  }

  Future<void> remove(String accountId) async {
    try {
      await _storage.delete(key: _key(accountId));
    } catch (_) {}
  }
}
