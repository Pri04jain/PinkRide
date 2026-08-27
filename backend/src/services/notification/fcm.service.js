/**
 * FCM Push Notification Service
 *
 * Token storage: Persisted to `device_tokens` table in Supabase.
 * One user can have multiple active tokens (phone + tablet).
 * Tokens are upserted on every login so they stay current.
 *
 * Push delivery:
 *   dev  → console.log (FIREBASE_PUSH_ENABLED not set or false)
 *   prod → Firebase Admin SDK (FIREBASE_PUSH_ENABLED=true + credentials configured)
 *
 * Firebase credentials — two supported modes (pick one):
 *   1. File path:   FIREBASE_SERVICE_ACCOUNT_PATH=/path/to/serviceAccount.json
 *   2. Inline JSON: FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
 *      (useful on platforms like Railway/Render where you can't mount files)
 */

const { supabase } = require('../../shared/db/client');

// ─── Firebase Admin Init (lazy, singleton) ────────────────────────────────────

let _messagingInstance = null;

const getMessaging = () => {
  if (_messagingInstance) return _messagingInstance;

  const admin = require('firebase-admin');

  // Avoid re-initialising if another module already did it
  if (!admin.apps.length) {
    let credential;

    if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
      // Inline JSON — preferred for cloud deployments
      const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
      credential = admin.credential.cert(serviceAccount);
    } else if (process.env.FIREBASE_SERVICE_ACCOUNT_PATH) {
      // File path — convenient for local dev
      const serviceAccount = require(process.env.FIREBASE_SERVICE_ACCOUNT_PATH);
      credential = admin.credential.cert(serviceAccount);
    } else {
      // Application Default Credentials (GCP / Cloud Run environments)
      credential = admin.credential.applicationDefault();
    }

    admin.initializeApp({ credential });
    console.log('[FCM] Firebase Admin initialised.');
  }

  _messagingInstance = admin.messaging();
  return _messagingInstance;
};

// ─── Device Token Registration ────────────────────────────────────────────────

/**
 * Register (or refresh) an FCM device token for a user.
 * Uses upsert on fcm_token so re-registration is idempotent.
 * Old tokens for the same user on the same platform are marked inactive.
 */
const registerDeviceToken = async (userId, fcmToken, platform = 'android') => {
  // Deactivate stale tokens for this user on the same platform
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
 *
 * Controlled by FIREBASE_PUSH_ENABLED env flag:
 *   false / unset → logs to console (dev mode, no Firebase needed)
 *   true          → sends via Firebase Admin SDK
 *
 * Handles dead tokens: if Firebase returns 'registration-token-not-registered'
 * the token is automatically marked inactive in the DB so we don't keep
 * hitting it on future pushes.
 */
const sendToUser = async (userId, title, body, data = {}) => {
  const pushEnabled = process.env.FIREBASE_PUSH_ENABLED === 'true';

  if (!pushEnabled) {
    console.log(`[FCM DEV] → ${userId}: "${title}" — ${body}`);
    return { sent: true, dev: true };
  }

  const tokens = await getActiveTokens(userId);
  if (!tokens.length) {
    console.warn(`[FCM] No active tokens for user ${userId}`);
    return { sent: false, reason: 'No active device tokens' };
  }

  const messaging = getMessaging();

  const message = {
    tokens,
    notification: { title, body },
    // data values must all be strings for FCM
    data: Object.fromEntries(
      Object.entries(data).map(([k, v]) => [k, String(v)])
    ),
    android: {
      priority: 'high',
      notification: { sound: 'default' },
    },
    apns: {
      payload: {
        aps: { sound: 'default', badge: 1 },
      },
    },
  };

  const response = await messaging.sendEachForMulticast(message);

  // Clean up dead tokens so we don't keep spamming them
  const deadTokens = [];
  response.responses.forEach((resp, idx) => {
    if (
      !resp.success &&
      resp.error?.code === 'messaging/registration-token-not-registered'
    ) {
      deadTokens.push(tokens[idx]);
    }
  });

  if (deadTokens.length) {
    await supabase
      .from('device_tokens')
      .update({ is_active: false })
      .in('fcm_token', deadTokens);
    console.warn(`[FCM] Deactivated ${deadTokens.length} dead token(s) for user ${userId}`);
  }

  return {
    sent: true,
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
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

  newDriverApplication: (adminUserId, driverName) =>
    sendToUser(adminUserId, 'New Driver Application', `${driverName} has submitted all documents and is ready for review.`, { type: 'new_driver_application' }),

  applicationUnderReview: (driverUserId) =>
    sendToUser(driverUserId, 'Application Received', 'All your documents have been submitted. Our team will review your application within 24 hours.', { type: 'application_under_review' }),
};

module.exports = { registerDeviceToken, getActiveTokens, sendToUser, notify };
