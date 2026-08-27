const { validationResult } = require('express-validator');
const trackingService = require('./tracking.service');
const { success, error } = require('../../shared/utils/response');

const getDriverLocation = async (req, res, next) => {
  try {
    const location = await trackingService.getDriverLocation(req.params.rideId);
    return success(res, { location });
  } catch (err) { next(err); }
};

const getRideDeviations = async (req, res, next) => {
  try {
    const deviations = await trackingService.getRideDeviations(req.params.rideId);
    return success(res, { deviations });
  } catch (err) { next(err); }
};

const acknowledgeDeviation = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await trackingService.acknowledgeDeviation(
      req.params.deviationId,
      req.user.id,
      req.body.response
    );
    return success(res, result, 'Response recorded.');
  } catch (err) { next(err); }
};

const getRideLocationHistory = async (req, res, next) => {
  try {
    const history = await trackingService.getRideLocationHistory(req.params.rideId);
    return success(res, { history, count: history.length });
  } catch (err) { next(err); }
};

module.exports = { getDriverLocation, getRideDeviations, acknowledgeDeviation, getRideLocationHistory };
