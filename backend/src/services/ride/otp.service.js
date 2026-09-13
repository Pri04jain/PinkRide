const crypto = require('crypto');
const { supabase } = require('../../shared/db/client');
const { otpStore, keys } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const { notify } = require('../notification/fcm.service');
const { clearRideCache } = require('../tracking/tracking.service');

const OTP_EXPIRY_MIN = 15;

/**
 * Generate ride OTP after passenger face verification passes.
 * Stores OTP in memory (fast lookup) and in DB (audit trail).
 * Passenger shows this OTP to the driver.
 */
const generateRideOtp = async (rideId, passengerId) => {
  // Confirm face verification is done for this passenger
  const { data: rp, error } = await supabase
    .from('ride_passengers')
    .select('id, face_verified_at, status, rides(status, otp)')
    .eq('ride_id', rideId)
    .eq('passenger_id', passengerId)
    .single();

  if (error || !rp) throw new AppError('Ride booking not found.', 404);

  if (!rp.face_verified_at) {
    throw new AppError('Face verification is required before generating ride OTP.', 403);
  }

  const rideStatus = rp.rides?.status;
  if (['completed', 'cancelled'].includes(rideStatus)) {
    throw new AppError('This ride is no longer active.', 400);
  }

  // If OTP already in memory and valid, return it (idempotent)
  const existing = otpStore.get(keys.rideOtp(rideId));
  if (existing) {
    return { otp: existing, expiresInMinutes: OTP_EXPIRY_MIN, alreadyGenerated: true };
  }

  // ── F5: cryptographically secure OTP (was Math.random()) ──────────────────
  const otp = crypto.randomInt(100000, 1000000).toString();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MIN * 60000).toISOString();

  // Parallel: update ride status + update passenger status simultaneously
  const [rideUpdate] = await Promise.all([
    supabase
      .from('rides')
      .update({ otp, otp_expires_at: expiresAt, status: 'otp_pending' })
      .eq('id', rideId),
    supabase
      .from('ride_passengers')
      .update({ status: 'confirmed' })
      .eq('ride_id', rideId)
      .eq('passenger_id', passengerId),
  ]);

  if (rideUpdate.error) throw new AppError('Failed to generate OTP. Please try again.', 500);

  // Store in memory for fast driver lookup
  otpStore.set(keys.rideOtp(rideId), otp, OTP_EXPIRY_MIN * 60);

  // Push the OTP to the passenger's device (fire-and-forget)
  notify.rideOtpReady(passengerId, otp).catch((err) =>
    console.error('[OTP] Push notification failed:', err.message)
  );

  return { otp, expiresInMinutes: OTP_EXPIRY_MIN };
};

/**
 * Driver enters OTP to start the trip.
 */
const verifyRideOtp = async (rideId, driverUserId, enteredOtp) => {
  // Get ride + confirm this driver is assigned
  const { data: ride, error } = await supabase
    .from('rides')
    .select('id, otp, otp_expires_at, otp_verified, status, drivers!inner(user_id)')
    .eq('id', rideId)
    .single();

  if (error || !ride) throw new AppError('Ride not found.', 404);

  if (ride.drivers?.user_id !== driverUserId) {
    throw new AppError('You are not assigned to this ride.', 403);
  }

  if (ride.otp_verified) {
    throw new AppError('OTP already verified. Trip is in progress.', 400);
  }

  if (ride.status === 'cancelled') {
    throw new AppError('This ride has been cancelled.', 400);
  }

  if (new Date(ride.otp_expires_at) < new Date()) {
    throw new AppError('OTP has expired. Please ask the passenger to generate a new one.', 400);
  }

  // Check memory first (faster), fall back to DB value
  const cachedOtp = otpStore.get(keys.rideOtp(rideId));
  const validOtp = cachedOtp || ride.otp;

  if (enteredOtp !== validOtp) {
    throw new AppError("Incorrect OTP. Please check the code shown on the passenger's app.", 400);
  }

  // Start the trip — parallel: ride update + passenger boarded update
  const now = new Date().toISOString();
  await Promise.all([
    supabase
      .from('rides')
      .update({ otp_verified: true, status: 'in_progress', started_at: now })
      .eq('id', rideId),
    supabase
      .from('ride_passengers')
      .update({ status: 'boarded', boarded_at: now })
      .eq('ride_id', rideId),
  ]);

  // Clean up OTP from memory
  otpStore.del(keys.rideOtp(rideId));

  return { verified: true, rideId, message: 'Trip started!' };
};

/**
 * Complete a trip (driver marks as done).
 *
 * O5 optimisation — was 3 sequential DB writes.
 * Now: 4 operations fire in parallel via Promise.all, then push notifications
 * fire fire-and-forget. Total wall time ≈ single slowest operation instead
 * of sum of all operations.
 *
 * F7 fix: increments users.total_rides and drivers.total_trips which were
 * always 0 before. These feed the cancellation-rate penalty in reliability scoring.
 */
const completeRide = async (rideId, driverUserId) => {
  const { data: ride, error } = await supabase
    .from('rides')
    .select('id, status, driver_id, drivers!inner(id, user_id), ride_passengers(passenger_id, total_fare)')
    .eq('id', rideId)
    .single();

  if (error || !ride) throw new AppError('Ride not found.', 404);
  if (ride.drivers?.user_id !== driverUserId) throw new AppError('Not your ride.', 403);
  if (ride.status !== 'in_progress') throw new AppError('Ride is not in progress.', 400);

  const now = new Date().toISOString();
  const passengers = ride.ride_passengers || [];
  const passengerIds = passengers.map((rp) => rp.passenger_id);
  const driverRowId = ride.drivers?.id;

  // ── O5: all DB updates fire in parallel ───────────────────────────────────
  await Promise.all([
    // Mark ride completed
    supabase
      .from('rides')
      .update({ status: 'completed', ended_at: now, payment_status: 'pending' })
      .eq('id', rideId),

    // Mark all passengers dropped
    supabase
      .from('ride_passengers')
      .update({ status: 'dropped', dropped_at: now })
      .eq('ride_id', rideId),

    // F7: increment total_rides for each passenger
    // Uses a custom Postgres function defined in schema.sql to avoid N+1
    // and prevent race conditions from read-modify-write in JS.
    ...(passengerIds.length > 0 ? [
      supabase.rpc('increment_user_total_rides', { p_user_ids: passengerIds }),
    ] : []),

    // F7: increment total_trips for the driver
    ...(driverRowId ? [
      supabase.rpc('increment_driver_total_trips', { p_driver_id: driverRowId }),
    ] : []),
  ]);

  // Push notifications fire-and-forget — never block the response
  Promise.allSettled(
    passengers.map((rp) =>
      notify.rideCompleted(rp.passenger_id, rp.total_fare)
    )
  );

  // F9: evict location cache for this ride
  clearRideCache(rideId);

  return { completed: true, rideId };
};

module.exports = { generateRideOtp, verifyRideOtp, completeRide };
