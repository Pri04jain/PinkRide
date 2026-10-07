import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// RideTypeSelector — horizontal chip row for Private / Shared / Women Only Shared.
class RideTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const RideTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _options = [
    ('private',            'Private',   Icons.person_rounded),
    ('shared',             'Shared',    Icons.people_rounded),
    ('women_only_shared',  'Women Only', Icons.female_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _options.map((opt) {
          final (value, label, icon) = opt;
          final isSelected = selected == value;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primary
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: 15,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isSelected
                          ? Colors.white
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
