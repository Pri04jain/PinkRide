const { supabase } = require('../../shared/db/client');
const { otpStore } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const { emitToRide } = require('../../shared/socket/socket.server');

const DEVIATION_ALERT_METERS = parseFloat(process.env.ROUTE_DEVIATION_ALERT_METERS) || 500;
const AUTO_ALERT_SECONDS = parseInt(process.env.ROUTE_DEVIATION_AUTO_ALERT_SECONDS) || 120;

// In-memory cache for latest driver location per ride
// Key: rideId, Value: { lat, lng, ts }
// F9: entries are evicted via clearRideCache() when ride ends,
// and a 30-min sweep runs periodically as a safety net.
const locationCache = new Map();

// Periodic sweep — evict entries older than 30 minutes
setInterval(() => {
  const cutoff = Date.now() - 30 * 60 * 1000;
  for (const [rideId, entry] of locationCache.entries()) {
    if (entry.ts < cutoff) locationCache.delete(rideId);
  }
}, 10 * 60 * 1000); // run every 10 minutes

// Key builders
const activeDeviationKey = (rideId) => `active_deviation:${rideId}`;
const deviationTimerKey = (deviationId) => `dev_timer:${deviationId}`;

/**
 * Called on every driver_location socket event.
 * 1. Cache driver location in memory
 * 2. Persist to Supabase
 * 3. Check for route deviation (simple Haversine, no PostGIS needed)
 *
 * Why no PostGIS here?
 * Supabase supports PostGIS but calling raw SQL from the JS client is
 * more complex. For MVP, we compute distance server-side with Haversine —
 * it's accurate enough for 500m deviation detection.
 * Upgrade path: use supabase.rpc('check_deviation', {...}) when needed.
 */
const processLocationUpdate = async (driverUserId, rideId, lat, lng) => {
  // 1. Cache in memory (5 min TTL equivalent — just store it)
  locationCache.set(rideId, { lat, lng, ts: Date.now() });

  // 2. Persist driver location to Supabase (non-blocking)
  supabase
    .from('drivers')
    .update({
      current_lat: lat,
      current_lng: lng,
      last_location_update: new Date().toISOString(),
    })
    .eq('user_id', driverUserId)
    .then(({ error }) => {
      if (error) console.error('[Tracking] Location update error:', error.message);
    });

  // 3. Check if ride is in progress
  const { data: ride } = await supabase
    .from('rides')
    .select('id, status, driver_id, pickup_lat, pickup_lng, drop_lat, drop_lng')
    .eq('id', rideId)
    .eq('status', 'in_progress')
    .single();

  if (!ride) return; // not in progress, skip breadcrumb + deviation check

  // 4. Write GPS breadcrumb to location_history (non-blocking)
  //    Only written while ride is in_progress — keeps volume manageable.
  supabase
    .from('location_history')
    .insert({
      ride_id: rideId,
      driver_id: ride.driver_id,
      lat,
      lng,
      recorded_at: new Date().toISOString(),
    })
    .then(({ error }) => {
      if (error) console.error('[Tracking] Breadcrumb insert error:', error.message);
    });

  // 5. Calculate deviation using Haversine
  const deviationMeters = _pointToLineDistance(
    lat, lng,
    ride.pickup_lat, ride.pickup_lng,
    ride.drop_lat, ride.drop_lng
  );

  if (deviationMeters > DEVIATION_ALERT_METERS) {
    await _handleDeviation(rideId, driverUserId, lat, lng, deviationMeters);
  }
};

/**
 * F8 — True perpendicular distance from point P to line segment A→B.
 * Returns distance in meters.
 *
 * Algorithm: project P onto the infinite line through A and B using
 * dot-product in ECEF (Earth-Centered Earth-Fixed) Cartesian space,
 * clamp the projection to the segment [A,B], then compute the
 * Haversine distance from P to the clamped projection point.
 *
 * Why this matters:
 * The old version computed min(dist(P,A), dist(P,B), dist(P,midpoint)).
 * For a driver at the midpoint of a long route, ALL three samples are large
 * even when the driver is perfectly on-route → false deviation alert every time.
 * This version correctly returns near-zero for any point along the route.
 */
const _pointToLineDistance = (pLat, pLng, aLat, aLng, bLat, bLng) => {
  const toRad = (d) => (d * Math.PI) / 180;

  // Convert lat/lng to unit ECEF vectors
  const toVec = (lat, lng) => {
    const φ = toRad(lat);
    const λ = toRad(lng);
    return [Math.cos(φ) * Math.cos(λ), Math.cos(φ) * Math.sin(λ), Math.sin(φ)];
  };

  const dot = (u, v) => u[0] * v[0] + u[1] * v[1] + u[2] * v[2];
  const sub = (u, v) => [u[0] - v[0], u[1] - v[1], u[2] - v[2]];
  const add = (u, v) => [u[0] + v[0], u[1] + v[1], u[2] + v[2]];
  const scale = (u, s) => [u[0] * s, u[1] * s, u[2] * s];
  const norm = (u) => Math.sqrt(dot(u, u));

  const P = toVec(pLat, pLng);
  const A = toVec(aLat, aLng);
  const B = toVec(bLat, bLng);

  const AB = sub(B, A);
  const AP = sub(P, A);

  const lenSqAB = dot(AB, AB);

  // Degenerate segment (A === B) — fall back to point distance
  if (lenSqAB < 1e-12) return _haversine(pLat, pLng, aLat, aLng);

  // t is the unclamped projection parameter [0,1] along A→B
  const t = Math.max(0, Math.min(1, dot(AP, AB) / lenSqAB));

  // Closest point on segment in Cartesian space (may not be on the unit sphere)
  const closest = add(A, scale(AB, t));

  // Re-normalise back onto the unit sphere
  const len = norm(closest);
  const Q = scale(closest, 1 / len);

  // Angular distance between P and Q → metres
  const cosAngle = Math.min(1, Math.max(-1, dot(P, Q)));
  const R = 6371000; // Earth radius metres
  return R * Math.acos(cosAngle);
};

const _haversine = (lat1, lng1, lat2, lng2) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const _handleDeviation = async (rideId, driverUserId, lat, lng, deviationMeters) => {
  // Avoid spamming — only one active deviation alert per ride at a time
  const alreadyAlerted = otpStore.get(activeDeviationKey(rideId));
  if (alreadyAlerted) return;

  // Mark active (5 min window)
  otpStore.set(activeDeviationKey(rideId), '1', 300);

  // Record in Supabase
  const { data: deviationRecord, error } = await supabase
    .from('route_deviations')
    .insert({
      ride_id: rideId,
      actual_lat: lat,
      actual_lng: lng,
      deviation_meters: Math.round(deviationMeters),
      status: 'detected',
    })
    .select('id')
    .single();

  if (error) {
    console.error('[Tracking] Deviation insert error:', error.message);
    return;
  }

  const deviationId = deviationRecord.id;

  // Emit real-time alert to passenger
  emitToRide(rideId, 'route_deviation', {
    deviationId,
    deviationMeters: Math.round(deviationMeters),
    currentLat: lat,
    currentLng: lng,
    message: 'Your driver appears to have taken an unexpected route.',
    responseDeadlineSeconds: AUTO_ALERT_SECONDS,
  });

  // Record alert time
  await supabase
    .from('route_deviations')
    .update({ passenger_alerted_at: new Date().toISOString() })
    .eq('id', deviationId);

  // Set timer marker — if passenger doesn't respond, auto-alert contacts
  otpStore.set(deviationTimerKey(deviationId), 'pending', AUTO_ALERT_SECONDS + 10);

  if (!global._deviationTimers) global._deviationTimers = {};
  global._deviationTimers[deviationId] = setTimeout(async () => {
    const stillPending = otpStore.get(deviationTimerKey(deviationId));
    if (!stillPending) return;
    await _autoAlertContacts(rideId, deviationId, lat, lng);
  }, AUTO_ALERT_SECONDS * 1000);
};

/**
 * Passenger responded to deviation alert.
 */
const acknowledgeDeviation = async (deviationId, passengerId, response) => {
  // Cancel the auto-alert timer
  otpStore.del(deviationTimerKey(deviationId));
  if (global._deviationTimers?.[deviationId]) {
    clearTimeout(global._deviationTimers[deviationId]);
    delete global._deviationTimers[deviationId];
  }

  await supabase
    .from('route_deviations')
    .update({
      passenger_response: response,
      status: response === 'ok' ? 'resolved' : 'passenger_acknowledged',
      resolved_at: new Date().toISOString(),
    })
    .eq('id', deviationId);

  if (response === 'alert') {
    await _alertContactsForDeviation(deviationId, passengerId);
  }

  return { acknowledged: true, response };
};

const _autoAlertContacts = async (rideId, deviationId, lat, lng) => {
  const { data: passengers } = await supabase
    .from('ride_passengers')
    .select('passenger_id')
    .eq('ride_id', rideId)
    .eq('status', 'boarded');

  for (const row of passengers || []) {
    await _alertContactsForDeviation(deviationId, row.passenger_id);
  }

  await supabase
    .from('route_deviations')
    .update({ contacts_alerted_at: new Date().toISOString(), status: 'contacts_alerted' })
    .eq('id', deviationId);

  emitToRide(rideId, 'contacts_alerted', { deviationId, reason: 'no_response' });
};

const _alertContactsForDeviation = async (deviationId, passengerId) => {
  const smsService = require('../notification/sms.service');

  const { data: contacts } = await supabase
    .from('emergency_contacts')
    .select('phone, name, users!inner(full_name)')
    .eq('user_id', passengerId)
    .order('is_primary', { ascending: false })
    .limit(3);

  const { data: deviation } = await supabase
    .from('route_deviations')
    .select('ride_id, actual_lat, actual_lng')
    .eq('id', deviationId)
    .single();

  if (!deviation) return;

  const locationLink = `https://maps.google.com/?q=${deviation.actual_lat},${deviation.actual_lng}`;

  for (const contact of contacts || []) {
    await smsService.sendEmergencyAlert(
      contact.phone,
      contact.users?.full_name || 'A PinkRide passenger',
      deviation.ride_id,
      locationLink
    );
  }
};

/**
 * Get latest driver location for a ride (from cache first, then DB).
 */
const getDriverLocation = async (rideId) => {
  const cached = locationCache.get(rideId);
  if (cached) return cached;

  const { data } = await supabase
    .from('rides')
    .select('drivers!inner(current_lat, current_lng, last_location_update)')
    .eq('id', rideId)
    .single();

  if (!data?.drivers) return null;
  return {
    lat: data.drivers.current_lat,
    lng: data.drivers.current_lng,
    ts: data.drivers.last_location_update,
  };
};

/**
 * Get route deviation history for a ride.
 */
const getRideDeviations = async (rideId) => {
  const { data, error } = await supabase
    .from('route_deviations')
    .select('id, deviation_meters, status, passenger_response, passenger_alerted_at, contacts_alerted_at, detected_at, actual_lat, actual_lng')
    .eq('ride_id', rideId)
    .order('detected_at', { ascending: false });

  if (error) throw new AppError('Failed to fetch deviations.', 500);
  return data || [];
};

/**
 * Get GPS breadcrumb trail for a completed ride.
 * Returns all recorded locations in chronological order for route replay.
 */
const getRideLocationHistory = async (rideId) => {
  const { data, error } = await supabase
    .from('location_history')
    .select('id, lat, lng, heading, speed_kmh, recorded_at')
    .eq('ride_id', rideId)
    .order('recorded_at', { ascending: true });

  if (error) throw new AppError('Failed to fetch location history.', 500);
  return data || [];
};

/**
 * F9 — Evict a ride's location cache entry when the ride ends.
 * Called from completeRide() and cancelRide() in ride/otp.service.js
 * and ride/ride.service.js respectively.
 */
const clearRideCache = (rideId) => {
  locationCache.delete(rideId);
};

module.exports = {
  processLocationUpdate,
  acknowledgeDeviation,
  getDriverLocation,
  getRideDeviations,
  getRideLocationHistory,
  clearRideCache,
};
