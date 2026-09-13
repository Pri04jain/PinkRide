import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// RideTypeSelector — three horizontally scrolling chips for ride type.
///
/// Three types match the backend enum exactly:
///   private          → just you, higher fare
///   shared           → share with another passenger, split fare
///   women_only_shared → shared but only matched with women passengers

class RideTypeSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const RideTypeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _types = [
    _RideType('private', 'Private', Icons.person, 'Just you'),
    _RideType('shared', 'Shared', Icons.people, 'Split fare'),
    _RideType('women_only_shared', 'Women Only', Icons.female, 'Safe share'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ride type',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _types.map((type) {
            final isSelected = selected == type.value;
            return Expanded(
              child: GestureDetector(
                onTap: () => onChanged(type.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryLight.withOpacity(0.25)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primary
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        type.icon,
                        size: 20,
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        type.subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textHint,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _RideType {
  final String value;
  final String label;
  final IconData icon;
  final String subtitle;
  const _RideType(this.value, this.label, this.icon, this.subtitle);
}
