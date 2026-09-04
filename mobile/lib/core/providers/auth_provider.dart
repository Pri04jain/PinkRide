import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../constants/api_endpoints.dart';
import '../models/user_model.dart';
import '../utils/storage_service.dart';
import 'auth_state.dart';

/// AuthStateNotifier — manages the session lifecycle.
///
/// HOW RIVERPOD'S STATENOTIFIER WORKS:
/// Think of it like a class that holds one value (the "state") and exposes
/// methods to change it. Any widget or provider that watches this notifier
/// automatically rebuilds when state changes.
///
///   StateNotifier<AuthState>
///       │
///       ├── state = AuthLoading()        ← initial state
///       ├── state = AuthAuthenticated()  ← after login
///       └── state = AuthUnauthenticated() ← after logout
///
/// Widgets watch it like this:
///   final authState = ref.watch(authStateProvider);
///
/// And call methods like this:
///   ref.read(authStateProvider.notifier).logout();

class AuthStateNotifier extends StateNotifier<AuthState> {
  final ApiClient _api;

  // Start in loading state — we need to check storage before we know
  // if the user is logged in
  AuthStateNotifier(this._api) : super(const AuthLoading()) {
    // Run immediately when this notifier is created (app startup)
    _checkSession();
  }

  // ── Session check (app startup) ───────────────────────────────────────────
  // Called once at startup. Reads tokens from secure storage.
  // If a token exists, fetches the user profile to confirm it's still valid.
  // If not, transitions to Unauthenticated.

  Future<void> _checkSession() async {
    final isLoggedIn = await StorageService.isLoggedIn();

    if (!isLoggedIn) {
      state = const AuthUnauthenticated();
      return;
    }

    // Token exists — verify it's still valid by fetching the profile.
    // If the token expired, _AuthInterceptor will try to refresh it.
    // If refresh also fails, the 401 handler clears storage and we redirect.
    try {
      final data = await _api.get(ApiEndpoints.profile);
      final user = UserModel.fromJson(
        data['profile'] as Map<String, dynamic>? ?? data,
      );
      state = AuthAuthenticated(user);
    } catch (_) {
      // Token invalid or network error — treat as logged out
      await StorageService.clearAll();
      state = const AuthUnauthenticated();
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  // Called from the OTP verification screen after the backend returns tokens.
  // Saves tokens to secure storage, then fetches the full profile.

  Future<void> login({
    required String accessToken,
    required String refreshToken,
    required Map<String, dynamic> userJson,
  }) async {
    // Save tokens first so ApiClient can use them for the profile fetch
    await StorageService.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    final user = UserModel.fromJson(userJson);

    // Save role to storage so cold-start redirect is instant (no API call)
    await StorageService.saveUserMeta(
      userId: user.id,
      role: user.role.name,
    );

    state = AuthAuthenticated(user);
  }

  // ── Update profile ────────────────────────────────────────────────────────
  // Called after the user updates their name, photo, or wallet balance.
  // Updates state without hitting the API again.

  void updateUser(UserModel updatedUser) {
    if (state is AuthAuthenticated) {
      state = AuthAuthenticated(updatedUser);
    }
  }

  // ── Refresh profile from server ───────────────────────────────────────────
  // Called when we need the latest wallet balance, face_verified status, etc.

  Future<void> refreshProfile() async {
    if (state is! AuthAuthenticated) return;

    try {
      final data = await _api.get(ApiEndpoints.profile);
      final user = UserModel.fromJson(
        data['profile'] as Map<String, dynamic>? ?? data,
      );
      state = AuthAuthenticated(user);
    } catch (_) {
      // Silently fail — keep showing stale data rather than kicking the user out
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  // Calls the backend to revoke the refresh token (adds jti to blacklist),
  // then clears local storage and transitions to Unauthenticated.

  Future<void> logout() async {
    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken != null) {
        // Best-effort — if this fails (e.g. no internet), we still log out locally
        await _api.post(
          ApiEndpoints.logout,
          data: {'refreshToken': refreshToken},
        );
      }
    } catch (_) {
      // Network error on logout is fine — local clear still happens
    } finally {
      await StorageService.clearAll();
      state = const AuthUnauthenticated();
    }
  }

  // ── Convenience getters ───────────────────────────────────────────────────

  /// The current user, or null if not authenticated.
  /// Use ref.watch(authStateProvider) directly for reactive listening.
  UserModel? get currentUser =>
      state is AuthAuthenticated ? (state as AuthAuthenticated).user : null;

  bool get isAuthenticated => state is AuthAuthenticated;
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// The main auth provider — watched by the router and any screen
/// that needs to know who is logged in.
///
/// Usage in a widget:
///   final authState = ref.watch(authStateProvider);
///
/// Usage to call a method:
///   ref.read(authStateProvider.notifier).logout();

final authStateProvider =
    StateNotifierProvider<AuthStateNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthStateNotifier(api);
});

/// Convenience provider — returns the current UserModel or null.
/// Use this when you just need the user data and don't care about loading state.
///
/// Usage:
///   final user = ref.watch(currentUserProvider);
///   Text(user?.displayName ?? 'Guest')

final currentUserProvider = Provider<UserModel?>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState is AuthAuthenticated ? authState.user : null;
});
