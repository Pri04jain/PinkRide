const { Server } = require('socket.io');
const jwt = require('jsonwebtoken');
const { supabase } = require('../db/client');
const trackingService = require('../../services/tracking/tracking.service');
// Lazy-required to avoid circular dependency (safety → socket → safety)
const getSafetyService = () => require('../../services/safety/safety.service');

let io;

/**
 * Initialise Socket.io on the existing HTTP server.
 * Called once from app.js after server.listen().
 */
const initSocket = (httpServer) => {
  io = new Server(httpServer, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : '*',
      credentials: true,
    },
    transports: ['websocket', 'polling'],
  });

  // JWT auth middleware — runs before every connection
  io.use(async (socket, next) => {
    try {
      const token =
        socket.handshake.auth?.token ||
        socket.handshake.headers?.authorization?.split(' ')[1];

      if (!token) return next(new Error('Authentication required'));

      const decoded = jwt.verify(token, process.env.JWT_SECRET);

      const { data: user, error } = await supabase
        .from('users')
        .select('id, role, is_active')
        .eq('id', decoded.userId)
        .single();

      if (error || !user || !user.is_active) {
        return next(new Error('User not found or inactive'));
      }

      socket.user = user;
      next();
    } catch {
      next(new Error('Invalid or expired token'));
    }
  });

  io.on('connection', (socket) => {
    const { id: userId, role } = socket.user;
    console.log(`[Socket] Connected: ${userId} (${role}) — ${socket.id}`);

    // Both passenger and driver join the ride room by rideId
    socket.on('join_ride', async ({ rideId }) => {
      if (!rideId) return;

      const allowed = await _isUserInRide(userId, role, rideId);
      if (!allowed) {
        socket.emit('error', { message: 'Not authorised for this ride' });
        return;
      }

      socket.join(`ride:${rideId}`);
      socket.currentRideId = rideId;
      socket.emit('joined_ride', { rideId });
      console.log(`[Socket] ${userId} joined ride:${rideId}`);
    });

    // Driver sends live location — broadcast to all passengers in room
    socket.on('driver_location', ({ rideId, lat, lng, heading, speedKmh }) => {
      if (!rideId || role !== 'driver') return;

      const payload = {
        lat,
        lng,
        heading: heading || 0,
        speedKmh: speedKmh || 0,
        timestamp: Date.now(),
      };

      // Broadcast to everyone in the ride room except the sender
      socket.to(`ride:${rideId}`).emit('driver_location_update', payload);

      // Run deviation detection asynchronously — errors are logged, never thrown
      trackingService.processLocationUpdate(userId, rideId, lat, lng)
        .catch((err) => console.error('[Tracking] processLocationUpdate error:', err.message));
    });

    // Passenger acknowledges a deviation alert
    socket.on('deviation_response', ({ rideId, response }) => {
      io.to(`ride:${rideId}`).emit('deviation_acknowledged', {
        passengerId: userId,
        response,
        timestamp: Date.now(),
      });
    });

    // Passenger triggers SOS — delegate to safetyService for full response:
    // DB record + SMS to emergency contacts + FCM push to driver + socket broadcast.
    // lat/lng are optional — client sends current position when available.
    socket.on('sos_triggered', ({ rideId, lat, lng }) => {
      if (!rideId || role !== 'passenger') return;

      // Fire-and-forget — a slow SMS must never delay the socket acknowledgement
      getSafetyService().triggerSOS(userId, rideId, lat || null, lng || null)
        .catch((err) => console.error('[Socket] SOS trigger error:', err.message));
    });

    socket.on('leave_ride', ({ rideId }) => {
      socket.leave(`ride:${rideId}`);
    });

    socket.on('disconnect', () => {
      console.log(`[Socket] Disconnected: ${userId}`);
    });
  });

  return io;
};

// Check if user belongs to a ride before letting them join the room
const _isUserInRide = async (userId, role, rideId) => {
  try {
    if (role === 'passenger') {
      const { data } = await supabase
        .from('ride_passengers')
        .select('id')
        .eq('ride_id', rideId)
        .eq('passenger_id', userId)
        .single();
      return !!data;
    }
    if (role === 'driver') {
      const { data } = await supabase
        .from('rides')
        .select('drivers!inner(user_id)')
        .eq('id', rideId)
        .eq('drivers.user_id', userId)
        .single();
      return !!data;
    }
    return false;
  } catch {
    return false;
  }
};

// Emit to everyone in a ride room (called from service layer)
const emitToRide = (rideId, event, data) => {
  if (!io) return;
  io.to(`ride:${rideId}`).emit(event, data);
};

const getIo = () => io;

module.exports = { initSocket, emitToRide, getIo };
