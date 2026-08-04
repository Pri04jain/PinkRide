const jwt = require('jsonwebtoken');
const { supabase } = require('../../shared/db/client');
const { otpStore, keys } = require('../../shared/cache/otpStore');
const { AppError } = require('../../shared/middleware/errorHandler');
const { sendOtp } = require('../notification/sms.service');

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

  // Generate 6-digit OTP
  const otp = Math.floor(100000 + Math.random() * 900000).toString();

  // Store with TTL
  otpStore.set(keys.otp(phone, purpose), otp, OTP_EXPIRY_MINUTES * 60);

  // Send SMS (logs to console in dev, sends real SMS in production)
  await sendOtp(phone, otp, purpose);

  // Audit log in Supabase (non-blocking, best-effort)
  supabase
    .from('otp_logs')
    .insert({
      phone,
      purpose,
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

  return true;
};

// ─── JWT ─────────────────────────────────────────────────────────────────────

const generateTokens = (userId, role) => {
  const accessToken = jwt.sign(
    { userId, role },
    process.env.JWT_SECRET,
    { expiresIn: process.env.JWT_EXPIRES_IN || '7d' }
  );

  const refreshToken = jwt.sign(
    { userId, role, type: 'refresh' },
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
 * Refresh access token using refresh token
 */
const refreshAccessToken = async (refreshToken) => {
  let decoded;
  try {
    decoded = jwt.verify(refreshToken, process.env.JWT_REFRESH_SECRET);
    if (decoded.type !== 'refresh') throw new Error('Invalid token type');
  } catch {
    throw new AppError('Invalid or expired refresh token', 401);
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

module.exports = { requestOtp, verifyOtp, loginOrRegister, refreshAccessToken, generateTokens };
