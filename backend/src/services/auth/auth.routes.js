const express = require('express');
const { body } = require('express-validator');
const rateLimit = require('express-rate-limit');
const controller = require('./auth.controller');

const router = express.Router();

// Strict rate limit for OTP requests
const otpLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 5,
  message: { success: false, message: 'Too many OTP requests. Try again in an hour.' },
  keyGenerator: (req) => req.body.phone || req.ip,
});

// POST /api/v1/auth/request-otp
router.post(
  '/request-otp',
  otpLimiter,
  [
    body('phone')
      .trim()
      .matches(/^[6-9]\d{9}$/)
      .withMessage('Enter a valid 10-digit Indian mobile number'),
    body('purpose')
      .optional()
      .isIn(['login', 'registration', 'ride_verification'])
      .withMessage('Invalid OTP purpose'),
  ],
  controller.requestOtp
);

// POST /api/v1/auth/verify-otp
router.post(
  '/verify-otp',
  [
    body('phone')
      .trim()
      .matches(/^[6-9]\d{9}$/)
      .withMessage('Enter a valid 10-digit Indian mobile number'),
    body('otp')
      .trim()
      .isLength({ min: 6, max: 6 })
      .isNumeric()
      .withMessage('OTP must be 6 digits'),
    body('purpose')
      .optional()
      .isIn(['login', 'registration', 'ride_verification'])
      .withMessage('Invalid OTP purpose'),
  ],
  controller.verifyOtpAndLogin
);

// POST /api/v1/auth/refresh-token
router.post('/refresh-token', controller.refreshToken);

// POST /api/v1/auth/logout
router.post('/logout', controller.logout);

module.exports = router;
