import '../models/user_model.dart';

/// AuthState — sealed class representing every possible authentication state.
///
/// STATES:
///   AuthLoading        — app just opened, checking secure storage for tokens
///   AuthUnauthenticated — no valid session, show auth flow
///   AuthAuthenticated   — logged in, user data available
///
/// go_router's redirect checks this on every navigation to decide
/// where to send the user. RouterNotifier bridges state changes → router refresh.

sealed class AuthState {
  const AuthState();
}

/// Checking secure storage on app startup.
/// The splash screen is shown while in this state.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// No session / logged out.
/// Router sends user to /auth/phone.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Logged in with a valid token.
/// Router sends user to their role-appropriate home screen.
class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}
