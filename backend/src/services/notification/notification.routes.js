const express = require('express');
const { body } = require('express-validator');
const { validationResult } = require('express-validator');
const { authenticate } = require('../../shared/middleware/authenticate');
const { registerDeviceToken } = require('./fcm.service');
const { success, error } = require('../../shared/utils/response');

const router = express.Router();
router.use(authenticate);

// POST /api/v1/notifications/device-token — register FCM token
router.post('/device-token', [
  body('fcmToken').notEmpty().withMessage('FCM token required'),
  body('platform').isIn(['android', 'ios']).withMessage('Platform must be android or ios'),
], async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await registerDeviceToken(req.user.id, req.body.fcmToken, req.body.platform);
    return success(res, result, 'Device token registered.');
  } catch (err) { next(err); }
});

module.exports = router;
