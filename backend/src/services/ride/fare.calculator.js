/**
 * PinkRide Fare Calculator
 *
 * Jaipur MVP base rates (can be moved to DB/config later):
 *   Base fare:       ₹30
 *   Per km rate:     ₹12/km
 *   Per minute rate: ₹1.5/min  (traffic buffer)
 *   Platform fee:    5% of total fare
 *   Min fare:        ₹50
 *   Cancellation:    ₹50 (passenger), ₹150 (driver fine)
 *
 * Shared ride split logic (Scenario A→C, B→C):
 *   Passenger A pays: (A_exclusive_km × rate) + (shared_km × rate / 2) + platform_fee
 *   Passenger B pays: (shared_km × rate / 2) + platform_fee
 */

const RATES = {
  baseFare: 30,
  perKmRate: 12,
  perMinRate: 1.5,
  platformFeePercent: parseFloat(process.env.PLATFORM_FEE_PERCENT) || 5,
  minFare: 50,
  surgeMultiplier: 1.0, // Phase 2: dynamic surge
};

/**
 * Calculate fare for a private ride (single passenger, full route)
 * @param {number} distanceKm
 * @param {number} durationMin
 * @returns {{ baseFare, distanceFare, timeFare, subtotal, platformFee, totalFare }}
 */
const calculatePrivateFare = (distanceKm, durationMin = 0) => {
  const distanceFare = distanceKm * RATES.perKmRate;
  const timeFare = durationMin * RATES.perMinRate;
  const subtotal = Math.max(RATES.baseFare + distanceFare + timeFare, RATES.minFare);
  const surgeSubtotal = subtotal * RATES.surgeMultiplier;
  const platformFee = _round(surgeSubtotal * (RATES.platformFeePercent / 100));
  const totalFare = _round(surgeSubtotal + platformFee);

  return {
    baseFare: _round(RATES.baseFare),
    distanceFare: _round(distanceFare),
    timeFare: _round(timeFare),
    subtotal: _round(surgeSubtotal),
    platformFee,
    totalFare,
    ratePerKm: RATES.perKmRate,
  };
};

/**
 * Calculate shared ride fares for two passengers.
 *
 * Route: A ──────── B ──────── C
 *        |←exclusive→|←shared→|
 *
 * @param {number} totalDistanceKm     — full route A→C
 * @param {number} sharedDistanceKm    — shared segment B→C
 * @param {number} durationMin         — total trip duration estimate
 * @returns {{ passengerA, passengerB, savings }}
 */
const calculateSharedFare = (totalDistanceKm, sharedDistanceKm, durationMin = 0) => {
  const exclusiveDistanceKm = totalDistanceKm - sharedDistanceKm;

  // Cost if each rode alone
  const privateA = calculatePrivateFare(totalDistanceKm, durationMin);
  const privateB = calculatePrivateFare(sharedDistanceKm, Math.round(durationMin * (sharedDistanceKm / totalDistanceKm)));

  // Shared fare split
  const exclusiveFare = exclusiveDistanceKm * RATES.perKmRate;
  const sharedFareHalf = (sharedDistanceKm * RATES.perKmRate) / 2;
  const timeFareA = durationMin * RATES.perMinRate;

  const subtotalA = Math.max(RATES.baseFare + exclusiveFare + sharedFareHalf + timeFareA, RATES.minFare);
  const subtotalB = Math.max(sharedFareHalf, RATES.minFare / 2);

  const platformFeeA = _round(subtotalA * (RATES.platformFeePercent / 100));
  const platformFeeB = _round(subtotalB * (RATES.platformFeePercent / 100));

  const totalA = _round(subtotalA + platformFeeA);
  const totalB = _round(subtotalB + platformFeeB);

  return {
    passengerA: {
      exclusiveDistanceKm: _round(exclusiveDistanceKm),
      sharedDistanceKm: _round(sharedDistanceKm),
      exclusiveFare: _round(exclusiveFare),
      sharedFare: _round(sharedFareHalf),
      platformFee: platformFeeA,
      totalFare: totalA,
      savingsVsPrivate: _round(privateA.totalFare - totalA),
    },
    passengerB: {
      exclusiveDistanceKm: 0,
      sharedDistanceKm: _round(sharedDistanceKm),
      exclusiveFare: 0,
      sharedFare: _round(sharedFareHalf),
      platformFee: platformFeeB,
      totalFare: totalB,
      savingsVsPrivate: _round(privateB.totalFare - totalB),
    },
    totalCollected: _round(totalA + totalB),
    privateAWouldHavePaid: privateA.totalFare,
    privateBWouldHavePaid: privateB.totalFare,
  };
};

/**
 * Estimate fare before booking (no duration available yet, use avg speed).
 * Average Jaipur city speed: ~25 km/h
 */
const estimateFare = (distanceKm, rideType = 'private', sharedDistanceKm = 0) => {
  const avgSpeedKmh = 25;
  const durationMin = Math.round((distanceKm / avgSpeedKmh) * 60);

  if (rideType === 'private') {
    return { estimate: calculatePrivateFare(distanceKm, durationMin) };
  }

  // For shared, estimate B passenger saves ~half
  const sharedDist = sharedDistanceKm || distanceKm * 0.6; // default: 60% shared
  return { estimate: calculateSharedFare(distanceKm, sharedDist, durationMin) };
};

const _round = (val) => Math.round(val * 100) / 100;

module.exports = { calculatePrivateFare, calculateSharedFare, estimateFare, RATES };
