import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data classes for API responses ─────────────────────────────────────────
// These are simple Dart classes — no code generation needed here.
// They represent exactly what the backend returns for each auth endpoint.

/// Returned by verifyOtp — contains both tokens and the user profile.
class VerifyOtpResult {
  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;
  final bool isNewUser;

  const VerifyOtpResult({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.isNewUser,
  });

  factory VerifyOtpResult.fromJson(Map<String, dynamic> json) {
    // Backend shape: { tokens: { accessToken, refreshToken }, user: {...}, isNewUser: bool }
    final tokens = json['tokens'] as Map<String, dynamic>? ?? {};
    return VerifyOtpResult(
      accessToken: tokens['accessToken'] as String? ?? '',
      refreshToken: tokens['refreshToken'] as String? ?? '',
      user: json['user'] as Map<String, dynamic>? ?? {},
      isNewUser: json['isNewUser'] as bool? ?? false,
    );
  }
}

// ── AuthService ─────────────────────────────────────────────────────────────
// Contains all API calls for the authentication flow.
// Providers call these methods — screens never call ApiClient directly.
//
// WHY SEPARATE SERVICE FROM PROVIDER?
// The provider holds state (loading, error, data).
// The service holds the API logic (what endpoints to call, what to parse).
// This separation means:
//   - Easy to test service logic without Flutter widgets
//   - Provider stays clean — just calls service and updates state
//   - If the backend API changes, we only update the service

class AuthService {
  final ApiClient _api;

  const AuthService(this._api);

  /// Step 1: Send a 6-digit OTP to the given phone number.
  /// Phone must be 10 digits (country code handled separately).
  /// Backend rate-limits to 5 requests per hour per number.
  Future<void> requestOtp({
    required String phone,
    required String countryCode,
    String purpose = 'login',
  }) async {
    await _api.post(
      ApiEndpoints.requestOtp,
      data: {
        'phone': phone,
        'countryCode': countryCode,
        'purpose': purpose,
      },
    );
    // No return value — success means OTP was sent.
    // The backend prints it to console in dev mode.
  }

  /// Step 2: Verify the OTP the user entered.
  /// On success: returns tokens + user profile.
  /// On failure: throws AppError with a human-readable message.
  Future<VerifyOtpResult> verifyOtp({
    required String phone,
    required String countryCode,
    required String otp,
    String purpose = 'login',
  }) async {
    final data = await _api.post(
      ApiEndpoints.verifyOtp,
      data: {
        'phone': phone,
        'countryCode': countryCode,
        'otp': otp,
        'purpose': purpose,
      },
    );
    return VerifyOtpResult.fromJson(data);
  }

  /// Step 3 (new users only): Complete the profile after first login.
  /// Sends name, gender, DOB, and role to the backend.
  /// Returns the updated user profile.
  Future<Map<String, dynamic>> completeRegistration({
    required String fullName,
    required String gender,
    required String dateOfBirth, // ISO format: 2000-05-15
    required String role,        // 'passenger' or 'driver'
  }) async {
    final data = await _api.post(
      ApiEndpoints.register,
      data: {
        'fullName': fullName,
        'gender': gender,
        'dateOfBirth': dateOfBirth,
        'role': role,
      },
    );
    // Backend returns { user: {...} }
    return data['user'] as Map<String, dynamic>? ?? data;
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(apiClientProvider));
});
