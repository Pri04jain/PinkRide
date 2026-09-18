// ── PinkRide Demo App ──────────────────────────────────────────────────────────

const API = 'http://localhost:3000/api/v1';

// ── State ─────────────────────────────────────────────────────────────────────
const state = {
  passengerToken: null,
  driverToken:    null,
  adminToken:     null,
  rideId:         null,
  ridePassengerId: null,
  currentStep:    0,
  capturedImageBase64: null,
  passengerPhone: '9876543210',
};

// ── Navigation ────────────────────────────────────────────────────────────────
function navigate(page) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + page)?.classList.add('active');
  document.querySelector(`[data-page="${page}"]`)?.classList.add('active');

  const titles = {
    dashboard: { title: 'Admin Dashboard', sub: 'Manage drivers, view live stats' },
    sim:       { title: 'Ride Simulation', sub: 'See PinkRide from both sides — passenger & driver' },
    demo:      { title: 'Live API Demo', sub: 'Walk through the full ride flow step by step' },
    arch:      { title: 'Architecture', sub: 'Tech stack decisions and system design' },
  };
  const t = titles[page] || {};
  document.getElementById('topbar-title').textContent = t.title || '';
  document.getElementById('topbar-sub').textContent = t.sub || '';
}

// ── Toast ─────────────────────────────────────────────────────────────────────
function toast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = (type === 'success' ? '✓ ' : '✗ ') + msg;
  el.className = `toast ${type} show`;
  setTimeout(() => el.classList.remove('show'), 3500);
}

// ── Token Status Bar ──────────────────────────────────────────────────────────
function updateTokenStatus() {
  const bar = document.getElementById('token-status-bar');
  if (!bar) return;
  const pills = [
    state.passengerToken ? `<span style="background:#dcfce7;color:#16a34a;padding:3px 10px;border-radius:20px;font-size:12px;font-weight:600">👤 Passenger ✓</span>` : `<span style="background:#f1f5f9;color:#94a3b8;padding:3px 10px;border-radius:20px;font-size:12px">👤 Passenger —</span>`,
    state.driverToken   ? `<span style="background:#dcfce7;color:#16a34a;padding:3px 10px;border-radius:20px;font-size:12px;font-weight:600">🚗 Driver ✓</span>`    : `<span style="background:#f1f5f9;color:#94a3b8;padding:3px 10px;border-radius:20px;font-size:12px">🚗 Driver —</span>`,
    state.rideId        ? `<span style="background:#dbeafe;color:#2563eb;padding:3px 10px;border-radius:20px;font-size:12px;font-weight:600">🛣 Ride ${state.rideId.slice(0,6)}…</span>` : `<span style="background:#f1f5f9;color:#94a3b8;padding:3px 10px;border-radius:20px;font-size:12px">🛣 No ride yet</span>`,
  ];
  bar.innerHTML = pills.join('');
}

// ── Reset Demo ────────────────────────────────────────────────────────────────
function resetDemo() {
  state.passengerToken = null;
  state.driverToken    = null;
  state.rideId         = null;
  state.ridePassengerId = null;
  state.capturedImageBase64 = null;
  completedSteps = new Set();
  updateTokenStatus();
  renderDemoSteps();
  selectStep(0);
  toast('Demo reset — start from Step 1');
}

// ── API Helper ────────────────────────────────────────────────────────────────
async function apiCall(method, path, body = null, token = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const opts = { method, headers };
  if (body && Object.keys(body).length) opts.body = JSON.stringify(body);
  try {
    const res = await fetch(API + path, opts);
    return await res.json();
  } catch (e) {
    return { success: false, message: 'Network error — is the backend running on port 3000? ' + e.message };
  }
}

function fmt(obj) {
  return JSON.stringify(obj, null, 2);
}

// ══════════════════════════════════════════════════════════════════════════════
// DASHBOARD PAGE
// ══════════════════════════════════════════════════════════════════════════════

async function loadDashboard() {
  // Load stats
  await loadStats();
  // Load driver queue
  await loadDriverQueue();
}

async function loadStats() {
  // We build stats from the drivers + rides tables via the admin endpoint
  // First we need an admin token - use the one from state or try to get fresh
  if (!state.adminToken) {
    document.getElementById('stat-drivers').textContent = '—';
    document.getElementById('stat-pending').textContent = '—';
    document.getElementById('stat-rides').textContent = '—';
    document.getElementById('stat-users').textContent = '—';
    document.getElementById('stats-note').textContent = 'Login as admin to see live stats';
    return;
  }

  const res = await apiCall('GET', '/drivers/admin/stats', null, state.adminToken);
  if (res.success) {
    const s = res.data?.stats || res.data || {};
    document.getElementById('stat-drivers').textContent =
      (s.drivers?.approved ?? 0) + (s.drivers?.under_review ?? 0) + (s.drivers?.pending ?? 0);
    document.getElementById('stat-pending').textContent = s.drivers?.under_review ?? '0';
    document.getElementById('stat-rides').textContent   = s.rides?.total ?? s.totalRides ?? '0';
    document.getElementById('stat-users').textContent   =
      (s.users?.passengers ?? 0) + (s.users?.drivers ?? 0) || s.totalUsers || '—';
    document.getElementById('stats-note').textContent = 'Live from Supabase';
  }
}

async function loadDriverQueue() {
  const tbody = document.getElementById('driver-tbody');

  if (!state.adminToken) {
    tbody.innerHTML = `<tr><td colspan="6" class="empty-cell">
      <div class="empty">
        <div class="emoji">🔐</div>
        <h3>Admin login required</h3>
        <p>Click "Admin Login" to authenticate and view the driver queue</p>
      </div>
    </td></tr>`;
    return;
  }

  tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:32px;color:#94a3b8">Loading...</td></tr>`;

  const res = await apiCall('GET', '/drivers/admin/queue?status=under_review&limit=20', null, state.adminToken);

  if (!res.success) {
    tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;padding:24px;color:#ef4444">${res.message}</td></tr>`;
    return;
  }

  const drivers = res.data?.drivers || [];
  if (!drivers.length) {
    tbody.innerHTML = `<tr><td colspan="6">
      <div class="empty">
        <div class="emoji">✅</div>
        <h3>No pending applications</h3>
        <p>All driver applications have been reviewed</p>
      </div>
    </td></tr>`;
    return;
  }

  tbody.innerHTML = drivers.map(d => {
    const u = d.users || {};
    const initials = (u.full_name || 'D').split(' ').map(x => x[0]).join('').toUpperCase().slice(0,2);
    const statusBadge = {
      pending:      '<span class="badge badge-grey">Pending</span>',
      under_review: '<span class="badge badge-review">Under Review</span>',
      approved:     '<span class="badge badge-approved">Approved</span>',
      rejected:     '<span class="badge badge-rejected">Rejected</span>',
      suspended:    '<span class="badge badge-pending">Suspended</span>',
    }[d.approval_status] || d.approval_status;

    return `<tr>
      <td>
        <div style="display:flex;align-items:center;gap:10px">
          <div class="avatar">${initials}</div>
          <div class="user-info">
            <h4>${u.full_name || 'Unknown'}</h4>
            <p>${u.phone || ''}</p>
          </div>
        </div>
      </td>
      <td>${d.vehicle_make || ''} ${d.vehicle_model || ''}<br><small style="color:#94a3b8">${d.vehicle_color || ''} · ${d.vehicle_year || ''}</small></td>
      <td style="font-family:monospace;font-size:13px">${d.license_number || ''}</td>
      <td>${statusBadge}</td>
      <td style="font-size:12px;color:#94a3b8">${new Date(d.created_at).toLocaleDateString('en-IN')}</td>
      <td>
        <div style="display:flex;gap:6px">
          <button class="btn btn-green btn-sm" onclick="approveDriver('${d.id}', '${u.full_name || 'Driver'}')">✓ Approve</button>
          <button class="btn btn-red btn-sm" onclick="openRejectModal('${d.id}', '${u.full_name || 'Driver'}')">✗ Reject</button>
        </div>
      </td>
    </tr>`;
  }).join('');
}

async function approveDriver(driverId, name) {
  if (!state.adminToken) return toast('Login as admin first', 'error');
  const res = await apiCall('POST', `/drivers/admin/${driverId}/approve`, {}, state.adminToken);
  if (res.success) {
    toast(`${name} approved successfully`);
    await loadDriverQueue();
    await loadStats();
  } else {
    toast(res.message, 'error');
  }
}

function openRejectModal(driverId, name) {
  document.getElementById('reject-driver-id').value = driverId;
  document.getElementById('reject-driver-name').textContent = name;
  document.getElementById('reject-reason').value = '';
  document.getElementById('reject-modal').classList.add('show');
}

async function submitReject() {
  const driverId = document.getElementById('reject-driver-id').value;
  const reason   = document.getElementById('reject-reason').value.trim();
  if (!reason) return toast('Please enter a rejection reason', 'error');

  const res = await apiCall('POST', `/drivers/admin/${driverId}/reject`, { reason }, state.adminToken);
  if (res.success) {
    toast('Driver application rejected');
    document.getElementById('reject-modal').classList.remove('show');
    await loadDriverQueue();
    await loadStats();
  } else {
    toast(res.message, 'error');
  }
}

// ── Admin Login modal ─────────────────────────────────────────────────────────
function openAdminLogin() {
  document.getElementById('admin-login-modal').classList.add('show');
}

async function submitAdminLogin() {
  const phone = document.getElementById('admin-phone').value.trim();
  if (!phone) return toast('Enter admin phone number', 'error');

  // Step 1 — request OTP
  const otpRes = await apiCall('POST', '/auth/request-otp', { phone });
  if (!otpRes.success) return toast(otpRes.message, 'error');

  document.getElementById('admin-otp-section').style.display = 'block';
  toast('OTP sent — check server terminal for the code');
}

async function verifyAdminOtp() {
  const phone = document.getElementById('admin-phone').value.trim();
  const otp   = document.getElementById('admin-otp').value.trim();
  if (!otp) return toast('Enter the OTP', 'error');

  const res = await apiCall('POST', '/auth/verify-otp', { phone, otp });
  if (!res.success) return toast(res.message, 'error');

  // Check the logged-in user actually has admin role
  const role = res.data?.user?.role;
  if (role && role !== 'admin') {
    return toast(`Phone ${phone} has role "${role}", not admin. Use 9000000000 or 9000000001`, 'error');
  }

  state.adminToken = res.data?.tokens?.accessToken;
  document.getElementById('admin-login-modal').classList.remove('show');
  document.getElementById('admin-login-btn').textContent = '✓ Admin';
  document.getElementById('admin-login-btn').classList.add('btn-green');
  document.getElementById('admin-login-btn').classList.remove('btn-outline');
  toast('Admin logged in ✓');
  await loadDashboard();
}

// ══════════════════════════════════════════════════════════════════════════════
// LIVE DEMO PAGE
// ══════════════════════════════════════════════════════════════════════════════

const demoSteps = [
  {
    id: 'step-1',
    title: 'Request OTP (Passenger)',
    desc: 'Passenger requests a login OTP',
    method: 'POST',
    path: '/auth/request-otp',
    body: () => ({ phone: document.getElementById('passenger-phone-input')?.value || '9876543210' }),
    run: stepRequestPassengerOtp,
  },
  {
    id: 'step-2',
    title: 'Verify OTP + Login',
    desc: 'Verify OTP, receive JWT token',
    method: 'POST',
    path: '/auth/verify-otp',
    body: () => ({ phone: document.getElementById('passenger-phone-input')?.value || '9876543210', otp: document.getElementById('demo-otp-input')?.value || '______' }),
    run: stepVerifyPassengerOtp,
  },
  {
    id: 'step-3',
    title: 'Complete Profile Registration',
    desc: 'Enter name (consent auto-recorded during face verification)',
    method: 'POST',
    path: '/users/register',
    body: () => ({ fullName: 'John Doe', gender: 'male', dateOfBirth: '1995-01-15', role: 'passenger' }),
    run: stepCompleteRegistration,
  },
  {
    id: 'step-4',
    title: 'Face Verification - Validate Liveness',
    desc: 'Take selfie, detect face, check liveness',
    method: 'POST',
    path: '/verification/register/validate',
    body: () => ({ image: state.capturedImageBase64 ? '&lt;photo captured ✓&gt;' : '⚠ Take photo first' }),
    run: stepFaceValidate,
  },
  {
    id: 'step-5',
    title: 'Face Verification - Confirm Registration',
    desc: 'Index face into Rekognition (photo auto-sent from step 4)',
    method: 'POST',
    path: '/verification/register/confirm',
    body: () => ({ image: state.capturedImageBase64 ? '&lt;same photo as step 4&gt;' : '&lt;from server session&gt;' }),
    run: stepFaceConfirm,
  },
  {
    id: 'step-6',
    title: 'Get Fare Estimate',
    desc: 'Estimate fare before booking',
    method: 'GET',
    path: '/rides/fare-estimate?distanceKm=8&rideType=private',
    body: () => null,
    run: stepFareEstimate,
  },
  {
    id: 'step-7',
    title: 'Book a Ride',
    desc: 'Passenger books a private ride',
    method: 'POST',
    path: '/rides/book',
    body: () => ({
      rideType: 'private',
      pickupLat: 26.9124, pickupLng: 75.7873,
      pickupAddress: 'Vaishali Nagar, Jaipur',
      dropLat: 26.8535, dropLng: 75.8069,
      dropAddress: 'Malviya Nagar, Jaipur',
      scheduledAt: new Date(Date.now() + 3600000).toISOString(),
      distanceKm: 8, paymentMethod: 'cash',
    }),
    run: stepBookRide,
  },
  {
    id: 'step-8',
    title: 'Driver Goes Online',
    desc: 'Driver sets location and goes available',
    method: 'PATCH',
    path: '/drivers/availability',
    body: () => ({ isAvailable: true }),
    run: stepDriverOnline,
  },
  {
    id: 'step-9',
    title: 'Driver Accepts Ride',
    desc: 'Driver sees booking and accepts the ride',
    method: 'POST',
    path: '/drivers/ride-requests/:rideId/accept',
    body: () => null,
    run: stepDriverAccept,
  },
];

let completedSteps = new Set();

function renderDemoSteps() {
  const list = document.getElementById('step-list');
  list.innerHTML = demoSteps.map((s, i) => `
    <div class="step-item ${completedSteps.has(i) ? 'done' : (state.currentStep === i ? 'active' : '')}"
         id="step-item-${i}" onclick="selectStep(${i})">
      <div class="step-num">${completedSteps.has(i) ? '✓' : (i + 1)}</div>
      <div class="step-info">
        <h4>${s.title}</h4>
        <p>${s.desc}</p>
      </div>
    </div>
  `).join('');
}

function selectStep(i) {
  state.currentStep = i;
  renderDemoSteps();
  renderDemoPanel(i);
}

function renderDemoPanel(i) {
  const s = demoSteps[i];
  const panel = document.getElementById('demo-panel');

  const bodyJson = s.body();
  // bodyJson may contain placeholder strings (not real objects), render as-is
  const bodySection = bodyJson ? `
    <div class="request-body">
      <label>Request Body</label>
      <pre class="code">${JSON.stringify(bodyJson, null, 2)}</pre>
    </div>` : '';

  // Special OTP input for step 2
  const otpInput = i === 1 ? `
    <div class="request-body">
      <label>Enter OTP (check server terminal)</label>
      <input id="demo-otp-input" type="text" maxlength="6" placeholder="6-digit OTP"
        style="width:100%;padding:10px 14px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:18px;letter-spacing:6px;text-align:center;font-family:monospace"
        oninput="this.value=this.value.replace(/\D/g,'')">
    </div>` : '';

  // Phone input for step 1
  const phoneInput = i === 0 ? `
    <div class="request-body">
      <label>Passenger Phone Number</label>
      <input id="passenger-phone-input" type="text" maxlength="10" placeholder="10-digit mobile number"
        style="width:100%;padding:10px 14px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:15px;font-family:monospace;letter-spacing:2px"
        oninput="this.value=this.value.replace(/\D/g,'')" value="${document.getElementById('passenger-phone-input')?.value || ''}">
    </div>` : (i === 1 ? `
    <div class="request-body">
      <label>Phone Number</label>
      <input id="passenger-phone-input" type="text" maxlength="10" placeholder="Same number as step 1"
        style="width:100%;padding:10px 14px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:15px;font-family:monospace;letter-spacing:2px"
        oninput="this.value=this.value.replace(/\D/g,'')" value="${document.getElementById('passenger-phone-input')?.value || ''}">
    </div>` : '');

  // Special camera section for face verification steps
  const cameraSection = (i === 3 || i === 4 || i === 11) ? `
    <div class="request-body" style="border:2px dashed #e91e8c;padding:16px;border-radius:8px;background:#fce4f3">
      <label style="color:#e91e8c;font-weight:700">📷 Camera Capture</label>
      <div style="display:flex;flex-direction:column;gap:10px;margin-top:10px">
        <video id="camera-feed-${i}" width="280" height="280" 
          style="border-radius:8px;background:#000;display:none;border:2px solid #e91e8c;autoplay;playsinline" autoplay playsinline></video>
        <canvas id="camera-canvas-${i}" width="280" height="280" 
          style="border-radius:8px;background:#f1f5f9;display:none;border:2px solid #22c55e"></canvas>
        <img id="captured-photo-${i}" 
          style="border-radius:8px;max-height:280px;display:none;border:2px solid #22c55e">
        <div style="display:flex;gap:8px;flex-wrap:wrap">
          <button class="btn btn-outline btn-sm" id="start-camera-${i}" 
            onclick="startCamera(${i})">🎥 Open Camera</button>
          <button class="btn btn-pink btn-sm" id="capture-btn-${i}" 
            onclick="capturePhoto(${i})" style="display:none">📸 Capture</button>
          <button class="btn btn-outline btn-sm" id="retake-btn-${i}" 
            onclick="retakePhoto(${i})" style="display:none">🔄 Retake</button>
        </div>
        <small style="color:#64748b;font-size:12px">
          ${i === 3 || i === 4 ? '✓ Face toward camera • Eyes open • Good lighting' : '✓ Verify your identity before boarding'}
        </small>
      </div>
    </div>` : '';

  // Special driver login section for step 8 (Driver Goes Online)
  const driverLoginSection = (i === 7 || i === 8) ? `
    <div class="request-body">
      <label>Driver Setup</label>
      <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">
        <input id="driver-phone-input" type="text" placeholder="Driver phone (9111111111)"
          style="flex:1;padding:9px 12px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:13px;"
          value="9111111111">
        <button class="btn btn-outline btn-sm" onclick="driverGetOtp()">Get OTP</button>
        <input id="driver-otp-input" type="text" maxlength="6" placeholder="OTP"
          style="width:80px;padding:9px 12px;border:1.5px solid #e2e8f0;border-radius:8px;font-size:13px;font-family:monospace;letter-spacing:3px">
        <button class="btn btn-pink btn-sm" onclick="driverLogin()">Login</button>
      </div>
      <p style="font-size:12px;color:#94a3b8;margin-top:8px">OTP will print in the server terminal</p>
    </div>` : '';

  panel.innerHTML = `
    <div class="request-card">
      <div class="request-header">
        <span class="method-badge method-${s.method}">${s.method}</span>
        <span class="request-url">${API}${s.path}</span>
      </div>
      ${phoneInput}
      ${otpInput}
      ${cameraSection}
      ${driverLoginSection}
      ${bodySection}
      <button class="run-btn" id="run-btn-${i}" onclick="runStep(${i})">
        ▶ Run Request
      </button>
      <div class="response-area">
        <label>Response</label>
        <pre class="response-box waiting" id="response-${i}">Click "Run Request" to execute...</pre>
      </div>
    </div>

    <div style="display:flex;gap:12px;margin-top:4px">
      ${i > 0 ? `<button class="btn btn-outline" onclick="selectStep(${i-1})">← Previous</button>` : ''}
      ${i < demoSteps.length-1 ? `<button class="btn btn-pink" id="next-btn-${i}" onclick="selectStep(${i+1})">Next Step →</button>` : '<span class="badge badge-approved" style="padding:10px 18px;font-size:14px">🎉 Demo Complete!</span>'}
    </div>
  `;
}

async function runStep(i) {
  const btn = document.getElementById(`run-btn-${i}`);
  const box = document.getElementById(`response-${i}`);
  btn.disabled = true;
  btn.innerHTML = '<div class="spinner"></div> Running...';
  box.className = 'response-box waiting';
  box.textContent = 'Calling API...';

  try {
    const result = await demoSteps[i].run();
    box.className = result.success ? 'response-box' : 'response-box error';
    box.textContent = fmt(result);
    if (result.success) {
      completedSteps.add(i);
      renderDemoSteps();
      updateTokenStatus();
    }
  } catch(e) {
    box.className = 'response-box error';
    box.textContent = 'Error: ' + e.message;
  }

  btn.disabled = false;
  btn.innerHTML = '▶ Run Request';
}

// ── Step implementations ──────────────────────────────────────────────────────

async function stepRequestPassengerOtp() {
  const phone = document.getElementById('passenger-phone-input')?.value?.trim() || '9876543210';
  state.passengerPhone = phone;
  const res = await apiCall('POST', '/auth/request-otp', { phone });
  if (res.success) toast('OTP sent — check server terminal for code');
  else toast(res.message, 'error');
  return res;
}

async function stepVerifyPassengerOtp() {
  const phone = document.getElementById('passenger-phone-input')?.value?.trim() || state.passengerPhone || '9876543210';
  const otp = document.getElementById('demo-otp-input')?.value?.trim();
  if (!otp || otp.length !== 6) return { success: false, message: 'Enter the 6-digit OTP from the server terminal first' };
  const res = await apiCall('POST', '/auth/verify-otp', { phone, otp });
  if (res.success) {
    state.passengerToken = res.data?.tokens?.accessToken;
    updateTokenStatus();
    toast('Passenger logged in ✓');
  }
  return res;
}

async function stepCompleteRegistration() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 (login) first' };
  const res = await apiCall('POST', '/users/register',
    { fullName: 'Demo Passenger', gender: 'female', dateOfBirth: '1995-01-15', role: 'passenger' },
    state.passengerToken);
  if (res.success) toast('Profile set ✓');
  // 400/409 here just means profile already exists — not fatal, continue
  else if (res.message?.toLowerCase().includes('already')) {
    toast('Profile already set — continuing', 'success');
    return { success: true, message: 'Profile already registered, continuing', data: res.data };
  }
  return res;
}

async function stepFareEstimate() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 (login) first' };
  return await apiCall('GET', '/rides/fare-estimate?distanceKm=8&rideType=private', null, state.passengerToken);
}

async function stepBookRide() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 (login) first' };
  const res = await apiCall('POST', '/rides/book', {
    rideType: 'private',
    pickupLat: 26.9124, pickupLng: 75.7873,
    pickupAddress: 'Vaishali Nagar, Jaipur',
    dropLat: 26.8535, dropLng: 75.8069,
    dropAddress: 'Malviya Nagar, Jaipur',
    scheduledAt: new Date(Date.now() + 3600000).toISOString(),
    distanceKm: 8, paymentMethod: 'cash',
  }, state.passengerToken);
  if (res.success) {
    state.rideId = res.data?.rideId;
    state.ridePassengerId = res.data?.ridePassengerId || res.data?.ride_passengers?.[0]?.id;
    updateTokenStatus();
    toast(`Ride booked — ID: ${state.rideId?.slice(0,8)}…`);
  }
  return res;
}

async function driverGetOtp() {
  const phone = document.getElementById('driver-phone-input')?.value?.trim() || '9111111111';
  const res = await apiCall('POST', '/auth/request-otp', { phone });
  if (res.success) toast('Driver OTP sent — check server terminal');
  else toast(res.message, 'error');
}

async function driverLogin() {
  const phone = document.getElementById('driver-phone-input')?.value?.trim() || '9111111111';
  const otp   = document.getElementById('driver-otp-input')?.value?.trim();
  if (!otp) return toast('Enter driver OTP first', 'error');
  const res = await apiCall('POST', '/auth/verify-otp', { phone, otp });
  if (res.success) {
    state.driverToken = res.data?.tokens?.accessToken;
    updateTokenStatus();
    toast('Driver logged in ✓');
  } else {
    toast(res.message, 'error');
  }
}

async function stepDriverOnline() {
  if (!state.driverToken) return { success: false, message: 'Log in as driver using the form above first, then click Run' };
  // Update location so Haversine radius filter finds the ride
  await apiCall('PATCH', '/drivers/location', { lat: 26.9124, lng: 75.7873 }, state.driverToken);
  const res = await apiCall('PATCH', '/drivers/availability', { isAvailable: true }, state.driverToken);
  if (res.success) toast('Driver online ✓ — location set to Vaishali Nagar');
  return res;
}

async function stepDriverAccept() {
  if (!state.driverToken) return { success: false, message: 'Complete Step 8 (driver online) first' };
  if (!state.rideId)      return { success: false, message: 'Complete Step 7 (book ride) first' };
  const res = await apiCall('POST', `/drivers/ride-requests/${state.rideId}/accept`, {}, state.driverToken);
  if (res.success) toast('Ride accepted ✓ — Socket.io event emitted to passenger');
  return res;
}

async function stepPassengerActive() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 first' };
  return await apiCall('GET', '/rides/active', null, state.passengerToken);
}

// ── Camera & Face Verification ───────────────────────────────────────────────

let cameraStream = null;

async function startCamera(stepIndex) {
  try {
    const canvas = document.getElementById(`camera-canvas-${stepIndex}`);
    const video = document.getElementById(`camera-feed-${stepIndex}`);
    const startBtn = document.getElementById(`start-camera-${stepIndex}`);
    const captureBtn = document.getElementById(`capture-btn-${stepIndex}`);
    
    // Request camera access
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 1280 }, height: { ideal: 720 } }
    });
    
    video.srcObject = cameraStream;
    video.style.display = 'block';
    startBtn.style.display = 'none';
    captureBtn.style.display = 'inline-flex';
    
    toast('Camera ready. Click Capture when ready.');
  } catch (err) {
    toast('Camera access denied: ' + err.message, 'error');
  }
}

function capturePhoto(stepIndex) {
  const video = document.getElementById(`camera-feed-${stepIndex}`);
  const canvas = document.getElementById(`camera-canvas-${stepIndex}`);
  const img = document.getElementById(`captured-photo-${stepIndex}`);
  const captureBtn = document.getElementById(`capture-btn-${stepIndex}`);
  const retakeBtn = document.getElementById(`retake-btn-${stepIndex}`);
  
  // Draw video frame to canvas
  const ctx = canvas.getContext('2d');
  ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
  
  // Convert to base64
  const imageData = canvas.toDataURL('image/jpeg', 0.9);
  state.capturedImageBase64 = imageData.split(',')[1]; // Remove data:image/jpeg;base64, prefix
  
  // Show preview
  img.src = imageData;
  img.style.display = 'block';
  video.style.display = 'none';
  canvas.style.display = 'none';
  captureBtn.style.display = 'none';
  retakeBtn.style.display = 'inline-flex';
  
  // Stop camera
  if (cameraStream) {
    cameraStream.getTracks().forEach(track => track.stop());
    cameraStream = null;
  }
  
  toast('Photo captured ✓');
}

function retakePhoto(stepIndex) {
  const video = document.getElementById(`camera-feed-${stepIndex}`);
  const img = document.getElementById(`captured-photo-${stepIndex}`);
  const captureBtn = document.getElementById(`capture-btn-${stepIndex}`);
  const retakeBtn = document.getElementById(`retake-btn-${stepIndex}`);
  
  img.style.display = 'none';
  video.style.display = 'block';
  captureBtn.style.display = 'inline-flex';
  retakeBtn.style.display = 'none';
  
  startCamera(stepIndex);
}

async function stepFaceValidate() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 (login) first' };
  if (!state.capturedImageBase64) return { success: false, message: '📷 Open the camera above, take a selfie, then click Run' };

  const res = await apiCall('POST', '/verification/register/validate',
    { image: state.capturedImageBase64 }, state.passengerToken);

  if (res.success) toast('Face validated ✓ — proceed to Step 5 to confirm');
  // Do NOT clear capturedImageBase64 here — Step 5 needs it
  return res;
}

async function stepFaceConfirm() {
  if (!state.passengerToken) return { success: false, message: 'Complete Step 2 (login) first' };
  if (!state.capturedImageBase64) return { success: false, message: 'Complete Step 4 (validate) first — photo is required' };

  const body = { image: state.capturedImageBase64 };
  const res = await apiCall('POST', '/verification/register/confirm', body, state.passengerToken);

  if (res.success) {
    toast('Face registered ✓');
    state.capturedImageBase64 = null; // safe to clear now — Step 5 is done
  }
  return res;
}

async function stepPreRideFaceVerify() {
  if (!state.passengerToken) return { success: false, message: 'Complete step 2 first' };
  if (!state.ridePassengerId) return { success: false, message: 'Complete step 9 (driver accept) first' };
  if (!state.capturedImageBase64) return { success: false, message: 'Capture a new photo using the camera' };
  
  const res = await apiCall('POST', `/verification/ride/${state.ridePassengerId}`, 
    { image: state.capturedImageBase64 }, state.passengerToken);
  
  if (res.success) {
    toast(`Identity verified ✓ — similarity ${res.data?.similarity?.toFixed(1)}%`);
    state.capturedImageBase64 = null;
  }
  return res;
}

// ══════════════════════════════════════════════════════════════════════════════
// INIT
// ══════════════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  navigate('dashboard');
  loadDashboard();
  renderDemoSteps();
  selectStep(0);
  updateTokenStatus();

  // Nav clicks
  document.querySelectorAll('.nav-item[data-page]').forEach(el => {
    el.addEventListener('click', () => {
      const page = el.dataset.page;
      navigate(page);
      if (page === 'dashboard') {
        loadDashboard();
        // If sim has a pending driver approval, prompt admin login and refresh queue
        if (typeof S !== 'undefined' && S.approvalPolling) {
          setTimeout(() => {
            const note = document.getElementById('sim-admin-hint');
            if (!note) {
              const hint = document.createElement('div');
              hint.id = 'sim-admin-hint';
              hint.style.cssText = 'background:#fce4f3;border:1.5px solid var(--pink);border-radius:10px;padding:12px 18px;margin-bottom:16px;font-size:13px;font-weight:600;color:var(--pink-dark);display:flex;align-items:center;gap:10px';
              hint.innerHTML = '🔔 <span>Driver application pending from simulation — login as admin and approve from the queue below</span>';
              const page = document.getElementById('page-dashboard');
              if (page) page.insertBefore(hint, page.firstChild);
            }
          }, 100);
        }
      }
      if (page === 'sim') initSimulation();
      if (page === 'demo') updateTokenStatus();
    });
  });
});
