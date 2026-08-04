const { supabase } = require('../../shared/db/client');
const { otpStore, keys } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');

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

  // If OTP already in memory and valid, return it
  const existing = otpStore.get(keys.rideOtp(rideId));
  if (existing) {
    return { otp: existing, expiresInMinutes: OTP_EXPIRY_MIN, alreadyGenerated: true };
  }

  // Generate a new 6-digit OTP
  const otp = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MIN * 60000).toISOString();

  // Store in DB
  const { error: updateError } = await supabase
    .from('rides')
    .update({ otp, otp_expires_at: expiresAt, status: 'otp_pending' })
    .eq('id', rideId);

  if (updateError) throw new AppError('Failed to generate OTP. Please try again.', 500);

  // Update passenger status to confirmed
  await supabase
    .from('ride_passengers')
    .update({ status: 'confirmed' })
    .eq('ride_id', rideId)
    .eq('passenger_id', passengerId);

  // Store in memory for fast driver lookup
  otpStore.set(keys.rideOtp(rideId), otp, OTP_EXPIRY_MIN * 60);

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

  // Start the trip
  await supabase
    .from('rides')
    .update({ otp_verified: true, status: 'in_progress', started_at: new Date().toISOString() })
    .eq('id', rideId);

  await supabase
    .from('ride_passengers')
    .update({ status: 'boarded', boarded_at: new Date().toISOString() })
    .eq('ride_id', rideId);

  // Clean up OTP from memory
  otpStore.del(keys.rideOtp(rideId));

  return { verified: true, rideId, message: 'Trip started!' };
};

/**
 * Complete a trip (driver marks as done).
 */
const completeRide = async (rideId, driverUserId) => {
  const { data: ride, error } = await supabase
    .from('rides')
    .select('id, status, drivers!inner(user_id)')
    .eq('id', rideId)
    .single();

  if (error || !ride) throw new AppError('Ride not found.', 404);

  if (ride.drivers?.user_id !== driverUserId) throw new AppError('Not your ride.', 403);
  if (ride.status !== 'in_progress') throw new AppError('Ride is not in progress.', 400);

  await supabase
    .from('rides')
    .update({ status: 'completed', ended_at: new Date().toISOString(), payment_status: 'pending' })
    .eq('id', rideId);

  await supabase
    .from('ride_passengers')
    .update({ status: 'dropped', dropped_at: new Date().toISOString() })
    .eq('ride_id', rideId);

  return { completed: true, rideId };
};

module.exports = { generateRideOtp, verifyRideOtp, completeRide };
