// App-wide constants — values that never change at runtime.
// Import this wherever you need them:
//   import 'package:pinkride/core/constants/app_constants.dart';

class AppConstants {
  AppConstants._(); // private constructor — prevents instantiation

  // App info
  static const String appName = 'PinkRide';
  static const String appTagline = 'Safe. Verified. Shared.';
  static const String appVersion = '1.0.0';
  static const String city = 'Jaipur';

  // Secure storage keys — used with flutter_secure_storage
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String userRoleKey = 'user_role';

  // API timeout durations
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // OTP
  static const int otpLength = 6;
  static const int otpResendSeconds = 60;

  // Ride
  static const double cancellationFeeINR = 50.0;
  static const double minWalletBalanceForShared = 50.0;
  static const int driverLocationUpdateSeconds = 5;
  static const int sosCountdownSeconds = 5;

  // Fare display
  static const String currencySymbol = '₹';
}
