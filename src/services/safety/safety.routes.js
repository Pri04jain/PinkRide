const express = require('express');
const { param, body } = require('express-validator');
const controller = require('./safety.controller');
const { authenticate, requireRole } = require('../../shared/middleware/authenticate');

const router = express.Router();
router.use(authenticate);

// POST /api/v1/safety/sos/:rideId — passenger triggers SOS
router.post('/sos/:rideId', requireRole('passenger'), [
  param('rideId').isUUID(),
  body('lat').optional().isFloat({ min: -90, max: 90 }),
  body('lng').optional().isFloat({ min: -180, max: 180 }),
], controller.triggerSOS);

// POST /api/v1/safety/deviations/:deviationId/respond — passenger responds to deviation
router.post('/deviations/:deviationId/respond', requireRole('passenger'), [
  param('deviationId').isUUID(),
  body('response').isIn(['ok', 'alert']).withMessage('Must be "ok" or "alert"'),
], controller.respondToDeviation);

// POST /api/v1/safety/check-in/:rideId — passenger safety check-in
router.post('/check-in/:rideId', requireRole('passenger'), [
  param('rideId').isUUID(),
], controller.safetyCheckIn);

// GET /api/v1/safety/emergency-contacts
router.get('/emergency-contacts', controller.getEmergencyContacts);

module.exports = router;
