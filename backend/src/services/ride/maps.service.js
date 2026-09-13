/**
 * Google Maps Distance Matrix Service
 *
 * Calculates the real driving distance and duration between two coordinates
 * using the Google Maps Distance Matrix API.
 *
 * Why server-side?
 *   The client currently sends distanceKm + durationMin in the booking request.
 *   Those values are used directly for fare calculation, meaning a passenger
 *   could send distanceKm=1 for a 50km trip and pay almost nothing.
 *   By computing distance on the server we own the value the fare is based on.
 *
 * Fallback:
 *   If GOOGLE_MAPS_API_KEY is not set (dev / CI), we fall back to a Haversine
 *   straight-line estimate with a 1.35 road factor and 25 km/h city speed.
 *   This is the same estimate the fare calculator has always used — so dev
 *   behaviour is unchanged.
 */

const axios = require('axios');

const MAPS_API_KEY = process.env.GOOGLE_MAPS_API_KEY;
const ROAD_FACTOR = 1.35;      // straight-line → road distance correction
const AVG_SPEED_KMH = 25;      // Jaipur city average

// ─── Haversine fallback ───────────────────────────────────────────────────────

const _haversineKm = (lat1, lng1, lat2, lng2) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

const _fallback = (originLat, originLng, destLat, destLng) => {
  const straightKm = _haversineKm(originLat, originLng, destLat, destLng);
  const distanceKm = Math.round(straightKm * ROAD_FACTOR * 10) / 10;
  const durationMin = Math.round((distanceKm / AVG_SPEED_KMH) * 60);
  return { distanceKm, durationMin, source: 'haversine_fallback' };
};

// ─── Google Maps Distance Matrix ──────────────────────────────────────────────

/**
 * Returns { distanceKm, durationMin, source } for the driving route between
 * two lat/lng pairs.
 *
 * source is 'google_maps' or 'haversine_fallback' — useful for logging/debugging.
 *
 * Throws only on unrecoverable errors (bad coordinates, quota exhausted).
 * Network timeouts and ZERO_RESULTS fall back to Haversine silently.
 */
const getDrivingDistance = async (originLat, originLng, destLat, destLng) => {
  if (!MAPS_API_KEY) {
    console.warn('[Maps] GOOGLE_MAPS_API_KEY not set — using Haversine fallback.');
    return _fallback(originLat, originLng, destLat, destLng);
  }

  try {
    const url = 'https://maps.googleapis.com/maps/api/distancematrix/json';
    const response = await axios.get(url, {
      params: {
        origins: `${originLat},${originLng}`,
        destinations: `${destLat},${destLng}`,
        mode: 'driving',
        units: 'metric',
        key: MAPS_API_KEY,
      },
      timeout: 5000, // 5s — don't block bookings on Maps latency
    });

    const element = response.data?.rows?.[0]?.elements?.[0];

    if (!element || element.status !== 'OK') {
      console.warn(`[Maps] Distance Matrix status: ${element?.status} — falling back to Haversine.`);
      return _fallback(originLat, originLng, destLat, destLng);
    }

    const distanceKm = Math.round((element.distance.value / 1000) * 10) / 10; // metres → km
    const durationMin = Math.round(element.duration.value / 60);               // seconds → minutes

    return { distanceKm, durationMin, source: 'google_maps' };
  } catch (err) {
    console.error('[Maps] Distance Matrix error:', err.message, '— falling back to Haversine.');
    return _fallback(originLat, originLng, destLat, destLng);
  }
};

module.exports = { getDrivingDistance };
