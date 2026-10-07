/// All backend API endpoint paths — single source of truth.
/// Import this anywhere we make an HTTP call.
/// Paths are relative to the baseUrl set in ApiClient.

class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String requestOtp    = '/auth/request-otp';
  static const String verifyOtp     = '/auth/verify-otp';
  static const String refreshToken  = '/auth/refresh-token'; // was /auth/refresh
  static const String logout        = '/auth/logout';

  // ── User ──────────────────────────────────────────────────────────────────
  static const String registerUser      = '/users/register';   // POST — new user profile setup
  static const String userProfile       = '/users/profile';    // GET  — fetch current user
  static const String updateProfile     = '/users/profile';    // PATCH — update profile fields
  static const String emergencyContacts = '/users/emergency-contacts';
  static const String walletBalance     = '/users/wallet';

  // ── Driver ────────────────────────────────────────────────────────────────
  static const String driverProfile      = '/drivers/me';
  static const String driverRegister     = '/drivers/register';
  static const String driverAvailability = '/drivers/me/availability';
  static const String driverLocation     = '/drivers/me/location';
  static const String nearbyRides        = '/drivers/me/nearby-rides';
  static const String driverRideRequests = '/drivers/me/nearby-rides';
  static const String acceptRide         = '/drivers/me/accept-ride';

  static String acceptRideById(String rideId) =>
      '/drivers/me/accept-ride/$rideId';

  static String uploadDocument(String docType) =>
      '/drivers/me/documents/$docType';

  // ── Rides ─────────────────────────────────────────────────────────────────
  static const String fareEstimate = '/rides/fare-estimate'; // was /rides/estimate
  static const String bookRide     = '/rides/book';          // was /rides
  static const String activeRide   = '/rides/active';

  static String rideById(String id)   => '/rides/$id';
  static String cancelRide(String id) => '/rides/$id/cancel';

  // ── Verification ──────────────────────────────────────────────────────────
  static const String registerFace   = '/verification/face/register';
  static const String verifyFace     = '/verification/face/verify';
  static const String preRideFace    = '/verification/face/pre-ride';

  // ── Safety ────────────────────────────────────────────────────────────────
  static String triggerSos(String rideId) => '/safety/$rideId/sos';
  static String resolveDeviation(String rideId) =>
      '/safety/$rideId/deviation/resolve';

  // ── Payment ───────────────────────────────────────────────────────────────
  static String createOrder(String rideId)  => '/payments/$rideId/order';
  static String verifyPayment(String rideId) => '/payments/$rideId/verify';
  static String rateRide(String rideId)     => '/payments/$rideId/rate';

  // ── Notifications ─────────────────────────────────────────────────────────
  static const String registerFcmToken = '/notifications/token';

  // ── Admin ──────────────────────────────────────────────────────────────────
  static const String adminDriverQueue     = '/drivers/admin/queue';
  static String adminApproveDriver(String id) => '/drivers/$id/approve';
  static String adminRejectDriver(String id)  => '/drivers/$id/reject';
}
