import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/auth_state.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/primary_button.dart';

/// ProfileSetupScreen — shown once, only to new users after first login.
///
/// Collects:
///   - Full name (text field, min 2 characters)
///   - Gender (chip selector: Female / Male / Other / Prefer not to say)
///   - Date of birth (native date picker — opens the OS date selector)
///   - Role (card selector: Passenger or Driver)
///
/// WHY ROLE SELECTION HERE AND NOT DURING BOOKING?
/// The backend uses role for authorization (passengers can book,
/// drivers can accept rides). It needs to be set before any other flow.
/// Showing it during signup makes the intent clear upfront.
///
/// On submit → calls ProfileSetupNotifier.submit() → navigates to home.

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  // Local state for the three pickers
  String _selectedGender = 'female'; // default matches most users on PinkRide
  String _selectedRole = 'passenger';
  DateTime? _selectedDob;

  // Date formatter — shows "15 May 2000" to the user
  // but we send ISO format "2000-05-15" to the backend
  final _dobFormatter = DateFormat('d MMMM yyyy');

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Date picker ───────────────────────────────────────────────────────────
  // Opens the platform native date picker (iOS: spinner, Android: calendar)
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Reasonable default initial date — 25 years ago
      initialDate: _selectedDob ?? DateTime(now.year - 25, now.month, now.day),
      // Users must be at least 18
      firstDate: DateTime(1940),
      // Can't pick a date in the future or < 18 years ago
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select your date of birth',
      builder: (context, child) {
        // Wrap with Theme to apply PinkRide colours to the date picker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.surface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) setState(() => _selectedDob = picked);
  }

  void _submit() {
    // Flutter's Form validates all FormField children at once
    // Returns true only if every validator returns null
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth.')),
      );
      return;
    }

    ref.read(profileSetupProvider.notifier).submit(
          fullName: _nameController.text.trim(),
          gender: _selectedGender,
          dateOfBirth: _selectedDob!,
          role: _selectedRole,
        );
  }

  @override
  Widget build(BuildContext context) {
    // Navigate when setup is done
    ref.listen<ProfileSetupState>(profileSetupProvider, (_, next) {
      if (next is ProfileSetupDone) {
        // Read the current user to decide which home screen to show
        final authState = ref.read(authStateProvider);
        if (authState is AuthAuthenticated) {
          final user = authState.user;
          if (user.isDriver) {
            context.go(AppRoutes.driverHome);
          } else {
            context.go(AppRoutes.passengerHome);
          }
        } else {
          context.go(AppRoutes.splash);
        }
      }
    });

    final state = ref.watch(profileSetupProvider);
    final isSubmitting = state is ProfileSetupSubmitting;
    final errorMessage =
        state is ProfileSetupError ? state.message : null;

    return AuthLayout(
      icon: Icons.person_outline_rounded,
      title: 'Complete\nYour Profile',
      subtitle: 'Tell us a bit about yourself\nto get started.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Full name ──────────────────────────────────────────────────
            const _SectionLabel('Full Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              decoration: const InputDecoration(
                hintText: 'Priya Sharma',
                prefixIcon: Icon(Icons.person_outline, color: AppTheme.textHint),
              ),
              // validator runs when _formKey.currentState.validate() is called
              validator: (value) {
                if (value == null || value.trim().length < 2) {
                  return 'Please enter your full name (min 2 characters)';
                }
                return null; // null = valid
              },
            ),

            const SizedBox(height: 24),

            // ── Gender selector ────────────────────────────────────────────
            const _SectionLabel('Gender'),
            const SizedBox(height: 10),
            _GenderSelector(
              selected: _selectedGender,
              onChanged: (g) => setState(() => _selectedGender = g),
            ),

            const SizedBox(height: 24),

            // ── Date of birth picker ───────────────────────────────────────
            const _SectionLabel('Date of Birth'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDob,
              // AbsorbPointer prevents the TextFormField from intercepting taps
              // so GestureDetector always handles it
              child: AbsorbPointer(
                child: TextFormField(
                  readOnly: true,
                  decoration: const InputDecoration(
                    hintText: 'Select date of birth',
                    prefixIcon: Icon(Icons.calendar_today_outlined,
                        color: AppTheme.textHint),
                    suffixIcon: Icon(Icons.arrow_drop_down_rounded,
                        color: AppTheme.textHint),
                  ),
                  controller: TextEditingController(
                    text: _selectedDob != null
                        ? _dobFormatter.format(_selectedDob!)
                        : '',
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Role selector ──────────────────────────────────────────────
            const _SectionLabel('I want to'),
            const SizedBox(height: 10),
            _RoleSelector(
              selected: _selectedRole,
              onChanged: (r) => setState(() => _selectedRole = r),
            ),

            const SizedBox(height: 28),

            // ── Error banner ───────────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: errorMessage != null
                  ? Container(
                      key: ValueKey(errorMessage),
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: AppTheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage,
                              style: const TextStyle(
                                  color: AppTheme.error, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(key: ValueKey('no-error')),
            ),

            // ── Submit button ──────────────────────────────────────────────
            PrimaryButton(
              label: 'Get Started',
              icon: Icons.arrow_forward_rounded,
              isLoading: isSubmitting,
              onPressed: _submit,
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────
// Extracted so the main build() method stays readable.
// Private classes (underscore prefix) are only visible in this file.

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }
}

// ── Gender chip selector ──────────────────────────────────────────────────────
// Four chips in a Wrap (wraps to next line on small screens automatically)

class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GenderSelector({
    required this.selected,
    required this.onChanged,
  });

  static const _options = [
    ('female', 'Female', '👩'),
    ('male', 'Male', '👨'),
    ('other', 'Other', '🧑'),
    ('prefer_not_to_say', 'Prefer not to say', '🤐'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options.map((opt) {
        final (value, label, emoji) = opt;
        final isSelected = selected == value;
        return GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryLight.withOpacity(0.3)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Role selector ─────────────────────────────────────────────────────────────
// Two large tappable cards side by side — Passenger or Driver

class _RoleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RoleSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            value: 'passenger',
            label: 'Ride as\nPassenger',
            icon: Icons.directions_walk_rounded,
            selected: selected == 'passenger',
            onTap: () => onChanged('passenger'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            value: 'driver',
            label: 'Drive &\nEarn',
            icon: Icons.drive_eta_rounded,
            selected: selected == 'driver',
            onTap: () => onChanged('driver'),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.value,
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
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryLight.withOpacity(0.2)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
