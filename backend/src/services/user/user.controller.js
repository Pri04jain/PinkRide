const { validationResult } = require('express-validator');
const userService = require('./user.service');
const { success, created, error } = require('../../shared/utils/response');

const completeRegistration = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());

    const user = await userService.completeRegistration(req.user.id, req.body);
    return success(res, { user }, 'Registration completed');
  } catch (err) { next(err); }
};

const recordFaceConsent = async (req, res, next) => {
  try {
    const result = await userService.recordFaceConsent(req.user.id);
    return success(res, result, 'Consent recorded. You may proceed with face verification.');
  } catch (err) { next(err); }
};

const getProfile = async (req, res, next) => {
  try {
    const profile = await userService.getProfile(req.user.id);
    return success(res, { profile });
  } catch (err) { next(err); }
};

const updateProfile = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());

    const profile = await userService.updateProfile(req.user.id, req.body);
    return success(res, { profile }, 'Profile updated');
  } catch (err) { next(err); }
};

const addEmergencyContact = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());

    const contact = await userService.upsertEmergencyContact(req.user.id, req.body);
    return created(res, { contact }, 'Emergency contact added');
  } catch (err) { next(err); }
};

const getEmergencyContacts = async (req, res, next) => {
  try {
    const contacts = await userService.getEmergencyContacts(req.user.id);
    return success(res, { contacts });
  } catch (err) { next(err); }
};

const deleteEmergencyContact = async (req, res, next) => {
  try {
    const result = await userService.deleteEmergencyContact(req.user.id, req.params.contactId);
    return success(res, result, 'Emergency contact removed');
  } catch (err) { next(err); }
};

const topUpWallet = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());

    const result = await userService.topUpWallet(req.user.id, req.body.amount, req.body.referenceId);
    return success(res, result, 'Wallet topped up successfully');
  } catch (err) { next(err); }
};

const deleteAccount = async (req, res, next) => {
  try {
    await userService.deleteAccount(req.user.id);
    return success(res, {}, 'Account deleted. Your data has been removed.');
  } catch (err) { next(err); }
};

module.exports = {
  completeRegistration, recordFaceConsent, getProfile, updateProfile,
  addEmergencyContact, getEmergencyContacts, deleteEmergencyContact,
  topUpWallet, deleteAccount,
};
