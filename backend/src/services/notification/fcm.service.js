/**
 * FCM Push Notification Service
 *
 * Day 1 status: Stubbed out — logs to console in dev.
 * Firebase Admin SDK is removed for now (it required a service account JSON file).
 *
 * Why removed for now?
 * firebase-admin pulls in a large SDK and needs a service account file that
 * doesn't exist yet. For Days 1–7, console logs are fine.
 * We'll wire up real push notifications on Day 9 (safety/notifications day).
 *
 * Upgrade path: Add firebase-admin back, set FIREBASE_SERVICE_ACCOUNT_PATH in .env.
 */

// In-memory token store (per-process, cleared on restart)
// In production, store these in the users table or a device_tokens table in Supabase
const deviceTokens = new Map(); // userId -> fcmToken

const registerDeviceToken = async (userId, fcmToken) => {
  deviceTokens.set(userId, fcmToken);
  return { registered: true };
};

/**
 * Send a push notification to a user.
 * In dev: logs to console.
 * In production (Day 9+): sends via Firebase.
 */
const sendToUser = async (userId, title, body, data = {}) => {
  const isDev = process.env.NODE_ENV !== 'production';

  if (isDev) {
    console.log(`[FCM DEV] → ${userId}: "${title}" — ${body}`);
    return { sent: true, dev: true };
  }

  // Production: wire up Firebase here on Day 9
  console.warn('[FCM] Production push not yet configured.');
  return { sent: false, reason: 'FCM not configured' };
};

/**
 * Pre-built notification templates used across services.
 */
const notify = {
  driverApproved: (userId) =>
    sendToUser(userId, "You're Approved!", 'Your PinkRide driver account is verified. Go online and start accepting rides.', { type: 'driver_approved' }),

  driverRejected: (userId, reason) =>
    sendToUser(userId, 'Application Update', `Your application needs attention: ${reason}`, { type: 'driver_rejected' }),

  rideConfirmed: (userId, driverName, vehicle) =>
    sendToUser(userId, 'Driver Assigned', `${driverName} is on the way in a ${vehicle}`, { type: 'ride_confirmed' }),

  coPassengerFound: (userId, detourMin) =>
    sendToUser(userId, 'Co-passenger Found!', `A match found — adds ~${detourMin} min to your trip. Open app to confirm.`, { type: 'co_passenger_found' }),

  rideOtpReady: (userId, otp) =>
    sendToUser(userId, `Your Ride OTP: ${otp}`, 'Show this to your driver to start the trip.', { type: 'ride_otp', otp }),

  rideCompleted: (userId, fare) =>
    sendToUser(userId, 'Trip Completed', `Fare: ₹${fare}. Please rate your experience.`, { type: 'ride_completed' }),

  sosReceived: (userId) =>
    sendToUser(userId, '🚨 SOS Alert', 'A passenger in your ride has triggered an emergency alert.', { type: 'sos' }),

  fineCharged: (userId, amount, reason) =>
    sendToUser(userId, `Fine Charged: ₹${amount}`, reason, { type: 'fine', amount: String(amount) }),
};

module.exports = { registerDeviceToken, sendToUser, notify };
