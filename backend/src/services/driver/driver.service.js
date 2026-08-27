const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');
const { emitToRide } = require('../../shared/socket/socket.server');
const { notify } = require('../notification/fcm.service');
const { saveFile } = require('../../shared/middleware/upload');

// Haversine distance in km (shared with matching engine — keeps driver service self-contained)
const haversineKm = (lat1, lng1, lat2, lng2) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
};

// ─── Register Driver Profile ──────────────────────────────────────────────────

const registerDriver = async (userId, driverData) => {
  const {
    licenseNumber, licenseExpiry,
    vehicleNumber, vehicleType,
    vehicleMake, vehicleModel,
    vehicleColor, vehicleYear,
  } = driverData;

  // Confirm user exists with driver role and face verified
  const { data: user, error: userError } = await supabase
    .from('users')
    .select('id, role, face_verified')
    .eq('id', userId)
    .single();

  if (userError || !user) throw new AppError('User not found.', 404);
  if (user.role !== 'driver') throw new AppError('Only accounts with driver role can register as a driver.', 403);
  if (!user.face_verified) throw new AppError('Face verification is required before driver registration.', 403);

  // Check if profile already exists
  const { data: existing } = await supabase
    .from('drivers')
    .select('id, approval_status')
    .eq('user_id', userId)
    .single();

  if (existing) {
    throw new AppError(`Driver profile already exists with status: ${existing.approval_status}.`, 409);
  }

  // Validate license format (India DL: XX00YYYYNNNNNNN)
  const dlRegex = /^[A-Z]{2}[0-9]{2}[0-9]{4}[0-9]{7}$/;
  if (!dlRegex.test(licenseNumber.replace(/\s/g, ''))) {
    throw new AppError('Invalid driving license number format.', 400);
  }

  if (new Date(licenseExpiry) < new Date()) {
    throw new AppError('Driving license has expired. Please renew before registering.', 400);
  }

  if (parseInt(vehicleYear) < 2005) {
    throw new AppError('Vehicle must be year 2005 or newer.', 400);
  }

  // Check for duplicate license / vehicle
  const { data: dup } = await supabase
    .from('drivers')
    .select('id')
    .or(`license_number.eq.${licenseNumber.toUpperCase()},vehicle_number.eq.${vehicleNumber.toUpperCase()}`)
    .maybeSingle();

  if (dup) throw new AppError('This license number or vehicle is already registered.', 409);

  const { data, error } = await supabase
    .from('drivers')
    .insert({
      user_id: userId,
      license_number: licenseNumber.toUpperCase(),
      license_expiry: licenseExpiry,
      license_doc_url: 'pending_upload',
      vehicle_number: vehicleNumber.toUpperCase(),
      vehicle_type: vehicleType,
      vehicle_make: vehicleMake,
      vehicle_model: vehicleModel,
      vehicle_color: vehicleColor,
      vehicle_year: parseInt(vehicleYear),
      vehicle_rc_url: 'pending_upload',
      approval_status: 'pending',
    })
    .select('id, approval_status, created_at')
    .single();

  if (error) throw new AppError('Failed to create driver profile.', 500);
  return data;
};

// ─── Upload Documents ─────────────────────────────────────────────────────────

const uploadDocument = async (userId, docType, fileBuffer, originalName) => {
  const { data: driver, error } = await supabase
    .from('drivers')
    .select('id, approval_status')
    .eq('user_id', userId)
    .single();

  if (error || !driver) throw new AppError('Driver profile not found.', 404);
  if (driver.approval_status === 'approved') {
    throw new AppError('Documents cannot be changed after approval. Contact support.', 403);
  }

  const columnMap = {
    license: 'license_doc_url',
    rc: 'vehicle_rc_url',
    insurance: 'vehicle_insurance_url',
  };

  const column = columnMap[docType];
  if (!column) throw new AppError('Invalid document type. Use: license, rc, insurance.', 400);

  // Save the file buffer to disk (dev) — returns a path like /uploads/documents/filename.pdf
  const fileUrl = await saveFile(fileBuffer, originalName, 'documents');

  await supabase
    .from('drivers')
    .update({ [column]: fileUrl })
    .eq('id', driver.id);

  // Check if all required docs uploaded — auto move to under_review
  await _checkAndAdvanceStatus(driver.id);

  return { uploaded: true, docType, fileUrl };
};

const _checkAndAdvanceStatus = async (driverId) => {
  const { data: driver } = await supabase
    .from('drivers')
    .select('license_doc_url, vehicle_rc_url, approval_status, user_id')
    .eq('id', driverId)
    .single();

  if (
    driver?.approval_status === 'pending' &&
    driver.license_doc_url !== 'pending_upload' &&
    driver.vehicle_rc_url !== 'pending_upload'
  ) {
    await supabase
      .from('drivers')
      .update({ approval_status: 'under_review' })
      .eq('id', driverId);

    // Fetch driver's name for the admin notification
    const { data: driverUser } = await supabase
      .from('users')
      .select('full_name')
      .eq('id', driver.user_id)
      .single();

    const driverName = driverUser?.full_name || 'A new driver';

    // Notify the driver that their application is in review (fire-and-forget)
    notify.applicationUnderReview(driver.user_id).catch((err) =>
      console.error('[Driver] applicationUnderReview push failed:', err.message)
    );

    // Notify all active admin users (fire-and-forget — a push failure must not block upload)
    supabase
      .from('users')
      .select('id')
      .eq('role', 'admin')
      .eq('is_active', true)
      .then(({ data: admins }) => {
        if (!admins?.length) return;
        Promise.allSettled(
          admins.map((admin) => notify.newDriverApplication(admin.id, driverName))
        );
      })
      .catch((err) => console.error('[Driver] Admin notification error:', err.message));
  }
};

// ─── Get Driver Profile ───────────────────────────────────────────────────────

const getDriverProfile = async (userId) => {
  const { data, error } = await supabase
    .from('drivers')
    .select(`
      id, user_id,
      license_number, license_expiry,
      vehicle_number, vehicle_type, vehicle_make, vehicle_model, vehicle_color, vehicle_year,
      approval_status, rejection_reason,
      is_available, total_trips, cancellation_count,
      license_doc_url, vehicle_rc_url, vehicle_insurance_url,
      created_at, updated_at,
      users!inner(full_name, phone, face_verified, reliability_score)
    `)
    .eq('user_id', userId)
    .single();

  if (error || !data) throw new AppError('Driver profile not found.', 404);
  return data;
};

// ─── Toggle Availability ──────────────────────────────────────────────────────

const setAvailability = async (userId, isAvailable) => {
  const { data: driver, error } = await supabase
    .from('drivers')
    .select('id, approval_status')
    .eq('user_id', userId)
    .single();

  if (error || !driver) throw new AppError('Driver profile not found.', 404);
  if (driver.approval_status !== 'approved') {
    throw new AppError('Your account must be approved before you can accept rides.', 403);
  }

  await supabase
    .from('drivers')
    .update({ is_available: isAvailable })
    .eq('id', driver.id);

  return { isAvailable };
};

// ─── Update Live Location ─────────────────────────────────────────────────────

const updateLocation = async (userId, lat, lng) => {
  // Store as flat columns (no PostGIS needed — Supabase supports it but
  // flat lat/lng columns are simpler to query from JS)
  await supabase
    .from('drivers')
    .update({
      current_lat: lat,
      current_lng: lng,
      last_location_update: new Date().toISOString(),
    })
    .eq('user_id', userId);

  return { updated: true };
};

// ─── Get Nearby Ride Requests ─────────────────────────────────────────────────
// Returns open rides (status = 'searching' | 'matching') that are within
// NEARBY_RADIUS_KM of the driver's current location, in the same city.
// Only available to approved drivers who are currently online.

const NEARBY_RADIUS_KM = parseFloat(process.env.DRIVER_NEARBY_RADIUS_KM) || 5;

const getNearbyRideRequests = async (driverUserId) => {
  // Get driver record with current location
  const { data: driver, error: driverError } = await supabase
    .from('drivers')
    .select('id, approval_status, is_available, current_lat, current_lng')
    .eq('user_id', driverUserId)
    .single();

  // Fetch city separately via user_id to avoid Supabase join ambiguity
  const { data: driverUser } = await supabase
    .from('users')
    .select('city')
    .eq('id', driverUserId)
    .single();

  if (driverError || !driver) throw new AppError('Driver profile not found.', 404);
  if (driver.approval_status !== 'approved') {
    throw new AppError('Your account must be approved to view ride requests.', 403);
  }
  if (!driver.is_available) {
    throw new AppError('Go online first to see ride requests.', 403);
  }
  if (!driver.current_lat || !driver.current_lng) {
    throw new AppError('Location not set. Share your location to see nearby rides.', 400);
  }

  const driverCity = driverUser?.city || 'Jaipur';

  // O1: bounding box pre-filter — Postgres discards rows outside a lat/lng square
  // before they reach Node.js. Haversine then does precise circular filtering on
  // the small result set. At 5km radius, 1° lat ≈ 111km so delta ≈ 0.045°.
  const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString();
  const DEG_PER_KM = 1 / 111;
  const delta = NEARBY_RADIUS_KM * DEG_PER_KM * Math.SQRT2; // expand slightly for square→circle
  const latMin = driver.current_lat - delta;
  const latMax = driver.current_lat + delta;
  const lngMin = driver.current_lng - delta;
  const lngMax = driver.current_lng + delta;

  const { data: rides, error: ridesError } = await supabase
    .from('rides')
    .select(`
      id, ride_type, status,
      pickup_lat, pickup_lng, pickup_address,
      drop_lat, drop_lng, drop_address,
      scheduled_at, final_fare, payment_method, max_passengers,
      ride_passengers(id, passenger_id, total_fare)
    `)
    .in('status', ['searching', 'matching'])
    .is('driver_id', null)
    .eq('city', driverCity)
    .gte('created_at', twoHoursAgo)
    .gte('pickup_lat', latMin)
    .lte('pickup_lat', latMax)
    .gte('pickup_lng', lngMin)
    .lte('pickup_lng', lngMax)
    .order('scheduled_at', { ascending: true });

  if (ridesError) throw new AppError('Failed to fetch ride requests.', 500);

  // Filter by Haversine distance from driver to pickup
  const nearby = (rides || [])
    .map((ride) => {
      const distanceKm = haversineKm(
        driver.current_lat, driver.current_lng,
        ride.pickup_lat, ride.pickup_lng
      );
      return { ...ride, distanceToPickupKm: Math.round(distanceKm * 10) / 10 };
    })
    .filter((ride) => ride.distanceToPickupKm <= NEARBY_RADIUS_KM)
    .sort((a, b) => a.distanceToPickupKm - b.distanceToPickupKm);

  return {
    requests: nearby,
    count: nearby.length,
    driverLocation: { lat: driver.current_lat, lng: driver.current_lng },
    radiusKm: NEARBY_RADIUS_KM,
  };
};

// ─── Accept Ride ──────────────────────────────────────────────────────────────
// Driver accepts an open ride request.
// Guards: driver must be approved + online, ride must still be unassigned.
// On success: assigns driver_id, advances ride to 'confirmed',
//             emits 'driver_assigned' Socket.io event to the ride room,
//             sends FCM push to all passengers in the ride.

const acceptRide = async (driverUserId, rideId) => {
  // 1. Verify driver is approved and online
  const { data: driver, error: driverError } = await supabase
    .from('drivers')
    .select('id, approval_status, is_available, vehicle_make, vehicle_model, vehicle_number, vehicle_color')
    .eq('user_id', driverUserId)
    .single();

  if (driverError || !driver) throw new AppError('Driver profile not found.', 404);

  // Fetch driver user info separately via user_id
  const { data: driverUserInfo } = await supabase
    .from('users')
    .select('full_name, phone, reliability_score')
    .eq('id', driverUserId)
    .single();

  if (driverError || !driver) throw new AppError('Driver profile not found.', 404);
  if (driver.approval_status !== 'approved') {
    throw new AppError('Your account must be approved to accept rides.', 403);
  }
  if (!driver.is_available) {
    throw new AppError('You must be online to accept rides.', 403);
  }

  // 2. Check driver has no other active ride
  const { data: activeRide } = await supabase
    .from('rides')
    .select('id')
    .eq('driver_id', driver.id)
    .not('status', 'in', '("completed","cancelled")')
    .maybeSingle();

  if (activeRide) {
    throw new AppError('You already have an active ride. Complete or cancel it first.', 409);
  }

  // 3. Atomically claim the ride — only succeeds if driver_id is still NULL
  //    We update with a filter on driver_id IS NULL to prevent double-acceptance
  const { data: updated, error: updateError } = await supabase
    .from('rides')
    .update({
      driver_id: driver.id,
      status: 'confirmed',
      driver_arriving_at: new Date().toISOString(),
    })
    .eq('id', rideId)
    .is('driver_id', null)   // atomic guard — another driver may have already accepted
    .in('status', ['searching', 'matching'])
    .select('id, status, pickup_address, drop_address, scheduled_at, ride_passengers(passenger_id)')
    .single();

  if (updateError || !updated) {
    throw new AppError('This ride has already been accepted by another driver. Try a different one.', 409);
  }

  // 4. Mark all passengers in this ride as confirmed
  await supabase
    .from('ride_passengers')
    .update({ status: 'confirmed' })
    .eq('ride_id', rideId)
    .neq('status', 'cancelled');

  // 5. Take driver offline (they now have an active ride — re-enable after completion)
  await supabase
    .from('drivers')
    .update({ is_available: false })
    .eq('id', driver.id);

  // 6. Build driver info payload for the Socket.io event
  const driverPayload = {
    driverId: driver.id,
    name: driverUserInfo?.full_name,
    phone: driverUserInfo?.phone,
    reliabilityScore: driverUserInfo?.reliability_score,
    vehicle: {
      make: driver.vehicle_make,
      model: driver.vehicle_model,
      number: driver.vehicle_number,
      color: driver.vehicle_color,
    },
  };

  // 7. Emit real-time event to all sockets in the ride room
  emitToRide(rideId, 'driver_assigned', {
    rideId,
    driver: driverPayload,
    status: 'confirmed',
    message: 'Your driver is on the way!',
    timestamp: Date.now(),
  });

  // 8. Send FCM push to every passenger
  const passengers = updated.ride_passengers || [];
  await Promise.allSettled(
    passengers.map((rp) =>
      notify.rideConfirmed(
        rp.passenger_id,
        driverUserInfo?.full_name,
        `${driver.vehicle_make} ${driver.vehicle_model} (${driver.vehicle_color})`
      )
    )
  );

  return {
    accepted: true,
    rideId: updated.id,
    status: updated.status,
    pickupAddress: updated.pickup_address,
    dropAddress: updated.drop_address,
    scheduledAt: updated.scheduled_at,
    passengerCount: passengers.length,
    message: 'Ride accepted. Head to the pickup point.',
  };
};

module.exports = {
  registerDriver,
  uploadDocument,
  getDriverProfile,
  setAvailability,
  updateLocation,
  getNearbyRideRequests,
  acceptRide,
};
