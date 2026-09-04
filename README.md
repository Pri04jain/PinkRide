# PinkRide

**Safe. Verified. Shared.**

A women-focused ride-sharing platform for Jaipur (MVP). Every ride is face-verified before it starts. Shared rides split the fare fairly based on actual distance travelled. Multiple safety layers — from face verification and ride OTPs to live GPS tracking, deviation alerts, and SOS — make every journey more accountable.

---

## Why PinkRide?

Current ride-hailing apps solve transport but leave gaps:

- Anyone can create an account with just a phone number — no real verification
- Shared rides have no transparent fare splitting
- Safety features exist but feel cosmetic, not structural

PinkRide doesn't claim to guarantee safety. It reduces risk through layers — verified identities, accountable rides, and real-time safety tools.

---

## Safety Layers

```
Verified User (OTP + face embedding)
        ↓
Verified Driver (documents + face check)
        ↓
Pre-ride Face Verification (passenger confirms identity before boarding)
        ↓
Ride OTP (driver enters code to start the trip)
        ↓
Live GPS Tracking (real-time via Socket.io)
        ↓
Route Deviation Alerts (auto-alert contacts if no response in 2 min)
        ↓
SOS (instant broadcast + SMS to emergency contacts)
        ↓
Ratings & Reliability Score (post-ride accountability)
```

---

## Tech Stack

| Layer | Technology | Why |
|---|---|---|
| Backend | Node.js + Express | Beginner-friendly, fast to build, huge ecosystem |
| Database | Supabase (PostgreSQL) | No local setup needed, free tier, hosted, easy dashboard |
| Real-time | Socket.io | Driver location updates and safety alerts over WebSocket |
| OTP Store | In-memory (Map) | Simple, fast, no extra service needed for MVP |
| Face Verification | AWS Rekognition | Accurate, stores face embedding not the photo |
| Maps | Google Maps Platform | Best accuracy in India |
| Payments | Razorpay | Best UPI + card support in India |
| SMS / OTP | MSG91 | Affordable India OTP delivery |
| Mobile | Flutter | One codebase for both Android and iOS |
| Push Notifications | Firebase FCM | Free, reliable |

No Docker. No Redis. No complex local setup. Just `npm run dev`.

---

## Project Structure

```
PinkRide/
├── backend/
│   └── src/
│       ├── app.js                    # Express server entry point
│       ├── services/
│       │   ├── auth/                 # Phone OTP login, JWT tokens
│       │   ├── user/                 # Profile, wallet, emergency contacts
│       │   ├── driver/               # Driver registration, admin approval queue
│       │   ├── verification/         # AWS Rekognition face verification
│       │   ├── ride/                 # Booking, matching, fare calculation, OTP
│       │   ├── tracking/             # Live location, route deviation detection
│       │   ├── safety/               # SOS trigger, emergency contact alerts
│       │   ├── payment/              # Razorpay UPI, wallet, fines, ratings
│       │   └── notification/         # MSG91 SMS, Firebase push
│       └── shared/
│           ├── db/                   # Supabase client + schema.sql
│           ├── cache/                # In-memory OTP store (Map)
│           ├── middleware/           # JWT auth, error handler, file upload
│           ├── socket/               # Socket.io server setup
│           └── utils/                # Standard API response helpers
│
├── mobile/                           # Flutter app (passenger + driver in one app)
│   └── lib/
│       ├── main.dart
│       ├── core/
│       │   ├── api/                  # HTTP client with auto token refresh
│       │   ├── constants/            # App-wide config
│       │   ├── router/               # Navigation with auth-gated routes
│       │   └── theme/                # Brand colours, typography
│       └── features/
│           ├── auth/                 # Phone input, OTP, profile setup
│           ├── verification/         # Face consent, registration, pre-ride check
│           ├── driver/               # Registration, docs, status, admin queue
│           ├── passenger/            # Home screen
│           ├── ride/                 # Booking, matching, active ride, OTP screens
│           ├── tracking/             # Live map
│           ├── safety/               # SOS screen
│           └── payment/              # Payment confirmation, rating screen
│
└── README.md
```

---

## Features Built

### Authentication
- Phone number + 6-digit OTP (MSG91 for production, prints to console in dev)
- JWT access token (7 days) + refresh token (30 days)
- Rate limited — max 5 OTP requests per hour per number
- Role-based: passenger, driver, admin

### Face Verification (DPDP Act 2025 Compliant)
- Explicit consent screen shown before any biometric is captured
- Liveness check — eyes open, face visible, no sunglasses, looking at camera
- Only an encrypted face embedding is stored — original photo discarded immediately
- Pre-ride: passenger must pass face check before OTP is generated (5 attempts, then ride is cancelled)
- Users can delete their face data from Settings at any time (right to erasure)
- Dev mode: mock responses when AWS is not configured

### Driver Onboarding
- Self-registration: driving license + vehicle details
- Document upload: License photo (required), RC photo (required), Insurance (optional)
- Auto-moves to "Under Review" once required docs are uploaded
- Admin approves / rejects / suspends drivers from inside the mobile app
- Rejection always includes a reason shown to the driver

### Ride Engine
- Three ride types: **Private**, **Shared**, **Women-Only Shared**
- Smart matching — finds passengers going the same direction, within ±30 minutes
- Time-shift negotiation: if schedules don't align exactly, passengers can propose a new time
- Co-passenger rejection limit: reject twice and your ride auto-upgrades to private pricing
- Shared rides require a small wallet balance to cover potential cancellation fees

### Fare Splitting (Shared Rides)

```
Route: Passenger A travels Vaishali Nagar → Malviya Nagar (10 km)
       Passenger B boards at Civil Lines → Malviya Nagar (6 km shared)

Passenger A pays:
  4 km exclusive  → ₹48
  3 km shared     → ₹36  (half of 6 km)
  Platform fee    → ₹4.20
  Total           → ₹88.20  (saved ₹57.80 vs solo)

Passenger B pays:
  3 km shared     → ₹36  (half of 6 km)
  Platform fee    → ₹1.80
  Total           → ₹37.80  (saved ₹64.20 vs solo)
```

Base rate: ₹30 + ₹12/km (Jaipur MVP rates)

### Ride OTP Flow
```
Passenger takes a live selfie → Face verified → 6-digit OTP shown to passenger
                                                          ↓
                                             Driver enters OTP in app
                                                          ↓
                                                    Trip starts
```

### Live Tracking & Safety
- Driver location sent every 5 seconds via Socket.io
- Route deviation detected using Haversine distance formula
- Alert shown to passenger — 2 minutes to respond ("I'm okay" or "Alert contacts")
- No response → emergency contacts auto-SMSed with live Google Maps link
- SOS button always visible during a ride — 5-second countdown, then sends alert
- Safety check-in button ("I'm safe") clears any active deviation timer

### Payments
- **Cash**: passenger pays driver directly, driver confirms in app
- **UPI**: Razorpay order → UPI deep link (PhonePe, GPay, Paytm, etc.)
- Wallet: top-up, auto-deductions for cancellation fines, transaction history
- Cancellation fees collected from wallet automatically

### Ratings
- Both driver and passenger rate each other after every trip
- Tag-based feedback: Punctual, Safe Driver, Clean Vehicle, Polite, etc.
- Optional comment (300 characters)
- Reliability score auto-updated after each rating

---

## How to Run Locally

### What you need
- [Node.js](https://nodejs.org) (v18 or higher)
- A [Supabase](https://supabase.com) account (free)
- A code editor (VS Code recommended)

### Step 1 — Clone the repo

```bash
git clone https://github.com/YOUR_USERNAME/PinkRide.git
cd PinkRide/backend
```

### Step 2 — Install dependencies

```bash
npm install
```

### Step 3 — Set up your Supabase database

1. Go to [supabase.com](https://supabase.com) and create a new project
2. Once created, go to **SQL Editor** in the left sidebar
3. Copy the entire contents of `src/shared/db/schema.sql`
4. Paste it into the SQL Editor and click **Run**
5. All tables, enums, indexes, and triggers will be created automatically

### Step 4 — Configure environment variables

```bash
cp .env.example .env
```

Open `.env` and fill in these values (get them from Supabase → Settings → API):

```env
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key

JWT_SECRET=any_random_string_at_least_32_characters
JWT_REFRESH_SECRET=another_different_random_string_32_chars
```

Everything else (MSG91, AWS, Razorpay) is optional for local development. The app runs in mock mode without them — OTPs print to your terminal, face verification returns mock success, payments return a fake order.

### Step 5 — Start the server

```bash
npm run dev
```

You should see:
```
PinkRide API running on port 3000 [development]
```

### Step 6 — Test it works

Open your browser and go to:
```
http://localhost:3000/health
```

You should see:
```json
{
  "success": true,
  "service": "PinkRide API",
  "version": "1.0.0",
  "city": "Jaipur"
}
```

### Step 7 — Test the OTP login (Postman or curl)

```bash
# Request OTP
curl -X POST http://localhost:3000/api/v1/auth/request-otp \
  -H "Content-Type: application/json" \
  -d '{"phone": "9876543210"}'

# Check your terminal — the OTP will print there (dev mode):
# [DEV OTP] Phone: +919876543210 | OTP: 482916

# Verify OTP and get your token
curl -X POST http://localhost:3000/api/v1/auth/verify-otp \
  -H "Content-Type: application/json" \
  -d '{"phone": "9876543210", "otp": "482916"}'
```

---

## Environment Variables

Full list in `.env.example`. Here's what each one does:

| Variable | Required | Where to get it |
|---|---|---|
| `SUPABASE_URL` | ✅ Yes | Supabase → Settings → API |
| `SUPABASE_SERVICE_KEY` | ✅ Yes | Supabase → Settings → API → service_role |
| `JWT_SECRET` | ✅ Yes | Any random 32+ character string |
| `JWT_REFRESH_SECRET` | ✅ Yes | Any different random 32+ character string |
| `MSG91_AUTH_KEY` | Optional | [msg91.com](https://msg91.com) — for real SMS |
| `MSG91_TEMPLATE_ID` | Optional | MSG91 dashboard after creating OTP template |
| `AWS_ACCESS_KEY_ID` | Optional | AWS Console → IAM → Access Keys |
| `AWS_SECRET_ACCESS_KEY` | Optional | Same as above |
| `RAZORPAY_KEY_ID` | Optional | [razorpay.com](https://razorpay.com) dashboard |
| `RAZORPAY_KEY_SECRET` | Optional | Razorpay dashboard |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | Optional | Firebase Console → Project Settings → Service Accounts |
| `GOOGLE_MAPS_API_KEY` | Optional | Google Cloud Console |

---

## Data Privacy (DPDP Act 2025)

- Face photos are **never stored** — only a face ID reference from AWS Rekognition
- Explicit consent is required before any biometric is captured
- Users can delete all their face data from the app at any time
- Account deletion anonymises all personal data in the database
- The backend uses Supabase's service role key — all database access is server-side only

---

## Roadmap

### Phase 1 — MVP (current, Jaipur)
- [x] User registration + OTP login
- [x] Face verification (DPDP compliant)
- [x] Driver onboarding + admin approval
- [x] Ride booking (private / shared / women-only)
- [x] Smart ride matching + fare splitting
- [x] Ride OTP
- [x] Live GPS tracking
- [x] Route deviation alerts
- [x] SOS + emergency contacts
- [x] Payments (cash + UPI)
- [x] Ratings + reliability score

### Phase 2 — Trust & Intelligence
- [ ] AI-based route prediction
- [ ] Reliability score influencing match priority
- [ ] Predictive commute suggestions
- [ ] Trusted family ride circles

### Phase 3 — Expansion
- [ ] Corporate commuting
- [ ] Multi-city rollout
- [ ] Aadhaar / DigiLocker verification
- [ ] Insurance partnerships
- [ ] Driver subscription plans

---

## Author

Built by Priyanjal — Jaipur.

---

*PinkRide does not claim to guarantee safety. It reduces risk through verified identities, multiple accountability layers, and real-time safety tools. Every layer matters.*
