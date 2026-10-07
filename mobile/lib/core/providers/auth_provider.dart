import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../constants/api_endpoints.dart';
import '../models/app_error.dart';
import '../models/user_model.dart';
import '../utils/storage_service.dart';
import 'auth_state.dart';

// ── AuthStateNotifier ─────────────────────────────────────────────────────────
//
// The single source of truth for authentication across the entire app.
//
// LIFECYCLE:
//   1. App starts → AuthStateNotifier is created → checkSession() fires
//   2. checkSession() reads tokens from secure storage
//      - No token → emit AuthUnauthenticated
//      - Token found → fetch /users/me → emit AuthAuthenticated(user)
//      - Network error → emit AuthUnauthenticated (safe fallback)
//   3. On login → saveSession() stores tokens + emits AuthAuthenticated
//   4. On logout → clearSession() deletes tokens + emits AuthUnauthenticated
//
// go_router's RouterNotifier listens to this and refreshes the router
// whenever state changes, triggering a redirect re-evaluation.

class AuthStateNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;

  AuthStateNotifier(this._api) : super(const AuthLoading()) {
    // Kick off session check immediately on creation.
    // This runs once per app launch.
    checkSession();
  }

  // ── Check session on startup ──────────────────────────────────────────────
  // Reads the access token from secure storage. If present, fetches the
  // user profile to confirm it's still valid. If the token is expired,
  // ApiClient's _AuthInterceptor will attempt a refresh automatically.
  // If refresh also fails, ApiClient throws AppError.unauthorized which
  // we catch here and treat as unauthenticated.

  Future<void> checkSession() async {
    state = const AuthLoading();

    try {
      final token = await StorageService.getAccessToken();
      if (token == null || token.isEmpty) {
        state = const AuthUnauthenticated();
        return;
      }

      // Token exists — validate by fetching current user.
      // Backend returns { profile: {...} } after ApiClient unwraps the outer data envelope.
      final data = await _api.get(ApiEndpoints.userProfile);
      final userJson = data['profile'] as Map<String, dynamic>?
          ?? data['user']    as Map<String, dynamic>?
          ?? data;
      final user = UserModel.fromJson(userJson);
      state = AuthAuthenticated(user);
    } on AppError catch (e) {
      if (e.type == AppErrorType.unauthorized) {
        await StorageService.clearAll();
      }
      state = const AuthUnauthenticated();
    } catch (_) {
      state = const AuthUnauthenticated();
    }
  }

  // ── Save session after login ──────────────────────────────────────────────
  // Called by AuthFlowNotifier after a successful OTP verification.
  // Stores tokens and updates auth state so the router redirects immediately.

  Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required UserModel user,
  }) async {
    await StorageService.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
    state = AuthAuthenticated(user);
  }

  // ── Refresh current user profile ─────────────────────────────────────────
  // Called after profile setup or whenever user data may have changed.
  // Keeps AuthAuthenticated.user in sync with the backend.

  Future<void> refreshProfile() async {
    try {
      final data = await _api.get(ApiEndpoints.userProfile);
      // GET /users/profile returns { profile: {...} }
      // POST /users/register returns { user: {...} }
      // Support both shapes.
      final userJson = data['profile'] as Map<String, dynamic>?
          ?? data['user']    as Map<String, dynamic>?
          ?? data;
      final user = UserModel.fromJson(userJson);
      state = AuthAuthenticated(user);
    } catch (_) {
      // Silently ignore — existing state is still usable
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  // Best-effort: calls the backend logout endpoint to revoke the refresh token,
  // then clears local storage regardless of whether the API call succeeded.

  Future<void> logout() async {
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken != null) {
        await _api.post(
          ApiEndpoints.logout,
          data: {'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // Ignore logout API errors — clear locally regardless
    } finally {
      await StorageService.clearAll();
      state = const AuthUnauthenticated();
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The main auth state provider — watched by go_router and every screen
/// that needs to know if the user is logged in.
final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  return AuthStateNotifier(ref.watch(apiClientProvider));
});

/// Convenience provider — returns the current user or null.
/// Screens that just need the user object without caring about loading state.
final currentUserProvider = Provider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState is AuthAuthenticated ? authState.user : null;
});
