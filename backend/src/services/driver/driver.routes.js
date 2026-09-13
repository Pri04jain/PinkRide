const express = require('express');
const { body, param, query } = require('express-validator');
const driverController = require('./driver.controller');
const adminController = require('./admin.controller');
const { authenticate, requireRole } = require('../../shared/middleware/authenticate');
const { upload, handleUploadError } = require('../../shared/middleware/upload');

const router = express.Router();

// ─── Driver Ride-Request Routes ───────────────────────────────────────────────

// GET /api/v1/drivers/ride-requests — list nearby open rides for an online driver
router.get(
  '/ride-requests',
  authenticate,
  requireRole('driver'),
  driverController.getNearbyRideRequests
);

// POST /api/v1/drivers/ride-requests/:rideId/accept — driver accepts a specific ride
router.post(
  '/ride-requests/:rideId/accept',
  authenticate,
  requireRole('driver'),
  [param('rideId').isUUID().withMessage('Invalid ride ID')],
  driverController.acceptRide
);

// ─── Driver Routes (role: driver) ─────────────────────────────────────────────

// POST /api/v1/drivers/register
router.post(
  '/register',
  authenticate,
  requireRole('driver'),
  [
    body('licenseNumber').trim().notEmpty().withMessage('License number is required'),
    body('licenseExpiry').isDate().withMessage('Valid license expiry date required'),
    body('vehicleNumber').trim().notEmpty().withMessage('Vehicle number is required'),
    body('vehicleType')
      .isIn(['Hatchback', 'Sedan', 'SUV', 'MUV', 'Van'])
      .withMessage('Invalid vehicle type'),
    body('vehicleMake').trim().notEmpty().withMessage('Vehicle make is required'),
    body('vehicleModel').trim().notEmpty().withMessage('Vehicle model is required'),
    body('vehicleColor').trim().notEmpty().withMessage('Vehicle color is required'),
    body('vehicleYear')
      .isInt({ min: 2005, max: new Date().getFullYear() })
      .withMessage('Vehicle year must be 2005 or newer'),
  ],
  driverController.registerDriver
);

// POST /api/v1/drivers/documents/:docType  (docType: license | rc | insurance)
router.post(
  '/documents/:docType',
  authenticate,
  requireRole('driver'),
  upload.single('file'),
  handleUploadError,
  [
    param('docType')
      .isIn(['license', 'rc', 'insurance'])
      .withMessage('Invalid document type. Use: license, rc, insurance'),
  ],
  driverController.uploadDocument
);

// GET /api/v1/drivers/profile
router.get('/profile', authenticate, requireRole('driver'), driverController.getProfile);

// PATCH /api/v1/drivers/availability
router.patch(
  '/availability',
  authenticate,
  requireRole('driver'),
  [body('isAvailable').isBoolean().withMessage('isAvailable must be true or false')],
  driverController.setAvailability
);

// PATCH /api/v1/drivers/location
router.patch(
  '/location',
  authenticate,
  requireRole('driver'),
  [
    body('lat').isFloat({ min: -90, max: 90 }).withMessage('Invalid latitude'),
    body('lng').isFloat({ min: -180, max: 180 }).withMessage('Invalid longitude'),
  ],
  driverController.updateLocation
);

// ─── Admin Routes (role: admin) ───────────────────────────────────────────────

// GET /api/v1/drivers/admin/queue?status=under_review&page=1
router.get(
  '/admin/queue',
  authenticate,
  requireRole('admin'),
  adminController.getQueue
);

// GET /api/v1/drivers/admin/stats
router.get('/admin/stats', authenticate, requireRole('admin'), adminController.getDashboardStats);

// GET /api/v1/drivers/admin/:driverId
router.get(
  '/admin/:driverId',
  authenticate,
  requireRole('admin'),
  [param('driverId').isUUID().withMessage('Invalid driver ID')],
  adminController.getDriverDetail
);

// POST /api/v1/drivers/admin/:driverId/approve
router.post(
  '/admin/:driverId/approve',
  authenticate,
  requireRole('admin'),
  [param('driverId').isUUID().withMessage('Invalid driver ID')],
  adminController.approveDriver
);

// POST /api/v1/drivers/admin/:driverId/reject
router.post(
  '/admin/:driverId/reject',
  authenticate,
  requireRole('admin'),
  [
    param('driverId').isUUID().withMessage('Invalid driver ID'),
    body('reason').trim().isLength({ min: 10 }).withMessage('Rejection reason must be at least 10 characters'),
  ],
  adminController.rejectDriver
);

// POST /api/v1/drivers/admin/:driverId/suspend
router.post(
  '/admin/:driverId/suspend',
  authenticate,
  requireRole('admin'),
  [
    param('driverId').isUUID().withMessage('Invalid driver ID'),
    body('reason').trim().isLength({ min: 10 }).withMessage('Suspension reason required'),
  ],
  adminController.suspendDriver
);

// POST /api/v1/drivers/admin/:driverId/reinstate
router.post(
  '/admin/:driverId/reinstate',
  authenticate,
  requireRole('admin'),
  [param('driverId').isUUID().withMessage('Invalid driver ID')],
  adminController.reinstateDriver
);

module.exports = router;
