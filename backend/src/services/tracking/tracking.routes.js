const express = require('express');
const { param, body } = require('express-validator');
const controller = require('./tracking.controller');
const { authenticate } = require('../../shared/middleware/authenticate');

const router = express.Router();
router.use(authenticate);

// GET /api/v1/tracking/:rideId/location — latest driver location
router.get('/:rideId/location', [
  param('rideId').isUUID(),
], controller.getDriverLocation);

// GET /api/v1/tracking/:rideId/deviations — deviation history for a ride
router.get('/:rideId/deviations', [
  param('rideId').isUUID(),
], controller.getRideDeviations);

// POST /api/v1/tracking/deviations/:deviationId/acknowledge
router.post('/deviations/:deviationId/acknowledge', [
  param('deviationId').isUUID(),
  body('response').isIn(['ok', 'alert']).withMessage('Response must be "ok" or "alert"'),
], controller.acknowledgeDeviation);

module.exports = router;
