const { validationResult } = require('express-validator');
const verificationService = require('./verification.service');
const { success, error } = require('../../shared/utils/response');
const { supabase } = require('../../shared/db/client');

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
    const { data: user, error: dbError } = await supabase
      .from('users')
      .select('face_verified, face_consent_given, face_consent_given_at')
      .eq('id', req.user.id)
      .single();

    if (dbError || !user) return error(res, 'User not found', 404);

    let status = 'verified';
    if (!user.face_consent_given) status = 'consent_required';
    else if (!user.face_verified) status = 'verification_required';

    return success(res, {
      faceVerified: user.face_verified,
      consentGiven: user.face_consent_given,
      consentGivenAt: user.face_consent_given_at,
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
