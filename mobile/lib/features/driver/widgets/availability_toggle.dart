import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// AvailabilityToggle — the prominent online/offline banner at the top of the
/// driver home screen.
///
/// Shows a large animated switch with a status label and short description.
/// While toggling is in progress it shows a spinner instead of the switch
/// to prevent double-taps.

class AvailabilityToggle extends StatelessWidget {
  final bool isOnline;
  final bool isLoading;
  final VoidCallback onToggle;

  const AvailabilityToggle({
    super.key,
    required this.isOnline,
    required this.isLoading,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isOnline
        ? AppTheme.success.withOpacity(0.08)
        : AppTheme.textHint.withOpacity(0.08);
    final dotColor = isOnline ? AppTheme.success : AppTheme.textHint;
    final label = isOnline ? 'You are Online' : 'You are Offline';
    final sub = isOnline
        ? 'Accepting nearby ride requests'
        : 'Go online to see ride requests';

    return GestureDetector(
      onTap: isLoading ? null : onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isOnline
                ? AppTheme.success.withOpacity(0.3)
                : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            // Animated status dot
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: isOnline
                    ? [
                        BoxShadow(
                          color: AppTheme.success.withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 12),

            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isOnline
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            ),

            // Switch or spinner
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primary,
                ),
              )
            else
              Switch(
                value: isOnline,
                onChanged: (_) => onToggle(),
                activeColor: AppTheme.success,
                inactiveThumbColor: AppTheme.textHint,
                inactiveTrackColor: AppTheme.divider,
              ),
          ],
        ),
      ),
    );
  }
}
