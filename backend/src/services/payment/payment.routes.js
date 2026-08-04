const express = require('express');
const { body, param } = require('express-validator');
const controller = require('./payment.controller');
const { authenticate, requireRole } = require('../../shared/middleware/authenticate');

const router = express.Router();
router.use(authenticate);

// ─── Wallet ───────────────────────────────────────────────────────────────────
// GET /api/v1/payments/wallet
router.get('/wallet', controller.getWallet);

// GET /api/v1/payments/fines
router.get('/fines', controller.getPendingFines);

// ─── Ride Payments ────────────────────────────────────────────────────────────
// POST /api/v1/payments/rides/:rideId/upi/order
router.post('/rides/:rideId/upi/order', requireRole('passenger'), [
  param('rideId').isUUID(),
], controller.createUpiOrder);

// POST /api/v1/payments/rides/:rideId/upi/verify
router.post('/rides/:rideId/upi/verify', requireRole('passenger'), [
  param('rideId').isUUID(),
  body('razorpay_order_id').notEmpty(),
  body('razorpay_payment_id').notEmpty(),
  body('razorpay_signature').notEmpty(),
], controller.verifyUpiPayment);

// POST /api/v1/payments/rides/:rideId/cash/confirm  (driver confirms cash received)
router.post('/rides/:rideId/cash/confirm', requireRole('driver'), [
  param('rideId').isUUID(),
], controller.confirmCashPayment);

// ─── Ratings ──────────────────────────────────────────────────────────────────
// GET /api/v1/payments/ratings/my
router.get('/ratings/my', controller.getUserRatings);

// GET /api/v1/payments/rides/:rideId/ratings/pending
router.get('/rides/:rideId/ratings/pending', [
  param('rideId').isUUID(),
], controller.getPendingRatings);

// GET /api/v1/payments/rides/:rideId/ratings
router.get('/rides/:rideId/ratings', [
  param('rideId').isUUID(),
], controller.getRideRatings);

// POST /api/v1/payments/rides/:rideId/rate
router.post('/rides/:rideId/rate', [
  param('rideId').isUUID(),
  body('ratedUserId').isUUID().withMessage('ratedUserId must be a valid UUID'),
  body('score').isInt({ min: 1, max: 5 }).withMessage('Score must be 1-5'),
  body('tags').optional().isArray(),
  body('comment').optional().trim().isLength({ max: 300 }),
], controller.submitRating);

module.exports = router;
