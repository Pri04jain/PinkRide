const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');

const MIN_TOPUP = parseInt(process.env.WALLET_MIN_TOPUP_INR) || 100;

/**
 * Complete user registration after OTP verification
 */
const completeRegistration = async (userId, profileData) => {
  const { fullName, gender, dateOfBirth, role = 'passenger' } = profileData;

  if (!['passenger', 'driver'].includes(role)) {
    throw new AppError('Invalid role specified', 400);
  }

  const { data, error } = await supabase
    .from('users')
    .update({
      full_name: fullName,
      gender,
      date_of_birth: dateOfBirth || null,
      role,
    })
    .eq('id', userId)
    .select('id, phone, full_name, gender, role, city, face_verified, reliability_score, wallet_balance, created_at')
    .single();

  if (error || !data) throw new AppError('User not found', 404);
  return data;
};

/**
 * Get user profile (with average rating)
 */
const getProfile = async (userId) => {
  const { data: user, error } = await supabase
    .from('users')
    .select('id, phone, full_name, gender, role, city, face_verified, reliability_score, wallet_balance, total_rides, cancellation_count, created_at, last_active_at')
    .eq('id', userId)
    .single();

  if (error || !user) throw new AppError('User not found', 404);

  // Get average rating separately
  const { data: ratings } = await supabase
    .from('ratings')
    .select('score')
    .eq('rated_user', userId);

  const avgRating = ratings?.length
    ? Math.round((ratings.reduce((s, r) => s + r.score, 0) / ratings.length) * 100) / 100
    : 0;

  return { ...user, average_rating: avgRating, total_ratings: ratings?.length || 0 };
};

/**
 * Update user profile (limited fields)
 */
const updateProfile = async (userId, updates) => {
  const allowed = ['full_name', 'date_of_birth', 'profile_photo_url'];
  const filtered = Object.fromEntries(
    Object.entries(updates).filter(([k]) => allowed.includes(k))
  );

  if (!Object.keys(filtered).length) throw new AppError('No valid fields to update', 400);

  const { data, error } = await supabase
    .from('users')
    .update(filtered)
    .eq('id', userId)
    .select('id, full_name, gender, role, city, reliability_score')
    .single();

  if (error) throw new AppError('Update failed', 500);
  return data;
};

/**
 * Add emergency contact (max 3 per user)
 */
const upsertEmergencyContact = async (userId, contact) => {
  const { name, phone, relation, isPrimary = false } = contact;

  // Check count
  const { count } = await supabase
    .from('emergency_contacts')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId);

  if (count >= 3) throw new AppError('Maximum 3 emergency contacts allowed', 400);

  // Unset existing primary if setting new one
  if (isPrimary) {
    await supabase
      .from('emergency_contacts')
      .update({ is_primary: false })
      .eq('user_id', userId);
  }

  const { data, error } = await supabase
    .from('emergency_contacts')
    .insert({ user_id: userId, name, phone, relation: relation || null, is_primary: isPrimary })
    .select()
    .single();

  if (error) throw new AppError('Failed to add emergency contact', 500);
  return data;
};

/**
 * Get emergency contacts
 */
const getEmergencyContacts = async (userId) => {
  const { data, error } = await supabase
    .from('emergency_contacts')
    .select('id, name, phone, relation, is_primary, created_at')
    .eq('user_id', userId)
    .order('is_primary', { ascending: false });

  if (error) throw new AppError('Failed to fetch contacts', 500);
  return data || [];
};

/**
 * Delete emergency contact
 */
const deleteEmergencyContact = async (userId, contactId) => {
  const { error, count } = await supabase
    .from('emergency_contacts')
    .delete({ count: 'exact' })
    .eq('id', contactId)
    .eq('user_id', userId);

  if (error || count === 0) throw new AppError('Emergency contact not found', 404);
  return { deleted: true };
};

/**
 * Top up wallet balance
 */
const topUpWallet = async (userId, amount, referenceId = null) => {
  if (amount < MIN_TOPUP) throw new AppError(`Minimum top-up is ₹${MIN_TOPUP}`, 400);

  // Get current balance
  const { data: user } = await supabase
    .from('users')
    .select('wallet_balance')
    .eq('id', userId)
    .single();

  const newBalance = parseFloat(user.wallet_balance) + amount;

  const { error } = await supabase
    .from('users')
    .update({ wallet_balance: newBalance })
    .eq('id', userId);

  if (error) throw new AppError('Wallet top-up failed', 500);

  // Log transaction
  await supabase.from('wallet_transactions').insert({
    user_id: userId,
    amount,
    type: 'topup',
    reference_id: referenceId,
    balance_after: newBalance,
    notes: 'Wallet top-up',
  });

  return { walletBalance: newBalance };
};

/**
 * Soft-delete account (DPDP Act — right to erasure)
 */
const deleteAccount = async (userId) => {
  await supabase
    .from('users')
    .update({
      is_active: false,
      full_name: 'Deleted User',
      face_embedding_ref: null,
      face_verified: false,
      face_consent_given: false,
    })
    .eq('id', userId);

  return { deleted: true };
};

module.exports = {
  completeRegistration,
  getProfile,
  updateProfile,
  upsertEmergencyContact,
  getEmergencyContacts,
  deleteEmergencyContact,
  topUpWallet,
  deleteAccount,
};
