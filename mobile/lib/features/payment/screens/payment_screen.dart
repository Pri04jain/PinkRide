import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/models/app_error.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../payment_service.dart';

/// PaymentScreen — post-ride payment.
///
/// Receives rideId + paymentMethod ('cash' | 'upi') via go_router extra.
///
/// CASH flow:
///   Simple screen — shows amount, "Confirm Cash Payment" button.
///   Driver taps → POST /payments/rides/:rideId/cash/confirm → done.
///   (In real app this is on the driver side — here it's simplified.)
///
/// UPI flow:
///   1. POST /payments/rides/:rideId/upi/order → get orderId + keyId
///   2. Open Razorpay checkout (native sheet via razorpay_flutter plugin)
///   3. Razorpay calls back with success/failure/external-wallet
///   4. On success: POST /payments/rides/:rideId/upi/verify → done
///
/// WHY RAZORPAY USES CALLBACKS (not async/await)?
/// Razorpay opens a native payment sheet (bottom sheet from the OS).
/// The app goes to background while the user pays.
/// When payment completes, the OS brings the app back and Razorpay
/// fires a callback. There's no "await" because the user might take
/// minutes to complete the payment. We register handlers with
/// _razorpay.on() and clean up with _razorpay.clear() in dispose().

class PaymentScreen extends ConsumerStatefulWidget {
  final String rideId;
  final String paymentMethod;
  final double amount;

  const PaymentScreen({
    super.key,
    required this.rideId,
    required this.paymentMethod,
    required this.amount,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _razorpay = Razorpay();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Register Razorpay callback handlers
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    // IMPORTANT: always clear Razorpay listeners on dispose
    // or they fire on a dead widget
    _razorpay.clear();
    super.dispose();
  }

  // ── Cash payment ──────────────────────────────────────────────────────────

  Future<void> _confirmCash() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(paymentServiceProvider)
          .confirmCashPayment(widget.rideId);
      if (mounted) _navigateToRating();
    } on AppError catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Payment confirmation failed. Please try again.';
      });
    }
  }

  // ── UPI payment ───────────────────────────────────────────────────────────

  Future<void> _startUpiPayment() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final order = await ref
          .read(paymentServiceProvider)
          .createUpiOrder(widget.rideId);

      // In dev/mock mode, skip Razorpay and go straight to verify
      if (order.isMock) {
        await ref.read(paymentServiceProvider).verifyUpiPayment(
          widget.rideId,
          {
            'razorpay_order_id': order.orderId,
            'razorpay_payment_id': 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
            'razorpay_signature': 'mock_signature',
          },
        );
        if (mounted) _navigateToRating();
        return;
      }

      // Real mode — open Razorpay checkout sheet
      final user = ref.read(currentUserProvider);
      final options = {
        'key': order.keyId,
        'amount': order.amountPaise,
        'currency': order.currency,
        'name': 'PinkRide',
        'description': 'Ride payment',
        'order_id': order.orderId,
        'prefill': {
          'contact': user?.phone ?? '',
        },
        'theme': {'color': '#E91E8C'},
      };

      setState(() => _loading = false); // spinner off before Razorpay opens
      _razorpay.open(options);
    } on AppError catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = 'Could not create payment order. Please try again.';
      });
    }
  }

  // ── Razorpay callbacks ────────────────────────────────────────────────────

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(paymentServiceProvider).verifyUpiPayment(
        widget.rideId,
        {
          'razorpay_order_id': response.orderId ?? '',
          'razorpay_payment_id': response.paymentId ?? '',
          'razorpay_signature': response.signature ?? '',
        },
      );
      if (mounted) _navigateToRating();
    } on AppError catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() {
      _loading = false;
      _error = response.message ?? 'Payment failed. Please try again.';
    });
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // External wallet (e.g. Paytm) selected — treat as pending
    setState(() {
      _loading = false;
      _error = 'External wallet payment initiated. '
          'Please complete in your wallet app.';
    });
  }

  void _navigateToRating() {
    context.pushReplacement(
      AppRoutes.rating.replaceAll(':rideId', widget.rideId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUpi = widget.paymentMethod == 'upi';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Amount card ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  const Text(
                    'Amount Due',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${widget.amount.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isUpi ? 'Pay via UPI' : 'Pay cash to your driver',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Payment method info ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isUpi
                          ? Icons.phone_android_rounded
                          : Icons.payments_outlined,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUpi ? 'UPI Payment' : 'Cash Payment',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          isUpi
                              ? 'PhonePe, GPay, Paytm, or any UPI app'
                              : 'Hand the cash directly to your driver',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Error ────────────────────────────────────────────────────
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 13)),
                    ),
                  ],
                ),
              ),

            // ── Action button ────────────────────────────────────────────
            PrimaryButton(
              label: isUpi
                  ? 'Pay ₹${widget.amount.toStringAsFixed(0)} via UPI'
                  : 'Confirm Cash Payment',
              icon: isUpi ? Icons.launch_rounded : Icons.check_circle_outline,
              isLoading: _loading,
              onPressed: isUpi ? _startUpiPayment : _confirmCash,
            ),

            const SizedBox(height: 12),

            // ── Skip for now ─────────────────────────────────────────────
            Center(
              child: TextButton(
                onPressed: () => _navigateToRating(),
                child: const Text(
                  'Skip for now',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
