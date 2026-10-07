import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';
import '../widgets/fare_estimate_card.dart';
import '../widgets/ride_type_selector.dart';

/// RideBookingSheet — bottom sheet shown when user taps "Book a Ride".
///
/// Lets the user:
///   - Switch ride type
///   - Switch payment method
///   - See fare estimate
///   - Confirm booking
class RideBookingSheet extends ConsumerWidget {
  const RideBookingSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final form = ref.watch(bookingFormProvider);
    final bookingState = ref.watch(bookingProvider);
    final notifier = ref.read(bookingProvider.notifier);

    final isBooking = bookingState is BookingInProgress;

    // Navigate to active ride on success
    ref.listen<BookingState>(bookingProvider, (_, next) {
      if (next is BookingSuccess) {
        Navigator.pop(context); // close sheet
        context.push(
          AppRoutes.activeRide.replaceFirst(':rideId', next.ride.id),
        );
      }
    });

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            'Confirm Booking',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),

          const SizedBox(height: 20),

          // Ride type
          const Text('Ride Type',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          RideTypeSelector(
            selected: form.rideType,
            onChanged: notifier.setRideType,
          ),

          const SizedBox(height: 16),

          // Payment method
          const Text('Payment',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _PaymentChip(
                label: 'Cash',
                icon: Icons.money_rounded,
                selected: form.paymentMethod == 'cash',
                onTap: () => notifier.setPaymentMethod('cash'),
              ),
              const SizedBox(width: 8),
              _PaymentChip(
                label: 'UPI',
                icon: Icons.account_balance_wallet_rounded,
                selected: form.paymentMethod == 'upi',
                onTap: () => notifier.setPaymentMethod('upi'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Fare estimate
          if (form.estimate != null)
            FareEstimateCard(estimate: form.estimate)
          else if (form.isEstimating)
            const FareEstimateCard(isLoading: true),

          if (bookingState is BookingError) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(bookingState.message,
                  style: const TextStyle(
                      color: AppTheme.error, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 20),

          // Confirm button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (form.canBook && !isBooking)
                  ? notifier.confirmBooking
                  : null,
              child: isBooking
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white),
                    )
                  : const Text('Confirm Booking'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryLight.withOpacity(0.2)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
