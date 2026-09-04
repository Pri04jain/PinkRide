import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

/// StorageService — single place for all secure token reads and writes.
///
/// Why a dedicated class instead of calling FlutterSecureStorage directly?
/// - Key names are defined once in AppConstants (no typos scattered around)
/// - Easy to swap the storage backend in the future (e.g. add encryption layer)
/// - Every read/write is testable in isolation
///
/// FlutterSecureStorage internals:
///   iOS     → Keychain Services (hardware-backed on modern iPhones)
///   Android → EncryptedSharedPreferences (AES-256 via Android Keystore)
///   Web     → localStorage (less secure — tokens should be short-lived on web)
class StorageService {
  StorageService._();

  static const _storage = FlutterSecureStorage(
    // Android options: use encrypted storage (default is true in v5+)
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // iOS options: store in Keychain, accessible after first unlock
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  // ── Write ──────────────────────────────────────────────────────────────────

  /// Save both tokens after a successful login or token refresh.
  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.accessTokenKey, value: accessToken),
      _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
    ]);
  }

  /// Save only the access token (used after a silent token refresh).
  static Future<void> saveAccessToken(String token) async {
    await _storage.write(key: AppConstants.accessTokenKey, value: token);
  }

  /// Save user metadata so the app can show the correct home screen
  /// immediately on cold start without hitting the API.
  static Future<void> saveUserMeta({
    required String userId,
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: AppConstants.userIdKey, value: userId),
      _storage.write(key: AppConstants.userRoleKey, value: role),
    ]);
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  /// Returns null if no token exists (user not logged in).
  static Future<String?> getAccessToken() =>
      _storage.read(key: AppConstants.accessTokenKey);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: AppConstants.refreshTokenKey);

  static Future<String?> getUserId() =>
      _storage.read(key: AppConstants.userIdKey);

  static Future<String?> getUserRole() =>
      _storage.read(key: AppConstants.userRoleKey);

  /// Returns true if an access token exists.
  /// Used by the router to decide whether to show the auth flow or home screen.
  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Clear everything — called on logout or account deletion.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Clear only the access token — used when a 401 cannot be refreshed.
  static Future<void> clearTokens() async {
    await Future.wait([
      _storage.delete(key: AppConstants.accessTokenKey),
      _storage.delete(key: AppConstants.refreshTokenKey),
    ]);
  }
}
