const { validationResult } = require('express-validator');
const adminService = require('./admin.service');
const { success, error } = require('../../shared/utils/response');

const getQueue = async (req, res, next) => {
  try {
    const { status = 'under_review', page = 1, limit = 20 } = req.query;
    const result = await adminService.getDriverQueue({
      status,
      page: parseInt(page),
      limit: parseInt(limit),
    });
    return success(res, result);
  } catch (err) { next(err); }
};

const getDriverDetail = async (req, res, next) => {
  try {
    const driver = await adminService.getDriverDetail(req.params.driverId);
    return success(res, { driver });
  } catch (err) { next(err); }
};

const approveDriver = async (req, res, next) => {
  try {
    const result = await adminService.approveDriver(req.params.driverId, req.user.id);
    return success(res, result, 'Driver approved successfully.');
  } catch (err) { next(err); }
};

const rejectDriver = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await adminService.rejectDriver(req.params.driverId, req.user.id, req.body.reason);
    return success(res, result, 'Driver rejected.');
  } catch (err) { next(err); }
};

const suspendDriver = async (req, res, next) => {
  try {
    const errs = validationResult(req);
    if (!errs.isEmpty()) return error(res, 'Validation failed', 422, errs.array());
    const result = await adminService.suspendDriver(req.params.driverId, req.user.id, req.body.reason);
    return success(res, result, 'Driver suspended.');
  } catch (err) { next(err); }
};

const reinstateDriver = async (req, res, next) => {
  try {
    const result = await adminService.reinstateDriver(req.params.driverId, req.user.id);
    return success(res, result, 'Driver reinstated.');
  } catch (err) { next(err); }
};

const getDashboardStats = async (req, res, next) => {
  try {
    const stats = await adminService.getDashboardStats();
    return success(res, { stats });
  } catch (err) { next(err); }
};

module.exports = {
  getQueue, getDriverDetail, approveDriver, rejectDriver,
  suspendDriver, reinstateDriver, getDashboardStats,
};
