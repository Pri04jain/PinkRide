const jwt = require('jsonwebtoken');
const { AppError } = require('./errorHandler');
const { supabase } = require('../db/client');

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
