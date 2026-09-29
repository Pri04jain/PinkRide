const axios = require('axios');

// ─── Provider helpers ─────────────────────────────────────────────────────────

/**
 * Send OTP via Fast2SMS (India — production use)
 * Requires DLT registration (TRAI mandate for commercial SMS in India).
 * Sign up at fast2sms.com → Dev API to get your key.
 * Set SMS_PROVIDER=fast2sms and SEND_REAL_SMS_IN_DEV=true in .env.
 */
const sendViaFast2SMS = async (phone, otp) => {
  const response = await axios.get('https://www.fast2sms.com/dev/bulkV2', {
    params: {
      variables_values: otp,
      route:            'otp',   // OTP route — requires DLT approval
      numbers:          phone,   // 10-digit Indian number, no country code
    },
    headers: {
      authorization: process.env.FAST2SMS_API_KEY, // key goes in header
    },
    timeout: 5000,
  });
  return response.data;
};

/**
 * Send OTP via MSG91 (India — production use, paid)
 * Sign up at msg91.com — requires DLT registration.
 * Set SMS_PROVIDER=msg91 in .env.
 */
const sendViaMSG91 = async (phone, otp) => {
  const response = await axios.post(
    'https://control.msg91.com/api/v5/otp',
    {
      template_id: process.env.MSG91_TEMPLATE_ID,
      mobile:      `91${phone}`,
      authkey:     process.env.MSG91_AUTH_KEY,
      otp,
    },
    {
      headers: { 'Content-Type': 'application/json' },
      timeout: 5000,
    }
  );
  return response.data;
};

// ─── Main sendOtp ─────────────────────────────────────────────────────────────

/**
 * Send OTP via the configured SMS provider.
 *
 * SMS_PROVIDER options (.env):
 *   fast2sms  → Fast2SMS (India, requires DLT registration for production)
 *   msg91     → MSG91    (India, paid, requires DLT registration)
 *
 * Development behaviour:
 *   SEND_REAL_SMS_IN_DEV=false (default) → OTP only printed to console, no SMS sent
 *   SEND_REAL_SMS_IN_DEV=true            → real SMS sent even in development
 *
 * NOTE: All Indian SMS providers require TRAI DLT registration for production.
 * During development, console logging is the standard approach — no SMS needed.
 */
const sendOtp = async (phone, otp, purpose = 'login') => {
  const isDev         = process.env.NODE_ENV !== 'production';
  const sendRealInDev = process.env.SEND_REAL_SMS_IN_DEV === 'true';

  // Always log OTP to server console — useful in dev and as an audit trail
  console.log(`\n[OTP] Phone: +91${phone} | Purpose: ${purpose} | OTP: ${otp}\n`);

  if (isDev && !sendRealInDev) {
    // Dev mode: OTP is visible in terminal — no SMS sent
    return { sent: true, dev: true };
  }

  const provider = (process.env.SMS_PROVIDER || 'fast2sms').toLowerCase();

  try {
    let result;
    if (provider === 'msg91') {
      result = await sendViaMSG91(phone, otp);
    } else {
      result = await sendViaFast2SMS(phone, otp);
    }

    console.log(`[SMS] OTP sent via ${provider}`);
    return { sent: true, provider, response: result };
  } catch (err) {
    console.error(`[SMS] ${provider} send error:`, err.response?.data || err.message);
    return { sent: false, provider, error: err.message };
  }
};

// ─── Emergency alert ──────────────────────────────────────────────────────────

/**
 * Send emergency alert SMS to a trusted contact.
 * Uses MSG91 flow in production, logs to console in dev.
 */
const sendEmergencyAlert = async (contactPhone, passengerName, rideId, locationLink) => {
  const isDev   = process.env.NODE_ENV !== 'production';
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
        sender:  process.env.MSG91_SENDER_ID || 'PINKRD',
        mobiles: `91${contactPhone}`,
        VAR1:    passengerName,
        VAR2:    rideId,
        VAR3:    locationLink,
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
