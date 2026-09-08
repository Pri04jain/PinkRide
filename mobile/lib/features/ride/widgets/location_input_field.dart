import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';

/// LocationInputField — a tappable field for pickup or drop address.
///
/// WHY TAPPABLE AND NOT EDITABLE?
/// A real production app would use Google Places Autocomplete here —
/// the user types and sees a live dropdown of real addresses.
/// That requires the Places API (separate billing from Maps API).
///
/// For now we open a simple dialog that lets the user type an address
/// and manually set coordinates. The pattern is identical to what a
/// real autocomplete would use — we just swap the dialog for a Places
/// widget in a later polish pass without changing the rest of the code.
///
/// The key interface: onLocationSelected(RideLocation) — both the
/// dialog and a real Places widget call the same callback.

class LocationInputField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final Color iconColor;
  final String? value;               // current address text (null = not set)
  final ValueChanged<RideLocation> onLocationSelected;

  const LocationInputField({
    super.key,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.onLocationSelected,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showLocationDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null
                ? AppTheme.primary.withOpacity(0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? hint,
                style: TextStyle(
                  fontSize: 15,
                  color: value != null
                      ? AppTheme.textPrimary
                      : AppTheme.textHint,
                  fontWeight: value != null
                      ? FontWeight.w500
                      : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value != null)
              const Icon(Icons.check_circle,
                  size: 16, color: AppTheme.success),
          ],
        ),
      ),
    );
  }

  // Simple dialog — replace with Google Places in production
  void _showLocationDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationPickerSheet(
        hint: hint,
        onSelected: (loc) {
          Navigator.of(ctx).pop();
          onLocationSelected(loc);
        },
      ),
    );
  }
}

// ── Location picker sheet ─────────────────────────────────────────────────────
// Simple MVP: type address + hardcoded Jaipur landmarks for demo.
// In production: swap for Google Places Autocomplete widget.

class _LocationPickerSheet extends StatefulWidget {
  final String hint;
  final ValueChanged<RideLocation> onSelected;

  const _LocationPickerSheet({
    required this.hint,
    required this.onSelected,
  });

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  final _controller = TextEditingController();

  // Demo landmarks in Jaipur for testing the full flow
  // In production these come from Google Places API suggestions
  static const _suggestions = [
    _Place('Malviya Nagar, Jaipur', 26.8633, 75.8082),
    _Place('Vaishali Nagar, Jaipur', 26.9135, 75.7408),
    _Place('Civil Lines, Jaipur', 26.9264, 75.8184),
    _Place('Mansarovar, Jaipur', 26.8524, 75.7722),
    _Place('C-Scheme, Jaipur', 26.9041, 75.8154),
    _Place('Jawahar Nagar, Jaipur', 26.9217, 75.8031),
    _Place('Raja Park, Jaipur', 26.9063, 75.8291),
    _Place('Tonk Road, Jaipur', 26.8744, 75.8169),
    _Place('MI Road, Jaipur', 26.9220, 75.8216),
    _Place('Jaipur Railway Station', 26.9200, 75.7877),
    _Place('Jaipur International Airport', 26.8242, 75.8122),
    _Place('Amber Fort, Jaipur', 26.9855, 75.8513),
  ];

  List<_Place> _filtered = _suggestions;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      _filtered = query.isEmpty
          ? _suggestions
          : _suggestions
              .where((p) =>
                  p.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              widget.hint,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Search field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Search for an area or landmark',
                prefixIcon: const Icon(Icons.search,
                    color: AppTheme.textHint, size: 20),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Results list
          Expanded(
            child: ListView.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final place = _filtered[i];
                return ListTile(
                  leading: const Icon(Icons.location_on_outlined,
                      color: AppTheme.primary, size: 20),
                  title: Text(
                    place.name,
                    style: const TextStyle(
                        fontSize: 14, color: AppTheme.textPrimary),
                  ),
                  onTap: () => widget.onSelected(
                    RideLocation(
                      lat: place.lat,
                      lng: place.lng,
                      address: place.name,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Simple data class for the hardcoded suggestions
class _Place {
  final String name;
  final double lat;
  final double lng;
  const _Place(this.name, this.lat, this.lng);
}
