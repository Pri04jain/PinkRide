const { validationResult } = require('express-validator');
const safetyService = require('./safety.service');
const { success, error } = require('../../shared/utils/response');

const triggerSOS = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await safetyService.triggerSOS(
      req.user.id,
      req.params.rideId,
      req.body.lat,
      req.body.lng
    );
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const respondToDeviation = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await safetyService.respondToDeviation(
      req.user.id,
      req.params.deviationId,
      req.body.response
    );
    return success(res, result, 'Response recorded.');
  } catch (err) { next(err); }
};

const safetyCheckIn = async (req, res, next) => {
  try {
    const result = await safetyService.safetyCheckIn(req.user.id, req.params.rideId);
    return success(res, result, 'Check-in recorded. Glad you are safe.');
  } catch (err) { next(err); }
};

const getEmergencyContacts = async (req, res, next) => {
  try {
    const contacts = await safetyService.getEmergencyContacts(req.user.id);
    return success(res, { contacts });
  } catch (err) { next(err); }
};

module.exports = { triggerSOS, respondToDeviation, safetyCheckIn, getEmergencyContacts };
