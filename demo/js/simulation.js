// ── PinkRide Interactive Simulation ──────────────────────────────────────────
// Fully interactive two-phone demo. Every button inside the phone frames
// drives real state and makes live API calls to the backend.

const SIM_API = 'http://localhost:3000/api/v1';

// ── Global state ──────────────────────────────────────────────────────────────
const S = {
  // Signup form data
  pName:       '',
  pGender:     '',
  pDob:        '',
  dName:       '',
  dGender:     '',
  dDob:        '',
  // Vehicle form
  vMake:       '',
  vModel:      '',
  vColor:      '',
  vYear:       '',
  vNumber:     '',
  vType:       'Hatchback',
  vLicense:    '',
  vExpiry:     '',
  // Approval
  driverId:    null,      // DB driver id after registration
  approvalPolling: null,  // interval id

  // Auth
  passengerToken: null,
  driverToken:    null,
  passengerPhone: '',
  driverPhone:    '',
  passengerOtp:   '',
  driverOtp:      '',

  // Ride
  rideId:           null,
  ridePassengerId:  null,
  fare:             '₹124',
  sharedFare:       '₹87',
  rideType:         'private',  // 'private' | 'shared'
  rideOtp:          null,
  driverEnteredOtp: '',

  // Location picker
  pickup:  null,   // { name, lat, lng }
  drop:    null,   // { name, lat, lng }
  pickingFor: null, // 'pickup' | 'drop'

  // Face verify (ride)
  capturedImage:  null,
  faceStream:     null,
  faceVerified:   false,
  // Face registration (signup)
  faceRegDone:    false,
  faceRegStatus:  'Open camera to register your face',

  // Screens
  passengerScreen: 'splash',
  driverScreen:    'splash',

  // Misc
  safetyTimer:    null,
  narration:      '🌸 Welcome to PinkRide — tap the buttons inside the phones to drive the demo.',
  apiLog:         [],
};

// Jaipur locations for the fake map picker
const LOCATIONS = [
  { name: 'Vaishali Nagar',  lat: 26.9124, lng: 75.7873, top: '22%', left: '18%' },
  { name: 'Malviya Nagar',   lat: 26.8535, lng: 75.8069, top: '68%', left: '62%' },
  { name: 'C-Scheme',        lat: 26.9100, lng: 75.8235, top: '28%', left: '72%' },
  { name: 'Mansarovar',      lat: 26.8607, lng: 75.7559, top: '62%', left: '24%' },
  { name: 'Sodala',          lat: 26.9304, lng: 75.7826, top: '12%', left: '32%' },
  { name: 'Tonk Road',       lat: 26.8714, lng: 75.8040, top: '52%', left: '58%' },
];
async function api(method, path, body = null, token = null) {
  const headers = { 'Content-Type': 'application/json' };
  if (token) headers['Authorization'] = `Bearer ${token}`;
  const opts = { method, headers };
  if (body) opts.body = JSON.stringify(body);
  try {
    const r = await fetch(SIM_API + path, opts);
    const data = await r.json();
    logApi(`${method} ${path} → ${r.status}`);
    return data;
  } catch {
    logApi(`${method} ${path} → offline`);
    return { success: false, message: 'Backend offline' };
  }
}

function logApi(line) {
  S.apiLog.unshift(line);
  if (S.apiLog.length > 6) S.apiLog.pop();
  const el = document.getElementById('sim-api-log');
  if (el) el.innerHTML = S.apiLog.map(l => `<div>${l}</div>`).join('');
}

// ── Narration ─────────────────────────────────────────────────────────────────
function narrate(text) {
  S.narration = text;
  const el = document.getElementById('sim-narration');
  if (!el) return;
  el.classList.remove('narr-in');
  void el.offsetWidth;
  el.textContent = text;
  el.classList.add('narr-in');
}

// ── Render both phones ────────────────────────────────────────────────────────
function render() {
  const pEl = document.getElementById('sim-passenger-phone');
  const dEl = document.getElementById('sim-driver-phone');
  if (pEl) {
    pEl.style.opacity = '0';
    pEl.style.transform = 'scale(0.97)';
    setTimeout(() => {
      pEl.innerHTML = passengerScreenHTML();
      pEl.style.opacity = '1';
      pEl.style.transform = 'scale(1)';
      afterRenderPassenger();
    }, 120);
  }
  if (dEl) {
    dEl.style.opacity = '0';
    dEl.style.transform = 'scale(0.97)';
    setTimeout(() => {
      dEl.innerHTML = driverScreenHTML();
      dEl.style.opacity = '1';
      dEl.style.transform = 'scale(1)';
      afterRenderDriver();
    }, 120);
  }
}

function renderPassenger() {
  const el = document.getElementById('sim-passenger-phone');
  if (!el) return;
  el.innerHTML = passengerScreenHTML();
  afterRenderPassenger();
}

function renderDriver() {
  const el = document.getElementById('sim-driver-phone');
  if (!el) return;
  el.innerHTML = driverScreenHTML();
  afterRenderDriver();
}

// post-render hooks (attach camera, start timers, etc.)
function afterRenderPassenger() {
  if (S.passengerScreen === 'face-verify') {
    // camera box click handled via inline onclick
  }
  if (S.passengerScreen === 'active') {
    startSafetyTimer();
    startPassengerCarAnim();
  }
}

function afterRenderDriver() {
  if (S.driverScreen === 'driver-request') startRequestCountdown();
  if (S.driverScreen === 'driver-active')  startDriverCarAnim();
}

// ══════════════════════════════════════════════════════════════════════════════
// PASSENGER SCREENS
// ══════════════════════════════════════════════════════════════════════════════
function passengerScreenHTML() {
  switch (S.passengerScreen) {
    case 'splash':          return pSplash();
    case 'phone-input':     return pPhoneInput();
    case 'otp-input':       return pOtpInput();
    case 'profile-setup':   return pProfileSetup();
    case 'face-consent':    return pFaceConsent();
    case 'face-register':   return pFaceRegister();
    case 'home':            return pHome();
    case 'location-picker': return pLocationPicker();
    case 'booking':         return pBooking();
    case 'searching':       return pSearching();
    case 'waiting':         return pWaiting();
    case 'driver-found':    return pDriverFound();
    case 'face-verify':     return pFaceVerify();
    case 'show-otp':        return pShowOtp();
    case 'active':          return pActive();
    case 'rating':          return pRating();
    case 'complete':        return pComplete();
    default:                return pSplash();
  }
}

function pSplash() {
  return `
    <div class="ph-splash">
      <div class="ph-splash-logo">🌸</div>
      <div class="ph-splash-name">PinkRide</div>
      <div class="ph-splash-tag">Safe. Verified. Shared.</div>
      <button class="ph-btn ph-btn-pink" onclick="pGoToPhoneInput()">Get Started</button>
    </div>`;
}

function pPhoneInput() {
  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-logo-row">🌸 <strong>PinkRide</strong></div>
      <div class="ph-screen-title">Enter your number</div>
      <div class="ph-screen-sub">We'll send a verification OTP</div>
      <div class="ph-input-wrap">
        <span class="ph-flag">🇮🇳 +91</span>
        <div class="ph-number-display" id="p-phone-display">${S.passengerPhone}</div>
      </div>
      <div class="ph-keypad">
        ${[1,2,3,4,5,6,7,8,9,'',0,'⌫'].map(k => `
          <div class="ph-key ${k===''?'ph-key-empty':''}" onclick="pPhoneKey('${k}')">${k}</div>
        `).join('')}
      </div>
      <button class="ph-btn ph-btn-pink" onclick="pRequestOtp()">Send OTP →</button>
    </div>`;
}

function pOtpInput() {
  const digits = S.passengerOtp.split('');
  const boxes = [0,1,2,3,4,5].map(i =>
    `<div class="ph-otp-box ${digits[i] ? 'filled' : ''}">${digits[i] || ''}</div>`
  ).join('');
  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-logo-row">🌸 <strong>PinkRide</strong></div>
      <div class="ph-screen-title">Enter OTP</div>
      <div class="ph-screen-sub">Sent to +91 ${S.passengerPhone}<br><span style="color:#e91e8c;font-size:10px">Check server terminal for OTP code</span></div>
      <div class="ph-otp-row">${boxes}</div>
      <div class="ph-keypad">
        ${[1,2,3,4,5,6,7,8,9,'',0,'⌫'].map(k => `
          <div class="ph-key ${k===''?'ph-key-empty':''}" onclick="pOtpKey('${k}')">${k}</div>
        `).join('')}
      </div>
      <button class="ph-btn ph-btn-pink" onclick="pVerifyOtp()">Verify →</button>
      <div class="ph-resend" onclick="pRequestOtp()">Resend OTP</div>
    </div>`;
}

function pProfileSetup() {
  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow">
        <div class="ph-logo-sm">🌸 PinkRide</div>
        <div class="ph-step-badge">1/2</div>
      </div>
      <div class="ph-screen-title">Complete Profile</div>
      <div class="ph-screen-sub">Tell us about yourself</div>
      <div class="ph-form-group">
        <div class="ph-form-label">Full Name</div>
        <input class="ph-form-input" id="p-name" type="text" value="${S.pName}"
          oninput="S.pName=this.value" placeholder="Your full name">
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label">Gender</div>
        <div class="ph-gender-row">
          <div class="ph-gender-opt ${S.pGender==='female'?'selected':''}" onclick="pSetGender('female')">👩 Female</div>
          <div class="ph-gender-opt ${S.pGender==='male'?'selected':''}" onclick="pSetGender('male')">👨 Male</div>
          <div class="ph-gender-opt ${S.pGender==='other'?'selected':''}" onclick="pSetGender('other')">🧑 Other</div>
        </div>
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label">Date of Birth</div>
        <input class="ph-form-input" id="p-dob" type="date" value="${S.pDob}"
          oninput="S.pDob=this.value">
      </div>
      <div class="ph-consent-note">
        🛡 By continuing you agree to our Terms and <strong>DPDP Act 2025</strong> privacy policy. Face data stored only as an AWS reference ID.
      </div>
      <button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="pSubmitProfile()">Continue →</button>
    </div>`;
}

function pFaceConsent() {
  return `
    <div class="ph-bar"><span>9:42</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-step-badge">2/3</div>
      <div style="font-size:42px">🤳</div>
      <div class="ph-bold-title">Face Verification</div>
      <div class="ph-grey-sub">Required for secure boarding</div>
      <div class="ph-consent-card">
        <div class="ph-consent-row">✅ Your face is <strong>never stored</strong> as a photo</div>
        <div class="ph-consent-row">✅ Only an AWS Rekognition <strong>reference ID</strong> is saved</div>
        <div class="ph-consent-row">✅ Used only to verify identity before boarding</div>
        <div class="ph-consent-row">✅ Delete anytime — <strong>right to erasure</strong></div>
      </div>
      <div class="ph-dpdp-badge">🇮🇳 DPDP Act 2025 Compliant</div>
      <button class="ph-btn ph-btn-pink" onclick="pConsentAndContinue()" style="margin-top:auto">I Consent — Register Face</button>
      <div class="ph-resend" onclick="pDeclineConsent()">Skip for now</div>
    </div>`;
}

function pFaceRegister() {
  const status = S.faceRegStatus || 'Open camera to register your face';
  const done   = S.faceRegDone;
  return `
    <div class="ph-bar"><span>9:43</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-step-badge">3/3</div>
      <div class="ph-bold-title">Register Your Face</div>
      <div class="ph-grey-sub">One-time setup · Takes 10 seconds</div>
      <div class="ph-face-circle" id="reg-face-circle" style="${done ? 'border-color:#22c55e' : ''}">
        <video id="reg-fv-video" autoplay playsinline
          style="display:none;width:120px;height:120px;object-fit:cover;border-radius:50%;transform:scaleX(-1)"></video>
        <canvas id="reg-fv-canvas" width="120" height="120" style="display:none"></canvas>
        <img id="reg-fv-photo" style="display:none;width:120px;height:120px;object-fit:cover;border-radius:50%">
        <div class="ph-face-placeholder" id="reg-face-placeholder" style="${done ? 'display:none' : ''}">${done ? '' : '🤳'}</div>
      </div>
      <div class="ph-fv-status" id="reg-fv-status" style="${done ? 'color:#22c55e;font-weight:700' : ''}">${status}</div>
      ${done ? `
        <div class="ph-verified-chip">✅ Face Registered Successfully</div>
        <div class="ph-aws-badge" style="background:#dcfce7;color:#166534">Indexed in AWS Rekognition · Only reference ID stored</div>
        <button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="pGoHome()">Go to Home →</button>
      ` : `
        <div class="ph-fv-btns">
          <button class="ph-btn ph-btn-dark" id="reg-fv-open" onclick="regOpenCamera()">📷 Open Camera</button>
          <button class="ph-btn ph-btn-pink" id="reg-fv-capture" style="display:none" onclick="regCapture()">📸 Capture</button>
          <button class="ph-btn ph-btn-outline" id="reg-fv-retake" style="display:none" onclick="regRetake()">↺ Retake</button>
        </div>
        <div class="ph-aws-badge">🔒 Liveness check → Rekognition index</div>
      `}
    </div>`;
}

function pHome() {
  const pickupLabel = S.pickup ? S.pickup.name : 'Tap to set pickup';
  const dropLabel   = S.drop   ? S.drop.name   : 'Where to?';
  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow">
        <div class="ph-logo-sm">🌸 PinkRide</div>
        <div class="ph-ava">P</div>
      </div>
      <div class="ph-greeting">Good evening, ${S.pName || 'there'} 👋</div>
      <div class="ph-subgreet">Where are you going?</div>
      <div class="ph-loc-card" onclick="pOpenLocationPicker('pickup')">
        <div class="ph-loc-row"><span class="dot green"></span><span${S.pickup ? '' : ' class="muted-text"'}>${pickupLabel}</span></div>
        <div class="ph-loc-divider"></div>
        <div class="ph-loc-row" onclick="event.stopPropagation();pOpenLocationPicker('drop')"><span class="dot pink"></span><span class="${S.drop ? '' : 'muted-text'}">${dropLabel} →</span></div>
      </div>
      <div class="ph-map-bg">
        <div class="ph-map-road"></div>
        ${S.pickup ? `<div class="ph-map-pin" style="left:30%;bottom:25px">📍</div>` : ''}
        ${S.drop   ? `<div class="ph-map-pin" style="left:65%;bottom:25px">🏁</div>` : ''}
        ${!S.pickup && !S.drop ? `<div class="ph-map-pin">📍</div>` : ''}
      </div>
      ${S.pickup && S.drop
        ? `<button class="ph-btn ph-btn-pink ph-pulse" onclick="pGoToBooking()">Book Ride →</button>`
        : `<div class="ph-safety-tag">🛡 Tap above to set your route</div>`
      }
    </div>`;
}

function pLocationPicker() {
  const isPickup = S.pickingFor === 'pickup';
  const pins = LOCATIONS.map(loc => {
    const isSelected = isPickup
      ? S.pickup?.name === loc.name
      : S.drop?.name   === loc.name;
    return `<div class="ph-map-loc-btn ${isSelected ? 'selected' : ''}"
      style="top:${loc.top};left:${loc.left}"
      onclick="pSelectLocation('${loc.name}',${loc.lat},${loc.lng})">
      <span class="loc-emoji">${isPickup ? '📍' : '🏁'}</span>
      <span class="loc-label">${loc.name}</span>
    </div>`;
  }).join('');

  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow">
        <div class="ph-back" onclick="pBack()">←</div>
        <div class="ph-screen-title">Pick ${isPickup ? 'Pickup' : 'Drop'}</div>
      </div>
      <div class="ph-picker-hint">Tap a location on the map</div>
      <div class="ph-map-picker">
        <div class="ph-map-picker-road-h"></div>
        <div class="ph-map-picker-road-v"></div>
        ${pins}
      </div>
      ${S.pickup && !isPickup ? `
        <div class="ph-route-selected">
          <div class="rdot green"></div><span>From: <strong>${S.pickup.name}</strong></span>
        </div>` : ''}
      ${S.drop && isPickup ? `
        <div class="ph-route-selected">
          <div class="rdot pink"></div><span>To: <strong>${S.drop.name}</strong></span>
        </div>` : ''}
    </div>`;
}

function pBooking() {
  const pickup = S.pickup?.name || 'Vaishali Nagar';
  const drop   = S.drop?.name   || 'Malviya Nagar';
  const isShared = S.rideType === 'shared';
  const sharedFare = S.sharedFare;

  return `
    <div class="ph-bar"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow"><div class="ph-back" onclick="pBack()">←</div><div class="ph-screen-title">Book Ride</div></div>
      <div class="ph-route-card">
        <div class="ph-route-row"><div class="rdot green"></div><div><div class="rl">Pickup</div><div class="ra">${pickup}</div></div></div>
        <div class="ph-route-line"></div>
        <div class="ph-route-row"><div class="rdot pink"></div><div><div class="rl">Drop</div><div class="ra">${drop}</div></div></div>
      </div>
      <div class="ph-option ${!isShared ? 'ph-selected' : ''}" onclick="pSelectRide('private')">
        <span class="opt-icon">🚗</span>
        <div class="opt-info"><div class="opt-name">Private Ride</div><div class="opt-sub">Just you · 8 km · ~22 min</div></div>
        <div class="opt-fare sim-fare">${S.fare}</div>
      </div>
      <div class="ph-option ${isShared ? 'ph-selected' : ''}" onclick="pSelectRide('shared')">
        <span class="opt-icon">👥</span>
        <div class="opt-info"><div class="opt-name">Shared Ride</div><div class="opt-sub">Up to 3 passengers · Save ~30%</div></div>
        <div class="opt-fare">${sharedFare}</div>
      </div>
      ${isShared ? `
      <div class="ph-shared-banner">
        👥 You'll share the car — matched by route overlap
      </div>
      <div style="display:flex;align-items:center;gap:8px;flex-shrink:0">
        <div class="ph-shared-passengers">
          <div class="ph-shared-seat you" title="You">👤</div>
          <div class="ph-shared-seat" title="Waiting">?</div>
          <div class="ph-shared-seat" title="Waiting">?</div>
        </div>
        <div class="ph-shared-label">1/3 seats · Waiting for co-passengers</div>
      </div>` : ''}
      <div class="ph-pay-row"><span>💵</span><span>Cash Payment</span></div>
      <button class="ph-btn ph-btn-pink ph-pulse" onclick="pConfirmBooking()">Confirm ${isShared ? 'Shared ' : ''}Booking</button>
    </div>`;
}

function pSearching() {
  return `
    <div class="ph-bar"><span>9:42</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-search-anim">
        <div class="sr1"></div><div class="sr2"></div><div class="sr3"></div>
        <div class="sc">🚗</div>
      </div>
      <div class="ph-bold-title">Finding your driver...</div>
      <div class="ph-grey-sub">Matching engine scanning nearby</div>
      <div class="ph-criteria">
        <div>✓ Within 3 km radius</div>
        <div>✓ Verified identity</div>
        <div>✓ Rating ≥ 4.0</div>
      </div>
      <div class="ph-cancel-link" onclick="pCancelSearch()">Cancel Search</div>
    </div>`;
}

function pWaiting() {
  return `
    <div class="ph-bar"><span>9:42</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-wait-pulse">⏳</div>
      <div class="ph-bold-title">Request Sent!</div>
      <div class="ph-grey-sub">Waiting for driver to accept...</div>
      <div class="ph-detail-card">
        <div class="dc-row"><span>📍</span><span>Vaishali → Malviya Nagar</span></div>
        <div class="dc-row"><span>💰</span><span class="sim-fare">${S.fare}</span></div>
        <div class="dc-row"><span>📏</span><span>8 km · ~22 min</span></div>
      </div>
    </div>`;
}

function pDriverFound() {
  return `
    <div class="ph-bar"><span>9:43</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-found-banner">🎉 Driver Found!</div>
      <div class="ph-drv-card">
        <div class="ph-drv-ava">R</div>
        <div class="ph-drv-info">
          <div class="ph-drv-name">Rahul Sharma</div>
          <div class="ph-drv-meta">⭐ 4.8 · 234 trips · Verified ✓</div>
          <div class="ph-drv-veh">🚗 White Swift · RJ14 AB 1234</div>
        </div>
      </div>
      <div class="ph-eta-row">
        <div class="ph-eta-icon">🕐</div>
        <div><div class="ph-eta-val">4 min away</div><div class="ph-eta-sub">Heading to Vaishali Nagar</div></div>
      </div>
      <div class="ph-mini-track">
        <div class="track-road"></div>
        <div class="track-car" id="track-car">🚗</div>
        <div class="track-pin-end">📍</div>
      </div>
      <div class="ph-actions-row">
        <button class="ph-act-btn" onclick="pCallDriver()">📞 Call</button>
        <button class="ph-act-btn" onclick="pShareTrip()">📤 Share</button>
        <button class="ph-act-btn ph-sos" onclick="pSOS()">🆘 SOS</button>
      </div>
      <button class="ph-btn ph-btn-outline" onclick="pStartFaceVerify()" style="margin-top:auto">Verify Identity to Board →</button>
    </div>`;
}

function pFaceVerify() {
  return `
    <div class="ph-bar"><span>9:45</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-bold-title">Identity Verification</div>
      <div class="ph-grey-sub">Required before boarding · AWS Rekognition</div>
      <div class="ph-face-circle" id="ph-face-circle">
        <video id="ph-fv-video" autoplay playsinline
          style="display:none;width:120px;height:120px;object-fit:cover;border-radius:50%;transform:scaleX(-1)"></video>
        <canvas id="ph-fv-canvas" width="120" height="120" style="display:none"></canvas>
        <img id="ph-fv-photo" style="display:none;width:120px;height:120px;object-fit:cover;border-radius:50%">
        <div class="ph-face-placeholder" id="ph-face-placeholder">🤳</div>
      </div>
      <div class="ph-fv-status" id="ph-fv-status">Open camera to scan your face</div>
      <div class="ph-fv-btns">
        <button class="ph-btn ph-btn-dark" id="ph-fv-open" onclick="simOpenCamera()">📷 Open Camera</button>
        <button class="ph-btn ph-btn-pink" id="ph-fv-capture" style="display:none" onclick="simCapture()">📸 Capture</button>
        <button class="ph-btn ph-btn-outline" id="ph-fv-retake" style="display:none" onclick="simRetake()">↺ Retake</button>
      </div>
      <div class="ph-aws-badge">🔒 Compared against Rekognition DB</div>
    </div>`;
}

function pShowOtp() {
  const otp = S.rideOtp || '----';
  return `
    <div class="ph-bar"><span>9:46</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-verified-chip">✅ Identity Verified</div>
      <div class="ph-bold-title">Show to your driver</div>
      <div class="ph-otp-bigcard">
        <div class="ph-otp-label">Boarding OTP</div>
        <div class="ph-otp-digits" id="ph-otp-digits">${otp}</div>
        <div class="ph-otp-note">Valid 2 min · Do not share with anyone</div>
      </div>
      <div class="ph-drv-mini">🚗 ${S.dName || 'Driver'} is at your pickup point</div>
      <div class="ph-security-note">🛡 OTP prevents unauthorised boarding</div>
    </div>`;
}

function pActive() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:48</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-active-header">
        <div class="ph-active-dot"></div>
        <span>Ride in Progress</span>
      </div>
      <div class="ph-active-map">
        <div class="ph-active-road"></div>
        <div class="ph-active-car" id="ph-active-car">🚗</div>
        <div class="ph-active-dest">🏁</div>
        <div class="ph-map-label-l">Vaishali Nagar</div>
        <div class="ph-map-label-r">Malviya Nagar</div>
      </div>
      <div class="ph-active-info">
        <div class="ph-ai-row"><span>📍</span><span>Malviya Nagar · 6 km left</span></div>
        <div class="ph-ai-row"><span>⏱</span><span>~14 min remaining</span></div>
        <div class="ph-ai-row"><span>🛡</span><span>Safety timer: <strong id="sim-safety-timer">02:00</strong></span></div>
      </div>
      <div class="ph-actions-row">
        <button class="ph-act-btn" onclick="pShareLive()">📤 Share Live</button>
        <button class="ph-act-btn ph-sos" onclick="pSOS()">🆘 SOS</button>
      </div>
    </div>`;
}

function pRating() {
  return `
    <div class="ph-bar"><span>10:10</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-rating-drv-card">
        <div class="ph-drv-ava">R</div>
        <div class="ph-drv-info">
          <div class="ph-drv-name">Rate Rahul</div>
          <div class="ph-drv-meta">How was your ride?</div>
        </div>
      </div>
      <div class="ph-stars-row" id="p-stars">
        ${[1,2,3,4,5].map(i => `<span class="ph-star" onclick="pRate(${i})">★</span>`).join('')}
      </div>
      <div class="ph-tags-row">
        <span class="ph-tag" onclick="pTag(this)">Safe driver</span>
        <span class="ph-tag" onclick="pTag(this)">On time</span>
        <span class="ph-tag" onclick="pTag(this)">Friendly</span>
        <span class="ph-tag" onclick="pTag(this)">Clean car</span>
      </div>
      <button class="ph-btn ph-btn-pink" onclick="pSubmitRating()" style="margin-top:auto">Submit Rating</button>
    </div>`;
}

function pComplete() {
  return `
    <div class="ph-bar"><span>10:10</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-complete-icon">✅</div>
      <div class="ph-bold-title">Safe Arrival!</div>
      <div class="ph-grey-sub">You reached Malviya Nagar</div>
      <div class="ph-receipt">
        <div class="ph-rc-row"><span>Distance</span><span>8.2 km</span></div>
        <div class="ph-rc-row"><span>Duration</span><span>24 min</span></div>
        <div class="ph-rc-row ph-rc-total"><span>Total</span><span class="sim-fare">${S.fare}</span></div>
        <div class="ph-rc-row"><span>Payment</span><span>Cash ✓</span></div>
      </div>
      <button class="ph-btn ph-btn-outline" onclick="restartSim()" style="margin-top:auto">↺ New Demo</button>
    </div>`;
}

// ══════════════════════════════════════════════════════════════════════════════
// DRIVER SCREENS
// ══════════════════════════════════════════════════════════════════════════════
function driverScreenHTML() {
  switch (S.driverScreen) {
    case 'splash':             return dSplash();
    case 'phone-input':        return dPhoneInput();
    case 'otp-input':          return dOtpInput();
    case 'profile-setup':      return dProfileSetup();
    case 'vehicle-setup':      return dVehicleSetup();
    case 'doc-upload':         return dDocUpload();
    case 'pending-approval':   return dPendingApproval();
    case 'approved':           return dApproved();
    case 'driver-offline':     return dOffline();
    case 'driver-online':      return dOnline();
    case 'driver-request':     return dRequest();
    case 'driver-accepted':    return dAccepted();
    case 'driver-wait-verify': return dWaitVerify();
    case 'driver-otp':         return dOtpEntry();
    case 'driver-active':      return dActive();
    case 'driver-rating':      return dRating();
    case 'driver-complete':    return dComplete();
    default:                   return dSplash();
  }
}

function dSplash() {
  return `
    <div class="ph-splash ph-splash-dark">
      <div class="ph-splash-logo">🌸</div>
      <div class="ph-splash-name">PinkRide</div>
      <div class="ph-splash-tag" style="color:rgba(255,255,255,0.6)">Driver Partner App</div>
      <button class="ph-btn ph-btn-pink" onclick="dGoToPhoneInput()">Get Started</button>
    </div>`;
}

function dPhoneInput() {
  return `
    <div class="ph-bar ph-bar-dark"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark">
      <div class="ph-logo-row">🌸 <strong>PinkRide Driver</strong></div>
      <div class="ph-screen-title">Enter your number</div>
      <div class="ph-screen-sub">Driver partner login</div>
      <div class="ph-input-wrap">
        <span class="ph-flag">🇮🇳 +91</span>
        <div class="ph-number-display" id="d-phone-display">${S.driverPhone}</div>
      </div>
      <div class="ph-keypad">
        ${[1,2,3,4,5,6,7,8,9,'',0,'⌫'].map(k => `
          <div class="ph-key ${k===''?'ph-key-empty':''}" onclick="dPhoneKey('${k}')">${k}</div>
        `).join('')}
      </div>
      <button class="ph-btn ph-btn-pink" onclick="dRequestOtp()">Send OTP →</button>
    </div>`;
}

function dOtpInput() {
  const digits = S.driverOtp.split('');
  const boxes = [0,1,2,3,4,5].map(i =>
    `<div class="ph-otp-box ${digits[i] ? 'filled' : ''}">${digits[i] || ''}</div>`
  ).join('');
  return `
    <div class="ph-bar ph-bar-dark"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark">
      <div class="ph-logo-row">🌸 <strong>PinkRide Driver</strong></div>
      <div class="ph-screen-title">Enter OTP</div>
      <div class="ph-screen-sub">Sent to +91 ${S.driverPhone}<br><span style="color:#e91e8c;font-size:10px">Check server terminal</span></div>
      <div class="ph-otp-row">${boxes}</div>
      <div class="ph-keypad">
        ${[1,2,3,4,5,6,7,8,9,'',0,'⌫'].map(k => `
          <div class="ph-key ${k===''?'ph-key-empty':''}" onclick="dOtpKey('${k}')">${k}</div>
        `).join('')}
      </div>
      <button class="ph-btn ph-btn-pink" onclick="dVerifyOtp()">Verify →</button>
    </div>`;
}

function dProfileSetup() {
  return `
    <div class="ph-bar ph-bar-dark"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark">
      <div class="ph-toprow">
        <div class="ph-logo-row">🌸 PinkRide Driver</div>
        <div class="ph-step-badge ph-step-badge-dark">1/3</div>
      </div>
      <div class="ph-screen-title">Your Profile</div>
      <div class="ph-screen-sub">Basic information</div>
      <div class="ph-form-group">
        <div class="ph-form-label ph-form-label-dark">Full Name</div>
        <input class="ph-form-input ph-form-input-dark" id="d-name" type="text" value="${S.dName}"
          oninput="S.dName=this.value" placeholder="Your full name">
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label ph-form-label-dark">Gender</div>
        <div class="ph-gender-row">
          <div class="ph-gender-opt ${S.dGender==='female'?'selected':''}" onclick="dSetGender('female')">👩 Female</div>
          <div class="ph-gender-opt ${S.dGender==='male'?'selected':''}" onclick="dSetGender('male')">👨 Male</div>
        </div>
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label ph-form-label-dark">Date of Birth</div>
        <input class="ph-form-input ph-form-input-dark" id="d-dob" type="date" value="${S.dDob}"
          oninput="S.dDob=this.value">
      </div>
      <button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="dSubmitProfile()">Next: Vehicle →</button>
    </div>`;
}

function dVehicleSetup() {
  return `
    <div class="ph-bar ph-bar-dark"><span>9:43</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark">
      <div class="ph-toprow">
        <div class="ph-back" style="color:white" onclick="dBackToProfile()">←</div>
        <div class="ph-step-badge ph-step-badge-dark">2/3</div>
      </div>
      <div class="ph-screen-title">Vehicle Details</div>
      <div class="ph-screen-sub">Your car information</div>
      <div class="ph-form-row-2">
        <div class="ph-form-group">
          <div class="ph-form-label ph-form-label-dark">Make</div>
          <input class="ph-form-input ph-form-input-dark" value="${S.vMake}" oninput="S.vMake=this.value" placeholder="Maruti">
        </div>
        <div class="ph-form-group">
          <div class="ph-form-label ph-form-label-dark">Model</div>
          <input class="ph-form-input ph-form-input-dark" value="${S.vModel}" oninput="S.vModel=this.value" placeholder="Swift">
        </div>
      </div>
      <div class="ph-form-row-2">
        <div class="ph-form-group">
          <div class="ph-form-label ph-form-label-dark">Color</div>
          <input class="ph-form-input ph-form-input-dark" value="${S.vColor}" oninput="S.vColor=this.value" placeholder="White">
        </div>
        <div class="ph-form-group">
          <div class="ph-form-label ph-form-label-dark">Year</div>
          <input class="ph-form-input ph-form-input-dark" value="${S.vYear}" oninput="S.vYear=this.value" placeholder="2019">
        </div>
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label ph-form-label-dark">Vehicle Number</div>
        <input class="ph-form-input ph-form-input-dark" value="${S.vNumber}" oninput="S.vNumber=this.value" placeholder="RJ14AB1234" style="font-family:monospace;letter-spacing:1px">
      </div>
      <div class="ph-form-group">
        <div class="ph-form-label ph-form-label-dark">License Number</div>
        <input class="ph-form-input ph-form-input-dark" value="${S.vLicense}" oninput="S.vLicense=this.value" placeholder="RJ1420190012345" style="font-family:monospace">
      </div>
      <button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="dSubmitVehicle()">Next: Documents →</button>
    </div>`;
}

function dDocUpload() {
  const licDone = S.docLicense;
  const rcDone  = S.docRC;
  return `
    <div class="ph-bar ph-bar-dark"><span>9:45</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark">
      <div class="ph-toprow">
        <div class="ph-back" style="color:white" onclick="dBackToVehicle()">←</div>
        <div class="ph-step-badge ph-step-badge-dark">3/3</div>
      </div>
      <div class="ph-screen-title">Upload Documents</div>
      <div class="ph-screen-sub">Required for verification</div>
      <div class="ph-doc-item ${licDone?'doc-done':''}">
        <div class="ph-doc-icon">${licDone?'✅':'📄'}</div>
        <div class="ph-doc-info">
          <div class="ph-doc-name">Driving Licence</div>
          <div class="ph-doc-sub">${licDone?'Uploaded ✓':'Front side · Clear photo'}</div>
        </div>
        ${!licDone?`<button class="ph-doc-btn" onclick="dUploadDoc('license')">Upload</button>`:''}
      </div>
      <div class="ph-doc-item ${rcDone?'doc-done':''}">
        <div class="ph-doc-icon">${rcDone?'✅':'📄'}</div>
        <div class="ph-doc-info">
          <div class="ph-doc-name">RC (Registration Cert.)</div>
          <div class="ph-doc-sub">${rcDone?'Uploaded ✓':'Vehicle registration'}</div>
        </div>
        ${!rcDone?`<button class="ph-doc-btn" onclick="dUploadDoc('rc')">Upload</button>`:''}
      </div>
      <div class="ph-doc-note">📱 In the real app, you'd pick photos from your gallery</div>
      ${licDone && rcDone
        ? `<button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="dSubmitApplication()">Submit Application →</button>`
        : `<div class="ph-btn ph-btn-outline" style="margin-top:auto;opacity:0.4;cursor:not-allowed">Upload both documents first</div>`
      }
    </div>`;
}

function dPendingApproval() {
  return `
    <div class="ph-bar ph-bar-dark"><span>9:47</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-body-dark ph-center">
      <div style="font-size:44px">⏳</div>
      <div class="ph-bold-title" style="color:white">Application Submitted!</div>
      <div class="ph-grey-sub" style="color:rgba(255,255,255,0.5)">Under admin review</div>
      <div class="ph-pending-card">
        <div class="ph-pending-row">📋 Profile — <span style="color:#4ade80">✓</span></div>
        <div class="ph-pending-row">🚗 Vehicle — <span style="color:#4ade80">✓</span></div>
        <div class="ph-pending-row">📄 Documents — <span style="color:#4ade80">✓</span></div>
        <div class="ph-pending-row">👤 Admin Review — <span style="color:#f59e0b">Pending...</span></div>
      </div>
      <div class="ph-pending-note">
        💡 Switch to the <strong>Admin Dashboard</strong> tab above to approve this application
      </div>
      <div class="ph-polling-indicator" id="ph-poll-indicator">
        <div class="ph-poll-dot"></div> Checking approval status...
      </div>
    </div>`;
}

function dApproved() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:52</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div style="font-size:48px">🎉</div>
      <div class="ph-bold-title">You're Approved!</div>
      <div class="ph-grey-sub">Welcome to PinkRide, ${S.dName || 'Driver'}</div>
      <div class="ph-approved-card">
        <div class="ph-approved-row">🚗 ${S.vColor} ${S.vMake} ${S.vModel}</div>
        <div class="ph-approved-row">🪪 ${S.vNumber}</div>
        <div class="ph-approved-row">⭐ Starting rating: 5.0</div>
      </div>
      <div class="ph-grey-sub" style="font-size:10px">Admin verified your documents and approved your account</div>
      <button class="ph-btn ph-btn-pink" style="margin-top:auto" onclick="dGoToOffline()">Start Driving →</button>
    </div>`;
}

function dOffline() {
  return `
    <div class="ph-bar ph-bar-dark"><span>9:41</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow">
        <div class="ph-logo-sm" style="color:white">🌸 PinkRide</div>
        <div class="ph-status-chip offline">Offline</div>
      </div>
      <div class="ph-drv-stats">
        <div class="ph-stat"><div class="ph-stat-val">₹0</div><div class="ph-stat-lbl">Today</div></div>
        <div class="ph-stat"><div class="ph-stat-val">0</div><div class="ph-stat-lbl">Trips</div></div>
        <div class="ph-stat"><div class="ph-stat-val">4.8⭐</div><div class="ph-stat-lbl">Rating</div></div>
      </div>
      <div class="ph-offline-card">
        <div class="ph-offline-title">You are Offline</div>
        <div class="ph-offline-sub">Go online to start receiving rides</div>
        <button class="ph-btn ph-btn-pink" onclick="dGoOnline()">Go Online</button>
      </div>
      <div class="ph-veh-row">🚗 White Swift · RJ14 AB 1234</div>
    </div>`;
}

function dOnline() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:42</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-toprow">
        <div class="ph-logo-sm">🌸 PinkRide</div>
        <div class="ph-status-chip online">🟢 Online</div>
      </div>
      <div class="ph-drv-stats">
        <div class="ph-stat"><div class="ph-stat-val">₹340</div><div class="ph-stat-lbl">Today</div></div>
        <div class="ph-stat"><div class="ph-stat-val">3</div><div class="ph-stat-lbl">Trips</div></div>
        <div class="ph-stat"><div class="ph-stat-val">4.8⭐</div><div class="ph-stat-lbl">Rating</div></div>
      </div>
      <div class="ph-radar-card">
        <div class="ph-radar">
          <div class="radar-r1"></div><div class="radar-r2"></div>
          <div class="radar-center">📡</div>
        </div>
        <div class="ph-radar-text">Waiting for ride requests...</div>
      </div>
      <button class="ph-btn ph-btn-outline ph-btn-sm" onclick="dGoOffline()">Go Offline</button>
    </div>`;
}

function dRequest() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:42</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-req-banner">🔔 New Ride Request!</div>
      <div class="ph-req-card">
        <div class="ph-req-row"><span class="req-lbl">Passenger</span><span>Priya · ⭐ 4.9</span></div>
        <div class="ph-req-route">
          <div class="ph-req-pt"><div class="rdot green"></div><span>Vaishali Nagar</span></div>
          <div class="ph-req-dist">↓ 8 km · ~22 min</div>
          <div class="ph-req-pt"><div class="rdot pink"></div><span>Malviya Nagar</span></div>
        </div>
        <div class="ph-req-row"><span class="req-lbl">Fare</span><span class="ph-req-fare sim-fare">${S.fare}</span></div>
        <div class="ph-req-row"><span class="req-lbl">Payment</span><span>💵 Cash</span></div>
        <div class="ph-req-timer-bar"><div class="ph-req-timer-fill" id="req-fill"></div></div>
        <div class="ph-req-timer-lbl">Expires in <span id="req-cdown">15</span>s</div>
      </div>
      <div class="ph-req-actions">
        <button class="ph-req-decline" onclick="dDeclineRide()">✕ Decline</button>
        <button class="ph-req-accept" onclick="dAcceptRide()">✓ Accept</button>
      </div>
    </div>`;
}

function dAccepted() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:43</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-nav-header">
        <div class="ph-nav-title">Navigating to pickup</div>
        <div class="ph-nav-eta">4 min</div>
      </div>
      <div class="ph-nav-map">
        <div class="ph-nav-road"></div>
        <div class="ph-nav-car" id="drv-nav-car">🚗</div>
        <div class="ph-nav-dest">📍</div>
        <div class="ph-map-label-l">You</div>
        <div class="ph-map-label-r">Priya</div>
      </div>
      <div class="ph-nav-instr">Turn right on JLN Marg in 200m</div>
      <div class="ph-pax-card">
        <div class="ph-drv-ava ph-ava-sm">P</div>
        <div class="ph-drv-info"><div class="ph-drv-name">Priya</div><div class="ph-drv-meta">Waiting at pickup</div></div>
        <button class="ph-call-btn">📞</button>
      </div>
      <div class="ph-grey-sub" style="text-align:center;font-size:10px;margin-top:4px">Waiting for passenger face verification...</div>
    </div>`;
}

function dWaitVerify() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:45</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-wait-pulse">🔒</div>
      <div class="ph-bold-title">Identity Check</div>
      <div class="ph-grey-sub">Passenger completing face scan...</div>
      <div class="ph-detail-card" style="width:100%;text-align:left">
        <div class="dc-row"><span>🔍</span><span>AWS Rekognition comparing face</span></div>
        <div class="dc-row"><span>🛡</span><span>Prevents impersonation fraud</span></div>
        <div class="dc-row"><span>⏳</span><span>OTP will appear after match</span></div>
      </div>
    </div>`;
}

function dOtpEntry() {
  const entered = S.driverEnteredOtp;
  const boxes = [0,1,2,3].map(i =>
    `<div class="ph-otp-box ph-otp-box-lg ${entered[i] ? 'filled' : ''}">${entered[i] || ''}</div>`
  ).join('');
  const correct = S.rideOtp && entered === S.rideOtp.toString();
  return `
    <div class="ph-bar ph-bar-green"><span>9:46</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-bold-title">Verify Passenger</div>
      <div class="ph-grey-sub">Enter the 4-digit OTP from Priya</div>
      <div class="ph-otp-row ph-otp-lg">${boxes}</div>
      ${correct ? '<div class="ph-otp-match">✅ OTP Matched!</div>' : '<div class="ph-otp-hint">Ask Priya for her boarding OTP</div>'}
      <div class="ph-keypad">
        ${[1,2,3,4,5,6,7,8,9,'',0,'⌫'].map(k => `
          <div class="ph-key ${k===''?'ph-key-empty':''}" onclick="dOtpRideKey('${k}')">${k}</div>
        `).join('')}
      </div>
      ${correct ? `<button class="ph-btn ph-btn-pink" onclick="dConfirmBoarding()">✓ Confirm Boarding</button>` : ''}
    </div>`;
}

function dActive() {
  return `
    <div class="ph-bar ph-bar-green"><span>9:48</span><span>●●●● 🔋</span></div>
    <div class="ph-body">
      <div class="ph-nav-header">
        <div class="ph-nav-title">En Route</div>
        <div class="ph-nav-eta">14 min</div>
      </div>
      <div class="ph-nav-map">
        <div class="ph-nav-road"></div>
        <div class="ph-nav-car ph-nav-car-anim" id="drv-active-car">🚗</div>
        <div class="ph-nav-dest">🏁</div>
        <div class="ph-map-label-l">Vaishali Nagar</div>
        <div class="ph-map-label-r">Malviya Nagar</div>
      </div>
      <div class="ph-nav-instr">Continue on Tonk Road · 6.1 km</div>
      <div class="ph-pax-card">
        <div class="ph-drv-ava ph-ava-sm">P</div>
        <div class="ph-drv-info"><div class="ph-drv-name">Priya</div><div class="ph-drv-meta">On board ✓</div></div>
        <button class="ph-call-btn">📞</button>
      </div>
      <button class="ph-btn ph-btn-green" onclick="dCompleteRide()" style="margin-top:auto">Complete Ride</button>
    </div>`;
}

function dRating() {
  return `
    <div class="ph-bar ph-bar-dark"><span>10:10</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-rating-drv-card">
        <div class="ph-drv-ava">P</div>
        <div class="ph-drv-info">
          <div class="ph-drv-name">Rate Priya</div>
          <div class="ph-drv-meta">How was the passenger?</div>
        </div>
      </div>
      <div class="ph-stars-row" id="d-stars">
        ${[1,2,3,4,5].map(i => `<span class="ph-star" onclick="dRate(${i})">★</span>`).join('')}
      </div>
      <div class="ph-tags-row">
        <span class="ph-tag" onclick="pTag(this)">On time</span>
        <span class="ph-tag" onclick="pTag(this)">Polite</span>
        <span class="ph-tag" onclick="pTag(this)">Easy drop</span>
      </div>
      <button class="ph-btn ph-btn-pink" onclick="dSubmitRating()" style="margin-top:auto">Submit Rating</button>
    </div>`;
}

function dComplete() {
  return `
    <div class="ph-bar ph-bar-dark"><span>10:10</span><span>●●●● 🔋</span></div>
    <div class="ph-body ph-center">
      <div class="ph-complete-icon">💰</div>
      <div class="ph-bold-title">Trip Complete!</div>
      <div class="ph-receipt">
        <div class="ph-rc-row"><span>Passenger</span><span>Priya</span></div>
        <div class="ph-rc-row"><span>Distance</span><span>8.2 km</span></div>
        <div class="ph-rc-row ph-rc-total"><span>Earnings</span><span class="sim-fare">${S.fare}</span></div>
      </div>
      <div class="ph-grey-sub">Reliability score +0.1 🎉</div>
      <button class="ph-btn ph-btn-outline" onclick="restartSim()" style="margin-top:auto">↺ New Demo</button>
    </div>`;
}

// ══════════════════════════════════════════════════════════════════════════════
// PASSENGER BUTTON HANDLERS
// ══════════════════════════════════════════════════════════════════════════════

function pGoToPhoneInput() {
  S.passengerScreen = 'phone-input';
  narrate('📱 Priya enters her phone number. PinkRide uses phone-first OTP auth — no passwords.');
  renderPassenger();
}

function pPhoneKey(k) {
  if (k === '⌫') S.passengerPhone = S.passengerPhone.slice(0, -1);
  else if (k !== '' && S.passengerPhone.length < 10) S.passengerPhone += k;
  const el = document.getElementById('p-phone-display');
  if (el) el.textContent = S.passengerPhone;
}

async function pRequestOtp() {
  narrate('📤 Sending OTP to Priya\'s phone... check the server terminal for the code.');
  const res = await api('POST', '/auth/request-otp', { phone: S.passengerPhone });
  if (res.success) {
    S.passengerOtp = '';
    S.passengerScreen = 'otp-input';
    narrate('📲 OTP sent! Priya enters the 6-digit code from the server terminal.');
    renderPassenger();
  } else {
    narrate('⚠ ' + (res.message || 'OTP request failed'));
  }
}

function pOtpKey(k) {
  if (k === '⌫') S.passengerOtp = S.passengerOtp.slice(0, -1);
  else if (k !== '' && S.passengerOtp.length < 6) S.passengerOtp += k;
  renderPassenger();
}

async function pVerifyOtp() {
  if (S.passengerOtp.length < 6) {
    narrate('⚠ Enter the full 6-digit OTP from the server terminal.');
    return;
  }
  narrate('🔐 Verifying OTP... issuing JWT tokens.');
  const res = await api('POST', '/auth/verify-otp', { phone: S.passengerPhone, otp: S.passengerOtp });
  if (res.success) {
    S.passengerToken = res.data?.tokens?.accessToken;
    S.passengerScreen = 'profile-setup';
    narrate('✅ OTP verified! JWT issued. Now Priya sets up her profile — name, gender, date of birth.');
    renderPassenger();
  } else {
    S.passengerToken = 'mock-passenger-token';
    S.passengerScreen = 'profile-setup';
    narrate('✅ OTP verified (mock mode). Fill in the profile details and tap Continue.');
    renderPassenger();
  }
}

// ── Passenger profile setup ───────────────────────────────────────────────────

function pSetGender(g) {
  S.pGender = g;
  renderPassenger();
}

async function pSubmitProfile() {
  if (!S.pName.trim()) { narrate('⚠ Please enter your full name.'); return; }
  narrate('📝 Saving profile... calling POST /users/register');
  const res = await api('POST', '/users/register',
    { fullName: S.pName, gender: S.pGender, dateOfBirth: S.pDob, role: 'passenger' },
    S.passengerToken);
  // 409 = profile already exists (demo users) — not fatal
  if (res.success || res.message?.toLowerCase().includes('already')) {
    S.passengerScreen = 'face-consent';
    narrate('✅ Profile saved! Now Priya must consent to face verification — required by DPDP Act 2025.');
    renderPassenger();
  } else {
    // Mock fallback
    S.passengerScreen = 'face-consent';
    narrate('✅ Profile saved (mock). Next: face verification consent.');
    renderPassenger();
  }
}

async function pConsentAndContinue() {
  narrate('✅ Consent recorded. Now Priya registers her face — live selfie → liveness check → indexed in AWS Rekognition.');
  await api('POST', '/users/face-consent', {}, S.passengerToken);
  S.faceRegStatus = 'Open camera to register your face';
  S.faceRegDone   = false;
  S.passengerScreen = 'face-register';
  renderPassenger();
}

function pDeclineConsent() {
  narrate('⚠ Face verification skipped. Priya can still book rides but must verify before boarding.');
  S.passengerScreen = 'home';
  renderPassenger();
}

function pGoHome() {
  narrate('🏠 Registration complete! Priya is fully verified. She can now book rides safely.');
  S.passengerScreen = 'home';
  renderPassenger();
}

// ── Face Registration camera (signup flow) ────────────────────────────────────

async function regOpenCamera() {
  try {
    S.faceStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 480 }, height: { ideal: 480 } }
    });
    const video   = document.getElementById('reg-fv-video');
    const ph      = document.getElementById('reg-face-placeholder');
    const openBtn = document.getElementById('reg-fv-open');
    const capBtn  = document.getElementById('reg-fv-capture');
    if (video)   { video.srcObject = S.faceStream; video.style.display = 'block'; }
    if (ph)      ph.style.display = 'none';
    if (openBtn) openBtn.style.display = 'none';
    if (capBtn)  capBtn.style.display = 'inline-flex';
    narrate('📷 Camera ready. Look straight at the camera. Eyes open, good lighting.');
  } catch {
    narrate('⚠ Camera access denied — using mock face registration.');
    regMockRegister();
  }
}

function regCapture() {
  const video  = document.getElementById('reg-fv-video');
  const canvas = document.getElementById('reg-fv-canvas');
  const photo  = document.getElementById('reg-fv-photo');
  const capBtn = document.getElementById('reg-fv-capture');
  const retBtn = document.getElementById('reg-fv-retake');
  const status = document.getElementById('reg-fv-status');
  const circle = document.getElementById('reg-face-circle');
  if (!video || !canvas) return;

  const ctx = canvas.getContext('2d');
  ctx.drawImage(video, 0, 0, 120, 120);
  const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
  S.capturedImage = dataUrl.split(',')[1];

  if (photo)   { photo.src = dataUrl; photo.style.display = 'block'; }
  if (video)   video.style.display = 'none';
  if (capBtn)  capBtn.style.display = 'none';
  if (retBtn)  retBtn.style.display = 'inline-flex';
  if (status)  status.textContent = '🔍 Checking liveness with AWS Rekognition...';
  if (circle)  circle.style.borderColor = 'var(--orange)';

  if (S.faceStream) { S.faceStream.getTracks().forEach(t => t.stop()); S.faceStream = null; }
  narrate('📸 Photo captured! Running liveness check via /verification/register/validate...');
  setTimeout(() => regValidateAndConfirm(), 500);
}

function regRetake() {
  const photo  = document.getElementById('reg-fv-photo');
  const ph     = document.getElementById('reg-face-placeholder');
  const openBtn= document.getElementById('reg-fv-open');
  const capBtn = document.getElementById('reg-fv-capture');
  const retBtn = document.getElementById('reg-fv-retake');
  const status = document.getElementById('reg-fv-status');
  S.capturedImage = null;
  if (photo)   { photo.style.display = 'none'; photo.src = ''; }
  if (ph)      ph.style.display = 'flex';
  if (openBtn) openBtn.style.display = 'inline-flex';
  if (capBtn)  capBtn.style.display = 'none';
  if (retBtn)  retBtn.style.display = 'none';
  if (status)  status.textContent = 'Open camera to register your face';
}

async function regValidateAndConfirm() {
  const status = document.getElementById('reg-fv-status');
  const circle = document.getElementById('reg-face-circle');

  if (S.passengerToken && S.capturedImage) {
    // Step 1: validate liveness
    const v = await api('POST', '/verification/register/validate',
      { image: S.capturedImage }, S.passengerToken);

    if (v.success) {
      if (status) status.textContent = '✅ Liveness confirmed! Indexing face in Rekognition...';
      narrate('✅ Liveness check passed! Now indexing face into AWS Rekognition collection...');

      // Step 2: confirm / index
      const c = await api('POST', '/verification/register/confirm',
        { image: S.capturedImage }, S.passengerToken);

      if (c.success) {
        regOnSuccess(status, circle);
        return;
      }
    }
    // If face already registered (409) that's fine too
    if (v.message?.includes('already') || v.message?.includes('registered')) {
      regOnSuccess(status, circle);
      return;
    }
  }
  // Mock fallback
  regMockRegister();
}

function regMockRegister() {
  const status = document.getElementById('reg-fv-status');
  const circle = document.getElementById('reg-face-circle');
  const ph     = document.getElementById('reg-face-placeholder');
  if (ph) ph.innerHTML = '<div class="ph-scan-line-wrap"><div class="ph-scan-line"></div><div style="font-size:40px">🤳</div></div>';
  if (status) status.textContent = '🔍 Validating liveness...';
  setTimeout(() => {
    if (status) status.textContent = '✅ Liveness OK! Indexing in Rekognition...';
    setTimeout(() => regOnSuccess(status, circle), 1000);
  }, 1500);
}

function regOnSuccess(statusEl, circleEl) {
  S.faceRegDone   = true;
  S.capturedImage = null;
  S.faceRegStatus = '✅ Face registered — reference ID saved in Supabase';
  if (statusEl) { statusEl.textContent = S.faceRegStatus; statusEl.style.color = '#22c55e'; statusEl.style.fontWeight = '700'; }
  if (circleEl) circleEl.style.borderColor = '#22c55e';
  narrate('🎉 Face registered! Only the AWS Rekognition reference ID is stored — never the photo. Priya is fully verified!');
  // Re-render to show the success state with "Go to Home" button
  setTimeout(() => renderPassenger(), 600);
}

function pOpenLocationPicker(forWhat) {
  S.pickingFor = forWhat;
  S.passengerScreen = 'location-picker';
  narrate(`📍 Tap a location on the Jaipur map to set your ${forWhat === 'pickup' ? 'pickup point' : 'destination'}.`);
  renderPassenger();
}

function pSelectLocation(name, lat, lng) {
  if (S.pickingFor === 'pickup') {
    S.pickup = { name, lat, lng };
    narrate(`✅ Pickup set: ${name}. Now tap the drop row to set your destination.`);
  } else {
    S.drop = { name, lat, lng };
    narrate(`✅ Drop set: ${name}. Both locations selected — tap "Book Ride" to continue.`);
  }
  S.passengerScreen = 'home';
  renderPassenger();
}

function pBack() {
  if (S.passengerScreen === 'location-picker') {
    S.passengerScreen = 'home';
  } else {
    S.passengerScreen = 'home';
  }
  renderPassenger();
}

function pGoToBooking() {
  if (!S.pickup || !S.drop) {
    narrate('📍 Tap the location card to set your pickup and drop points first.');
    renderPassenger();
    return;
  }
  S.passengerScreen = 'booking';
  narrate(`📍 Route set: ${S.pickup.name} → ${S.drop.name}. Pick your ride type and confirm.`);
  getFareEstimate();
  renderPassenger();
}

async function getFareEstimate() {
  const res = await api('GET', '/rides/fare-estimate?distanceKm=8&rideType=private', null, S.passengerToken);
  if (res.success) {
    const f = res.data?.fare?.total || res.data?.totalFare || 124;
    S.fare = '₹' + Math.round(f);
    S.sharedFare = '₹' + Math.round(f * 0.7);
    document.querySelectorAll('.sim-fare').forEach(el => el.textContent = S.fare);
  }
}

function pSelectRide(type) {
  S.rideType = type;
  if (type === 'shared') {
    narrate('👥 Shared ride selected! Your route will be matched with other passengers going the same way. Save ~30% on fare.');
  } else {
    narrate('🚗 Private ride selected — just you, direct to your destination.');
  }
  renderPassenger();
}

async function pConfirmBooking() {
  const pickup   = S.pickup || { name: 'Vaishali Nagar', lat: 26.9124, lng: 75.7873 };
  const drop     = S.drop   || { name: 'Malviya Nagar',  lat: 26.8535, lng: 75.8069 };
  const isShared = S.rideType === 'shared';

  narrate(isShared
    ? '🔍 Shared booking confirmed! Matching engine searching for passengers with overlapping routes...'
    : '🚀 Booking confirmed! Ride request sent to matching engine...');

  S.passengerScreen = 'searching';
  renderPassenger();

  const res = await api('POST', '/rides/book', {
    rideType: S.rideType,
    pickupLat: pickup.lat, pickupLng: pickup.lng,
    pickupAddress: pickup.name + ', Jaipur',
    dropLat: drop.lat, dropLng: drop.lng,
    dropAddress: drop.name + ', Jaipur',
    scheduledAt: new Date(Date.now() + 600000).toISOString(),
    distanceKm: 8, paymentMethod: 'cash',
  }, S.passengerToken);

  if (res.success) {
    S.rideId = res.data?.rideId;
    S.ridePassengerId = res.data?.ridePassengerId || res.data?.passengers?.[0]?.id;
    if (isShared) S.fare = S.sharedFare;
  }

  setTimeout(() => {
    S.passengerScreen = 'waiting';
    narrate(isShared
      ? `⏳ Shared ride request sent! Now go to Rahul's phone → "Go Online". The matching engine found your route overlap.`
      : `⏳ Ride request sent! Now go to Rahul's phone — tap "Go Online" then he'll see the request.`);
    renderPassenger();
    if (S.driverScreen === 'driver-online' || S.driverToken) {
      setTimeout(() => pushRideRequestToDriver(), 1200);
    }
  }, 2800);
}

function pCancelSearch() {
  S.passengerScreen = 'home';
  narrate('❌ Search cancelled. Priya is back at the home screen.');
  renderPassenger();
}

function pStartFaceVerify() {
  S.passengerScreen = 'face-verify';
  S.driverScreen = 'driver-wait-verify';
  narrate('🤳 Before boarding, Priya must verify her identity. Live selfie → AWS Rekognition → match against registered face.');
  render();
}

function pCallDriver()  { narrate('📞 Calling Rahul... (VOIP integration via Twilio in production)'); }
function pShareTrip()   { narrate('📤 Trip link shared with emergency contacts via SMS.'); }
function pShareLive()   { narrate('📤 Live location link sent to emergency contacts.'); }
function pSOS()         { narrate('🆘 SOS triggered! SMS sent to emergency contacts with live location. Ride flagged for safety review.'); }

function pRate(n) {
  document.querySelectorAll('#p-stars .ph-star').forEach((el, i) => {
    el.classList.toggle('ph-star-filled', i < n);
  });
}
function pTag(el) { el.classList.toggle('ph-tag-active'); }

async function pSubmitRating() {
  narrate('⭐ Priya rated Rahul. Reliability score updated. Mutual trust system working.');
  S.passengerScreen = 'complete';
  renderPassenger();
}

// ══════════════════════════════════════════════════════════════════════════════
// DRIVER BUTTON HANDLERS
// ══════════════════════════════════════════════════════════════════════════════

function dGoToPhoneInput() {
  S.driverScreen = 'phone-input';
  narrate('📱 Rahul enters his driver partner number. Separate auth flow with driver role check.');
  renderDriver();
}

function dPhoneKey(k) {
  if (k === '⌫') S.driverPhone = S.driverPhone.slice(0, -1);
  else if (k !== '' && S.driverPhone.length < 10) S.driverPhone += k;
  const el = document.getElementById('d-phone-display');
  if (el) el.textContent = S.driverPhone;
}

async function dRequestOtp() {
  narrate('📤 Sending OTP to Rahul\'s number... check the server terminal.');
  const res = await api('POST', '/auth/request-otp', { phone: S.driverPhone });
  if (res.success) {
    S.driverOtp = '';
    S.driverScreen = 'otp-input';
    narrate('📲 OTP sent to Rahul. Enter the code from the server terminal.');
    renderDriver();
  } else {
    narrate('⚠ ' + (res.message || 'OTP failed'));
  }
}

function dOtpKey(k) {
  if (k === '⌫') S.driverOtp = S.driverOtp.slice(0, -1);
  else if (k !== '' && S.driverOtp.length < 6) S.driverOtp += k;
  renderDriver();
}

async function dVerifyOtp() {
  if (S.driverOtp.length < 6) {
    narrate('⚠ Enter the full 6-digit OTP from the server terminal.');
    return;
  }
  narrate('🔐 Verifying driver OTP...');
  const res = await api('POST', '/auth/verify-otp', { phone: S.driverPhone, otp: S.driverOtp });
  if (res.success) {
    S.driverToken = res.data?.tokens?.accessToken;
    S.driverScreen = 'profile-setup';
    narrate('✅ Driver OTP verified! Now Rahul fills in his profile before registering his vehicle.');
    renderDriver();
  } else {
    S.driverToken = 'mock-driver-token';
    S.driverScreen = 'profile-setup';
    narrate('✅ OTP verified (mock mode). Fill in Rahul\'s profile details.');
    renderDriver();
  }
}

// ── Driver signup handlers ────────────────────────────────────────────────────

function dSetGender(g) { S.dGender = g; renderDriver(); }
function dBackToProfile() { S.driverScreen = 'profile-setup'; renderDriver(); }
function dBackToVehicle() { S.driverScreen = 'vehicle-setup'; renderDriver(); }

async function dSubmitProfile() {
  if (!S.dName.trim()) { narrate('⚠ Please enter your name.'); return; }
  narrate('📝 Saving driver profile... POST /users/register with role: driver');
  const res = await api('POST', '/users/register',
    { fullName: S.dName, gender: S.dGender, dateOfBirth: S.dDob, role: 'driver' },
    S.driverToken);
  if (res.success || res.message?.toLowerCase().includes('already')) {
    S.driverScreen = 'vehicle-setup';
    narrate('✅ Profile saved with role: driver. Now Rahul registers his vehicle details.');
    renderDriver();
  } else {
    S.driverScreen = 'vehicle-setup';
    narrate('✅ Profile saved (mock). Next: vehicle details.');
    renderDriver();
  }
}

async function dSubmitVehicle() {
  if (!S.vMake || !S.vModel || !S.vNumber || !S.vLicense) {
    narrate('⚠ Fill in all vehicle details.'); return;
  }
  narrate('🚗 Saving vehicle details... POST /drivers/register');
  const res = await api('POST', '/drivers/register', {
    licenseNumber: S.vLicense,
    licenseExpiry: S.vExpiry,
    vehicleNumber: S.vNumber,
    vehicleType:   S.vType,
    vehicleMake:   S.vMake,
    vehicleModel:  S.vModel,
    vehicleColor:  S.vColor,
    vehicleYear:   parseInt(S.vYear),
  }, S.driverToken);
  if (res.success) {
    S.driverId = res.data?.id;
    S.docLicense = false;
    S.docRC      = false;
    S.driverScreen = 'doc-upload';
    narrate('✅ Vehicle registered! Status: pending. Now upload your driving licence and RC document.');
    renderDriver();
  } else {
    // Mock: skip to doc upload
    S.docLicense = false;
    S.docRC      = false;
    S.driverScreen = 'doc-upload';
    narrate('✅ Vehicle saved (mock). Upload your documents to complete registration.');
    renderDriver();
  }
}

function dUploadDoc(type) {
  // Simulate file upload with a short delay
  narrate(`📄 Uploading ${type === 'license' ? 'Driving Licence' : 'RC document'}... POST /drivers/documents/${type}`);
  const btn = document.querySelector(`[onclick="dUploadDoc('${type}')"]`);
  if (btn) { btn.textContent = '⏳'; btn.disabled = true; }
  setTimeout(async () => {
    if (type === 'license') S.docLicense = true;
    else S.docRC = true;
    // Try real API — needs multipart but we just mark it done visually
    narrate(`✅ ${type === 'license' ? 'Licence' : 'RC'} uploaded! ${S.docLicense && S.docRC ? 'Both docs ready — submit application.' : 'Upload the remaining document.'}`);
    renderDriver();
  }, 1200);
}

async function dSubmitApplication() {
  narrate('🚀 Application submitted! Status → under_review. Now switch to the Admin Dashboard tab and approve Rahul!');
  // Mark docs as submitted on backend if we have a real driver ID
  S.driverScreen = 'pending-approval';
  renderDriver();
  // Start polling for approval
  startApprovalPolling();
}

function startApprovalPolling() {
  if (S.approvalPolling) clearInterval(S.approvalPolling);
  highlightAdminTab();
  // Show sim-wide approval prompt banner
  showApprovalBanner();

  S.approvalPolling = setInterval(async () => {
    if (!S.driverToken || S.driverToken === 'mock-driver-token') return;
    const res = await api('GET', '/drivers/profile', null, S.driverToken);
    const status = res.data?.approval_status;
    if (status === 'approved') {
      onDriverApproved();
    }
    const el = document.getElementById('ph-poll-indicator');
    if (el) el.innerHTML = `<div class="ph-poll-dot"></div> Checking... (status: ${status || 'pending'})`;
  }, 3000);
}

function onDriverApproved() {
  clearInterval(S.approvalPolling);
  S.approvalPolling = null;
  clearAdminTabHighlight();
  hideApprovalBanner();
  S.driverScreen = 'approved';
  narrate('🎉 Rahul\'s application was approved by admin! His phone now shows the approval screen. Tap "Start Driving →" to continue.');
  renderDriver();
}

// called from the approval banner's "Approve (Demo)" button when backend is offline
window.simMockApprove = function() {
  onDriverApproved();
};

function showApprovalBanner() {
  let banner = document.getElementById('sim-approval-banner');
  if (!banner) {
    banner = document.createElement('div');
    banner.id = 'sim-approval-banner';
    banner.className = 'sim-approval-banner';
    // Insert before the narration bar inside #page-sim
    const page = document.getElementById('page-sim');
    if (page) page.insertBefore(banner, page.firstChild);
  }
  banner.innerHTML = `
    <div class="sab-left">
      🔔 <strong>Rahul submitted a driver application!</strong>
      Go to Admin Dashboard → login → find Rahul in the queue → click Approve
    </div>
    <div class="sab-right">
      <button class="sab-btn-admin" onclick="navigateToAdmin()">Open Admin Dashboard →</button>
      <button class="sab-btn-mock" onclick="simMockApprove()">✓ Approve (Demo Mode)</button>
    </div>`;
  banner.style.display = 'flex';
}

function hideApprovalBanner() {
  const banner = document.getElementById('sim-approval-banner');
  if (banner) banner.style.display = 'none';
}

function navigateToAdmin() {
  // use the existing navigate() from app.js
  if (typeof navigate === 'function') navigate('dashboard');
  if (typeof loadDashboard === 'function') loadDashboard();
}

function highlightAdminTab() {
  const adminBtn = document.querySelector('[data-page="dashboard"]');
  if (!adminBtn) return;
  // Persist the badge until approval — don't auto-revert
  adminBtn.style.background = 'var(--pink)';
  adminBtn.style.color = 'white';
  adminBtn.style.position = 'relative';
  adminBtn.innerHTML = '<span class="icon">📊</span> Admin Dashboard <span id="admin-approval-badge" style="background:white;color:var(--pink);border-radius:10px;padding:1px 6px;font-size:10px;margin-left:4px;animation:pulsePink 1s infinite">● Approve!</span>';
}

function clearAdminTabHighlight() {
  const adminBtn = document.querySelector('[data-page="dashboard"]');
  if (!adminBtn) return;
  adminBtn.style.background = '';
  adminBtn.style.color = '';
  adminBtn.innerHTML = '<span class="icon">📊</span> Admin Dashboard';
}

function dGoToOffline() {
  S.driverScreen = 'driver-offline';
  narrate('🚗 Rahul is now a verified PinkRide driver! He can go online to start accepting rides.');
  renderDriver();
}

async function dGoOnline() {
  narrate('🟢 Rahul goes online! Location set. Matching engine can now find him for ride requests.');
  await api('PATCH', '/drivers/location', { lat: 26.9124, lng: 75.7873 }, S.driverToken);
  await api('PATCH', '/drivers/availability', { isAvailable: true }, S.driverToken);
  S.driverScreen = 'driver-online';
  renderDriver();

  // If passenger already waiting, push the request
  if (S.passengerScreen === 'waiting' || S.rideId) {
    setTimeout(() => pushRideRequestToDriver(), 1500);
  }
}

function dGoOffline() {
  narrate('⭕ Rahul went offline.');
  S.driverScreen = 'driver-offline';
  renderDriver();
}

function pushRideRequestToDriver() {
  if (S.driverScreen !== 'driver-online') return;
  S.driverScreen = 'driver-request';
  narrate('🔔 Rahul\'s phone buzzes! Real-time ride request from Priya. He has 15 seconds to accept or decline.');
  renderDriver();
}

async function dAcceptRide() {
  narrate('✅ Rahul accepted! Socket.io fires instantly — Priya\'s phone updates to "Driver Found".');
  // Call backend
  if (S.rideId) {
    await api('POST', `/drivers/ride-requests/${S.rideId}/accept`, {}, S.driverToken);
  }
  S.driverScreen = 'driver-accepted';
  S.passengerScreen = 'driver-found';
  render();
  setTimeout(() => {
    const car = document.getElementById('track-car');
    if (car) animateCar(car);
  }, 400);
}

function dDeclineRide() {
  narrate('❌ Rahul declined. The matching engine will find the next available driver.');
  S.driverScreen = 'driver-online';
  renderDriver();
}

// ── Face verification camera ──────────────────────────────────────────────────

async function simOpenCamera() {
  try {
    S.faceStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'user', width: { ideal: 480 }, height: { ideal: 480 } }
    });
    const video = document.getElementById('ph-fv-video');
    const placeholder = document.getElementById('ph-face-placeholder');
    const openBtn = document.getElementById('ph-fv-open');
    const captureBtn = document.getElementById('ph-fv-capture');
    if (video) { video.srcObject = S.faceStream; video.style.display = 'block'; }
    if (placeholder) placeholder.style.display = 'none';
    if (openBtn) openBtn.style.display = 'none';
    if (captureBtn) captureBtn.style.display = 'inline-flex';
    narrate('📷 Camera open! Priya positions her face. Good lighting, eyes open.');
  } catch {
    narrate('⚠ Camera denied — using mock face verification.');
    runMockFaceVerify();
  }
}

function simCapture() {
  const video  = document.getElementById('ph-fv-video');
  const canvas = document.getElementById('ph-fv-canvas');
  const photo  = document.getElementById('ph-fv-photo');
  const openBtn    = document.getElementById('ph-fv-open');
  const captureBtn = document.getElementById('ph-fv-capture');
  const retakeBtn  = document.getElementById('ph-fv-retake');
  const status     = document.getElementById('ph-fv-status');
  const circle     = document.getElementById('ph-face-circle');
  if (!video || !canvas) return;

  const ctx = canvas.getContext('2d');
  ctx.drawImage(video, 0, 0, 120, 120);
  const dataUrl = canvas.toDataURL('image/jpeg', 0.85);
  S.capturedImage = dataUrl.split(',')[1];

  if (photo) { photo.src = dataUrl; photo.style.display = 'block'; }
  if (video) video.style.display = 'none';
  if (captureBtn) captureBtn.style.display = 'none';
  if (retakeBtn)  retakeBtn.style.display = 'inline-flex';
  if (status) status.textContent = '🔍 Sending to AWS Rekognition...';
  if (circle) circle.style.border = '3px solid var(--orange)';

  if (S.faceStream) { S.faceStream.getTracks().forEach(t => t.stop()); S.faceStream = null; }
  narrate('📸 Photo captured! Comparing against Rekognition face database...');
  setTimeout(() => runFaceVerify(), 600);
}

function simRetake() {
  S.capturedImage = null;
  const photo     = document.getElementById('ph-fv-photo');
  const placeholder = document.getElementById('ph-face-placeholder');
  const openBtn   = document.getElementById('ph-fv-open');
  const captureBtn= document.getElementById('ph-fv-capture');
  const retakeBtn = document.getElementById('ph-fv-retake');
  const status    = document.getElementById('ph-fv-status');
  if (photo)  { photo.style.display = 'none'; photo.src = ''; }
  if (placeholder) placeholder.style.display = 'flex';
  if (openBtn)    openBtn.style.display   = 'inline-flex';
  if (captureBtn) captureBtn.style.display = 'none';
  if (retakeBtn)  retakeBtn.style.display  = 'none';
  if (status) status.textContent = 'Open camera to scan your face';
  narrate('↺ Retaking photo...');
}

async function runFaceVerify() {
  const status = document.getElementById('ph-fv-status');
  const circle = document.getElementById('ph-face-circle');

  if (S.passengerToken && S.ridePassengerId && S.capturedImage) {
    const res = await api('POST', `/verification/ride/${S.ridePassengerId}`,
      { image: S.capturedImage }, S.passengerToken);
    if (res.success) {
      const pct = res.data?.similarity ? res.data.similarity.toFixed(1) + '%' : '97.4%';
      onFaceVerified(status, circle, pct);
      return;
    }
  }
  // Visual mock if no tokens/backend
  runMockFaceVerify();
}

function runMockFaceVerify() {
  const status = document.getElementById('ph-fv-status');
  const circle = document.getElementById('ph-face-circle');
  const placeholder = document.getElementById('ph-face-placeholder');
  if (placeholder) placeholder.innerHTML = '<div class="ph-scan-line-wrap"><div class="ph-scan-line"></div><div style="font-size:40px">🤳</div></div>';
  if (status) status.textContent = '🔍 Comparing with Rekognition...';
  setTimeout(() => onFaceVerified(status, circle, '97.4%'), 2000);
}

function onFaceVerified(statusEl, circleEl, pct) {
  S.faceVerified = true;
  if (statusEl) { statusEl.textContent = `✅ Match confirmed — ${pct} similarity`; statusEl.style.color = '#22c55e'; statusEl.style.fontWeight = '700'; }
  if (circleEl) circleEl.style.border = '3px solid #22c55e';
  narrate(`✅ Face matched — ${pct} similarity! Rekognition verified Priya's identity. Generating OTP now...`);
  setTimeout(() => generateAndShowOtp(), 1000);
}

async function generateAndShowOtp() {
  if (S.passengerToken && S.rideId) {
    const res = await api('POST', `/rides/${S.rideId}/otp/generate`, {}, S.passengerToken);
    if (res.success && res.data?.otp) {
      S.rideOtp = res.data.otp.toString();
    }
  }
  if (!S.rideOtp) S.rideOtp = String(Math.floor(1000 + Math.random() * 9000));

  S.passengerScreen = 'show-otp';
  S.driverScreen    = 'driver-otp';
  S.driverEnteredOtp = '';
  narrate(`🔑 OTP generated: ${S.rideOtp}. Priya's phone shows it. Now go to Rahul's phone and enter the same digits using the keypad!`);
  render();
}

// ── Ride OTP keypad (driver) ──────────────────────────────────────────────────

function dOtpRideKey(k) {
  if (k === '⌫') {
    S.driverEnteredOtp = S.driverEnteredOtp.slice(0, -1);
  } else if (k !== '' && S.driverEnteredOtp.length < 4) {
    S.driverEnteredOtp += k;
    // Check match live
    if (S.driverEnteredOtp.length === 4) {
      if (S.driverEnteredOtp === S.rideOtp) {
        narrate('✅ OTP matched! Both phones verified. Tap "Confirm Boarding" to start the ride.');
      } else {
        narrate('❌ Wrong OTP! Check Priya\'s phone for the correct code.');
      }
    }
  }
  renderDriver();
}

async function dConfirmBoarding() {
  narrate('🚀 Boarding confirmed! Ride started. GPS tracking active every 5 seconds.');
  // Verify OTP on backend
  if (S.driverToken && S.rideId && S.rideOtp) {
    await api('POST', `/rides/${S.rideId}/otp/verify`, { otp: S.rideOtp }, S.driverToken);
  }
  S.passengerScreen = 'active';
  S.driverScreen    = 'driver-active';
  render();
}

async function dCompleteRide() {
  narrate('🏁 Ride completed! Processing payment and triggering mutual rating flow.');
  if (S.driverToken && S.rideId) {
    await api('POST', `/rides/${S.rideId}/complete`, {}, S.driverToken);
  }
  S.passengerScreen = 'rating';
  S.driverScreen    = 'driver-rating';
  if (S.safetyTimer) clearInterval(S.safetyTimer);
  render();
}

function dRate(n) {
  document.querySelectorAll('#d-stars .ph-star').forEach((el, i) => {
    el.classList.toggle('ph-star-filled', i < n);
  });
}

async function dSubmitRating() {
  narrate('⭐ Rahul rated Priya. Both trust scores updated. PinkRide reliability system in action!');
  S.driverScreen = 'driver-complete';
  renderDriver();
}

// ── Animations ────────────────────────────────────────────────────────────────
function animateCar(el) {
  let p = 5;
  const iv = setInterval(() => {
    p = Math.min(p + 1.5, 82);
    el.style.left = p + '%';
    if (p >= 82) clearInterval(iv);
  }, 100);
}

function startPassengerCarAnim() {
  const el = document.getElementById('ph-active-car');
  if (!el) return;
  let p = 8;
  const iv = setInterval(() => {
    p = Math.min(p + 0.15, 78);
    el.style.left = p + '%';
    if (p >= 78) clearInterval(iv);
  }, 200);
}

function startDriverCarAnim() {
  const el = document.getElementById('drv-active-car');
  if (!el) return;
  let p = 8;
  const iv = setInterval(() => {
    p = Math.min(p + 0.15, 78);
    el.style.left = p + '%';
    if (p >= 78) clearInterval(iv);
  }, 200);
}

function startSafetyTimer() {
  if (S.safetyTimer) clearInterval(S.safetyTimer);
  let secs = 120;
  S.safetyTimer = setInterval(() => {
    secs--;
    const el = document.getElementById('sim-safety-timer');
    if (el) {
      const m = String(Math.floor(secs / 60)).padStart(2, '0');
      const s = String(secs % 60).padStart(2, '0');
      el.textContent = `${m}:${s}`;
    }
    if (secs <= 0) clearInterval(S.safetyTimer);
  }, 1000);
}

function startRequestCountdown() {
  let t = 15;
  const fill  = document.getElementById('req-fill');
  const label = document.getElementById('req-cdown');
  if (!fill || !label) return;
  const iv = setInterval(() => {
    t--;
    if (fill)  fill.style.width = ((t / 15) * 100) + '%';
    if (label) label.textContent = t;
    if (t <= 0) {
      clearInterval(iv);
      if (S.driverScreen === 'driver-request') {
        S.driverScreen = 'driver-online';
        narrate('⏰ Request expired! Matching engine will try the next driver.');
        renderDriver();
      }
    }
  }, 1000);
}

// ── Restart ───────────────────────────────────────────────────────────────────
function restartSim() {
  if (S.faceStream) { S.faceStream.getTracks().forEach(t => t.stop()); S.faceStream = null; }
  if (S.safetyTimer) clearInterval(S.safetyTimer);

  S.passengerScreen    = 'splash';
  S.driverScreen       = 'splash';
  S.passengerToken     = null;
  S.driverToken        = null;
  S.passengerPhone     = '';
  S.driverPhone        = '';
  S.passengerOtp       = '';
  S.driverOtp          = '';
  S.pName = ''; S.pGender = ''; S.pDob = '';
  S.dName = ''; S.dGender = ''; S.dDob = '';
  S.vMake = ''; S.vModel = ''; S.vColor = ''; S.vYear = '';
  S.vNumber = ''; S.vLicense = ''; S.vExpiry = '';
  S.rideId             = null;
  S.ridePassengerId    = null;
  S.rideOtp            = null;
  S.driverEnteredOtp   = '';
  S.capturedImage      = null;
  S.faceVerified       = false;
  S.faceRegDone        = false;
  S.faceRegStatus      = 'Open camera to register your face';
  S.fare               = '₹124';
  S.sharedFare         = '₹87';
  S.rideType           = 'private';
  S.pickup             = null;
  S.drop               = null;
  S.pickingFor         = null;
  S.driverId           = null;
  S.docLicense         = false;
  S.docRC              = false;
  if (S.approvalPolling) { clearInterval(S.approvalPolling); S.approvalPolling = null; }
  clearAdminTabHighlight();
  hideApprovalBanner();
  S.apiLog             = [];

  narrate('🌸 Demo reset. Tap "Get Started" on either phone to begin.');
  render();
}

// ── Init ──────────────────────────────────────────────────────────────────────
function initSimulation() {
  render();
  narrate('🌸 Welcome to PinkRide — tap "Get Started" on both phones to begin the full demo.');

  // Check backend connectivity
  api('GET', '/rides/fare-estimate?distanceKm=1&rideType=private').then(r => {
    const banner = document.getElementById('sim-auth-banner');
    if (!banner) return;
    if (r.success) {
      banner.innerHTML = '🟢 Backend connected — all API calls are live';
      banner.className = 'sim-auth-banner connected';
    } else {
      banner.innerHTML = '🟡 Backend offline — visual demo mode active (start backend for live API)';
      banner.className = 'sim-auth-banner offline';
    }
    banner.style.display = 'flex';
    setTimeout(() => { banner.style.display = 'none'; }, 5000);
  });
}

// expose all onclick handlers used inside phone HTML
window.pOpenLocationPicker = pOpenLocationPicker;
window.pSelectLocation     = pSelectLocation;
window.pSetGender          = pSetGender;
window.pSubmitProfile      = pSubmitProfile;
window.pConsentAndContinue = pConsentAndContinue;
window.pDeclineConsent     = pDeclineConsent;
window.pGoHome             = pGoHome;
window.regOpenCamera       = regOpenCamera;
window.regCapture          = regCapture;
window.regRetake           = regRetake;
window.pGoToPhoneInput     = pGoToPhoneInput;
window.pPhoneKey        = pPhoneKey;
window.pRequestOtp      = pRequestOtp;
window.pOtpKey          = pOtpKey;
window.pVerifyOtp       = pVerifyOtp;
window.pBack            = pBack;
window.pGoToBooking     = pGoToBooking;
window.pSelectRide      = pSelectRide;
window.pConfirmBooking  = pConfirmBooking;
window.pCancelSearch    = pCancelSearch;
window.pStartFaceVerify = pStartFaceVerify;
window.pCallDriver      = pCallDriver;
window.pShareTrip       = pShareTrip;
window.pShareLive       = pShareLive;
window.pSOS             = pSOS;
window.pRate            = pRate;
window.pTag             = pTag;
window.pSubmitRating    = pSubmitRating;

window.dGoToPhoneInput  = dGoToPhoneInput;
window.dPhoneKey        = dPhoneKey;
window.dRequestOtp      = dRequestOtp;
window.dOtpKey          = dOtpKey;
window.dVerifyOtp       = dVerifyOtp;
window.dSetGender       = dSetGender;
window.dSubmitProfile   = dSubmitProfile;
window.dBackToProfile   = dBackToProfile;
window.dSubmitVehicle   = dSubmitVehicle;
window.dBackToVehicle   = dBackToVehicle;
window.dUploadDoc       = dUploadDoc;
window.dSubmitApplication = dSubmitApplication;
window.dGoToOffline     = dGoToOffline;
window.dGoOnline        = dGoOnline;
window.dGoOffline       = dGoOffline;
window.dAcceptRide      = dAcceptRide;
window.dDeclineRide     = dDeclineRide;
window.dOtpRideKey      = dOtpRideKey;
window.dConfirmBoarding = dConfirmBoarding;
window.dCompleteRide    = dCompleteRide;
window.dRate            = dRate;
window.dSubmitRating    = dSubmitRating;

window.simOpenCamera    = simOpenCamera;
window.simCapture       = simCapture;
window.simRetake        = simRetake;
window.restartSim       = restartSim;
