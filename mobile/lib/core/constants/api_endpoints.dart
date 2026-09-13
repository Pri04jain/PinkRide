// All backend API endpoint paths in one place.
// Using constants prevents typos and makes renaming easy.
// The base URL comes from .env — these are just the paths.

class ApiEndpoints {
  ApiEndpoints._();

  // Auth
  static const String requestOtp = '/auth/request-otp';
  static const String verifyOtp = '/auth/verify-otp';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';

  // User
  static const String register = '/users/register';
  static const String profile = '/users/profile';
  static const String faceConsent = '/users/face-consent';
  static const String emergencyContacts = '/users/emergency-contacts';
  static const String walletTopupOrder = '/users/wallet/topup/order';
  static const String walletTopupVerify = '/users/wallet/topup/verify';

  // Verification
  static const String verificationStatus = '/verification/status';
  static const String verificationValidate = '/verification/register/validate';
  static const String verificationConfirm = '/verification/register/confirm';
  static String verifyForRide(String ridePassengerId) =>
      '/verification/ride/$ridePassengerId';

  // Drivers
  static const String driverRegister = '/drivers/register';
  static const String driverProfile = '/drivers/profile';
  static const String driverAvailability = '/drivers/availability';
  static const String driverLocation = '/drivers/location';
  static const String driverRideRequests = '/drivers/ride-requests';
  static String acceptRide(String rideId) =>
      '/drivers/ride-requests/$rideId/accept';
  static String uploadDocument(String docType) =>
      '/drivers/documents/$docType';

  // Rides
  static const String bookRide = '/rides/book';
  static const String fareEstimate = '/rides/fare-estimate';
  static String rideDetail(String rideId) => '/rides/$rideId';
  static String cancelRide(String rideId) => '/rides/$rideId/cancel';
  static String generateOtp(String rideId) => '/rides/$rideId/otp/generate';
  static String verifyOtpRide(String rideId) => '/rides/$rideId/otp/verify';
  static String completeRide(String rideId) => '/rides/$rideId/complete';
  static String findMatch(String rideId) => '/rides/$rideId/find-match';

  // Tracking
  static String driverLocationTrack(String rideId) =>
      '/tracking/$rideId/location';
  static String rideDeviations(String rideId) =>
      '/tracking/$rideId/deviations';
  static String locationHistory(String rideId) =>
      '/tracking/$rideId/history';

  // Safety
  static String triggerSos(String rideId) => '/safety/sos/$rideId';
  static String acknowledgeDeviation(String deviationId) =>
      '/safety/deviations/$deviationId/respond';

  // Payments
  static const String wallet = '/payments/wallet';
  static String createUpiOrder(String rideId) =>
      '/payments/rides/$rideId/order';
  static String verifyUpiPayment(String rideId) =>
      '/payments/rides/$rideId/verify';
  static String confirmCash(String rideId) =>
      '/payments/rides/$rideId/cash-confirm';
  static const String pendingFines = '/payments/fines';
  static String collectFine(String fineId) =>
      '/payments/fines/$fineId/collect';

  // Ratings
  static String submitRating(String rideId) =>
      '/payments/rides/$rideId/rating';
  static String pendingRatings(String rideId) =>
      '/payments/rides/$rideId/ratings/pending';

  // Notifications
  static const String registerToken = '/notifications/token';

  // Admin
  static const String adminQueue = '/drivers/admin/queue';
  static String adminApprove(String driverId) =>
      '/drivers/admin/$driverId/approve';
  static String adminReject(String driverId) =>
      '/drivers/admin/$driverId/reject';
  static const String adminStats = '/drivers/admin/stats';
}
