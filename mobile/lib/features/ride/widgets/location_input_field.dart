import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';

/// LocationInputField — a tappable field for pickup or drop location.
/// Tapping it opens a search/autocomplete flow (placeholder for now).
class LocationInputField extends StatelessWidget {
  final String hint;
  final String? value;
  final IconData icon;
  final Color iconColor;
  /// Called when the field is tapped — no argument version.
  final VoidCallback? onTap;
  /// Called when a location is selected — used by passenger_home_screen.
  final ValueChanged<RideLocation>? onLocationSelected;

  const LocationInputField({
    super.key,
    required this.hint,
    this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
    this.onLocationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {
        // When onLocationSelected is provided, tapping opens a search dialog.
        // For now this is a placeholder — full implementation uses a
        // Places/Geocoding API or map tap to produce a RideLocation.
        // The callback is wired but the picker UI is not yet built.
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: value != null && value!.isNotEmpty
                  ? Text(
                      value!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      hint,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textHint,
                      ),
                    ),
            ),
            if (value != null && value!.isNotEmpty)
              const Icon(Icons.edit_rounded,
                  size: 14, color: AppTheme.textHint),
          ],
        ),
      ),
    );
  }
}
