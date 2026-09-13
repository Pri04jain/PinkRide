import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../ride_service.dart';

/// FareEstimateCard — shows the fare breakdown once both locations are set.
///
/// Three visual states:
///   1. Neither location set   → soft placeholder "Set pickup & drop to see fare"
///   2. Estimating (loading)   → shimmer/spinner with "Calculating fare..."
///   3. Estimate loaded        → fare breakdown: subtotal + platform fee = total
///   4. Error                  → error message with retry hint

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
    if (isLoading) return _LoadingCard();
    if (errorMessage != null) return _ErrorCard(message: errorMessage!);
    if (estimate == null) return const _EmptyCard();
    return _EstimateCard(estimate: estimate!);
  }
}

// ── Empty state — no locations set yet ───────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 18, color: AppTheme.textHint),
          SizedBox(width: 10),
          Text(
            'Set pickup & drop to see fare',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }
}

// ── Loading state ─────────────────────────────────────────────────────────────

class _LoadingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
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
          SizedBox(width: 10),
          Text(
            'Calculating fare...',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.error.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline,
              size: 16, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Estimate loaded ───────────────────────────────────────────────────────────

class _EstimateCard extends StatelessWidget {
  final FareEstimate estimate;
  const _EstimateCard({required this.estimate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.primary.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          // Top row: distance + duration + total fare
          Row(
            children: [
              // Distance
              _InfoChip(
                  icon: Icons.straighten,
                  label: estimate.formattedDistance),
              const SizedBox(width: 8),
              // Duration
              _InfoChip(
                  icon: Icons.timer_outlined,
                  label: estimate.formattedDuration),
              const Spacer(),
              // Total fare — big and bold
              Text(
                estimate.formattedFare,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 8),

          // Breakdown row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _BreakdownItem(
                  label: 'Base fare',
                  value: '₹${estimate.subtotal.toStringAsFixed(0)}'),
              _BreakdownItem(
                  label: 'Platform fee',
                  value: '₹${estimate.platformFee.toStringAsFixed(0)}'),
              _BreakdownItem(
                  label: 'Total',
                  value: estimate.formattedFare,
                  bold: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _BreakdownItem extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _BreakdownItem(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
              fontSize: 11, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            color: bold ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}
