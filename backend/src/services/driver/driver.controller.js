const { validationResult } = require('express-validator');
const driverService = require('./driver.service');
const { success, created, error } = require('../../shared/utils/response');

const registerDriver = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await driverService.registerDriver(req.user.id, req.body);
    return created(res, result, 'Driver profile created. Please upload your documents.');
  } catch (err) { next(err); }
};

const uploadDocument = async (req, res, next) => {
  try {
    if (!req.file) return error(res, 'No file uploaded.', 400);
    const { docType } = req.params;
    const result = await driverService.uploadDocument(
      req.user.id, docType, req.file.buffer, req.file.originalname
    );
    return success(res, result, 'Document uploaded successfully.');
  } catch (err) { next(err); }
};

const getProfile = async (req, res, next) => {
  try {
    const profile = await driverService.getDriverProfile(req.user.id);
    return success(res, { profile });
  } catch (err) { next(err); }
};

const setAvailability = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await driverService.setAvailability(req.user.id, req.body.isAvailable);
    return success(res, result, `You are now ${result.isAvailable ? 'online' : 'offline'}.`);
  } catch (err) { next(err); }
};

const updateLocation = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await driverService.updateLocation(req.user.id, req.body.lat, req.body.lng);
    return success(res, result);
  } catch (err) { next(err); }
};

// GET /api/v1/drivers/ride-requests — driver sees nearby open rides
const getNearbyRideRequests = async (req, res, next) => {
  try {
    const result = await driverService.getNearbyRideRequests(req.user.id);
    return success(res, result, `${result.count} ride request(s) nearby.`);
  } catch (err) { next(err); }
};

// POST /api/v1/drivers/ride-requests/:rideId/accept — driver accepts a ride
const acceptRide = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await driverService.acceptRide(req.user.id, req.params.rideId);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

module.exports = {
  registerDriver,
  uploadDocument,
  getProfile,
  setAvailability,
  updateLocation,
  getNearbyRideRequests,
  acceptRide,
};
