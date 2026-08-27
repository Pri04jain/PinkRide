const express = require('express');
const { body, query: qv, param } = require('express-validator');
const controller = require('./ride.controller');
const { authenticate, requireRole } = require('../../shared/middleware/authenticate');

const router = express.Router();
router.use(authenticate);

// GET  /api/v1/rides/fare-estimate?distanceKm=12&rideType=shared
// Also accepts pickupLat/pickupLng/dropLat/dropLng for server-side distance calculation
router.get('/fare-estimate', [
  qv('distanceKm').optional().isFloat({ min: 0.1 }).withMessage('distanceKm must be a positive number'),
  qv('rideType').optional().isIn(['private', 'shared', 'women_only_shared']),
  qv('pickupLat').optional().isFloat({ min: -90, max: 90 }),
  qv('pickupLng').optional().isFloat({ min: -180, max: 180 }),
  qv('dropLat').optional().isFloat({ min: -90, max: 90 }),
  qv('dropLng').optional().isFloat({ min: -180, max: 180 }),
], controller.getFareEstimate);

// GET  /api/v1/rides/active — current active ride for the user
router.get('/active', controller.getActiveRide);

// POST /api/v1/rides/book
router.post('/book', requireRole('passenger'), [
  body('rideType').isIn(['private', 'shared', 'women_only_shared']).withMessage('Invalid ride type'),
  body('pickupLat').isFloat({ min: -90, max: 90 }).withMessage('Invalid pickup latitude'),
  body('pickupLng').isFloat({ min: -180, max: 180 }).withMessage('Invalid pickup longitude'),
  body('pickupAddress').trim().notEmpty().withMessage('Pickup address required'),
  body('dropLat').isFloat({ min: -90, max: 90 }).withMessage('Invalid drop latitude'),
  body('dropLng').isFloat({ min: -180, max: 180 }).withMessage('Invalid drop longitude'),
  body('dropAddress').trim().notEmpty().withMessage('Drop address required'),
  body('scheduledAt').isISO8601().withMessage('scheduledAt must be a valid ISO date'),
  body('distanceKm').optional().isFloat({ min: 0.1 }),  // ignored — server calculates from coordinates
  body('durationMin').optional().isInt({ min: 1 }),     // ignored — server calculates from coordinates
  body('paymentMethod').optional().isIn(['cash', 'upi']),
], controller.bookRide);

// GET  /api/v1/rides/:rideId/find-match
router.get('/:rideId/find-match', requireRole('passenger'), [
  param('rideId').isUUID(),
], controller.findMatch);

// POST /api/v1/rides/:rideId/match/:ridePassengerId/respond
router.post('/:rideId/match/:ridePassengerId/respond', requireRole('passenger'), [
  param('rideId').isUUID(),
  param('ridePassengerId').isUUID(),
  body('accept').isBoolean().withMessage('accept must be true or false'),
], controller.respondToMatch);

// POST /api/v1/rides/:rideId/time-shift
router.post('/:rideId/time-shift', requireRole('passenger'), [
  param('rideId').isUUID(),
  body('newScheduledAt').isISO8601().withMessage('newScheduledAt must be a valid ISO date'),
], controller.proposeTimeShift);

// POST /api/v1/rides/:rideId/time-shift/respond
router.post('/:rideId/time-shift/respond', requireRole('passenger'), [
  param('rideId').isUUID(),
  body('accept').isBoolean(),
], controller.respondToTimeShift);

// POST /api/v1/rides/:rideId/cancel
router.post('/:rideId/cancel', [
  param('rideId').isUUID(),
  body('reason').optional().trim(),
], controller.cancelRide);

// POST /api/v1/rides/:rideId/otp/generate  (passenger — after face verify)
router.post('/:rideId/otp/generate', requireRole('passenger'), [
  param('rideId').isUUID(),
], controller.generateOtp);

// POST /api/v1/rides/:rideId/otp/verify  (driver — enters OTP to start trip)
router.post('/:rideId/otp/verify', requireRole('driver'), [
  param('rideId').isUUID(),
  body('otp').isLength({ min: 6, max: 6 }).isNumeric().withMessage('OTP must be 6 digits'),
], controller.verifyOtp);

// POST /api/v1/rides/:rideId/complete  (driver marks trip done)
router.post('/:rideId/complete', requireRole('driver'), [
  param('rideId').isUUID(),
], controller.completeRide);

module.exports = router;
