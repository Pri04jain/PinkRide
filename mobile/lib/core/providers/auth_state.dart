import '../models/user_model.dart';

/// AuthState — a sealed class (union type) representing every possible
/// state of the user's session.
///
/// WHY A SEALED CLASS / UNION TYPE?
/// The session can only ever be in ONE of these states:
///   - We're checking storage (app just opened)
///   - Nobody is logged in
///   - Someone is logged in (and we know who)
///
/// Without this pattern, you'd track this with multiple booleans:
///   bool isLoading, bool isLoggedIn, UserModel? user
/// ...and you can end up in impossible states like isLoading=true AND isLoggedIn=true.
///
/// With a sealed class, the type system prevents that.
/// The router and screens switch on the type:
///
///   final authState = ref.watch(authStateProvider);
///   return switch (authState) {
///     AuthLoading() => SplashScreen(),
///     AuthUnauthenticated() => PhoneInputScreen(),
///     AuthAuthenticated(:final user) => user.isDriver
///         ? DriverHomeScreen()
///         : PassengerHomeScreen(),
///   };

sealed class AuthState {
  const AuthState();
}

/// App just opened — reading tokens from secure storage.
/// Show a splash screen during this state.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// No valid tokens found, or user logged out.
/// Router redirects to /auth/phone.
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// Valid tokens found and user profile loaded.
/// Router shows the correct home screen based on user.role.
class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}
