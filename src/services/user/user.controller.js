const { validationResult } = require('express-validator');
const userService = require('./user.service');
const paymentService = require('../payment/payment.service');
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

const createWalletTopupOrder = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());
    const result = await paymentService.createWalletTopupOrder(req.user.id, req.body.amount);
    return success(res, result, 'Top-up order created. Complete payment to credit your wallet.');
  } catch (err) { next(err); }
};

const verifyWalletTopup = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return error(res, 'Validation failed', 422, errors.array());
    // amount is NOT passed — service reads it from payment_orders for security
    const result = await paymentService.verifyWalletTopup(req.user.id, req.body);
    return success(res, result, 'Wallet topped up successfully.');
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
  createWalletTopupOrder, verifyWalletTopup, deleteAccount,
};
