const axios = require('axios');

/**
 * Send OTP via MSG91 (production) or log to console (development)
 */
const sendOtp = async (phone, otp, purpose = 'login') => {
  const isDev = process.env.NODE_ENV !== 'production';

  if (isDev) {
    // In development, just log the OTP — no real SMS sent
    console.log(`\n[DEV OTP] Phone: +91${phone} | Purpose: ${purpose} | OTP: ${otp}\n`);
    return { sent: true, dev: true };
  }

  // MSG91 OTP API
  try {
    const response = await axios.post(
      'https://control.msg91.com/api/v5/otp',
      {
        template_id: process.env.MSG91_TEMPLATE_ID,
        mobile: `91${phone}`,
        authkey: process.env.MSG91_AUTH_KEY,
        otp,
      },
      {
        headers: { 'Content-Type': 'application/json' },
        timeout: 5000,
      }
    );

    return { sent: true, response: response.data };
  } catch (err) {
    console.error('MSG91 SMS send error:', err.message);
    // Don't throw — log and continue. OTP is stored in Redis regardless.
    // In production, you may want to throw here and handle retry.
    return { sent: false, error: err.message };
  }
};

/**
 * Send emergency alert SMS to trusted contacts
 */
const sendEmergencyAlert = async (contactPhone, passengerName, rideId, locationLink) => {
  const isDev = process.env.NODE_ENV !== 'production';
  const message = `PINKRIDE ALERT: ${passengerName} may need help. Ride ID: ${rideId}. Last location: ${locationLink}. Please contact them immediately.`;

  if (isDev) {
    console.log(`\n[DEV EMERGENCY SMS] To: +91${contactPhone}\nMessage: ${message}\n`);
    return { sent: true, dev: true };
  }

  try {
    const response = await axios.post(
      'https://control.msg91.com/api/v5/flow/',
      {
        flow_id: process.env.MSG91_EMERGENCY_FLOW_ID,
        sender: process.env.MSG91_SENDER_ID || 'PINKRD',
        mobiles: `91${contactPhone}`,
        VAR1: passengerName,
        VAR2: rideId,
        VAR3: locationLink,
      },
      {
        headers: {
          'Content-Type': 'application/json',
          authkey: process.env.MSG91_AUTH_KEY,
        },
        timeout: 5000,
      }
    );

    return { sent: true, response: response.data };
  } catch (err) {
    console.error('Emergency SMS send error:', err.message);
    return { sent: false, error: err.message };
  }
};

module.exports = { sendOtp, sendEmergencyAlert };
