import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../ride_service.dart';

/// FareEstimateCard — shows the estimated fare breakdown.
/// Displayed on the home screen once both pickup and drop are set.
class FareEstimateCard extends StatelessWidget {
  final FareEstimate? estimate;
  final bool isLoading;
  final String? errorMessage;

  const FareEstimateCard({
    super.key,
    this.estimate,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(errorMessage!,
            style:
                const TextStyle(color: AppTheme.error, fontSize: 13)),
      );
    }

    if (isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.primary,
              ),
            ),
            SizedBox(width: 12),
            Text('Estimating fare...',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    if (estimate == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          const Icon(Icons.currency_rupee_rounded,
              color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${estimate!.totalFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  '${estimate!.distanceKm.toStringAsFixed(1)} km · '
                  '~${estimate!.durationMinutes} min',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Base ₹${estimate!.baseFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textHint)),
              Text('Fee ₹${estimate!.platformFee.toStringAsFixed(0)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textHint)),
            ],
          ),
        ],
      ),
    );
  }
}
