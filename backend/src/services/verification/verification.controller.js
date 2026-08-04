const { validationResult } = require('express-validator');
const verificationService = require('./verification.service');
const { success, error } = require('../../shared/utils/response');
const { query } = require('../../shared/db/client');

const validateForRegistration = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await verificationService.validateFaceForRegistration(req.user.id, req.body.image);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const confirmRegistration = async (req, res, next) => {
  try {
    const result = await verificationService.confirmFaceRegistration(req.user.id);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const verifyForRide = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await verificationService.verifyFaceForRide(
      req.user.id,
      req.params.ridePassengerId,
      req.body.image
    );
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const deleteFaceData = async (req, res, next) => {
  try {
    const result = await verificationService.deleteFaceData(req.user.id);
    return success(res, result, result.message);
  } catch (err) { next(err); }
};

const getVerificationStatus = async (req, res, next) => {
  try {
    const result = await query(
      'SELECT face_verified, face_consent_given, face_consent_given_at FROM users WHERE id = $1',
      [req.user.id]
    );
    if (!result.rows.length) return error(res, 'User not found', 404);
    const row = result.rows[0];
    let status = 'verified';
    if (!row.face_consent_given) status = 'consent_required';
    else if (!row.face_verified) status = 'verification_required';
    return success(res, {
      faceVerified: row.face_verified,
      consentGiven: row.face_consent_given,
      consentGivenAt: row.face_consent_given_at,
      status,
    });
  } catch (err) { next(err); }
};

module.exports = {
  validateForRegistration,
  confirmRegistration,
  verifyForRide,
  deleteFaceData,
  getVerificationStatus,
};
