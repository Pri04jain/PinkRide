import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// PaymentScreen — shown at end of ride for UPI payment or cash confirmation.
class PaymentScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.payment_rounded,
                size: 72, color: AppTheme.primary),
            const SizedBox(height: 24),
            Text(
              '₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'via ${paymentMethod.toUpperCase()}',
              style: const TextStyle(
                  fontSize: 14, color: AppTheme.textSecondary),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () =>
                    context.go('/rating/$rideId'),
                child: const Text('Payment Done'),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  context.go(AppRoutes.passengerHome),
              child: const Text('Skip for now'),
            ),
          ],
        ),
      ),
    );
  }
}
