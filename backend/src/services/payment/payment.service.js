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
    .select('total_fare, rides!inner(id, status, payment_status, payment_method)')
    .eq('ride_id', rideId)
    .eq('passenger_id', userId)
    .single();

  if (error || !rp) throw new AppError('Ride not found.', 404);

  const ride = rp.rides;
  if (ride.status !== 'completed') throw new AppError('Payment is only available after the ride completes.', 400);
  if (ride.payment_status === 'completed') throw new AppError('This ride has already been paid.', 409);
  if (ride.payment_method !== 'upi') throw new AppError('This ride is set to cash payment.', 400);

  const amountPaise = Math.round(parseFloat(rp.total_fare) * 100);

  const rp_client = getRazorpay();
  if (!rp_client) {
    // Mock mode for dev — lets the flow work without real credentials
    return {
      orderId: `order_mock_${Date.now()}`,
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
  getWalletBalance,
  getWalletTransactions,
  collectFine,
  getPendingFines,
};
