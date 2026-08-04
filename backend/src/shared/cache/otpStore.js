/**
 * In-memory OTP store (replaces Redis for MVP/development)
 *
 * Why not Redis?
 * Redis requires a running server (either Docker or a cloud instance).
 * For a single-server MVP, a Map with TTL cleanup is simpler and free.
 *
 * Limitation: if you restart the server, all pending OTPs are cleared.
 * That's acceptable during development.
 *
 * When to upgrade: once you have multiple server instances (load balancing),
 * switch to Upstash Redis — it's serverless, has a free tier, and needs
 * zero infrastructure setup.
 */

// Structure: key -> { value, expiresAt }
const store = new Map();

// Clean up expired entries every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of store.entries()) {
    if (entry.expiresAt <= now) {
      store.delete(key);
    }
  }
}, 5 * 60 * 1000);

const otpStore = {
  /**
   * Store a value with TTL in seconds
   */
  set(key, value, ttlSeconds) {
    store.set(key, {
      value,
      expiresAt: Date.now() + ttlSeconds * 1000,
    });
  },

  /**
   * Get a value — returns null if missing or expired
   */
  get(key) {
    const entry = store.get(key);
    if (!entry) return null;
    if (entry.expiresAt <= Date.now()) {
      store.delete(key);
      return null;
    }
    return entry.value;
  },

  /**
   * Delete a key
   */
  del(key) {
    store.delete(key);
  },

  /**
   * Increment a counter, set TTL on first increment
   * Returns the new count
   */
  incr(key, ttlSeconds) {
    const entry = store.get(key);
    if (!entry || entry.expiresAt <= Date.now()) {
      store.set(key, { value: 1, expiresAt: Date.now() + ttlSeconds * 1000 });
      return 1;
    }
    entry.value += 1;
    return entry.value;
  },
};

// Centralised key builders — same as before, avoids typos across services
const keys = {
  otp: (phone, purpose) => `otp:${purpose}:${phone}`,
  otpAttempts: (phone, purpose) => `otp_attempts:${purpose}:${phone}`,
  rideOtp: (rideId) => `ride_otp:${rideId}`,
};

module.exports = { otpStore, keys };
