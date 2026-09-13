const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const { supabase } = require('../../shared/db/client');
const { otpStore, keys } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const { sendOtp } = require('../notification/sms.service');

const crypto = require('crypto');

const OTP_EXPIRY_MINUTES = parseInt(process.env.OTP_EXPIRY_MINUTES) || 10;
const OTP_MAX_ATTEMPTS = parseInt(process.env.OTP_MAX_ATTEMPTS) || 5;

// ─── OTP ─────────────────────────────────────────────────────────────────────

/**
 * Generate a 6-digit OTP, store in memory with expiry, send via SMS
 */
const requestOtp = async (phone, purpose = 'login') => {
  const attemptsKey = keys.otpAttempts(phone, purpose);

  // Rate limit — max 5 OTP requests per hour
  const attempts = otpStore.incr(attemptsKey, 3600);
  if (attempts > OTP_MAX_ATTEMPTS) {
    throw new AppError('Too many OTP requests. Please wait before trying again.', 429);
  }

  // Generate cryptographically secure 6-digit OTP
  const otp = crypto.randomInt(100000, 1000000).toString();

  // Store with TTL
  otpStore.set(keys.otp(phone, purpose), otp, OTP_EXPIRY_MINUTES * 60);

  // Send SMS (logs to console in dev, sends real SMS in production)
  await sendOtp(phone, otp, purpose);

  // Audit log in Supabase (non-blocking, best-effort)
  // Upsert on (phone, purpose) within the expiry window so we track
  // the running attempt count on the same OTP session, not a new row each time.
  supabase
    .from('otp_logs')
    .insert({
      phone,
      purpose,
      attempts: attempts,  // current attempt number (1-based from incr)
      expires_at: new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000).toISOString(),
    })
    .then(({ error }) => {
      if (error) console.error('OTP log insert error:', error.message);
    });

  return {
    message: `OTP sent to ${phone}`,
    expiresInMinutes: OTP_EXPIRY_MINUTES,
  };
};

/**
 * Verify OTP from in-memory store
 */
const verifyOtp = async (phone, otp, purpose = 'login') => {
  const storedOtp = otpStore.get(keys.otp(phone, purpose));

  if (!storedOtp) {
    throw new AppError('OTP expired or not found. Please request a new one.', 400);
  }

  if (storedOtp !== otp) {
    throw new AppError('Invalid OTP. Please check and try again.', 400);
  }

  // OTP valid — delete immediately (single use)
  otpStore.del(keys.otp(phone, purpose));
  otpStore.del(keys.otpAttempts(phone, purpose));

  // Mark the most recent log row for this phone+purpose as verified (non-blocking)
  supabase
    .from('otp_logs')
    .update({ verified: true })
    .eq('phone', phone)
    .eq('purpose', purpose)
    .eq('verified', false)
    .gte('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .then(({ error }) => {
      if (error) console.error('OTP log verified update error:', error.message);
    });

  return true;
};

// ─── JWT ─────────────────────────────────────────────────────────────────────

const generateTokens = (userId, role) => {
  // jti (JWT ID) lets us individually revoke tokens without invalidating all user tokens
  const accessJti = uuidv4();
  const refreshJti = uuidv4();

  const accessToken = jwt.sign(
    { userId, role, jti: accessJti },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );

  const refreshToken = jwt.sign(
    { userId, role, type: 'refresh', jti: refreshJti },
    process.env.JWT_REFRESH_SECRET,
    { expiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '30d' }
  );

  return { accessToken, refreshToken };
};

// ─── Login / Register Flow ────────────────────────────────────────────────────

/**
 * After OTP verified — find or create user, return tokens + isNewUser flag
 */
const loginOrRegister = async (phone) => {
  // Check if user exists
  const { data: existingUser, error: fetchError } = await supabase
    .from('users')
    .select('id, role, full_name, is_active, face_verified, city')
    .eq('phone', phone)
    .single();

  if (fetchError && fetchError.code !== 'PGRST116') {
    // PGRST116 = row not found, anything else is a real error
    throw new AppError('Database error. Please try again.', 500);
  }

  if (!existingUser) {
    // New user — create a minimal record
    const { data: newUser, error: insertError } = await supabase
      .from('users')
      .insert({ phone, is_phone_verified: true })
      .select('id, role, city')
      .single();

    if (insertError) throw new AppError('Failed to create account. Please try again.', 500);

    const tokens = generateTokens(newUser.id, newUser.role);
    return { isNewUser: true, user: newUser, tokens };
  }

  if (!existingUser.is_active) {
    throw new AppError('Your account has been deactivated. Please contact support.', 403);
  }

  // Update last active (non-blocking)
  supabase
    .from('users')
    .update({ last_active_at: new Date().toISOString() })
    .eq('id', existingUser.id)
    .then(({ error }) => { if (error) console.error('last_active_at update error:', error.message); });

  const tokens = generateTokens(existingUser.id, existingUser.role);
  return { isNewUser: false, user: existingUser, tokens };
};

/**
 * Refresh access token using refresh token.
 * Checks the revoked_tokens table — a logged-out refresh token is rejected.
 */
const refreshAccessToken = async (refreshToken) => {
  let decoded;
  try {
    decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    if (decoded.type !== 'refresh') throw new Error('Invalid token type');
  } catch {
    throw new AppError('Invalid or expired refresh token', 401);
  }

  // Check if this token has been revoked (logout was called)
  const { data: revoked } = await supabase
    .from('revoked_tokens')
    .select('jti')
    .eq('jti', decoded.jti)
    .maybeSingle();

  if (revoked) {
    throw new AppError('Token has been revoked. Please log in again.', 401);
  }

  const { data: user, error } = await supabase
    .from('users')
    .select('id, role, is_active')
    .eq('id', decoded.userId)
    .single();

  if (error || !user || !user.is_active) {
    throw new AppError('Account not found or deactivated', 401);
  }

  const { accessToken } = generateTokens(decoded.userId, decoded.role);
  return { accessToken };
};

/**
 * Logout — revoke the refresh token by storing its jti in the DB.
 * The access token will expire naturally (short-lived).
 * Any future refresh attempt with this token will be rejected.
 */
const logout = async (refreshToken) => {
  if (!refreshToken) return { loggedOut: true }; // idempotent — no token = already logged out

  let decoded;
  try {
    decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
  } catch {
    // Expired or invalid — treat as already logged out, not an error
    return { loggedOut: true };
  }

  // Persist the revocation — expires_at matches the token's own expiry
  // O3: also write to otpStore (in-memory) so authenticate middleware
  // can check revocation without a DB hit on the hot path.
  // TTL matches the token's remaining lifetime.
  const ttlSeconds = Math.max(0, decoded.exp - Math.floor(Date.now() / 1000));
  if (ttlSeconds > 0) {
    otpStore.set(`revoked_jti:${decoded.jti}`, '1', ttlSeconds);
  }

  await supabase.from('revoked_tokens').upsert(
    {
      jti: decoded.jti,
      user_id: decoded.userId,
      expires_at: new Date(decoded.exp * 1000).toISOString(),
    },
    { onConflict: 'jti' } // idempotent — double-logout is safe
  );

  return { loggedOut: true };
};

module.exports = { requestOtp, verifyOtp, loginOrRegister, refreshAccessToken, logout, generateTokens };
