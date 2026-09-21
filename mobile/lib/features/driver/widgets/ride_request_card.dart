import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/ride_request_model.dart';

/// RideRequestCard — shown in the driver home feed for each open ride nearby.
///
/// Displays pickup/drop addresses, distance, fare, passenger count, and
/// payment method. The "Accept" button is the primary CTA.
///
/// onAccept is called with the ride ID — the parent screen handles the
/// API call via driverHomeProvider.acceptRide().

class RideRequestCard extends StatelessWidget {
  final RideRequestModel ride;
  final VoidCallback onAccept;

  const RideRequestCard({
    super.key,
    required this.ride,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: distance + fare + badge ─────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(
              children: [
                // Distance chip
                _Chip(
                  icon: Icons.near_me_outlined,
                  label: ride.distanceLabel,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),

                // Ride type badge
                _Chip(
                  icon: ride.isShared
                      ? Icons.people_outline
                      : Icons.person_outline,
                  label: ride.isShared ? 'Shared' : 'Private',
                  color: ride.isShared
                      ? AppTheme.primary
                      : AppTheme.secondary,
                ),

                const Spacer(),

                // Fare
                Text(
                  ride.fareLabel,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Route ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _RouteColumn(
              pickupAddress: ride.pickupAddress,
              dropAddress: ride.dropAddress,
            ),
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppTheme.divider),

          // ── Footer: payment method + passengers + accept ─────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                // Payment method
                Icon(
                  _paymentIcon(ride.paymentMethod),
                  size: 15,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  ride.paymentLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const SizedBox(width: 12),

                // Passenger count
                const Icon(Icons.person, size: 15, color: AppTheme.textSecondary),
                const SizedBox(width: 3),
                Text(
                  '${ride.passengerCount}/${ride.maxPassengers}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),

                const Spacer(),

                // Accept button
                SizedBox(
                  height: 38,
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _paymentIcon(String method) => switch (method) {
        'upi' => Icons.account_balance_outlined,
        'wallet' => Icons.account_balance_wallet_outlined,
        _ => Icons.payments_outlined,
      };
}

// ── Route column ──────────────────────────────────────────────────────────────

class _RouteColumn extends StatelessWidget {
  final String pickupAddress;
  final String dropAddress;
  const _RouteColumn(
      {required this.pickupAddress, required this.dropAddress});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dot + line + dot indicator
        Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: 2,
              height: 24,
              color: AppTheme.divider,
            ),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),

        // Address texts
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pickupAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                dropAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Small chip ────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
