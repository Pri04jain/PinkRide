const express = require('express');
const { body, param } = require('express-validator');
const rateLimit = require('express-rate-limit');
const controller = require('./verification.controller');
const { authenticate } = require('../../shared/middleware/authenticate');

const router = express.Router();

// All verification routes require authentication
router.use(authenticate);

// Strict rate limit for face verification (prevent brute force)
const faceLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  message: { success: false, message: 'Too many verification attempts. Try again in 15 minutes.' },
  keyGenerator: (req) => req.user.id,
});

router.use(faceLimiter);

// GET /api/v1/verification/status
router.get('/status', controller.getVerificationStatus);

// POST /api/v1/verification/register/validate
// Step 1: Submit selfie — validates liveness, returns session token
router.post(
  '/register/validate',
  [
    body('image')
      .notEmpty()
      .withMessage('Image data is required')
      .isString()
      .withMessage('Image must be base64 encoded'),
  ],
  controller.validateForRegistration
);

// POST /api/v1/verification/register/confirm
// Step 2: Index validated face into Rekognition
router.post('/register/confirm', controller.confirmRegistration);

// POST /api/v1/verification/ride/:ridePassengerId
// Pre-ride face check — must pass before OTP is issued
router.post(
  '/ride/:ridePassengerId',
  [
    param('ridePassengerId').isUUID().withMessage('Invalid ride passenger ID'),
    body('image')
      .notEmpty()
      .withMessage('Image data is required')
      .isString()
      .withMessage('Image must be base64 encoded'),
  ],
  controller.verifyForRide
);

// DELETE /api/v1/verification/face-data
// DPDP Act — user requests deletion of face embedding
router.delete('/face-data', controller.deleteFaceData);

module.exports = router;
