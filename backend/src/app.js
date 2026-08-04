require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const authRoutes = require('./services/auth/auth.routes');
const userRoutes = require('./services/user/user.routes');
const driverRoutes = require('./services/driver/driver.routes');
const verificationRoutes = require('./services/verification/verification.routes');
const rideRoutes = require('./services/ride/ride.routes');
const trackingRoutes = require('./services/tracking/tracking.routes');
const safetyRoutes = require('./services/safety/safety.routes');
const paymentRoutes = require('./services/payment/payment.routes');
const notificationRoutes = require('./services/notification/notification.routes');

const { errorHandler } = require('./shared/middleware/errorHandler');
const { notFound } = require('./shared/middleware/notFound');
const { initSocket } = require('./shared/socket/socket.server');

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
  credentials: true,
}));

// Rate limiting - global
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100,
  message: { success: false, message: 'Too many requests, please try again later.' },
});
app.use(limiter);

// Body parsing
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Logging
app.use(morgan(process.env.NODE_ENV === 'production' ? 'combined' : 'dev'));

// Health check
app.get('/health', (req, res) => {
  res.json({
    success: true,
    service: 'PinkRide API',
    version: '1.0.0',
    city: 'Jaipur',
    timestamp: new Date().toISOString(),
  });
});

// API routes
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/users', userRoutes);
app.use('/api/v1/drivers', driverRoutes);
app.use('/api/v1/verification', verificationRoutes);
app.use('/api/v1/rides', rideRoutes);
app.use('/api/v1/tracking', trackingRoutes);
app.use('/api/v1/safety', safetyRoutes);
app.use('/api/v1/payments', paymentRoutes);
app.use('/api/v1/notifications', notificationRoutes);

// Error handling
app.use(notFound);
app.use(errorHandler);

const PORT = process.env.PORT || 3000;
const server = app.listen(PORT, () => {
  console.log(`PinkRide API running on port ${PORT} [${process.env.NODE_ENV || 'development'}]`);
});

// Attach Socket.io to the HTTP server
initSocket(server);

module.exports = { app, server };
