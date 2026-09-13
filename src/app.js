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

// CORS — reads ALLOWED_ORIGINS from env (comma-separated list of allowed origins).
// In development, also allows any localhost port so Flutter web (random port) works.
// In production, ALLOWED_ORIGINS must be set explicitly.
const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map((o) => o.trim())
  : [];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (curl, Postman, server-to-server)
    if (!origin) return callback(null, true);

    // In development: allow ANY localhost origin regardless of port
    // This covers Flutter web which uses a random port on every run
    if (process.env.NODE_ENV !== 'production') {
      const isLocalhost = /^http:\/\/localhost(:\d+)?$/.test(origin) ||
                          /^http:\/\/127\.0\.0\.1(:\d+)?$/.test(origin);
      if (isLocalhost) return callback(null, true);
    }

    // In production: only explicitly listed origins
    if (allowedOrigins.includes(origin)) return callback(null, true);

    callback(new Error(`CORS: origin '${origin}' not allowed`));
  },
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

// Serve locally-uploaded files in development.
// In production, files are stored in Supabase Storage and served via signed URLs —
// this mount is a no-op when SUPABASE_STORAGE_BUCKET is configured.
if (!process.env.SUPABASE_STORAGE_BUCKET) {
  const path = require('path');
  app.use('/uploads', express.static(path.join(process.cwd(), 'uploads')));
}

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

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`Port ${PORT} is busy. Run this to fix it:\n  lsof -ti:${PORT} | xargs kill -9`);
    process.exit(1);
  }
});

// Attach Socket.io to the HTTP server
initSocket(server);

module.exports = { app, server };
