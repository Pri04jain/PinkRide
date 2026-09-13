const jwt = require('jsonwebtoken');
const { AppError } = require('./errorHandler');
const { supabase } = require('../db/client');
const { otpStore } = require('../cache/otpStore');

/**
 * Verify JWT and attach user to request
 */
const authenticate = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new AppError('Authentication required', 401);
    }

    const token = authHeader.split(' ')[1];
    const decoded = jwt.verify(token, process.env.JWT_SECRET);

    // O3: check revocation — in-memory first (sub-ms), DB fallback on miss.
    // Revoked JTIs are written to otpStore on logout with matching TTL,
    // so the DB is only queried on a process restart or across instances.
    if (decoded.jti) {
      const inMemory = otpStore.get(`revoked_jti:${decoded.jti}`);
      if (inMemory) {
        throw new AppError('Token has been revoked. Please log in again.', 401);
      }

      // DB fallback — covers post-restart scenarios and multi-instance deployments
      const { data: revoked } = await supabase
        .from('revoked_tokens')
        .select('jti')
        .eq('jti', decoded.jti)
        .maybeSingle();

      if (revoked) {
        // Backfill in-memory cache to short-circuit future DB hits
        const ttlSeconds = Math.max(0, decoded.exp - Math.floor(Date.now() / 1000));
        if (ttlSeconds > 0) otpStore.set(`revoked_jti:${decoded.jti}`, '1', ttlSeconds);
        throw new AppError('Token has been revoked. Please log in again.', 401);
      }
    }

    // Fetch user from Supabase to confirm they're still active
    const { data: user, error } = await supabase
      .from('users')
      .select('id, phone, role, is_active, face_verified, city')
      .eq('id', decoded.userId)
      .single();

    if (error || !user || !user.is_active) {
      throw new AppError('Account not found or deactivated', 401);
    }

    req.user = user;
    next();
  } catch (err) {
    if (err.name === 'JsonWebTokenError' || err.name === 'TokenExpiredError') {
      return next(new AppError('Invalid or expired token', 401));
    }
    next(err);
  }
};

/**
 * Restrict access to specific roles
 * Usage: router.get('/admin', authenticate, requireRole('admin'), handler)
 */
const requireRole = (...roles) => (req, res, next) => {
  if (!req.user || !roles.includes(req.user.role)) {
    return next(new AppError('Access denied: insufficient permissions', 403));
  }
  next();
};

module.exports = { authenticate, requireRole };
