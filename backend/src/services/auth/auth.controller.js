const { validationResult } = require('express-validator');
const authService = require('./auth.service');
const { success, error } = require('../../shared/utils/response');

const requestOtp = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return error(res, 'Validation failed', 422, errors.array());
    }

    const { phone, purpose = 'login' } = req.body;
    const result = await authService.requestOtp(phone, purpose);
    return success(res, result, 'OTP sent successfully');
  } catch (err) {
    next(err);
  }
};

const verifyOtpAndLogin = async (req, res, next) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return error(res, 'Validation failed', 422, errors.array());
    }

    const { phone, otp, purpose = 'login' } = req.body;

    await authService.verifyOtp(phone, otp, purpose);
    const result = await authService.loginOrRegister(phone);

    return success(res, result, result.isNewUser ? 'Registration started' : 'Login successful');
  } catch (err) {
    next(err);
  }
};

const refreshToken = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    if (!refreshToken) {
      return error(res, 'Refresh token required', 400);
    }

    const result = await authService.refreshAccessToken(refreshToken);
    return success(res, result, 'Token refreshed');
  } catch (err) {
    next(err);
  }
};

const logout = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    const result = await authService.logout(refreshToken);
    return success(res, result, 'Logged out successfully.');
  } catch (err) {
    next(err);
  }
};

module.exports = { requestOtp, verifyOtpAndLogin, refreshToken, logout };
