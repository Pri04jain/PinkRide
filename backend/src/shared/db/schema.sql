-- ============================================================
-- PinkRide Database Schema
-- Run this in Supabase SQL Editor to set up your database
-- Project: PinkRide MVP — Jaipur
-- ============================================================

-- ============================================================
-- ENUMS
-- Supabase supports native Postgres enums.
-- Create these FIRST before any tables that use them.
-- ============================================================

CREATE TYPE user_role AS ENUM ('passenger', 'driver', 'admin');
CREATE TYPE user_gender AS ENUM ('female', 'male', 'other', 'prefer_not_to_say');
CREATE TYPE driver_approval_status AS ENUM ('pending', 'under_review', 'approved', 'rejected', 'suspended');
CREATE TYPE ride_type AS ENUM ('private', 'shared', 'women_only_shared');
CREATE TYPE ride_status AS ENUM (
  'searching',
  'matching',
  'confirmed',
  'driver_arriving',
  'face_verification_pending',
  'otp_pending',
  'in_progress',
  'completed',
  'cancelled'
);
CREATE TYPE passenger_ride_status AS ENUM ('pending', 'confirmed', 'boarded', 'dropped', 'cancelled');
CREATE TYPE payment_method AS ENUM ('cash', 'upi');
CREATE TYPE payment_status AS ENUM ('pending', 'completed', 'failed', 'refunded');
CREATE TYPE fine_type AS ENUM ('passenger_cancellation', 'driver_cancellation', 'face_verify_failure', 'no_show');
CREATE TYPE fine_status AS ENUM ('pending', 'collected', 'waived');
CREATE TYPE deviation_status AS ENUM ('detected', 'passenger_acknowledged', 'contacts_alerted', 'resolved');

-- ============================================================
-- AUTO-UPDATE updated_at TRIGGER FUNCTION
-- Defined here — BEFORE any table that uses it.
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- USERS
-- Core table — both passengers and drivers are users
-- ============================================================

CREATE TABLE users (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone                 VARCHAR(15) UNIQUE NOT NULL,
  country_code          VARCHAR(5) NOT NULL DEFAULT '+91',
  role                  user_role NOT NULL DEFAULT 'passenger',
  full_name             VARCHAR(100),
  gender                user_gender,
  date_of_birth         DATE,
  profile_photo_url     TEXT,

  -- Face verification (no raw photo stored — only a reference ID)
  face_embedding_ref    TEXT,
  face_verified         BOOLEAN NOT NULL DEFAULT FALSE,
  face_consent_given    BOOLEAN NOT NULL DEFAULT FALSE,
  face_consent_given_at TIMESTAMPTZ,

  -- Account state
  is_active             BOOLEAN NOT NULL DEFAULT TRUE,
  is_phone_verified     BOOLEAN NOT NULL DEFAULT FALSE,

  -- Trust & reliability
  reliability_score     NUMERIC(3,2) NOT NULL DEFAULT 5.00,
  total_rides           INTEGER NOT NULL DEFAULT 0,
  cancellation_count    INTEGER NOT NULL DEFAULT 0,

  -- Wallet (used for fines and shared ride cancellation cover)
  wallet_balance        NUMERIC(10,2) NOT NULL DEFAULT 0.00,

  city                  VARCHAR(50) NOT NULL DEFAULT 'Jaipur',

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_active_at        TIMESTAMPTZ
);

CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_city ON users(city);


CREATE TABLE drivers (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

  -- Documents
  license_number        VARCHAR(20) UNIQUE NOT NULL,
  license_expiry        DATE NOT NULL,
  license_doc_url       TEXT NOT NULL DEFAULT 'pending_upload',

  vehicle_number        VARCHAR(15) UNIQUE NOT NULL,
  vehicle_type          VARCHAR(30) NOT NULL,
  vehicle_make          VARCHAR(30) NOT NULL,
  vehicle_model         VARCHAR(30) NOT NULL,
  vehicle_color         VARCHAR(20) NOT NULL,
  vehicle_year          SMALLINT NOT NULL,
  vehicle_rc_url        TEXT NOT NULL DEFAULT 'pending_upload',
  vehicle_insurance_url TEXT,

  -- Approval
  approval_status       driver_approval_status NOT NULL DEFAULT 'pending',
  approved_by           UUID REFERENCES users(id),
  approved_at           TIMESTAMPTZ,
  rejection_reason      TEXT,

  -- Availability & live location (flat columns — no PostGIS needed)
  is_available          BOOLEAN NOT NULL DEFAULT FALSE,
  current_lat           NUMERIC(10,7),
  current_lng           NUMERIC(10,7),
  last_location_update  TIMESTAMPTZ,

  -- Stats
  total_trips           INTEGER NOT NULL DEFAULT 0,
  cancellation_count    INTEGER NOT NULL DEFAULT 0,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_drivers_user_id ON drivers(user_id);
CREATE INDEX idx_drivers_approval_status ON drivers(approval_status);
CREATE INDEX idx_drivers_available ON drivers(is_available) WHERE is_available = TRUE;

-- ============================================================
-- EMERGENCY CONTACTS
-- ============================================================

CREATE TABLE emergency_contacts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name        VARCHAR(100) NOT NULL,
  phone       VARCHAR(15) NOT NULL,
  relation    VARCHAR(50),
  is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_emergency_contacts_user ON emergency_contacts(user_id);

-- ============================================================
-- RIDES
-- Flat lat/lng instead of PostGIS geometry for simplicity
-- ============================================================

CREATE TABLE rides (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id         UUID REFERENCES drivers(id),
  ride_type         ride_type NOT NULL,
  status            ride_status NOT NULL DEFAULT 'searching',

  -- Route (flat coordinates — Haversine in JS handles distance)
  pickup_lat        NUMERIC(10,7) NOT NULL,
  pickup_lng        NUMERIC(10,7) NOT NULL,
  pickup_address    TEXT NOT NULL,
  drop_lat          NUMERIC(10,7) NOT NULL,
  drop_lng          NUMERIC(10,7) NOT NULL,
  drop_address      TEXT NOT NULL,

  -- Timing
  scheduled_at      TIMESTAMPTZ NOT NULL,
  driver_arriving_at TIMESTAMPTZ,
  started_at        TIMESTAMPTZ,
  ended_at          TIMESTAMPTZ,

  -- Fare
  total_distance_km NUMERIC(6,2),
  base_fare         NUMERIC(8,2),
  platform_fee      NUMERIC(8,2),
  final_fare        NUMERIC(8,2),

  -- Payment
  payment_method    payment_method,
  payment_status    payment_status NOT NULL DEFAULT 'pending',
  payment_order_id  TEXT,                    -- Razorpay orderId — stored on first order creation,
                                             -- returned on retry to prevent duplicate orders

  -- OTP (generated after face verification passes)
  otp               VARCHAR(6),
  otp_expires_at    TIMESTAMPTZ,
  otp_verified      BOOLEAN NOT NULL DEFAULT FALSE,

  -- Shared ride config
  max_passengers    SMALLINT NOT NULL DEFAULT 1,
  city              VARCHAR(50) NOT NULL DEFAULT 'Jaipur',

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_rides_status ON rides(status);
CREATE INDEX idx_rides_driver ON rides(driver_id);
CREATE INDEX idx_rides_scheduled ON rides(scheduled_at);
CREATE INDEX idx_rides_city ON rides(city);

-- ============================================================
-- RIDE PASSENGERS
-- One row per passenger per ride
-- ============================================================

CREATE TABLE ride_passengers (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id               UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  passenger_id          UUID NOT NULL REFERENCES users(id),

  -- This passenger's pickup/drop (may differ from ride pickup in shared rides)
  boarding_address      TEXT NOT NULL,
  drop_address          TEXT NOT NULL,

  -- Segment distances for fare split
  exclusive_distance_km NUMERIC(6,2),
  shared_distance_km    NUMERIC(6,2),

  -- Fare for this passenger
  segment_fare          NUMERIC(8,2),
  platform_fee          NUMERIC(8,2),
  total_fare            NUMERIC(8,2),

  -- Face verification for this passenger before boarding
  face_verified_at      TIMESTAMPTZ,
  face_verify_attempts  SMALLINT NOT NULL DEFAULT 0,

  status                passenger_ride_status NOT NULL DEFAULT 'pending',
  boarded_at            TIMESTAMPTZ,
  dropped_at            TIMESTAMPTZ,

  -- Time shift negotiation
  original_scheduled_at TIMESTAMPTZ,
  adjusted_scheduled_at TIMESTAMPTZ,
  time_shift_accepted   BOOLEAN,

  -- Co-passenger rejection tracking
  rejection_count       SMALLINT NOT NULL DEFAULT 0,
  auto_upgraded_private BOOLEAN NOT NULL DEFAULT FALSE,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(ride_id, passenger_id)
);

CREATE INDEX idx_ride_passengers_ride ON ride_passengers(ride_id);
CREATE INDEX idx_ride_passengers_passenger ON ride_passengers(passenger_id);
CREATE INDEX idx_ride_passengers_status ON ride_passengers(status);

-- ============================================================
-- ROUTE DEVIATIONS
-- Recorded when driver goes off expected path during a ride
-- ============================================================

CREATE TABLE route_deviations (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id               UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  detected_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Flat lat/lng (Haversine used for distance calc in JS)
  actual_lat            NUMERIC(10,7) NOT NULL,
  actual_lng            NUMERIC(10,7) NOT NULL,
  deviation_meters      NUMERIC(8,2) NOT NULL,

  status                deviation_status NOT NULL DEFAULT 'detected',
  passenger_alerted_at  TIMESTAMPTZ,
  contacts_alerted_at   TIMESTAMPTZ,
  passenger_response    TEXT,
  resolved_at           TIMESTAMPTZ,

  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_deviations_ride ON route_deviations(ride_id);
CREATE INDEX idx_deviations_status ON route_deviations(status);

-- ============================================================
-- FINES & PENALTIES
-- ============================================================

CREATE TABLE fines (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id),
  ride_id       UUID REFERENCES rides(id),
  type          fine_type NOT NULL,
  amount        NUMERIC(8,2) NOT NULL,
  reason        TEXT NOT NULL,
  status        fine_status NOT NULL DEFAULT 'pending',
  collected_at  TIMESTAMPTZ,
  waived_by     UUID REFERENCES users(id),
  waived_at     TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_fines_user ON fines(user_id);
CREATE INDEX idx_fines_ride ON fines(ride_id);
CREATE INDEX idx_fines_status ON fines(status);

-- ============================================================
-- RATINGS
-- ============================================================

CREATE TABLE ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id     UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  rated_by    UUID NOT NULL REFERENCES users(id),
  rated_user  UUID NOT NULL REFERENCES users(id),
  score       SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
  tags        TEXT[],
  comment     TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE(ride_id, rated_by, rated_user)
);

CREATE INDEX idx_ratings_ride ON ratings(ride_id);
CREATE INDEX idx_ratings_rated_user ON ratings(rated_user);

-- ============================================================
-- OTP LOGS
-- Audit trail only — actual OTP is stored in memory (otpStore)
-- ============================================================

CREATE TABLE otp_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone       VARCHAR(15) NOT NULL,
  purpose     VARCHAR(30) NOT NULL,
  attempts    SMALLINT NOT NULL DEFAULT 0,
  verified    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL
);

-- ============================================================
-- DEVICE TOKENS
-- Stores FCM push-notification tokens per user device.
-- One user can have multiple devices (phone + tablet).
-- Token is upserted on login so it stays current.
-- ============================================================

CREATE TABLE device_tokens (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  fcm_token   TEXT NOT NULL,
  platform    VARCHAR(10) NOT NULL CHECK (platform IN ('android', 'ios')),
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- One token string maps to exactly one row
  UNIQUE(fcm_token)
);

CREATE INDEX idx_device_tokens_user ON device_tokens(user_id) WHERE is_active = TRUE;

-- Auto-update updated_at on token refresh
CREATE TRIGGER update_device_tokens_updated_at
  BEFORE UPDATE ON device_tokens
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE INDEX idx_otp_logs_phone ON otp_logs(phone);

-- ============================================================
-- WALLET TRANSACTIONS
-- ============================================================

CREATE TABLE wallet_transactions (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES users(id),
  amount        NUMERIC(8,2) NOT NULL,
  type          VARCHAR(30) NOT NULL,
  reference_id  UUID,
  balance_after NUMERIC(10,2) NOT NULL,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallet_user ON wallet_transactions(user_id);

-- ============================================================
-- LOCATION HISTORY
-- GPS breadcrumb trail — one row per driver location update
-- during an active ride (status = in_progress).
-- Used for post-ride dispute resolution and route replay.
-- Only written while a ride is in_progress to keep volume manageable.
-- ============================================================

CREATE TABLE location_history (
  id          BIGSERIAL PRIMARY KEY,          -- bigserial for high-volume inserts
  ride_id     UUID NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  driver_id   UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  lat         NUMERIC(10,7) NOT NULL,
  lng         NUMERIC(10,7) NOT NULL,
  heading     NUMERIC(5,2),                   -- degrees 0-360
  speed_kmh   NUMERIC(5,2),
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Partial index — queries always filter by ride_id
CREATE INDEX idx_location_history_ride ON location_history(ride_id, recorded_at DESC);

-- ============================================================
-- PAYMENT ORDERS
-- Stores Razorpay order IDs for wallet top-ups.
-- Prevents duplicate orders when the client retries the order
-- creation endpoint (e.g. after a network timeout).
-- One pending order per user at a time — resolved on verify.
-- ============================================================

CREATE TABLE payment_orders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  order_id    TEXT NOT NULL UNIQUE,          -- Razorpay orderId (order_xxx...)
  amount      NUMERIC(8,2) NOT NULL,
  purpose     VARCHAR(30) NOT NULL DEFAULT 'wallet_topup',
  status      VARCHAR(20) NOT NULL DEFAULT 'pending',  -- pending | completed | failed
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL           -- orders expire after 30 min if uncompleted
);

CREATE INDEX idx_payment_orders_user ON payment_orders(user_id);
CREATE INDEX idx_payment_orders_order_id ON payment_orders(order_id);

-- ============================================================
-- REVOKED TOKENS
-- Stores jti (JWT ID) of invalidated refresh tokens.
-- Checked on every token refresh and on every authenticated request.
-- Rows are safe to prune after expires_at passes.
-- ============================================================

CREATE TABLE revoked_tokens (
  jti         TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  revoked_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL
);

CREATE INDEX idx_revoked_tokens_user ON revoked_tokens(user_id);
CREATE INDEX idx_revoked_tokens_expires ON revoked_tokens(expires_at);

-- ============================================================
-- UTILITY FUNCTIONS
-- Called from the Node.js service layer via supabase.rpc().
-- ============================================================

-- Atomically increment total_rides for multiple users at once.
-- Avoids N+1 queries and race conditions from JS read-modify-write.
CREATE OR REPLACE FUNCTION increment_user_total_rides(p_user_ids UUID[])
RETURNS void AS $$
BEGIN
  UPDATE users SET total_rides = total_rides + 1 WHERE id = ANY(p_user_ids);
END;
$$ LANGUAGE plpgsql;

-- Atomically increment total_trips for a single driver.
CREATE OR REPLACE FUNCTION increment_driver_total_trips(p_driver_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE drivers SET total_trips = total_trips + 1 WHERE id = p_driver_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TRIGGER REGISTRATIONS
-- Wire update_updated_at() to all tables that have updated_at.
-- ============================================================

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_drivers_updated_at
  BEFORE UPDATE ON drivers FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_rides_updated_at
  BEFORE UPDATE ON rides FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_ride_passengers_updated_at
  BEFORE UPDATE ON ride_passengers FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- Supabase enables RLS by default on all tables.
-- We use the service role key in the backend (bypasses RLS),
-- so these policies only matter if you add a frontend that
-- talks to Supabase directly (Day 6+).
-- For now: enable RLS but allow all via service role.
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE ride_passengers ENABLE ROW LEVEL SECURITY;
ALTER TABLE route_deviations ENABLE ROW LEVEL SECURITY;
ALTER TABLE fines ENABLE ROW LEVEL SECURITY;
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;
ALTER TABLE otp_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE revoked_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE location_history ENABLE ROW LEVEL SECURITY;

-- Allow full access via service role (used by backend)
-- These are the default Supabase service role grants — no extra setup needed.
-- If you want to add user-facing policies later, add them here.
