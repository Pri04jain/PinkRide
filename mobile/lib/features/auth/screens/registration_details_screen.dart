import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/primary_button.dart';

/// RegistrationDetailsScreen — step 2 of new-user onboarding.
///
/// Collects:
///   - Full name        (required, min 2 chars)
///   - Phone number     (pre-filled, read-only — already verified via OTP)
///   - Email address    (optional)
///   - Gender           (chip selector)
///   - Date of birth    (date picker, must be ≥ 18)
///   - Role             (Passenger or Driver card)
///
/// Shows a circular photo preview at the top if the user took one on
/// PhotoCaptureScreen (reads from [photoCaptureProvider]).
///
/// On submit → calls [ProfileSetupNotifier.submit] → POST /users/register
///           → [authStateProvider] refreshes → router redirects to home.

class RegistrationDetailsScreen extends ConsumerStatefulWidget {
  final String phone;

  const RegistrationDetailsScreen({super.key, required this.phone});

  @override
  ConsumerState<RegistrationDetailsScreen> createState() =>
      _RegistrationDetailsScreenState();
}

class _RegistrationDetailsScreenState
    extends ConsumerState<RegistrationDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController  = TextEditingController();
  final _emailController = TextEditingController();

  String _gender   = 'female';
  String _role     = 'passenger';
  DateTime? _dob;

  final _dobFormatter = DateFormat('d MMMM yyyy');

  @override
  void initState() {
    super.initState();
    // Explicitly clear — ensures no stale text from previous sessions
    _nameController.clear();
    _emailController.clear();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  // ── Date picker ────────────────────────────────────────────────────────────
  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 22, now.month, now.day),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 18, now.month, now.day),
      helpText: 'Select your date of birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppTheme.primary,
            onPrimary: Colors.white,
            surface: AppTheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  // ── Submit ─────────────────────────────────────────────────────────────────
  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth.')),
      );
      return;
    }

    final photoPath = ref.read(photoCaptureProvider); // ignore: unused_local_variable

    ref.read(profileSetupProvider.notifier).submit(
          fullName:        _nameController.text.trim(),
          gender:          _gender,
          dateOfBirth:     _dob!,
          role:            _role,
          email:           _emailController.text.trim().isEmpty
                               ? null
                               : _emailController.text.trim(),
          // In production, upload the photo to Supabase Storage first, then
          // pass the returned URL. For now we pass null (local file is kept
          // in photoCaptureProvider for display only).
          profilePhotoUrl: null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final photoPath    = ref.watch(photoCaptureProvider);
    final setupState   = ref.watch(profileSetupProvider);
    final isSubmitting = setupState is ProfileSetupSubmitting;
    final errorMessage = setupState is ProfileSetupError ? setupState.message : null;

    // Route to home once done — router redirect takes over from splash
    ref.listen<ProfileSetupState>(profileSetupProvider, (_, next) {
      if (next is ProfileSetupDone) context.go(AppRoutes.splash);
    });

    return AuthLayout(
      icon: Icons.person_outline_rounded,
      title: 'Complete\nYour Profile',
      subtitle: 'Just a few more details and you\'re ready to ride.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Photo avatar preview ────────────────────────────────────────
            if (photoPath != null) ...[
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary, width: 2.5),
                  ),
                  child: ClipOval(
                    child: Image.file(File(photoPath), fit: BoxFit.cover),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ] else
              const SizedBox(height: 8),

            // ── Full name ───────────────────────────────────────────────────
            _Label('Full Name'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'e.g. Priya Sharma',
                prefixIcon: Icon(Icons.person_outline, color: AppTheme.textHint),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Please enter your full name'
                  : null,
            ),

            const SizedBox(height: 20),

            // ── Phone (pre-filled, locked — already verified via OTP) ──────
            _Label('Phone Number'),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      size: 18, color: AppTheme.textHint),
                  const SizedBox(width: 12),
                  Text(
                    '+91  ${widget.phone}',
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.verified_rounded,
                      color: AppTheme.success, size: 18),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Email ───────────────────────────────────────────────────────
            _Label('Email Address  (optional)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'priya@example.com',
                prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textHint),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return null; // optional
                final emailReg = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                if (!emailReg.hasMatch(v.trim())) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
            ),

            const SizedBox(height: 20),

            // ── Gender ──────────────────────────────────────────────────────
            _Label('Gender'),
            const SizedBox(height: 10),
            _GenderSelector(
              selected: _gender,
              onChanged: (g) => setState(() => _gender = g),
            ),

            const SizedBox(height: 20),

            // ── Date of birth ───────────────────────────────────────────────
            _Label('Date of Birth'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDob,
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
                    text: _dob != null ? _dobFormatter.format(_dob!) : '',
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── Role ────────────────────────────────────────────────────────
            _Label('I want to'),
            const SizedBox(height: 10),
            _RoleSelector(
              selected: _role,
              onChanged: (r) => setState(() => _role = r),
            ),

            const SizedBox(height: 28),

            // ── Error banner ────────────────────────────────────────────────
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

            // ── Submit ──────────────────────────────────────────────────────
            PrimaryButton(
              label: 'Create Account',
              icon: Icons.check_rounded,
              isLoading: isSubmitting,
              onPressed: _submit,
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }
}

// ── Gender chip selector ──────────────────────────────────────────────────────
class _GenderSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _GenderSelector({required this.selected, required this.onChanged});

  static const _options = [
    ('female',            'Female',             '👩'),
    ('male',              'Male',               '👨'),
    ('other',             'Other',              '🧑'),
    ('prefer_not_to_say', 'Prefer not to say',  '🤐'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _options.map((opt) {
        final (value, label, emoji) = opt;
        final active = selected == value;
        return GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primaryLight.withOpacity(0.25)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? AppTheme.primary : Colors.transparent,
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
                    fontWeight:
                        active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? AppTheme.primary : AppTheme.textSecondary,
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
class _RoleSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _RoleSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            icon: Icons.directions_walk_rounded,
            label: 'Ride as\nPassenger',
            active: selected == 'passenger',
            onTap: () => onChanged('passenger'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            icon: Icons.drive_eta_rounded,
            label: 'Drive\n& Earn',
            active: selected == 'driver',
            onTap: () => onChanged('driver'),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.active,
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
          color: active
              ? AppTheme.primaryLight.withOpacity(0.2)
              : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppTheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                size: 32,
                color: active ? AppTheme.primary : AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppTheme.primary : AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
