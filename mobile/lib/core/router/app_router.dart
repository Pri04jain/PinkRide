import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/auth_state.dart';
import '../theme/app_theme.dart';
import '../../features/auth/screens/phone_input_screen.dart';
import '../../features/auth/screens/otp_verify_screen.dart';
import '../../features/auth/screens/profile_setup_screen.dart';
import '../../features/verification/screens/consent_screen.dart';
import '../../features/verification/screens/face_register_screen.dart';
import '../../features/verification/screens/pre_ride_face_screen.dart';
import '../../features/verification/screens/verification_status_screen.dart';
import '../../features/ride/screens/passenger_home_screen.dart';
import '../../features/ride/screens/active_ride_screen.dart';

/// Route path constants — single source of truth for all navigation.
/// Use these everywhere instead of raw strings like '/auth/phone'.
class AppRoutes {
  AppRoutes._();

  // Auth
  static const String splash = '/';
  static const String phoneInput = '/auth/phone';
  static const String otpVerify = '/auth/otp';
  static const String profileSetup = '/auth/profile';

  // Face verification
  static const String faceConsent = '/verification/consent';
  static const String faceRegister = '/verification/register';
  static const String verificationStatus = '/verification/status';
  static const String preRideFace = '/verification/ride-face';

  // Ride OTP entry (after pre-ride face check)
  static const String otpEntry = '/ride/otp';

  // Passenger
  static const String passengerHome = '/passenger/home';
  static const String bookRide = '/passenger/book';
  static const String activeRide = '/passenger/ride/:rideId';

  // Driver
  static const String driverHome = '/driver/home';
  static const String driverRegister = '/driver/register';
  static const String driverStatus = '/driver/status';

  // Safety
  static const String sos = '/safety/sos';
  static const String emergencyContacts = '/safety/contacts';

  // Payment
  static const String payment = '/payment/:rideId';
  static const String rating = '/rating/:rideId';
  static const String wallet = '/wallet';

  // Admin
  static const String adminHome = '/admin/home';
  static const String adminDriverDetail = '/admin/driver/:driverId';
}

/// appRouterProvider — the go_router instance wired to AuthState.
///
/// HOW go_router REDIRECT WORKS:
/// Every time the user navigates (or the app starts), go_router calls
/// the `redirect` callback. We check the current AuthState and decide:
///
///   AuthLoading     → stay on splash (wait for session check)
///   Unauthenticated → send to /auth/phone (unless already there)
///   Authenticated   → send to correct home screen based on role
///                     (unless already on a valid screen for that role)
///
/// WHY ref.listen AND routerKey?
/// go_router doesn't automatically re-evaluate the redirect when Riverpod
/// state changes. We use a [RouterNotifier] that listens to authStateProvider
/// and calls GoRouter.refresh() whenever the session changes —
/// which triggers the redirect to re-run.
/// This is the standard go_router + Riverpod pattern.

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final location = state.matchedLocation;

      // Still checking storage — stay on splash
      if (authState is AuthLoading) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      // Not logged in — send to phone input unless already in auth flow
      if (authState is AuthUnauthenticated) {
        final inAuthFlow = location.startsWith('/auth');
        return inAuthFlow ? null : AppRoutes.phoneInput;
      }

      // Logged in — redirect from splash/auth pages to correct home
      if (authState is AuthAuthenticated) {
        final user = authState.user;
        final onSplashOrAuth =
            location == AppRoutes.splash || location.startsWith('/auth');

        if (onSplashOrAuth) {
          if (user.isAdmin) return AppRoutes.adminHome;
          if (user.isDriver) return AppRoutes.driverHome;
          return AppRoutes.passengerHome;
        }
      }

      // No redirect needed
      return null;
    },
    routes: [
      // ── Splash ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.phoneInput,
        builder: (context, state) => const PhoneInputScreen(),
      ),
      GoRoute(
        path: AppRoutes.otpVerify,
        builder: (context, state) {
          // OtpVerifyScreen needs phone + countryCode passed from PhoneInputScreen.
          // go_router passes arbitrary objects via state.extra.
          // We cast it here and fall back to empty strings if somehow missing.
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return OtpVerifyScreen(
            phone: extra['phone'] as String? ?? '',
            countryCode: extra['countryCode'] as String? ?? '+91',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        builder: (context, state) => const ProfileSetupScreen(),
      ),

      // ── Verification (Task 4) ─────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.faceConsent,
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: AppRoutes.faceRegister,
        builder: (context, state) => const FaceRegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.verificationStatus,
        builder: (context, state) => const VerificationStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.preRideFace,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PreRideFaceScreen(
            ridePassengerId: extra['ridePassengerId'] as String? ?? '',
            rideId: extra['rideId'] as String? ?? '',
          );
        },
      ),
      // OTP entry after face check — placeholder until Task 6 (active ride)
      GoRoute(
        path: AppRoutes.otpEntry,
        builder: (context, state) => const _PlaceholderScreen('OTP Entry'),
      ),

      // ── Passenger (Task 5) ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.passengerHome,
        builder: (context, state) => const PassengerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.activeRide,
        builder: (context, state) => ActiveRideScreen(
          rideId: state.pathParameters['rideId'] ?? '',
        ),
      ),

      // ── Driver (Task 8) ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (context, state) => const _PlaceholderScreen('Driver Home'),
      ),

      // ── Admin (Task 10) ───────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (context, state) => const _PlaceholderScreen('Admin Home'),
      ),
    ],

    // Error page — shown if navigation to a non-existent route is attempted
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.matchedLocation}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    ),
  );
});

/// RouterNotifier — bridges Riverpod state changes to go_router.
///
/// go_router's refreshListenable accepts a Listenable.
/// This class listens to authStateProvider and notifies go_router
/// whenever the session state changes, triggering a redirect re-evaluation.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    // Listen to auth state changes and notify go_router
    ref.listen<AuthState>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
  }
}

// ── Screens ───────────────────────────────────────────────────────────────────

/// Splash screen — shown while AuthStateNotifier checks secure storage.
/// Replaced with a branded animation in a later polish pass.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'PinkRide',
              style: TextStyle(
                color: Colors.white,
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: -1.5,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Safe. Verified. Shared.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                letterSpacing: 0.3,
              ),
            ),
            SizedBox(height: 48),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder screen used for routes not yet implemented.
/// Each task replaces these with the real screen.
class _PlaceholderScreen extends StatelessWidget {
  final String name;
  const _PlaceholderScreen(this.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text(
          '$name\n(Coming in a future task)',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
