const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');
const { emitToRide } = require('../../shared/socket/socket.server');
const { sendEmergencyAlert } = require('../notification/sms.service');

/**
 * Trigger SOS for a passenger mid-ride.
 * 1. Verifies passenger is in the ride
 * 2. Broadcasts socket alert to the ride room (driver sees it too)
 * 3. SMS all emergency contacts with live location link
 */
const triggerSOS = async (passengerId, rideId, lat, lng) => {
  const { data: rp, error } = await supabase
    .from('ride_passengers')
    .select('id, users!inner(full_name), rides!inner(status)')
    .eq('ride_id', rideId)
    .eq('passenger_id', passengerId)
    .single();

  if (error || !rp) throw new AppError('You are not part of this ride.', 403);

  const passengerName = rp.users?.full_name || 'A PinkRide passenger';
  const locationLink = lat && lng
    ? `https://maps.google.com/?q=${lat},${lng}`
    : 'Location unavailable';

  // Broadcast to everyone in the ride room immediately
  emitToRide(rideId, 'sos_alert', {
    triggeredBy: passengerId,
    passengerName,
    rideId,
    lat,
    lng,
    locationLink,
    timestamp: Date.now(),
  });

  // Fetch emergency contacts and SMS them
  const { data: contacts } = await supabase
    .from('emergency_contacts')
    .select('phone, name')
    .eq('user_id', passengerId)
    .order('is_primary', { ascending: false })
    .limit(3);

  const smsPromises = (contacts || []).map(contact =>
    sendEmergencyAlert(contact.phone, passengerName, rideId, locationLink)
      .catch(err => console.error(`[SOS] SMS failed to ${contact.phone}:`, err.message))
  );

  await Promise.allSettled(smsPromises);

  return {
    triggered: true,
    contactsAlerted: contacts?.length || 0,
    locationLink,
    message: contacts?.length > 0
      ? 'SOS sent. Your emergency contacts have been alerted.'
      : 'SOS sent. Please add emergency contacts in your profile for faster help.',
  };
};

/**
 * Passenger responds to a route deviation alert — 'ok' or 'alert'.
 */
const respondToDeviation = async (passengerId, deviationId, response) => {
  if (!['ok', 'alert'].includes(response)) {
    throw new AppError('Response must be "ok" or "alert".', 400);
  }
  const trackingService = require('../tracking/tracking.service');
  return trackingService.acknowledgeDeviation(deviationId, passengerId, response);
};

/**
 * Safety check-in — passenger confirms they are safe.
 * Resolves any pending deviation alerts for this ride.
 */
const safetyCheckIn = async (passengerId, rideId) => {
  await supabase
    .from('route_deviations')
    .update({
      passenger_response: 'check_in_ok',
      status: 'resolved',
      resolved_at: new Date().toISOString(),
    })
    .eq('ride_id', rideId)
    .in('status', ['detected', 'passenger_acknowledged']);

  emitToRide(rideId, 'safety_check_in', {
    passengerId,
    timestamp: Date.now(),
    message: 'Passenger confirmed safe.',
  });

  return { checkedIn: true };
};

module.exports = { triggerSOS, respondToDeviation, safetyCheckIn };
