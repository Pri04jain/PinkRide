const { supabase } = require('../../shared/db/client');
const { otpStore } = require('../../shared/cache/otpStore');

const MATCH_WINDOW_MIN = parseInt(process.env.RIDE_MATCH_WINDOW_MINUTES) || 30;
const MAX_PICKUP_DETOUR_KM = 3;
const CO_PASSENGER_MAX_REJECTIONS = parseInt(process.env.CO_PASSENGER_MAX_REJECTIONS) || 2;

/**
 * Haversine distance between two lat/lng points in kilometers.
 */
const haversineKm = (lat1, lng1, lat2, lng2) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

/**
 * Find compatible shared-ride passengers for a given ride.
 *
 * Why no PostGIS here?
 * We replaced the raw PostGIS SQL with JS-side Haversine filtering.
 * This is accurate to within ~1% for distances < 50km, which is more than
 * enough for city-level ride matching.
 * Upgrade path: use supabase.rpc() with a PostGIS function if performance
 * becomes an issue at scale.
 *
 * Compatibility criteria:
 * 1. Same city, same ride type
 * 2. Scheduled within ±MATCH_WINDOW_MIN minutes
 * 3. Drop point within 10km of anchor drop (same direction)
 * 4. Pickup detour under MAX_PICKUP_DETOUR_KM
 * 5. Women-only rides: both passengers must be female
 * 6. Neither passenger has exceeded rejection limit
 */
const findCompatiblePassengers = async (rideId) => {
  // Get the anchor ride
  const { data: anchor, error } = await supabase
    .from('rides')
    .select(`
      id, ride_type, scheduled_at, city,
      pickup_lat, pickup_lng, drop_lat, drop_lng,
      ride_passengers!inner(passenger_id, rejection_count, users!inner(gender))
    `)
    .eq('id', rideId)
    .eq('ride_passengers.status', 'pending')
    .single();

  if (error || !anchor) return [];

  const anchorPassenger = anchor.ride_passengers[0];
  const anchorGender = anchorPassenger?.users?.gender;

  const windowStart = new Date(new Date(anchor.scheduled_at).getTime() - MATCH_WINDOW_MIN * 60000).toISOString();
  const windowEnd = new Date(new Date(anchor.scheduled_at).getTime() + MATCH_WINDOW_MIN * 60000).toISOString();

  // O2: bounding box on anchor pickup — candidates must have their pickup within
  // MAX_PICKUP_DETOUR_KM of the anchor. Cuts DB rows before JS filtering.
  const DEG_PER_KM = 1 / 111;
  const delta = MAX_PICKUP_DETOUR_KM * DEG_PER_KM * Math.SQRT2;
  const latMin = parseFloat(anchor.pickup_lat) - delta;
  const latMax = parseFloat(anchor.pickup_lat) + delta;
  const lngMin = parseFloat(anchor.pickup_lng) - delta;
  const lngMax = parseFloat(anchor.pickup_lng) + delta;

  // Fetch candidate rides (same city, type, time window, shared, pending)
  const { data: candidates } = await supabase
    .from('rides')
    .select(`
      id, scheduled_at,
      pickup_lat, pickup_lng, drop_lat, drop_lng,
      ride_passengers!inner(id, passenger_id, rejection_count, users!inner(gender))
    `)
    .neq('id', rideId)
    .eq('city', anchor.city)
    .eq('ride_type', anchor.ride_type)
    .in('status', ['searching', 'matching'])
    .eq('ride_passengers.status', 'pending')
    .lt('ride_passengers.rejection_count', CO_PASSENGER_MAX_REJECTIONS)
    .gte('scheduled_at', windowStart)
    .lte('scheduled_at', windowEnd)
    .gt('max_passengers', 1)
    .gte('pickup_lat', latMin)
    .lte('pickup_lat', latMax)
    .gte('pickup_lng', lngMin)
    .lte('pickup_lng', lngMax);

  if (!candidates) return [];

  const matches = [];

  for (const ride of candidates) {
    for (const rp of ride.ride_passengers || []) {
      // Distance from candidate pickup to anchor pickup (detour)
      const pickupDetourKm = haversineKm(
        ride.pickup_lat, ride.pickup_lng,
        anchor.pickup_lat, anchor.pickup_lng
      );

      // Distance between drop points (direction similarity)
      const dropDistanceKm = haversineKm(
        ride.drop_lat, ride.drop_lng,
        anchor.drop_lat, anchor.drop_lng
      );

      // Filter by detour and direction
      if (pickupDetourKm > MAX_PICKUP_DETOUR_KM) continue;
      if (dropDistanceKm > 10) continue;

      // Women-only filter
      if (anchor.ride_type === 'women_only_shared') {
        if (rp.users?.gender !== 'female' || anchorGender !== 'female') continue;
      }

      matches.push({
        rideId: ride.id,
        ridePassengerId: rp.id,
        passengerId: rp.passenger_id,
        scheduledAt: ride.scheduled_at,
        pickupDetourKm: Math.round(pickupDetourKm * 10) / 10,
        dropDistanceKm: Math.round(dropDistanceKm * 10) / 10,
      });
    }
  }

  // Sort by closest drop point first
  return matches.sort((a, b) => a.dropDistanceKm - b.dropDistanceKm);
};

/**
 * Calculate extra time a detour adds (city avg speed = 25 km/h).
 */
const estimateDetourMinutes = (detourKm) => Math.round((detourKm / 25) * 60);

/**
 * Pending match store — replaces Redis.
 * Key: `pending_match:${anchorRideId}:${candidateRidePassengerId}`
 * TTL: MATCH_WINDOW_MIN minutes
 */
const storePendingMatch = (anchorRideId, candidateRidePassengerId, matchData) => {
  const key = `pending_match:${anchorRideId}:${candidateRidePassengerId}`;
  otpStore.set(key, JSON.stringify(matchData), MATCH_WINDOW_MIN * 60);
  return key;
};

const getPendingMatch = (anchorRideId, candidateRidePassengerId) => {
  const key = `pending_match:${anchorRideId}:${candidateRidePassengerId}`;
  const data = otpStore.get(key);
  return data ? JSON.parse(data) : null;
};

const deletePendingMatch = (anchorRideId, candidateRidePassengerId) => {
  const key = `pending_match:${anchorRideId}:${candidateRidePassengerId}`;
  otpStore.del(key);
};

module.exports = {
  findCompatiblePassengers,
  estimateDetourMinutes,
  storePendingMatch,
  getPendingMatch,
  deletePendingMatch,
  MATCH_WINDOW_MIN,
};
