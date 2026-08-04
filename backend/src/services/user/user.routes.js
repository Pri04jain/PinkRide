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

// Wallet
router.post('/wallet/topup', [
  body('amount').isFloat({ min: 50 }).withMessage('Minimum top-up is ₹50'),
  body('referenceId').optional().isString(),
], controller.topUpWallet);

// DELETE /api/v1/users/account — DPDP right to erasure
router.delete('/account', controller.deleteAccount);

module.exports = router;
