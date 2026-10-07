import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// StorageService — thin wrapper around flutter_secure_storage.
///
/// All JWT tokens are stored in the device's secure enclave
/// (iOS Keychain / Android EncryptedSharedPreferences).
/// Never store tokens in SharedPreferences — it's plain text on disk.
///
/// All methods are static so we don't need to inject the service everywhere.
/// The underlying FlutterSecureStorage instance is a singleton.

class StorageService {
  StorageService._();

  static const _storage = FlutterSecureStorage(
    // Android: store in EncryptedSharedPreferences (AES-256)
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // iOS: accessible only when device is unlocked
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Access token ──────────────────────────────────────────────────────────
  static Future<void> saveAccessToken(String token) =>
      _storage.write(key: AppConstants.accessTokenKey, value: token);

  static Future<String?> getAccessToken() =>
      _storage.read(key: AppConstants.accessTokenKey);

  static Future<void> deleteAccessToken() =>
      _storage.delete(key: AppConstants.accessTokenKey);

  // ── Refresh token ─────────────────────────────────────────────────────────
  static Future<void> saveRefreshToken(String token) =>
      _storage.write(key: AppConstants.refreshTokenKey, value: token);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: AppConstants.refreshTokenKey);

  static Future<void> deleteRefreshToken() =>
      _storage.delete(key: AppConstants.refreshTokenKey);

  // ── Save both at once (called after login) ────────────────────────────────
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
    ]);
  }

  // ── Clear everything (called on logout) ───────────────────────────────────
  static Future<void> clearAll() => _storage.deleteAll();
}
