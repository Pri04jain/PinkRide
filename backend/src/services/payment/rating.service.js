const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');

const VALID_TAGS = {
  passenger: ['punctual', 'polite', 'clean', 'safe', 'verified'],
  driver: ['punctual', 'safe_driver', 'clean_vehicle', 'polite', 'good_route', 'smooth_ride'],
};

// ─── Submit Rating ────────────────────────────────────────────────────────────

const submitRating = async (ratingData) => {
  const { rideId, ratedBy, ratedUserId, score, tags = [], comment } = ratingData;

  if (score < 1 || score > 5) throw new AppError('Score must be between 1 and 5.', 400);

  // Verify ride is completed
  const { data: ride } = await supabase
    .from('rides')
    .select('id')
    .eq('id', rideId)
    .eq('status', 'completed')
    .single();

  if (!ride) throw new AppError('Can only rate completed rides.', 400);

  // Verify rater was part of this ride
  const { data: asPassenger } = await supabase
    .from('ride_passengers')
    .select('id')
    .eq('ride_id', rideId)
    .eq('passenger_id', ratedBy)
    .maybeSingle();

  const { data: asDriver } = await supabase
    .from('rides')
    .select('drivers!inner(user_id)')
    .eq('id', rideId)
    .eq('drivers.user_id', ratedBy)
    .maybeSingle();

  if (!asPassenger && !asDriver) throw new AppError('You were not part of this ride.', 403);

  // Check for duplicate rating
  const { data: dup } = await supabase
    .from('ratings')
    .select('id')
    .eq('ride_id', rideId)
    .eq('rated_by', ratedBy)
    .eq('rated_user', ratedUserId)
    .maybeSingle();

  if (dup) throw new AppError('You have already rated this person for this ride.', 409);

  // Sanitise tags
  const validTags = tags.filter(t =>
    [...VALID_TAGS.passenger, ...VALID_TAGS.driver].includes(t)
  );

  // Insert rating
  const { error: ratingError } = await supabase
    .from('ratings')
    .insert({ ride_id: rideId, rated_by: ratedBy, rated_user: ratedUserId, score, tags: validTags, comment: comment || null });

  if (ratingError) throw new AppError('Failed to submit rating.', 500);

  // Recalculate reliability score
  const { data: allRatings } = await supabase
    .from('ratings')
    .select('score')
    .eq('rated_user', ratedUserId);

  const avgScore = allRatings?.length
    ? allRatings.reduce((s, r) => s + r.score, 0) / allRatings.length
    : score;

  const { data: user } = await supabase
    .from('users')
    .select('cancellation_count, total_rides')
    .eq('id', ratedUserId)
    .single();

  const cancelRate = (user?.total_rides || 0) > 0
    ? (user.cancellation_count || 0) / user.total_rides
    : 0;
  const penalty = Math.min(cancelRate * 2, 1.5);
  const newReliability = Math.max(0, Math.min(5, Math.round((avgScore - penalty) * 100) / 100));

  await supabase
    .from('users')
    .update({ reliability_score: newReliability })
    .eq('id', ratedUserId);

  return { rated: true, newReliabilityScore: newReliability };
};

// ─── Get Ratings ──────────────────────────────────────────────────────────────

const getUserRatings = async (userId, limit = 20) => {
  const { data, error } = await supabase
    .from('ratings')
    .select('id, score, tags, comment, created_at, users!rated_by(full_name, role)')
    .eq('rated_user', userId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) throw new AppError('Failed to fetch ratings.', 500);
  return data || [];
};

const getRideRatings = async (rideId) => {
  const { data, error } = await supabase
    .from('ratings')
    .select('id, score, tags, comment, rated_by, rated_user, users!rated_by(full_name)')
    .eq('ride_id', rideId);

  if (error) throw new AppError('Failed to fetch ride ratings.', 500);
  return data || [];
};

module.exports = { submitRating, getUserRatings, getRideRatings, VALID_TAGS };
