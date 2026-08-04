const { validationResult } = require('express-validator');
const rideService = require('./ride.service');
const otpService = require('./otp.service');
const { success, created, error } = require('../../shared/utils/response');

const bookRide = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await rideService.bookRide(req.user.id, req.body);
    return created(res, result, result.message);
  } catch (err) { next(err); }
};

const getFareEstimate = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const { distanceKm, rideType = 'private' } = req.query;
    const result = await rideService.getFareEstimate(parseFloat(distanceKm), rideType);
    return success(res, result);
  } catch (err) { next(err); }
};

const findMatch = async (req, res, next) => {
  try {
    const result = await rideService.findMatch(req.params.rideId);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const respondToMatch = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const { rideId, ridePassengerId } = req.params;
    const result = await rideService.respondToMatch(rideId, ridePassengerId, req.user.id, req.body.accept);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const proposeTimeShift = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await rideService.proposeTimeShift(req.params.rideId, req.user.id, req.body.newScheduledAt);
    return success(res, result, 'Time-shift proposal sent.');
  } catch (err) { next(err); }
};

const respondToTimeShift = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await rideService.respondToTimeShift(req.params.rideId, req.user.id, req.body.accept);
    return success(res, result, result.accepted ? 'Time-shift accepted.' : 'Time-shift declined.');
  } catch (err) { next(err); }
};

const cancelRide = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const cancelledBy = req.user.role === 'driver' ? 'driver' : 'passenger';
    const result = await rideService.cancelRide(req.user.id, req.params.rideId, req.body.reason, cancelledBy);
    return success(res, result, 'Ride cancelled.');
  } catch (err) { next(err); }
};

const getActiveRide = async (req, res, next) => {
  try {
    const ride = req.user.role === 'driver'
      ? await rideService.getDriverActiveRide(req.user.id)
      : await rideService.getActiveRide(req.user.id);
    return success(res, { ride });
  } catch (err) { next(err); }
};

const generateOtp = async (req, res, next) => {
  try {
    const result = await otpService.generateRideOtp(req.params.rideId, req.user.id);
    return success(res, result, 'Ride OTP generated.');
  } catch (err) { next(err); }
};

const verifyOtp = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await otpService.verifyRideOtp(req.params.rideId, req.user.id, req.body.otp);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const completeRide = async (req, res, next) => {
  try {
    const result = await otpService.completeRide(req.params.rideId, req.user.id);
    return success(res, result, 'Trip completed.');
  } catch (err) { next(err); }
};

module.exports = {
  bookRide, getFareEstimate, findMatch, respondToMatch,
  proposeTimeShift, respondToTimeShift, cancelRide,
  getActiveRide, generateOtp, verifyOtp, completeRide,
};
