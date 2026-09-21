import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../models/driver_model.dart';

/// DriverStatsBar — horizontal row of key stats shown below the availability
/// toggle on the driver home screen.
///
/// Displays: total trips, reliability score, cancellations.

class DriverStatsBar extends StatelessWidget {
  final DriverModel driver;

  const DriverStatsBar({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatTile(
          value: '${driver.totalTrips}',
          label: 'Total Trips',
          icon: Icons.route_outlined,
          color: AppTheme.primary,
        ),
        _VerticalDivider(),
        _StatTile(
          value: driver.reliabilityScore.toStringAsFixed(1),
          label: 'Rating',
          icon: Icons.star_outline_rounded,
          color: AppTheme.warning,
        ),
        _VerticalDivider(),
        _StatTile(
          value: '${driver.cancellationCount}',
          label: 'Cancellations',
          icon: Icons.cancel_outlined,
          color: driver.cancellationCount > 5
              ? AppTheme.error
              : AppTheme.textSecondary,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 8);
}
