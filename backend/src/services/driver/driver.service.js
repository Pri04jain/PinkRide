const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');

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

const uploadDocument = async (userId, docType, fileUrl) => {
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

  await supabase
    .from('drivers')
    .update({ [column]: fileUrl })
    .eq('id', driver.id);

  // Check if all required docs uploaded — auto move to under_review
  await _checkAndAdvanceStatus(driver.id);

  return { uploaded: true, docType };
};

const _checkAndAdvanceStatus = async (driverId) => {
  const { data: driver } = await supabase
    .from('drivers')
    .select('license_doc_url, vehicle_rc_url, approval_status')
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

module.exports = {
  registerDriver,
  uploadDocument,
  getDriverProfile,
  setAvailability,
  updateLocation,
};
