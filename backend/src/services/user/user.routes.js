const express = require('express');
const { body, param } = require('express-validator');
const controller = require('./user.controller');
const { authenticate } = require('../../shared/middleware/authenticate');

const router = express.Router();

// All user routes require authentication
router.use(authenticate);

// POST /api/v1/users/register — complete registration after OTP
router.post('/register', [
  body('fullName').trim().isLength({ min: 2, max: 100 }).withMessage('Full name is required'),
  body('gender').isIn(['female', 'male', 'other', 'prefer_not_to_say']).withMessage('Invalid gender'),
  body('role').optional().isIn(['passenger', 'driver']).withMessage('Invalid role'),
  body('dateOfBirth').optional().isDate().withMessage('Invalid date of birth'),
], controller.completeRegistration);

// POST /api/v1/users/face-consent — record DPDP consent before face verification
router.post('/face-consent', controller.recordFaceConsent);

// GET /api/v1/users/profile
router.get('/profile', controller.getProfile);

// PATCH /api/v1/users/profile
router.patch('/profile', [
  body('full_name').optional().trim().isLength({ min: 2, max: 100 }),
  body('date_of_birth').optional().isDate(),
], controller.updateProfile);

// Emergency contacts
router.get('/emergency-contacts', controller.getEmergencyContacts);

router.post('/emergency-contacts', [
  body('name').trim().isLength({ min: 2, max: 100 }).withMessage('Contact name is required'),
  body('phone').trim().matches(/^[6-9]\d{9}$/).withMessage('Valid Indian mobile number required'),
  body('relation').optional().trim().isLength({ max: 50 }),
  body('isPrimary').optional().isBoolean(),
], controller.addEmergencyContact);

router.delete('/emergency-contacts/:contactId', [
  param('contactId').isUUID().withMessage('Invalid contact ID'),
], controller.deleteEmergencyContact);

// Wallet — two-step Razorpay-verified top-up
// Step 1: POST /api/v1/users/wallet/topup/order  → get Razorpay order
router.post('/wallet/topup/order', [
  body('amount').isFloat({ min: 100 }).withMessage('Minimum top-up is ₹100'),
], controller.createWalletTopupOrder);

// Step 2: POST /api/v1/users/wallet/topup/verify → submit payment proof, wallet credited
router.post('/wallet/topup/verify', [
  body('amount').isFloat({ min: 100 }).withMessage('Amount is required'),
  body('razorpay_order_id').notEmpty().withMessage('razorpay_order_id is required'),
  body('razorpay_payment_id').notEmpty().withMessage('razorpay_payment_id is required'),
  body('razorpay_signature').notEmpty().withMessage('razorpay_signature is required'),
], controller.verifyWalletTopup);

// DELETE /api/v1/users/account — DPDP right to erasure
router.delete('/account', controller.deleteAccount);

module.exports = router;
