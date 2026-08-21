const { validationResult } = require('express-validator');
const paymentService = require('./payment.service');
const ratingService = require('./rating.service');
const { success, error } = require('../../shared/utils/response');

// ─── Payment ──────────────────────────────────────────────────────────────────

const createUpiOrder = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await paymentService.createUpiOrder(req.user.id, req.params.rideId);
    return success(res, result, 'Payment order created.');
  } catch (err) { next(err); }
};

const verifyUpiPayment = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await paymentService.verifyUpiPayment(req.user.id, req.params.rideId, req.body);
    return success(res, result, 'Payment verified. Thank you!');
  } catch (err) { next(err); }
};

const confirmCashPayment = async (req, res, next) => {
  try {
    const result = await paymentService.confirmCashPayment(req.user.id, req.params.rideId);
    return success(res, result, 'Cash payment confirmed.');
  } catch (err) { next(err); }
};

const getWallet = async (req, res, next) => {
  try {
    const [balance, transactions] = await Promise.all([
      paymentService.getWalletBalance(req.user.id),
      paymentService.getWalletTransactions(req.user.id),
    ]);
    return success(res, { balance, transactions });
  } catch (err) { next(err); }
};

const getPendingFines = async (req, res, next) => {
  try {
    const fines = await paymentService.getPendingFines(req.user.id);
    return success(res, { fines });
  } catch (err) { next(err); }
};

// ─── Ratings ──────────────────────────────────────────────────────────────────

const submitRating = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await ratingService.submitRating({
      rideId: req.params.rideId,
      ratedBy: req.user.id,
      ratedUserId: req.body.ratedUserId,
      score: req.body.score,
      tags: req.body.tags || [],
      comment: req.body.comment,
    });
    return success(res, result, 'Rating submitted. Thank you!');
  } catch (err) { next(err); }
};

const getPendingRatings = async (req, res, next) => {
  try {
    const pending = await ratingService.getPendingRatings(req.user.id);
    return success(res, { pending });
  } catch (err) { next(err); }
};

const getRideRatings = async (req, res, next) => {
  try {
    const ratings = await ratingService.getRideRatings(req.params.rideId);
    return success(res, { ratings });
  } catch (err) { next(err); }
};

const getUserRatings = async (req, res, next) => {
  try {
    const ratings = await ratingService.getUserRatings(req.user.id);
    return success(res, { ratings });
  } catch (err) { next(err); }
};

module.exports = {
  createUpiOrder, verifyUpiPayment, confirmCashPayment,
  getWallet, getPendingFines,
  submitRating, getPendingRatings, getRideRatings, getUserRatings,
};
