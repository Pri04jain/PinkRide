const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');

// ─── Approval Queue ───────────────────────────────────────────────────────────

const getDriverQueue = async ({ status = 'under_review', page = 1, limit = 20 } = {}) => {
  let query = supabase
    .from('drivers')
    .select(`
      id, user_id,
      license_number, license_expiry,
      vehicle_number, vehicle_type, vehicle_make, vehicle_model,
      vehicle_color, vehicle_year,
      approval_status, rejection_reason,
      license_doc_url, vehicle_rc_url, vehicle_insurance_url,
      created_at, updated_at
    `, { count: 'exact' })
    .order('created_at', { ascending: true })
    .range((page - 1) * limit, page * limit - 1);

  if (status !== 'all') {
    query = query.eq('approval_status', status);
  }

  const { data, error, count } = await query;
  if (error) throw new AppError('Failed to fetch driver queue.', 500);

  // Fetch user info separately for each driver (avoids Supabase join ambiguity)
  const drivers = await Promise.all((data || []).map(async (driver) => {
    const { data: user } = await supabase
      .from('users')
      .select('full_name, phone, face_verified, gender')
      .eq('id', driver.user_id)
      .single();
    return { ...driver, users: user || {} };
  }));

  return {
    drivers,
    pagination: {
      page, limit,
      total: count || 0,
      pages: Math.ceil((count || 0) / limit),
    },
  };
};

// ─── Get Single Driver for Review ────────────────────────────────────────────

const getDriverDetail = async (driverId) => {
  const { data, error } = await supabase
    .from('drivers')
    .select(`
      *,
      users!inner(full_name, phone, face_verified, gender, reliability_score, created_at)
    `)
    .eq('id', driverId)
    .single();

  if (error || !data) throw new AppError('Driver not found.', 404);
  return data;
};

// ─── Approve Driver ───────────────────────────────────────────────────────────

const approveDriver = async (driverId, adminUserId) => {
  const driver = await getDriverDetail(driverId);

  if (driver.approval_status === 'approved') throw new AppError('Driver is already approved.', 409);
  if (!driver.users?.face_verified) throw new AppError('Driver must complete face verification before approval.', 403);
  if (driver.license_doc_url === 'pending_upload' || driver.vehicle_rc_url === 'pending_upload') {
    throw new AppError('Driver has not uploaded all required documents.', 400);
  }

  const { error } = await supabase
    .from('drivers')
    .update({
      approval_status: 'approved',
      approved_by: adminUserId,
      approved_at: new Date().toISOString(),
      rejection_reason: null,
    })
    .eq('id', driverId);

  if (error) throw new AppError('Failed to approve driver.', 500);

  console.log(`[Admin] Driver ${driverId} approved by ${adminUserId}`);
  return { approved: true, driverId };
};

// ─── Reject Driver ────────────────────────────────────────────────────────────

const rejectDriver = async (driverId, adminUserId, reason) => {
  if (!reason || reason.trim().length < 10) {
    throw new AppError('Rejection reason must be at least 10 characters.', 400);
  }

  const driver = await getDriverDetail(driverId);
  if (driver.approval_status === 'approved') {
    throw new AppError('Cannot reject an already approved driver. Use suspend instead.', 409);
  }

  const { error } = await supabase
    .from('drivers')
    .update({ approval_status: 'rejected', rejection_reason: reason.trim() })
    .eq('id', driverId);

  if (error) throw new AppError('Failed to reject driver.', 500);

  console.log(`[Admin] Driver ${driverId} rejected by ${adminUserId}: ${reason}`);
  return { rejected: true, driverId, reason };
};

// ─── Suspend Driver ───────────────────────────────────────────────────────────

const suspendDriver = async (driverId, adminUserId, reason) => {
  if (!reason || reason.trim().length < 10) {
    throw new AppError('Suspension reason must be at least 10 characters.', 400);
  }

  const { error } = await supabase
    .from('drivers')
    .update({
      approval_status: 'suspended',
      is_available: false,
      rejection_reason: reason.trim(),
    })
    .eq('id', driverId);

  if (error) throw new AppError('Failed to suspend driver.', 500);

  console.log(`[Admin] Driver ${driverId} suspended by ${adminUserId}: ${reason}`);
  return { suspended: true, driverId, reason };
};

// ─── Reinstate Driver ─────────────────────────────────────────────────────────

const reinstateDriver = async (driverId, adminUserId) => {
  const driver = await getDriverDetail(driverId);
  if (driver.approval_status !== 'suspended') {
    throw new AppError('Driver is not currently suspended.', 409);
  }

  await supabase
    .from('drivers')
    .update({ approval_status: 'approved', rejection_reason: null })
    .eq('id', driverId);

  return { reinstated: true, driverId };
};

// ─── Dashboard Stats ──────────────────────────────────────────────────────────

const getDashboardStats = async () => {
  const { data: drivers } = await supabase
    .from('drivers')
    .select('approval_status, is_available');

  const { data: users } = await supabase
    .from('users')
    .select('role, created_at')
    .eq('is_active', true);

  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  return {
    drivers: {
      pending:      drivers?.filter(d => d.approval_status === 'pending').length || 0,
      under_review: drivers?.filter(d => d.approval_status === 'under_review').length || 0,
      approved:     drivers?.filter(d => d.approval_status === 'approved').length || 0,
      rejected:     drivers?.filter(d => d.approval_status === 'rejected').length || 0,
      suspended:    drivers?.filter(d => d.approval_status === 'suspended').length || 0,
      online_now:   drivers?.filter(d => d.is_available).length || 0,
    },
    users: {
      passengers:    users?.filter(u => u.role === 'passenger').length || 0,
      drivers:       users?.filter(u => u.role === 'driver').length || 0,
      new_this_week: users?.filter(u => u.created_at >= weekAgo).length || 0,
    },
  };
};

module.exports = {
  getDriverQueue,
  getDriverDetail,
  approveDriver,
  rejectDriver,
  suspendDriver,
  reinstateDriver,
  getDashboardStats,
};
