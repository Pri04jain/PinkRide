#!/usr/bin/env node
/**
 * PinkRide Demo Health Check
 * Run before opening the demo dashboard to catch every common failure.
 *
 *   node check-demo.js
 *
 * Exits 0 if everything is ready. Exits 1 and prints actionable fixes if not.
 */

'use strict';
require('dotenv').config({ path: './backend/.env' });

const http   = require('http');
const { createClient } = require('@supabase/supabase-js');

// ── Colours ───────────────────────────────────────────────────────────────────
const G = (s) => `\x1b[32m${s}\x1b[0m`;   // green
const R = (s) => `\x1b[31m${s}\x1b[0m`;   // red
const Y = (s) => `\x1b[33m${s}\x1b[0m`;   // yellow
const B = (s) => `\x1b[1m${s}\x1b[0m`;    // bold

const OK   = G('  ✓');
const FAIL = R('  ✗');
const WARN = Y('  ⚠');

let failures = 0;
let warnings = 0;

function pass(label)        { console.log(`${OK}  ${label}`); }
function fail(label, fix)   { console.log(`${FAIL}  ${label}`); if (fix) console.log(R(`       → Fix: ${fix}`)); failures++; }
function warn(label, hint)  { console.log(`${WARN}  ${label}`); if (hint) console.log(Y(`       → Hint: ${hint}`)); warnings++; }

// ── HTTP helper ───────────────────────────────────────────────────────────────
function httpGet(url) {
  return new Promise((resolve) => {
    http.get(url, (res) => {
      let body = '';
      res.on('data', (c) => body += c);
      res.on('end', () => {
        // A non-JSON response (e.g. HTML from the demo server) is still "ok"
        // as long as the status code is < 400
        let data = null;
        try { data = JSON.parse(body); } catch { /* HTML or non-JSON — that's fine */ }
        resolve({ ok: res.statusCode < 400, status: res.statusCode, data });
      });
    }).on('error', (e) => resolve({ ok: false, error: e.message }));
  });
}

function httpPost(url, body) {
  return new Promise((resolve) => {
    const payload = JSON.stringify(body);
    const opts = {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) },
    };
    const req = http.request(url, opts, (res) => {
      let data = '';
      res.on('data', (c) => data += c);
      res.on('end', () => {
        try { resolve({ ok: res.statusCode < 400, status: res.statusCode, data: JSON.parse(data) }); }
        catch { resolve({ ok: false, status: res.statusCode, data: null }); }
      });
    });
    req.on('error', (e) => resolve({ ok: false, error: e.message }));
    req.write(payload);
    req.end();
  });
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log('');
  console.log(B('🌸 PinkRide Demo — Pre-flight Check'));
  console.log('─'.repeat(48));

  // ── 1. Env vars ───────────────────────────────────────────────────────────
  console.log(B('\n[1] Environment variables'));

  const SUPABASE_URL = process.env.SUPABASE_URL;
  const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY;
  const JWT_SECRET   = process.env.JWT_SECRET;
  const MOCK_FACE    = process.env.FACE_VERIFICATION_MOCK;
  const ALLOWED      = process.env.ALLOWED_ORIGINS || '';

  if (SUPABASE_URL && SUPABASE_URL.includes('supabase.co')) pass('SUPABASE_URL is set');
  else fail('SUPABASE_URL missing or invalid', 'Set SUPABASE_URL=https://xxxx.supabase.co in backend/.env');

  if (SUPABASE_KEY && SUPABASE_KEY.length > 20) pass('SUPABASE_SERVICE_KEY is set');
  else fail('SUPABASE_SERVICE_KEY missing', 'Set SUPABASE_SERVICE_KEY in backend/.env');

  if (JWT_SECRET && JWT_SECRET.length >= 32) pass('JWT_SECRET is set (length OK)');
  else fail('JWT_SECRET too short or missing', 'Generate with: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))"');

  if (MOCK_FACE === 'true') pass('FACE_VERIFICATION_MOCK=true (AWS not required)');
  else warn('FACE_VERIFICATION_MOCK is not "true"', 'Set FACE_VERIFICATION_MOCK=true in backend/.env for demo without AWS keys');

  if (ALLOWED.includes('localhost:8080')) pass('ALLOWED_ORIGINS includes localhost:8080');
  else fail('localhost:8080 not in ALLOWED_ORIGINS', 'Add http://localhost:8080 to ALLOWED_ORIGINS in backend/.env');

  // ── 2. Backend reachable ──────────────────────────────────────────────────
  console.log(B('\n[2] Backend server (port 3000)'));

  const health = await httpGet('http://localhost:3000/health');
  if (health.ok && health.data?.success) {
    pass(`Backend running — ${health.data.service} v${health.data.version}`);
  } else {
    fail('Backend is NOT running on port 3000',
      'Run: cd backend/backend && npm start');
    console.log(R('\n  ✗ Cannot continue checks without a running backend.\n'));
    process.exit(1);
  }

  // ── 3. Demo server reachable ──────────────────────────────────────────────
  console.log(B('\n[3] Demo dashboard (port 8080)'));

  const demo = await httpGet('http://localhost:8080');
  if (demo.ok) pass('Demo server running on port 8080');
  else fail('Demo server NOT running on port 8080',
    'Run in a separate terminal: cd backend/demo && node server.js');

  // ── 4. Supabase DB connectivity ───────────────────────────────────────────
  console.log(B('\n[4] Supabase database'));

  const db = createClient(SUPABASE_URL, SUPABASE_KEY);

  const { data: tables, error: tableErr } = await db
    .from('users').select('id', { count: 'exact', head: true });

  if (!tableErr) pass('Supabase connection OK — users table reachable');
  else fail('Cannot connect to Supabase', `Error: ${tableErr.message}`);

  // ── 5. Demo passenger account ─────────────────────────────────────────────
  console.log(B('\n[5] Demo accounts'));

  const PASSENGER_PHONE = '9876543210';
  const DRIVER_PHONE    = '9111111111';

  const { data: pUser } = await db
    .from('users').select('id,phone,role,city,face_verified')
    .eq('phone', PASSENGER_PHONE).maybeSingle();

  if (pUser) {
    pass(`Passenger account exists (${PASSENGER_PHONE})`);
    if (pUser.role === 'passenger') pass('  Role = passenger ✓');
    else warn(`  Role = ${pUser.role} (expected passenger)`, 'Will be corrected by Step 3 of the demo automatically');
    if (pUser.city === 'Jaipur') pass('  City = Jaipur ✓');
    else warn(`  City = ${pUser.city || 'null'}`, 'Will be set to Jaipur by Step 3 of the demo automatically');
    if (pUser.face_verified) warn('  face_verified = true (from previous run)', 'Step 4 will auto-reset this — no action needed');
    else pass('  face_verified = false (ready for fresh demo)');
  } else {
    warn(`Passenger account not found (${PASSENGER_PHONE})`,
      'It will be created automatically when you run Step 1 (Request OTP)');
  }

  // ── 6. Demo driver account ────────────────────────────────────────────────
  const { data: dUser } = await db
    .from('users').select('id,phone,role,city')
    .eq('phone', DRIVER_PHONE).maybeSingle();

  if (!dUser) {
    fail(`Driver account missing (${DRIVER_PHONE})`,
      'Run: node backend/seed-demo.js to create demo accounts');
  } else {
    pass(`Driver account exists (${DRIVER_PHONE})`);

    const { data: dRecord } = await db
      .from('drivers').select('id,approval_status,is_available,current_lat,current_lng')
      .eq('user_id', dUser.id).maybeSingle();

    if (!dRecord) {
      fail('  Driver profile (drivers table row) missing',
        'Run: node backend/seed-demo.js');
    } else {
      if (dRecord.approval_status === 'approved') pass('  approval_status = approved ✓');
      else fail(`  approval_status = ${dRecord.approval_status} (must be "approved")`,
        'Run: node backend/seed-demo.js to fix');

      if (dRecord.current_lat) pass('  Location pre-set ✓');
      else warn('  Location not set', 'Step 8 (Driver Goes Online) will set it automatically');
    }
  }

  // ── 7. API smoke-tests ───────────────────────────────────────────────────
  console.log(B('\n[6] API smoke-tests'));

  const otpRes = await httpPost(
    'http://localhost:3000/api/v1/auth/request-otp',
    { phone: PASSENGER_PHONE }
  );

  if (otpRes.ok && otpRes.data?.success) pass('POST /auth/request-otp → 200 OK');
  else fail(`OTP request failed: ${otpRes.data?.message || otpRes.error}`,
    'Check backend terminal for startup errors');

  // Verify bad OTP is rejected correctly
  const badOtpRes = await httpPost(
    'http://localhost:3000/api/v1/auth/verify-otp',
    { phone: PASSENGER_PHONE, otp: '000000' }
  );
  if (!badOtpRes.ok && badOtpRes.data?.message) pass('POST /auth/verify-otp → rejects bad OTP correctly');
  else warn('Unexpected response from verify-otp', JSON.stringify(badOtpRes.data));

  // Fare estimate requires auth — test the endpoint is up by checking it rejects unauth requests
  const fareRes = await httpGet(
    'http://localhost:3000/api/v1/rides/fare-estimate?distanceKm=8&rideType=private'
  );
  const fareMsg = fareRes.data?.message?.toLowerCase() || '';
  if (fareRes.status === 401 || fareMsg.includes('token') || fareMsg.includes('auth')) {
    pass('GET /rides/fare-estimate → endpoint up, requires auth (correct)');
  } else if (fareRes.ok && fareRes.data?.success) {
    pass(`GET /rides/fare-estimate → ₹${fareRes.data.data?.totalFare || '?'} for 8km`);
  } else {
    fail('Fare estimate endpoint not responding', fareRes.data?.message || fareRes.error);
  }

  // ── Summary ───────────────────────────────────────────────────────────────
  console.log('\n' + '─'.repeat(48));
  if (failures === 0 && warnings === 0) {
    console.log(G(B('✓ All checks passed — demo is ready!')));
    console.log(G('  Open: http://localhost:8080'));
  } else if (failures === 0) {
    console.log(Y(B(`⚠ Ready with ${warnings} warning(s) — demo will work but check hints above`)));
    console.log(G('  Open: http://localhost:8080'));
  } else {
    console.log(R(B(`✗ ${failures} check(s) failed — fix the issues above before running the demo`)));
  }
  console.log('');

  process.exit(failures > 0 ? 1 : 0);
}

main().catch((e) => {
  console.error(R('Unexpected error: ' + e.message));
  process.exit(1);
});
