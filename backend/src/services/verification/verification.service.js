const { supabase } = require('../../shared/db/client');
const { otpStore } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');

/**
 * Face Verification Service
 *
 * Day 1 status: Stubbed — all face checks return success in dev.
 * This is intentional so the rest of the app (ride flow, OTP, payments)
 * can be built and tested without needing a face recognition service.
 *
 * Day 3 plan: Integrate face-api.js for browser-based face detection.
 * Why face-api.js over AWS Rekognition?
 *   - Free (runs in Node.js or browser, no API cost)
 *   - No AWS account needed
 *   - Good enough accuracy for MVP
 * Upgrade path: Swap to AWS Rekognition or Azure Face API if accuracy
 * needs to improve for production.
 */

const FACE_VERIFY_MAX_RETRIES = parseInt(process.env.FACE_VERIFY_MAX_RETRIES) || 5;

// ─── Consent ──────────────────────────────────────────────────────────────────

const recordConsent = async (userId) => {
  const { error } = await supabase
    .from('users')
    .update({ face_consent_given: true, face_consent_given_at: new Date().toISOString() })
    .eq('id', userId);

  if (error) throw new AppError('Failed to record consent.', 500);
  return { consentRecorded: true };
};

// ─── Registration Face Verification ──────────────────────────────────────────

/**
 * Step 1: Validate the selfie (liveness check).
 * Day 1: always passes in dev. Day 3: wire up face-api.js here.
 */
const validateFaceForRegistration = async (userId, base64Image) => {
  const { data: user, error } = await supabase
    .from('users')
    .select('face_consent_given, face_verified')
    .eq('id', userId)
    .single();

  if (error || !user) throw new AppError('User not found.', 404);
  if (!user.face_consent_given) throw new AppError('Face verification consent is required.', 403);
  if (user.face_verified) throw new AppError('Face already registered for this account.', 409);

  if (!base64Image) throw new AppError('Image data is required.', 400);

  // Store image temporarily (60s TTL) for the confirm step
  const tempKey = `face_reg_pending:${userId}`;
  otpStore.set(tempKey, base64Image, 60);

  return {
    validated: true,
    livenessScore: 99, // placeholder until face-api.js is integrated on Day 3
    message: 'Face validated. Confirm to complete registration.',
  };
};

/**
 * Step 2: Confirm registration — store face reference in DB.
 * Day 1: stores a placeholder reference.
 * Day 3: will store a real face embedding ID.
 */
const confirmFaceRegistration = async (userId) => {
  const tempKey = `face_reg_pending:${userId}`;
  const base64Image = otpStore.get(tempKey);

  if (!base64Image) {
    throw new AppError('Face validation session expired. Please take a new selfie.', 400);
  }

  // Day 3: replace this with real face-api.js embedding/ID
  const placeholderFaceRef = `face_ref:${userId}:${Date.now()}`;

  const { error } = await supabase
    .from('users')
    .update({ face_embedding_ref: placeholderFaceRef, face_verified: true })
    .eq('id', userId);

  if (error) throw new AppError('Failed to save face registration.', 500);

  otpStore.del(tempKey);

  return {
    registered: true,
    message: 'Face registered successfully. Your account is now verified.',
  };
};

// ─── Pre-Ride Face Verification ───────────────────────────────────────────────

/**
 * Verify passenger identity before a ride starts.
 * Day 1: always passes in dev.
 * Day 3: will compare live selfie against stored embedding.
 */
const verifyFaceForRide = async (userId, ridePassengerId, base64Image) => {
  const { data: user, error } = await supabase
    .from('users')
    .select('face_verified')
    .eq('id', userId)
    .single();

  if (error || !user) throw new AppError('User not found.', 404);
  if (!user.face_verified) {
    throw new AppError('Face not registered. Please complete face verification in your profile.', 403);
  }

  const { data: rp, error: rpError } = await supabase
    .from('ride_passengers')
    .select('face_verify_attempts, status')
    .eq('id', ridePassengerId)
    .eq('passenger_id', userId)
    .single();

  if (rpError || !rp) throw new AppError('Ride booking not found.', 404);
  if (rp.status === 'cancelled') throw new AppError('This ride has been cancelled.', 400);

  if (rp.face_verify_attempts >= FACE_VERIFY_MAX_RETRIES) {
    throw new AppError('Face verification failed after 5 attempts. Ride has been cancelled.', 403);
  }

  // Day 3: replace with real face comparison here
  const verified = true; // Always passes in dev

  if (!verified) {
    await supabase
      .from('ride_passengers')
      .update({ face_verify_attempts: rp.face_verify_attempts + 1 })
      .eq('id', ridePassengerId);
    throw new AppError('Face verification failed. Please try again.', 422);
  }

  // Mark verified
  await supabase
    .from('ride_passengers')
    .update({
      face_verified_at: new Date().toISOString(),
      face_verify_attempts: rp.face_verify_attempts + 1,
    })
    .eq('id', ridePassengerId);

  return {
    verified: true,
    message: 'Identity verified. You can now start your ride.',
  };
};

// ─── Delete Face Data (DPDP right to erasure) ─────────────────────────────────

const deleteFaceData = async (userId) => {
  const { error } = await supabase
    .from('users')
    .update({
      face_embedding_ref: null,
      face_verified: false,
      face_consent_given: false,
      face_consent_given_at: null,
    })
    .eq('id', userId);

  if (error) throw new AppError('Failed to delete face data.', 500);

  return { deleted: true, message: 'Face data removed from all systems.' };
};

module.exports = {
  recordConsent,
  validateFaceForRegistration,
  confirmFaceRegistration,
  verifyFaceForRide,
  deleteFaceData,
};
