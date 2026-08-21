const { supabase } = require('../../shared/db/client');
const { otpStore } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const { calculatePrivateFare, calculateSharedFare, estimateFare } = require('./fare.calculator');
const {
  findCompatiblePassengers,
  estimateDetourMinutes,
  storePendingMatch,
  deletePendingMatch,
  MATCH_WINDOW_MIN,
} = require('./matching.engine');

const CANCELLATION_FEE   = parseFloat(process.env.CANCELLATION_FEE_INR) || 50;
const DRIVER_FINE        = parseFloat(process.env.DRIVER_CANCELLATION_FINE_INR) || 150;
const RESPONSE_DEADLINE  = parseInt(process.env.RIDE_MATCH_RESPONSE_DEADLINE_MINUTES) || 10;

// ─── Book Ride ────────────────────────────────────────────────────────────────

const bookRide = async (passengerId, bookingData) => {
  const {
    rideType,
    pickupLat, pickupLng, pickupAddress,
    dropLat, dropLng, dropAddress,
    scheduledAt,
    paymentMethod = 'cash',
    distanceKm,
    durationMin,
  } = bookingData;

  const { data: user, error: userError } = await supabase
    .from('users')
    .select('id, role, wallet_balance, city')
    .eq('id', passengerId)
    .eq('is_active', true)
    .single();

  if (userError || !user) throw new AppError('User not found.', 404);
  if (user.role !== 'passenger') throw new AppError('Only passengers can book rides.', 403);

  const isShared = rideType !== 'private';
  if (isShared && parseFloat(user.wallet_balance) < CANCELLATION_FEE) {
    throw new AppError(
      `Shared rides require a minimum wallet balance of ₹${CANCELLATION_FEE}. Please top up your wallet.`,
      400
    );
  }

  const fare = calculatePrivateFare(distanceKm, durationMin);
  const scheduledTime = new Date(scheduledAt).toISOString();

  // Create ride
  const { data: ride, error: rideError } = await supabase
    .from('rides')
    .insert({
      ride_type: rideType,
      status: 'searching',
      pickup_lat: pickupLat,
      pickup_lng: pickupLng,
      pickup_address: pickupAddress,
      drop_lat: dropLat,
      drop_lng: dropLng,
      drop_address: dropAddress,
      scheduled_at: scheduledTime,
      total_distance_km: distanceKm,
      base_fare: fare.subtotal,
      platform_fee: fare.platformFee,
      final_fare: fare.totalFare,
      payment_method: paymentMethod,
      max_passengers: isShared ? 2 : 1,
      city: user.city,
    })
    .select('id')
    .single();

  if (rideError) throw new AppError('Failed to create ride. Please try again.', 500);

  // Create ride_passengers record
  const { error: rpError } = await supabase
    .from('ride_passengers')
    .insert({
      ride_id: ride.id,
      passenger_id: passengerId,
      boarding_address: pickupAddress,
      drop_address: dropAddress,
      segment_fare: fare.subtotal,
      platform_fee: fare.platformFee,
      total_fare: fare.totalFare,
      status: 'pending',
      original_scheduled_at: scheduledTime,
    });

  if (rpError) {
    // Clean up orphan ride
    await supabase.from('rides').delete().eq('id', ride.id);
    throw new AppError('Failed to create ride booking. Please try again.', 500);
  }

  return {
    rideId: ride.id,
    rideType,
    status: 'searching',
    pickupAddress,
    dropAddress,
    scheduledAt: scheduledTime,
    fare: {
      subtotal: fare.subtotal,
      platformFee: fare.platformFee,
      totalFare: fare.totalFare,
    },
    distanceKm,
    message: isShared
      ? `Ride booked. Looking for a co-passenger within ${MATCH_WINDOW_MIN} minutes.`
      : 'Private ride booked. Looking for a driver.',
  };
};

// ─── Find Match ───────────────────────────────────────────────────────────────

const findMatch = async (rideId) => {
  const matches = await findCompatiblePassengers(rideId);
  if (!matches.length) return { matched: false, message: 'No compatible passengers found yet.' };

  const best = matches[0];
  const extraMin = estimateDetourMinutes(best.pickupDetourKm);

  storePendingMatch(rideId, best.ridePassengerId, {
    ...best,
    extraMinutes: extraMin,
    expiresAt: new Date(Date.now() + RESPONSE_DEADLINE * 60000).toISOString(),
  });

  return {
    matched: true,
    candidate: {
      ridePassengerId: best.ridePassengerId,
      pickupDetourKm: best.pickupDetourKm,
      extraMinutes: extraMin,
      scheduledAt: best.scheduledAt,
    },
    responseDeadlineMinutes: RESPONSE_DEADLINE,
    message: `Co-passenger found! Detour adds ~${extraMin} minute(s). Confirm to proceed.`,
  };
};

// ─── Accept / Reject Match ────────────────────────────────────────────────────

const respondToMatch = async (rideId, ridePassengerId, passengerId, accept) => {
  const matchData = getPendingMatchData(rideId, ridePassengerId);
  if (!matchData) throw new AppError('Match offer expired or not found.', 404);

  if (!accept) {
    const { data: rp } = await supabase
      .from('ride_passengers')
      .select('rejection_count')
      .eq('id', ridePassengerId)
      .single();

    const newCount = (rp?.rejection_count || 0) + 1;

    await supabase
      .from('ride_passengers')
      .update({ rejection_count: newCount })
      .eq('id', ridePassengerId);

    const maxRejections = parseInt(process.env.CO_PASSENGER_MAX_REJECTIONS) || 2;
    if (newCount >= maxRejections) {
      await supabase
        .from('rides')
        .update({ ride_type: 'private', max_passengers: 1 })
        .eq('id', rideId);
      await supabase
        .from('ride_passengers')
        .update({ auto_upgraded_private: true })
        .eq('ride_id', rideId);
    }

    deletePendingMatch(rideId, ridePassengerId);
    return { accepted: false, message: 'Match declined.' };
  }

  // Accept — merge both passengers into one ride
  // Get anchor ride details for fare calc
  const { data: anchorRide } = await supabase
    .from('rides')
    .select('total_distance_km, pickup_lat, pickup_lng, drop_lat, drop_lng')
    .eq('id', rideId)
    .single();

  const { data: candidateRp } = await supabase
    .from('ride_passengers')
    .select('ride_id, drop_lat, drop_lng')
    .eq('id', ridePassengerId)
    .single();

  const totalKm = parseFloat(anchorRide?.total_distance_km || 10);
  const sharedKm = Math.max(totalKm * 0.5, 1); // simplified: assume 50% shared
  const fares = calculateSharedFare(totalKm, sharedKm);

  // Update anchor ride status
  await supabase
    .from('rides')
    .update({ status: 'matching', max_passengers: 2 })
    .eq('id', rideId);

  // Update anchor passenger fare
  await supabase
    .from('ride_passengers')
    .update({
      exclusive_distance_km: fares.passengerA.exclusiveDistanceKm,
      shared_distance_km: fares.passengerA.sharedDistanceKm,
      segment_fare: fares.passengerA.exclusiveFare + fares.passengerA.sharedFare,
      platform_fee: fares.passengerA.platformFee,
      total_fare: fares.passengerA.totalFare,
      time_shift_accepted: true,
      status: 'confirmed',
    })
    .eq('ride_id', rideId)
    .eq('passenger_id', passengerId);

  // Move candidate passenger into this ride
  await supabase
    .from('ride_passengers')
    .update({
      ride_id: rideId,
      shared_distance_km: fares.passengerB.sharedDistanceKm,
      segment_fare: fares.passengerB.sharedFare,
      platform_fee: fares.passengerB.platformFee,
      total_fare: fares.passengerB.totalFare,
      status: 'confirmed',
      time_shift_accepted: true,
    })
    .eq('id', ridePassengerId);

  // Cancel the candidate's original solo ride
  if (candidateRp?.ride_id && candidateRp.ride_id !== rideId) {
    await supabase
      .from('rides')
      .update({ status: 'cancelled' })
      .eq('id', candidateRp.ride_id);
  }

  deletePendingMatch(rideId, ridePassengerId);

  return {
    accepted: true,
    rideId,
    fares: {
      yourFare: fares.passengerA.totalFare,
      coPassengerFare: fares.passengerB.totalFare,
      yourSavings: fares.passengerA.savingsVsPrivate,
    },
    message: 'Co-passenger confirmed! Waiting for driver assignment.',
  };
};

// getPendingMatchData is now synchronous — uses otpStore (in-memory)
const getPendingMatchData = (rideId, ridePassengerId) => {
  const key = `pending_match:${rideId}:${ridePassengerId}`;
  const data = otpStore.get(key);
  return data ? JSON.parse(data) : null;
};

// ─── Time-Shift Negotiation ───────────────────────────────────────────────────

const proposeTimeShift = (rideId, proposingPassengerId, newScheduledAt) => {
  const shiftKey = `time_shift:${rideId}`;
  otpStore.set(shiftKey, JSON.stringify({
    proposedBy: proposingPassengerId,
    newScheduledAt,
    proposedAt: new Date().toISOString(),
  }), RESPONSE_DEADLINE * 60);

  return { proposed: true, newScheduledAt, responseDeadlineMinutes: RESPONSE_DEADLINE };
};

const respondToTimeShift = async (rideId, respondingPassengerId, accept) => {
  const shiftKey = `time_shift:${rideId}`;
  const shiftData = otpStore.get(shiftKey);

  if (!shiftData) throw new AppError('Time-shift proposal expired.', 404);
  const shift = JSON.parse(shiftData);

  if (!accept) {
    otpStore.del(shiftKey);
    return { accepted: false, message: 'Time-shift declined.' };
  }

  await supabase
    .from('ride_passengers')
    .update({ adjusted_scheduled_at: shift.newScheduledAt, time_shift_accepted: true })
    .eq('ride_id', rideId)
    .eq('passenger_id', respondingPassengerId);

  otpStore.del(shiftKey);
  return { accepted: true, newScheduledAt: shift.newScheduledAt };
};

// ─── Cancel Ride ──────────────────────────────────────────────────────────────

const cancelRide = async (userId, rideId, reason, cancelledBy = 'passenger') => {
  const { data: ride, error } = await supabase
    .from('rides')
    .select('id, status, driver_id, otp_verified, ride_passengers(id, passenger_id)')
    .eq('id', rideId)
    .single();

  if (error || !ride) throw new AppError('Ride not found.', 404);
  if (['in_progress', 'completed'].includes(ride.status)) {
    throw new AppError('Cannot cancel a ride that has already started.', 400);
  }

  await supabase.from('rides').update({ status: 'cancelled' }).eq('id', rideId);
  await supabase.from('ride_passengers').update({ status: 'cancelled' }).eq('ride_id', rideId);

  const isConfirmed = ride.status === 'confirmed' || ride.otp_verified;

  if (cancelledBy === 'passenger' && isConfirmed) {
    const { data: user } = await supabase.from('users').select('wallet_balance').eq('id', userId).single();
    const newBalance = Math.max(0, parseFloat(user?.wallet_balance || 0) - CANCELLATION_FEE);
    await supabase.from('users').update({ wallet_balance: newBalance }).eq('id', userId);
    await supabase.from('fines').insert({
      user_id: userId,
      ride_id: rideId,
      type: 'passenger_cancellation',
      amount: CANCELLATION_FEE,
      reason: reason || 'Passenger cancelled after confirmation',
      status: 'collected',
    });
  }

  if (cancelledBy === 'driver' && ride.driver_id) {
    const { data: driver } = await supabase
      .from('drivers')
      .select('user_id, users!inner(wallet_balance, cancellation_count, reliability_score)')
      .eq('id', ride.driver_id)
      .single();

    if (driver) {
      const driverUserId = driver.user_id;
      const driverBalance = parseFloat(driver.users?.wallet_balance || 0);
      const currentCancelCount = parseInt(driver.users?.cancellation_count || 0);
      const currentReliability = parseFloat(driver.users?.reliability_score || 5);

      // Deduct fine from wallet (floor at 0), increment cancellation count,
      // apply -0.3 reliability penalty (floor at 0) — all plain JS, no Supabase RPC
      await supabase.from('users').update({
        wallet_balance: Math.max(0, driverBalance - DRIVER_FINE),
        cancellation_count: currentCancelCount + 1,
        reliability_score: Math.max(0, Math.round((currentReliability - 0.3) * 100) / 100),
      }).eq('id', driverUserId);

      await supabase.from('fines').insert({
        user_id: driverUserId,
        ride_id: rideId,
        type: 'driver_cancellation',
        amount: DRIVER_FINE,
        reason: reason || 'Driver cancelled',
        status: 'pending',
      });
    }
  }

  return {
    cancelled: true,
    rideId,
    fine: cancelledBy === 'passenger' && isConfirmed ? CANCELLATION_FEE : 0,
  };
};

// ─── Get Active Ride ──────────────────────────────────────────────────────────

const getActiveRide = async (userId) => {
  const { data, error } = await supabase
    .from('ride_passengers')
    .select(`
      id,
      total_fare, status, face_verified_at,
      boarding_address, drop_address,
      rides!inner(
        id, ride_type, status, pickup_address, drop_address,
        pickup_lat, pickup_lng, drop_lat, drop_lng,
        scheduled_at, started_at, otp, otp_verified,
        drivers(
          vehicle_make, vehicle_model, vehicle_number, vehicle_color,
          current_lat, current_lng,
          users!inner(full_name, phone)
        )
      )
    `)
    .eq('passenger_id', userId)
    .not('rides.status', 'in', '("completed","cancelled")')
    .order('created_at', { ascending: false })
    .limit(1)
    .single();

  if (error) return null;
  return data;
};

const getDriverActiveRide = async (driverUserId) => {
  const { data, error } = await supabase
    .from('rides')
    .select(`
      id, ride_type, status,
      pickup_address, drop_address,
      pickup_lat, pickup_lng, drop_lat, drop_lng,
      scheduled_at, started_at, otp, otp_verified,
      drivers!inner(user_id),
      ride_passengers(
        id, passenger_id, boarding_address, drop_address,
        total_fare, status, face_verified_at,
        users!inner(full_name, phone)
      )
    `)
    .eq('drivers.user_id', driverUserId)
    .not('status', 'in', '("completed","cancelled")')
    .order('created_at', { ascending: false })
    .limit(1)
    .single();

  if (error) return null;
  return data;
};

// ─── Fare Estimate ────────────────────────────────────────────────────────────

const getFareEstimate = (distanceKm, rideType) => estimateFare(distanceKm, rideType);

module.exports = {
  bookRide,
  findMatch,
  respondToMatch,
  proposeTimeShift,
  respondToTimeShift,
  cancelRide,
  getActiveRide,
  getDriverActiveRide,
  getFareEstimate,
};
