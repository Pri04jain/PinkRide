/// App-wide constants — timeouts, limits, keys, config values.
/// All magic numbers live here so they're easy to find and change.

class AppConstants {
  AppConstants._();

  // ── Network timeouts ──────────────────────────────────────────────────────
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 20);

  // ── Secure storage keys ───────────────────────────────────────────────────
  // These are the keys used with flutter_secure_storage.
  // Changing these names will invalidate all stored tokens.
  static const String accessTokenKey  = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey       = 'user_id';

  // ── OTP ───────────────────────────────────────────────────────────────────
  static const int otpLength          = 6;
  static const int otpResendSeconds   = 30; // countdown before "Resend OTP"

  // ── Location ──────────────────────────────────────────────────────────────
  static const double defaultLat = 26.9124;  // Jaipur city centre
  static const double defaultLng = 75.7873;
  static const double defaultZoom = 13.0;

  // ── Ride ──────────────────────────────────────────────────────────────────
  static const int activeRidePollSeconds = 5;

  // ── Pagination ────────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;

  // ── Phone validation ──────────────────────────────────────────────────────
  static const int phoneMinLength = 10;
  static const int phoneMaxLength = 10; // Indian mobile numbers
}
