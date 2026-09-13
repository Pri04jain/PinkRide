const Razorpay = require('razorpay');
const { supabase } = require('../../shared/db/client');
const { AppError } = require('../../shared/middleware/errorHandler');
const { notify } = require('../notification/fcm.service');

// Razorpay — lazy init so the app starts without credentials in dev
let razorpayClient;

const getRazorpay = () => {
  if (razorpayClient) return razorpayClient;
  const keyId = process.env.RAZORPAY_KEY_ID;
  const keySecret = process.env.RAZORPAY_KEY_SECRET;
  if (!keyId || keyId === 'your_razorpay_key_id') {
    console.warn('[Payment] Razorpay not configured — UPI payments in mock mode.');
    return null;
  }
  razorpayClient = new Razorpay({ key_id: keyId, key_secret: keySecret });
  return razorpayClient;
};

// ─── Create UPI Payment Order ─────────────────────────────────────────────────

const createUpiOrder = async (userId, rideId) => {
  const { data: rp, error } = await supabase
    .from('ride_passengers')
    .select('total_fare, rides!inner(id, status, payment_status, payment_method, payment_order_id)')
    .eq('ride_id', rideId)
    .eq('passenger_id', userId)
    .single();

  if (error || !rp) throw new AppError('Ride not found.', 404);

  const ride = rp.rides;
  if (ride.status !== 'completed') throw new AppError('Payment is only available after the ride completes.', 400);
  if (ride.payment_status === 'completed') throw new AppError('This ride has already been paid.', 409);
  if (ride.payment_method !== 'upi') throw new AppError('This ride is set to cash payment.', 400);

  const amountPaise = Math.round(parseFloat(rp.total_fare) * 100);

  // ── Idempotency: return existing order if one was already created for this ride ──
  if (ride.payment_order_id) {
    return {
      orderId: ride.payment_order_id,
      amount: amountPaise,
      currency: 'INR',
      keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_mock',
      idempotent: true,
    };
  }

  const rp_client = getRazorpay();
  if (!rp_client) {
    const mockOrderId = `order_mock_${Date.now()}`;
    // Store mock order id so retries return the same one
    await supabase.from('rides').update({ payment_order_id: mockOrderId }).eq('id', rideId);
    return {
      orderId: mockOrderId,
      amount: amountPaise,
      currency: 'INR',
      keyId: 'rzp_test_mock',
      dev: true,
    };
  }

  const order = await rp_client.orders.create({
    amount: amountPaise,
    currency: 'INR',
    receipt: `pinkride_${rideId.substring(0, 8)}`,
    notes: { rideId, passengerId: userId },
  });

  // Persist the orderId so retries return this same order
  await supabase.from('rides').update({ payment_order_id: order.id }).eq('id', rideId);

  return {
    orderId: order.id,
    amount: amountPaise,
    currency: 'INR',
    keyId: process.env.RAZORPAY_KEY_ID,
  };
};

// ─── Verify UPI Payment ───────────────────────────────────────────────────────

const verifyUpiPayment = async (userId, rideId, paymentData) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = paymentData;

  const rp_client = getRazorpay();
  if (rp_client) {
    const crypto = require('crypto');
    const expected = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (expected !== razorpay_signature) {
      throw new AppError('Payment verification failed. Invalid signature.', 400);
    }
  }

  return _markRidePaid(userId, rideId, 'upi', razorpay_payment_id);
};

// ─── Confirm Cash Payment ─────────────────────────────────────────────────────

const confirmCashPayment = async (driverUserId, rideId) => {
  const { data, error } = await supabase
    .from('rides')
    .select('id, drivers!inner(user_id)')
    .eq('id', rideId)
    .eq('status', 'completed')
    .single();

  if (error || !data || data.drivers?.user_id !== driverUserId) {
    throw new AppError('Ride not found or you are not the assigned driver.', 404);
  }

  return _markRidePaid(driverUserId, rideId, 'cash', null);
};

// ─── Internal: Mark Ride Paid ─────────────────────────────────────────────────

const _markRidePaid = async (userId, rideId, method, paymentRef) => {
  await supabase
    .from('rides')
    .update({ payment_status: 'completed' })
    .eq('id', rideId);

  // Get passengers for wallet logging
  const { data: passengers } = await supabase
    .from('ride_passengers')
    .select('passenger_id, platform_fee, total_fare')
    .eq('ride_id', rideId);

  for (const row of passengers || []) {
    const { data: user } = await supabase
      .from('users')
      .select('wallet_balance')
      .eq('id', row.passenger_id)
      .single();

    const currentBalance = parseFloat(user?.wallet_balance || 0);

    await supabase.from('wallet_transactions').insert({
      user_id: row.passenger_id,
      amount: -parseFloat(row.total_fare),
      type: 'ride_payment',
      reference_id: rideId,
      balance_after: currentBalance,
      notes: method === 'cash' ? 'Cash payment confirmed by driver' : `UPI payment ref: ${paymentRef}`,
    });

    notify.rideCompleted(row.passenger_id, row.total_fare).catch(console.error);
  }

  return { paid: true, rideId, method };
};

// ─── Wallet Top-up via Razorpay ───────────────────────────────────────────────

/**
 * Step 1 — Create a Razorpay order for the wallet top-up amount.
 * The client uses the returned orderId + keyId to open the Razorpay checkout.
 * Idempotent: if a pending order for this user+amount exists and hasn't expired,
 * returns the existing order instead of creating a new one.
 * In dev/mock mode returns a mock order so the flow works without real money.
 */
const createWalletTopupOrder = async (userId, amount) => {
  const MIN_TOPUP = parseFloat(process.env.WALLET_MIN_TOPUP_INR) || 100;
  if (amount < MIN_TOPUP) {
    throw new AppError(`Minimum top-up is ₹${MIN_TOPUP}.`, 400);
  }

  const amountPaise = Math.round(amount * 100);

  // ── Idempotency: return existing pending order for same user+amount if not expired ──
  const { data: existing } = await supabase
    .from('payment_orders')
    .select('order_id, amount')
    .eq('user_id', userId)
    .eq('purpose', 'wallet_topup')
    .eq('status', 'pending')
    .eq('amount', amount)
    .gte('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing) {
    return {
      orderId: existing.order_id,
      amount: amountPaise,
      currency: 'INR',
      keyId: process.env.RAZORPAY_KEY_ID || 'rzp_test_mock',
      idempotent: true,
    };
  }

  const rp_client = getRazorpay();
  const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString(); // 30 min

  if (!rp_client) {
    const mockOrderId = `order_mock_topup_${Date.now()}`;
    await supabase.from('payment_orders').insert({
      user_id: userId,
      order_id: mockOrderId,
      amount,
      purpose: 'wallet_topup',
      status: 'pending',
      expires_at: expiresAt,
    });
    return {
      orderId: mockOrderId,
      amount: amountPaise,
      currency: 'INR',
      keyId: 'rzp_test_mock',
      dev: true,
    };
  }

  const order = await rp_client.orders.create({
    amount: amountPaise,
    currency: 'INR',
    receipt: `wallet_topup_${userId.substring(0, 8)}_${Date.now()}`,
    notes: { userId, purpose: 'wallet_topup' },
  });

  // Persist so retries return this same order
  await supabase.from('payment_orders').insert({
    user_id: userId,
    order_id: order.id,
    amount,
    purpose: 'wallet_topup',
    status: 'pending',
    expires_at: expiresAt,
  });

  return {
    orderId: order.id,
    amount: amountPaise,
    currency: 'INR',
    keyId: process.env.RAZORPAY_KEY_ID,
  };
};

/**
 * Step 2 — Verify Razorpay signature then credit the wallet.
 * SECURITY: amount is read from payment_orders (set at order-creation time).
 * The client-supplied amount is intentionally ignored — this prevents a user
 * from creating a ₹100 order, paying it, then calling verify with amount=99999.
 */
const verifyWalletTopup = async (userId, paymentData) => {
  const { razorpay_order_id, razorpay_payment_id, razorpay_signature } = paymentData;

  if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
    throw new AppError('Missing Razorpay payment fields.', 400);
  }

  // Fetch the order record — this is the authoritative source of the amount
  const { data: orderRecord, error: orderError } = await supabase
    .from('payment_orders')
    .select('amount, status, user_id')
    .eq('order_id', razorpay_order_id)
    .single();

  if (orderError || !orderRecord) {
    throw new AppError('Payment order not found. Please start a new top-up.', 404);
  }
  if (orderRecord.user_id !== userId) {
    throw new AppError('This payment order does not belong to your account.', 403);
  }
  if (orderRecord.status === 'completed') {
    throw new AppError('This payment has already been processed.', 409);
  }

  const rp_client = getRazorpay();
  if (rp_client) {
    const crypto = require('crypto');
    const expected = crypto
      .createHmac('sha256', process.env.RAZORPAY_KEY_SECRET)
      .update(`${razorpay_order_id}|${razorpay_payment_id}`)
      .digest('hex');

    if (expected !== razorpay_signature) {
      throw new AppError('Payment verification failed. Invalid signature.', 400);
    }
  }

  // Use the server-stored amount — never the client value
  const verifiedAmount = parseFloat(orderRecord.amount);

  const { data: user, error: userError } = await supabase
    .from('users')
    .select('wallet_balance')
    .eq('id', userId)
    .single();

  if (userError || !user) throw new AppError('User not found.', 404);

  const newBalance = parseFloat(user.wallet_balance) + verifiedAmount;

  const { error } = await supabase
    .from('users')
    .update({ wallet_balance: newBalance })
    .eq('id', userId);

  if (error) throw new AppError('Wallet top-up failed.', 500);

  await supabase.from('wallet_transactions').insert({
    user_id: userId,
    amount: verifiedAmount,
    type: 'topup',
    reference_id: null,
    balance_after: newBalance,
    notes: `Wallet top-up via Razorpay — ${razorpay_payment_id}`,
  });

  // Mark order completed so idempotency check ignores it on future calls
  await supabase
    .from('payment_orders')
    .update({ status: 'completed' })
    .eq('order_id', razorpay_order_id);

  return { walletBalance: newBalance, amountCredited: verifiedAmount, paymentId: razorpay_payment_id };
};

// ─── Wallet ───────────────────────────────────────────────────────────────────

const getWalletBalance = async (userId) => {
  const { data } = await supabase
    .from('users')
    .select('wallet_balance')
    .eq('id', userId)
    .single();
  return data?.wallet_balance || 0;
};

const getWalletTransactions = async (userId, limit = 20) => {
  const { data, error } = await supabase
    .from('wallet_transactions')
    .select('id, amount, type, reference_id, balance_after, notes, created_at')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(limit);

  if (error) throw new AppError('Failed to fetch transactions.', 500);
  return data || [];
};

// ─── Fines ────────────────────────────────────────────────────────────────────

const collectFine = async (fineId) => {
  const { data: fine, error } = await supabase
    .from('fines')
    .select('id, user_id, amount, type, reason')
    .eq('id', fineId)
    .eq('status', 'pending')
    .single();

  if (error || !fine) throw new AppError('Fine not found or already collected.', 404);

  const { data: user } = await supabase
    .from('users')
    .select('wallet_balance')
    .eq('id', fine.user_id)
    .single();

  const balance = parseFloat(user?.wallet_balance || 0);
  if (balance < fine.amount) {
    return { collected: false, reason: 'Insufficient wallet balance. Fine remains pending.' };
  }

  const newBalance = balance - fine.amount;

  await supabase.from('users').update({ wallet_balance: newBalance }).eq('id', fine.user_id);
  await supabase.from('fines').update({ status: 'collected', collected_at: new Date().toISOString() }).eq('id', fineId);
  await supabase.from('wallet_transactions').insert({
    user_id: fine.user_id,
    amount: -fine.amount,
    type: 'fine_deduction',
    reference_id: fineId,
    balance_after: newBalance,
    notes: `Fine: ${fine.reason}`,
  });

  notify.fineCharged(fine.user_id, fine.amount, fine.reason).catch(console.error);
  return { collected: true, fineId, amountDeducted: fine.amount, newBalance };
};

const getPendingFines = async (userId) => {
  const { data, error } = await supabase
    .from('fines')
    .select('id, type, amount, reason, status, created_at')
    .eq('user_id', userId)
    .eq('status', 'pending')
    .order('created_at', { ascending: false });

  if (error) throw new AppError('Failed to fetch fines.', 500);
  return data || [];
};

module.exports = {
  createUpiOrder,
  verifyUpiPayment,
  confirmCashPayment,
  createWalletTopupOrder,
  verifyWalletTopup,
  getWalletBalance,
  getWalletTransactions,
  collectFine,
  getPendingFines,
};
