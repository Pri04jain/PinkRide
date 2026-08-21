// ── PinkRide Demo App ──────────────────────────────────────────────────────────

const API = 'http://localhost:3000/api/v1';

// ── State ─────────────────────────────────────────────────────────────────────
const state = {
  passengerToken: null,
  driverToken:    null,
  adminToken:     null,
  activeToken:    null,
  rideId:         null,
  otp:            null,
  currentStep:    0,
};

// ── Navigation ────────────────────────────────────────────────────────────────
function navigate(page) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
  document.getElementById('page-' + page)?.classList.add('active');
  document.querySelector(`[data-page="${page}"]`)?.classList.add('active');

  const titles = {
    dashboard: { title: 'Admin Dashboard', sub: 'Manage drivers, view live stats' },
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
  setTimeout(() => el.classList.remove('show'), 3000);
}

// ── API Helper ────────────────────────────────────────────────────────────────
async function apiCall(method, path, body = null, token = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  try {
    const res = await fetch(API + path, opts);
    return await res.json();
  } catch (e) {
    return { success: false, message: 'Network error: ' + e.message };
  }
}

// ── Format JSON for display ───────────────────────────────────────────────────
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

  state.adminToken = res.data?.tokens?.accessToken;
  document.getElementById('admin-login-modal').classList.remove('show');
  document.getElementById('admin-login-btn').textContent = '✓ Admin';
  document.getElementById('admin-login-btn').classList.add('btn-green');
  document.getElementById('admin-login-btn').classList.remove('btn-outline');
  toast('Admin logged in');
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
    title: 'Get Fare Estimate',
    desc: 'Estimate fare before booking',
    method: 'GET',
    path: '/rides/fare-estimate?distanceKm=8&rideType=private',
    body: () => null,
    run: stepFareEstimate,
  },
  {
    id: 'step-4',
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
    id: 'step-5',
    title: 'Driver Goes Online',
    desc: 'Driver sets availability to true',
    method: 'PATCH',
    path: '/drivers/availability',
    body: () => ({ isAvailable: true }),
    run: stepDriverOnline,
  },
  {
    id: 'step-6',
    title: 'Driver Sees Requests',
    desc: 'Driver fetches nearby ride requests',
    method: 'GET',
    path: '/drivers/ride-requests',
    body: () => null,
    run: stepDriverSeeRequests,
  },
  {
    id: 'step-7',
    title: 'Driver Accepts Ride',
    desc: 'Driver accepts — passenger gets confirmed',
    method: 'POST',
    path: '/drivers/ride-requests/:rideId/accept',
    body: () => null,
    run: stepDriverAccept,
  },
  {
    id: 'step-8',
    title: 'Passenger Active Ride',
    desc: 'Passenger sees driver details + status',
    method: 'GET',
    path: '/rides/active',
    body: () => null,
    run: stepPassengerActive,
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

  // Special driver login section for step 5
  const driverLoginSection = i === 4 ? `
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
  const res = await apiCall('POST', '/auth/request-otp', { phone });
  if (res.success) toast('OTP sent — check server terminal for code');
  return res;
}

async function stepVerifyPassengerOtp() {
  const phone = document.getElementById('passenger-phone-input')?.value?.trim() || '9876543210';
  const otp = document.getElementById('demo-otp-input')?.value?.trim();
  if (!otp || otp.length !== 6) return { success: false, message: 'Enter the 6-digit OTP from the server terminal first' };
  const res = await apiCall('POST', '/auth/verify-otp', { phone, otp });
  if (res.success) {
    state.passengerToken = res.data?.tokens?.accessToken;
    toast('Passenger logged in ✓');
  }
  return res;
}

async function stepFareEstimate() {
  return await apiCall('GET', '/rides/fare-estimate?distanceKm=8&rideType=private', null, state.passengerToken);
}

async function stepBookRide() {
  if (!state.passengerToken) return { success: false, message: 'Complete step 2 (passenger login) first' };
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
    toast(`Ride booked — ID: ${state.rideId?.slice(0,8)}...`);
  }
  return res;
}

async function driverGetOtp() {
  const phone = document.getElementById('driver-phone-input').value.trim();
  const res = await apiCall('POST', '/auth/request-otp', { phone });
  if (res.success) toast('Driver OTP sent — check server terminal');
  else toast(res.message, 'error');
}

async function driverLogin() {
  const phone = document.getElementById('driver-phone-input').value.trim();
  const otp   = document.getElementById('driver-otp-input').value.trim();
  if (!otp) return toast('Enter driver OTP', 'error');
  const res = await apiCall('POST', '/auth/verify-otp', { phone, otp });
  if (res.success) {
    state.driverToken = res.data?.tokens?.accessToken;
    toast('Driver logged in ✓');
  } else {
    toast(res.message, 'error');
  }
}

async function stepDriverOnline() {
  if (!state.driverToken) return { success: false, message: 'Login as driver first using the form above, then click Run' };
  // Also update location so Haversine filter works
  await apiCall('PATCH', '/drivers/location', { lat: 26.9124, lng: 75.7873 }, state.driverToken);
  return await apiCall('PATCH', '/drivers/availability', { isAvailable: true }, state.driverToken);
}

async function stepDriverSeeRequests() {
  if (!state.driverToken) return { success: false, message: 'Complete step 5 (driver login) first' };
  return await apiCall('GET', '/drivers/ride-requests', null, state.driverToken);
}

async function stepDriverAccept() {
  if (!state.driverToken) return { success: false, message: 'Complete step 5 first' };
  if (!state.rideId)      return { success: false, message: 'Complete step 4 (book ride) first' };
  const res = await apiCall('POST', `/drivers/ride-requests/${state.rideId}/accept`, {}, state.driverToken);
  if (res.success) toast('Ride accepted — passenger notified via Socket.io ✓');
  return res;
}

async function stepPassengerActive() {
  if (!state.passengerToken) return { success: false, message: 'Complete step 2 first' };
  return await apiCall('GET', '/rides/active', null, state.passengerToken);
}

// ══════════════════════════════════════════════════════════════════════════════
// INIT
// ══════════════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  navigate('dashboard');
  loadDashboard();
  renderDemoSteps();
  selectStep(0);

  // Nav clicks
  document.querySelectorAll('.nav-item[data-page]').forEach(el => {
    el.addEventListener('click', () => {
      const page = el.dataset.page;
      navigate(page);
      if (page === 'dashboard') loadDashboard();
    });
  });
});
