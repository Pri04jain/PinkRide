import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../providers/auth_state.dart';
import '../theme/app_theme.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/photo_capture_screen.dart';
import '../../features/auth/screens/registration_details_screen.dart';
import '../../features/verification/screens/consent_screen.dart';
import '../../features/verification/screens/face_register_screen.dart';
import '../../features/verification/screens/pre_ride_face_screen.dart';
import '../../features/verification/screens/verification_status_screen.dart';
import '../../features/ride/screens/passenger_home_screen.dart';
import '../../features/ride/screens/active_ride_screen.dart';
import '../../features/ride/screens/otp_entry_screen.dart';
import '../../features/safety/screens/emergency_contacts_screen.dart';
import '../../features/safety/screens/sos_screen.dart';
import '../../features/payment/screens/payment_screen.dart';
import '../../features/payment/screens/rating_screen.dart';
import '../../features/payment/screens/wallet_screen.dart';
import '../../features/admin/screens/driver_queue_screen.dart';
import '../../features/admin/screens/driver_detail_screen.dart';
import '../../features/admin/admin_service.dart';
import '../../features/driver/screens/driver_home_screen.dart';
import '../../features/driver/screens/driver_register_screen.dart';
import '../../features/driver/screens/driver_status_screen.dart';

/// Route path constants — single source of truth for all navigation.
class AppRoutes {
  AppRoutes._();

  // ── Auth / Onboarding ─────────────────────────────────────────────────────
  static const String splash               = '/';
  static const String welcome              = '/welcome';         // landing page
  static const String login                = '/auth/login';      // returning users
  static const String signUp               = '/auth/signup';     // new users
  // Legacy routes kept for back-compat
  static const String phoneInput           = '/auth/phone';
  static const String otpVerify            = '/auth/otp';
  static const String photoCapture         = '/auth/photo';
  static const String registrationDetails  = '/auth/register';
  static const String profileSetup         = '/auth/profile';

  // ── Face verification ─────────────────────────────────────────────────────
  static const String faceConsent       = '/verification/consent';
  static const String faceRegister      = '/verification/register';
  static const String verificationStatus = '/verification/status';
  static const String preRideFace       = '/verification/ride-face';

  // ── Ride ──────────────────────────────────────────────────────────────────
  static const String otpEntry     = '/ride/otp';
  static const String passengerHome = '/passenger/home';
  static const String bookRide     = '/passenger/book';
  static const String activeRide   = '/passenger/ride/:rideId';

  // ── Driver ────────────────────────────────────────────────────────────────
  static const String driverHome     = '/driver/home';
  static const String driverRegister = '/driver/register';
  static const String driverStatus   = '/driver/status';

  // ── Safety ────────────────────────────────────────────────────────────────
  static const String sos               = '/safety/sos';
  static const String emergencyContacts = '/safety/contacts';

  // ── Ride OTP (driver entry + passenger display) ───────────────────────────
  static const String rideOtpDisplay = '/ride/otp-display';

  // ── Payment ───────────────────────────────────────────────────────────────
  static const String payment = '/payment/:rideId';
  static const String rating  = '/rating/:rideId';
  static const String wallet  = '/wallet';

  // ── Admin ──────────────────────────────────────────────────────────────────
  static const String adminHome        = '/admin/home';
  static const String adminDriverDetail = '/admin/driver/:driverId';
}

/// Router provider — GoRouter wired to AuthState via RouterNotifier.
///
/// REDIRECT LOGIC:
///   AuthLoading        → splash (wait)
///   AuthUnauthenticated → /auth/phone (unless already in /auth/*)
///   AuthAuthenticated + incomplete profile
///                      → /auth/photo  (new user onboarding, unless already in /auth/*)
///   AuthAuthenticated + complete profile + on splash/auth
///                      → role home screen

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final location  = state.matchedLocation;

      // ── Still loading ──────────────────────────────────────────────────────
      if (authState is AuthLoading) {
        return location == AppRoutes.splash ? null : AppRoutes.splash;
      }

      // ── Not logged in ──────────────────────────────────────────────────────
      // Allow any /auth/* route (login, signup, photo, register).
      // Splash / everything else → welcome screen.
      if (authState is AuthUnauthenticated) {
        if (location.startsWith('/auth') || location == AppRoutes.welcome) {
          return null;
        }
        return AppRoutes.welcome;
      }

      // ── Logged in ──────────────────────────────────────────────────────────
      if (authState is AuthAuthenticated) {
        final user = authState.user;

        final profileIncomplete =
            (user.fullName == null || user.fullName!.trim().isEmpty) ||
            user.role == UserRole.unknown;

        if (profileIncomplete) {
          // Mid-onboarding — allow /auth/* so photo+register screens work
          return location.startsWith('/auth') ? null : AppRoutes.photoCapture;
        }

        // Profile complete — leave feature screens alone, redirect away from auth/splash
        final onSplashOrWelcomeOrAuth =
            location == AppRoutes.splash ||
            location == AppRoutes.welcome ||
            location.startsWith('/auth');

        if (onSplashOrWelcomeOrAuth) {
          if (user.isAdmin) return AppRoutes.adminHome;
          if (user.isDriver) return AppRoutes.driverHome;
          return AppRoutes.passengerHome;
        }
      }

      return null;
    },
    routes: [
      // ── Splash (loading state only) ──────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const SplashScreen(),
      ),

      // ── Welcome ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),

      // ── Login (returning users) ───────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (_, __) => const LoginScreen(),
      ),

      // ── Sign Up (new users) ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.signUp,
        builder: (_, __) => const SignUpScreen(),
      ),

      // ── New-user onboarding ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.photoCapture,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PhotoCaptureScreen(phone: extra['phone'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.registrationDetails,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return RegistrationDetailsScreen(phone: extra['phone'] as String? ?? '');
        },
      ),
      // Legacy redirects
      GoRoute(path: AppRoutes.phoneInput,  redirect: (_, __) => AppRoutes.welcome),
      GoRoute(path: AppRoutes.otpVerify,   redirect: (_, __) => AppRoutes.welcome),
      GoRoute(path: AppRoutes.profileSetup, redirect: (_, __) => AppRoutes.signUp),

      // ── Verification ──────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.faceConsent,
        builder: (_, __) => const ConsentScreen(),
      ),
      GoRoute(
        path: AppRoutes.faceRegister,
        builder: (_, __) => const FaceRegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.verificationStatus,
        builder: (_, __) => const VerificationStatusScreen(),
      ),
      GoRoute(
        path: AppRoutes.preRideFace,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PreRideFaceScreen(
            ridePassengerId: extra['ridePassengerId'] as String? ?? '',
            rideId:          extra['rideId']          as String? ?? '',
          );
        },
      ),
      // OTP entry — driver enters the passenger's OTP to start the trip
      GoRoute(
        path: AppRoutes.otpEntry,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final rideId = extra['rideId'] as String? ?? '';
          return OtpEntryScreen(rideId: rideId);
        },
      ),

      // OTP display — passenger sees the OTP after face check
      GoRoute(
        path: AppRoutes.rideOtpDisplay,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return RideOtpDisplayScreen(
            ridePassengerId: extra['ridePassengerId'] as String? ?? '',
            rideId:          extra['rideId']          as String? ?? '',
            otp:             extra['otp']              as String? ?? '------',
          );
        },
      ),

      // ── Passenger ─────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.passengerHome,
        builder: (_, __) => const PassengerHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.activeRide,
        builder: (_, state) => ActiveRideScreen(
          rideId: state.pathParameters['rideId'] ?? '',
        ),
      ),

      // ── Safety ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.sos,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return SosScreen(rideId: extra['rideId'] as String? ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.emergencyContacts,
        builder: (_, __) => const EmergencyContactsScreen(),
      ),

      // ── Payment ───────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.payment,
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return PaymentScreen(
            rideId:        state.pathParameters['rideId'] ?? '',
            paymentMethod: extra['paymentMethod'] as String? ?? 'cash',
            amount:        (extra['amount'] as num?)?.toDouble() ?? 0,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.rating,
        builder: (_, state) => RatingScreen(
          rideId: state.pathParameters['rideId'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.wallet,
        builder: (_, __) => const WalletScreen(),
      ),

      // ── Driver ────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.driverHome,
        builder: (_, __) => const DriverHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverRegister,
        builder: (_, __) => const DriverRegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.driverStatus,
        builder: (_, __) => const DriverStatusScreen(),
      ),

      // ── Admin ──────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.adminHome,
        builder: (_, __) => const DriverQueueScreen(),
      ),
      GoRoute(
        path: AppRoutes.adminDriverDetail,
        builder: (_, state) {
          final driver = state.extra as DriverQueueItem?;
          return driver != null
              ? DriverDetailScreen(driver: driver)
              : const _PlaceholderScreen('Driver Detail');
        },
      ),
    ],

    errorBuilder: (_, state) => Scaffold(
      body: Center(
        child: Text(
          'Page not found: ${state.matchedLocation}',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ),
    ),
  );
});

/// Bridges Riverpod auth state changes → GoRouter redirect re-evaluation.
class RouterNotifier extends ChangeNotifier {
  RouterNotifier(Ref ref) {
    ref.listen<AuthState>(authStateProvider, (_, __) => notifyListeners());
  }
}

// ── Splash screen ─────────────────────────────────────────────────────────────
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

/// Placeholder for routes not yet fully implemented.
class _PlaceholderScreen extends StatelessWidget {
  final String name;
  const _PlaceholderScreen(this.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text(
          '$name\n(Coming soon)',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
      ),
    );
  }
}
