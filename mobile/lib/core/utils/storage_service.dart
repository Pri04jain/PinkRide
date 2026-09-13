import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

/// StorageService — single place for all token reads and writes.
///
/// On mobile (iOS/Android): FlutterSecureStorage (hardware-backed keychain).
/// On web (Chrome dev): SharedPreferences (localStorage).
///
/// WHY DIFFERENT FOR WEB?
/// flutter_secure_storage on web uses the Web Crypto API which requires
/// HTTPS or a secure context. On localhost during Flutter web dev, it
/// throws OperationError. SharedPreferences (localStorage) is less secure
/// but fine for development. On real iOS/Android, always FlutterSecureStorage.
class StorageService {
  StorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Write ──────────────────────────────────────────────────────────────────

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.accessTokenKey, accessToken);
      await prefs.setString(AppConstants.refreshTokenKey, refreshToken);
    } else {
      await Future.wait([
        _storage.write(key: AppConstants.accessTokenKey, value: accessToken),
        _storage.write(key: AppConstants.refreshTokenKey, value: refreshToken),
      ]);
    }
  }

  static Future<void> saveAccessToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.accessTokenKey, token);
    } else {
      await _storage.write(key: AppConstants.accessTokenKey, value: token);
    }
  }

  static Future<void> saveUserMeta({
    required String userId,
    required String role,
  }) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.userIdKey, userId);
      await prefs.setString(AppConstants.userRoleKey, role);
    } else {
      await Future.wait([
        _storage.write(key: AppConstants.userIdKey, value: userId),
        _storage.write(key: AppConstants.userRoleKey, value: role),
      ]);
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────

  static Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.accessTokenKey);
    }
    return _storage.read(key: AppConstants.accessTokenKey);
  }

  static Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.refreshTokenKey);
    }
    return _storage.read(key: AppConstants.refreshTokenKey);
  }

  static Future<String?> getUserId() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.userIdKey);
    }
    return _storage.read(key: AppConstants.userIdKey);
  }

  static Future<String?> getUserRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(AppConstants.userRoleKey);
    }
    return _storage.read(key: AppConstants.userRoleKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.accessTokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
      await prefs.remove(AppConstants.userIdKey);
      await prefs.remove(AppConstants.userRoleKey);
    } else {
      await _storage.deleteAll();
    }
  }

  static Future<void> clearTokens() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.accessTokenKey);
      await prefs.remove(AppConstants.refreshTokenKey);
    } else {
      await Future.wait([
        _storage.delete(key: AppConstants.accessTokenKey),
        _storage.delete(key: AppConstants.refreshTokenKey),
      ]);
    }
  }
}
