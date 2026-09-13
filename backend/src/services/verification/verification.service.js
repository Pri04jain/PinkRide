const { supabase } = require('../../shared/db/client');
const { otpStore } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const {
  detectAndValidateFace,
  indexFace,
  compareFace,
  deleteFace,
  ensureCollection,
} = require('./rekognition.service');

/**
 * Face Verification Service
 *
 * All face operations go through rekognition.service.js which has two modes:
 *   - Mock mode (default in dev): returns success without calling AWS.
 *     Activates when AWS_ACCESS_KEY_ID is missing or set to 'your_aws_access_key'.
 *   - Production mode: calls AWS Rekognition (DetectFaces, IndexFaces,
 *     SearchFacesByImage, DeleteFaces).
 *
 * DPDP Act compliance:
 *   - Explicit consent required before any biometric capture.
 *   - Only the AWS faceId reference is stored — no raw photo, no embedding bytes.
 *   - Users can delete their face data at any time (right to erasure).
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
 * Step 1 — Liveness check.
 * Decodes the base64 image, calls AWS Rekognition DetectFaces (or mock),
 * validates eyes open / no sunglasses / good pose & quality.
 * The raw image buffer is held in otpStore for 60 s until Step 2 confirms.
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

  // Decode base64 → Buffer for Rekognition
  const imageBuffer = Buffer.from(base64Image, 'base64');

  // Liveness + quality check via Rekognition (or mock in dev)
  const detection = await detectAndValidateFace(imageBuffer);

  if (!detection.faceDetected) {
    throw new AppError(detection.reason || 'Face not detected. Please try again.', 422);
  }

  // Keep buffer in memory (60 s TTL) so confirmFaceRegistration can index it
  const tempKey = `face_reg_pending:${userId}`;
  // Store as base64 string (otpStore holds strings, not Buffers)
  otpStore.set(tempKey, base64Image, 60);

  return {
    validated: true,
    livenessScore: detection.livenessScore,
    message: 'Face validated. Confirm to complete registration.',
  };
};

/**
 * Step 2 — Index the face into the Rekognition collection.
 * Stores only the faceId reference string — no raw photo persisted.
 */
const confirmFaceRegistration = async (userId) => {
  const tempKey = `face_reg_pending:${userId}`;
  const base64Image = otpStore.get(tempKey);

  if (!base64Image) {
    throw new AppError('Face validation session expired. Please take a new selfie.', 400);
  }

  // Ensure the Rekognition collection exists (idempotent)
  await ensureCollection();

  const imageBuffer = Buffer.from(base64Image, 'base64');

  // Index face → get back the faceId reference
  const { faceId } = await indexFace(imageBuffer, userId);

  // Persist only the faceId reference (never the raw photo or embedding bytes)
  const { error } = await supabase
    .from('users')
    .update({ face_embedding_ref: faceId, face_verified: true })
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
 * Compares the live selfie against the stored faceId in Rekognition.
 * Up to FACE_VERIFY_MAX_RETRIES attempts; ride is cancelled after that.
 */
const verifyFaceForRide = async (userId, ridePassengerId, base64Image) => {
  const { data: user, error } = await supabase
    .from('users')
    .select('face_verified, face_embedding_ref')
    .eq('id', userId)
    .single();

  if (error || !user) throw new AppError('User not found.', 404);
  if (!user.face_verified || !user.face_embedding_ref) {
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
    // Auto-cancel the ride after too many failed attempts
    await supabase.from('rides')
      .update({ status: 'cancelled' })
      .eq('id',
        (await supabase.from('ride_passengers').select('ride_id').eq('id', ridePassengerId).single())
          .data?.ride_id
      );
    throw new AppError('Face verification failed after 5 attempts. Ride has been cancelled.', 403);
  }

  if (!base64Image) throw new AppError('Image data is required.', 400);

  const imageBuffer = Buffer.from(base64Image, 'base64');

  // Compare live selfie against the stored faceId
  const result = await compareFace(imageBuffer, user.face_embedding_ref);

  if (!result.matched) {
    // Increment attempt counter
    await supabase
      .from('ride_passengers')
      .update({ face_verify_attempts: rp.face_verify_attempts + 1 })
      .eq('id', ridePassengerId);

    const attemptsLeft = FACE_VERIFY_MAX_RETRIES - (rp.face_verify_attempts + 1);
    throw new AppError(
      `Face verification failed. ${attemptsLeft > 0 ? `${attemptsLeft} attempt(s) remaining.` : 'No attempts remaining.'}`,
      422
    );
  }

  // Success — mark face verified for this ride leg
  await supabase
    .from('ride_passengers')
    .update({
      face_verified_at: new Date().toISOString(),
      face_verify_attempts: rp.face_verify_attempts + 1,
    })
    .eq('id', ridePassengerId);

  return {
    verified: true,
    similarity: result.similarity,
    message: 'Identity verified. You can now start your ride.',
  };
};

// ─── Get Verification Status ──────────────────────────────────────────────────

const getVerificationStatus = async (userId) => {
  const { data: user, error } = await supabase
    .from('users')
    .select('face_verified, face_consent_given, face_consent_given_at')
    .eq('id', userId)
    .single();

  if (error || !user) throw new AppError('User not found.', 404);

  return {
    faceVerified: user.face_verified,
    consentGiven: user.face_consent_given,
    consentGivenAt: user.face_consent_given_at,
  };
};

// ─── Delete Face Data (DPDP right to erasure) ─────────────────────────────────

const deleteFaceData = async (userId) => {
  // Get the stored faceId reference before wiping it
  const { data: user } = await supabase
    .from('users')
    .select('face_embedding_ref')
    .eq('id', userId)
    .single();

  // Delete from Rekognition collection if a real faceId is stored
  if (user?.face_embedding_ref && !user.face_embedding_ref.startsWith('mock-face-')) {
    await deleteFace(user.face_embedding_ref).catch((err) => {
      // Log but don't block erasure if Rekognition call fails
      console.error('[Face] Rekognition delete failed:', err.message);
    });
  }

  // Wipe all face fields from DB
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
  getVerificationStatus,
  deleteFaceData,
};
