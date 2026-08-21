/**
 * FCM Push Notification Service
 *
 * Token storage: Persisted to `device_tokens` table in Supabase.
 * One user can have multiple active tokens (phone + tablet).
 * Tokens are upserted on every login so they stay current.
 *
 * Push delivery:
 *   dev  → console.log (no Firebase SDK needed)
 *   prod → wire up firebase-admin here on Day 9
 *          (set FIREBASE_SERVICE_ACCOUNT_PATH in .env, npm i firebase-admin)
 */

const { supabase } = require('../../shared/db/client');

// ─── Device Token Registration ────────────────────────────────────────────────

/**
 * Register (or refresh) an FCM device token for a user.
 * Uses upsert on fcm_token so re-registration is idempotent.
 * Old tokens for the same user on the same platform are marked inactive.
 */
const registerDeviceToken = async (userId, fcmToken, platform = 'android') => {
  // Deactivate stale tokens for this user on the same platform
  // so we don't spam dead tokens when pushing
  await supabase
    .from('device_tokens')
    .update({ is_active: false })
    .eq('user_id', userId)
    .eq('platform', platform)
    .neq('fcm_token', fcmToken);

  // Upsert the current token — conflict on the unique fcm_token column
  const { error } = await supabase
    .from('device_tokens')
    .upsert(
      { user_id: userId, fcm_token: fcmToken, platform, is_active: true },
      { onConflict: 'fcm_token' }
    );

  if (error) {
    console.error('[FCM] Failed to save device token:', error.message);
    // Don't throw — a failed token save shouldn't break the caller (e.g. login)
  }

  return { registered: true };
};

/**
 * Get all active FCM tokens for a user (may have multiple devices).
 */
const getActiveTokens = async (userId) => {
  const { data } = await supabase
    .from('device_tokens')
    .select('fcm_token, platform')
    .eq('user_id', userId)
    .eq('is_active', true);

  return (data || []).map((row) => row.fcm_token);
};

// ─── Send Push Notification ───────────────────────────────────────────────────

/**
 * Send a push notification to all active devices for a user.
 * dev:  logs to console, returns { sent: true, dev: true }
 * prod: wire up firebase-admin here on Day 9
 */
const sendToUser = async (userId, title, body, data = {}) => {
  const isDev = process.env.NODE_ENV !== 'production';

  if (isDev) {
    console.log(`[FCM DEV] → ${userId}: "${title}" — ${body}`);
    return { sent: true, dev: true };
  }

  // Production path — fetch tokens from DB and send via Firebase
  const tokens = await getActiveTokens(userId);
  if (!tokens.length) {
    console.warn(`[FCM] No active tokens for user ${userId}`);
    return { sent: false, reason: 'No active device tokens' };
  }

  // TODO Day 9: Replace with real Firebase Admin SDK calls
  // const { getMessaging } = require('firebase-admin/messaging');
  // await getMessaging().sendEachForMulticast({ tokens, notification: { title, body }, data });

  console.warn('[FCM] Production push not yet configured.');
  return { sent: false, reason: 'FCM not configured' };
};

// ─── Notification Templates ───────────────────────────────────────────────────

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

  newRideRequest: (driverUserId, pickupAddress, fareAmount) =>
    sendToUser(driverUserId, 'New Ride Request', `Pickup: ${pickupAddress} — ₹${fareAmount}`, { type: 'new_ride_request' }),
};

module.exports = { registerDeviceToken, getActiveTokens, sendToUser, notify };
