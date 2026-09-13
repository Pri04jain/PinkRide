import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../providers/verification_provider.dart';

/// ConsentScreen — shown once before any face capture happens.
///
/// WHY THIS SCREEN EXISTS (legal requirement):
/// India's DPDP Act 2025 requires explicit informed consent before
/// collecting any biometric data. "Informed" means the user must
/// understand WHAT is collected, WHY, and HOW it is stored.
/// Without this screen, the entire face verification feature is
/// non-compliant and the app could be taken down.
///
/// What this screen does:
///   1. Explains face verification in plain language
///   2. Lists exactly what is and isn't stored
///   3. User taps "I Agree" → POST /users/face-consent → navigate to camera
///   4. User can tap "Not Now" → goes back (cannot use shared rides without it)
///
/// ref.listen watches ConsentRecorded → navigates to FaceRegisterScreen.

class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate to camera when consent is recorded
    ref.listen<ConsentState>(consentProvider, (_, next) {
      if (next is ConsentRecorded) {
        context.push(AppRoutes.faceRegister);
      }
    });

    final state = ref.watch(consentProvider);
    final isLoading = state is ConsentRecording;
    final errorMessage = state is ConsentError ? state.message : null;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Hero illustration area ─────────────────────────────────
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryLight.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural,
                    size: 60,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Title ──────────────────────────────────────────────────
              const Text(
                'Verify Your Identity',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'PinkRide verifies every passenger before a ride starts. '
                'This keeps everyone on the platform accountable.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // ── What happens section ───────────────────────────────────
              const _SectionTitle('What happens'),
              const SizedBox(height: 12),
              const _StepTile(
                number: '1',
                title: 'Take a selfie',
                subtitle:
                    'You\'ll take a photo using your front camera. Good lighting helps.',
              ),
              const _StepTile(
                number: '2',
                title: 'Liveness check',
                subtitle:
                    'We confirm it\'s a real person — eyes open, face visible, no sunglasses.',
              ),
              const _StepTile(
                number: '3',
                title: 'Before every ride',
                subtitle:
                    'You\'ll take a quick selfie to confirm it\'s you before the trip starts.',
              ),

              const SizedBox(height: 28),
              const Divider(color: AppTheme.divider),
              const SizedBox(height: 20),

              // ── Privacy section ────────────────────────────────────────
              const _SectionTitle('Your privacy'),
              const SizedBox(height: 12),

              const _PrivacyTile(
                icon: Icons.check_circle_outline,
                iconColor: AppTheme.success,
                text: 'Only a face reference ID is stored — never the photo itself.',
              ),
              const _PrivacyTile(
                icon: Icons.check_circle_outline,
                iconColor: AppTheme.success,
                text: 'Your selfie is deleted from our servers immediately after processing.',
              ),
              const _PrivacyTile(
                icon: Icons.check_circle_outline,
                iconColor: AppTheme.success,
                text: 'You can delete your face data at any time from Settings.',
              ),
              const _PrivacyTile(
                icon: Icons.block,
                iconColor: AppTheme.error,
                text: 'Your photo is never shared with drivers or third parties.',
              ),

              const SizedBox(height: 28),
              const Divider(color: AppTheme.divider),
              const SizedBox(height: 20),

              // ── Legal note ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.primary.withOpacity(0.2),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Face verification is required for shared rides. '
                        'Private rides do not require it. '
                        'This feature complies with India\'s DPDP Act 2025.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Error message ──────────────────────────────────────────
              if (errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
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
                            color: AppTheme.error,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Agree button ───────────────────────────────────────────
              PrimaryButton(
                label: 'I Agree — Continue',
                icon: Icons.verified_user_outlined,
                isLoading: isLoading,
                onPressed: () =>
                    ref.read(consentProvider.notifier).recordConsent(),
              ),

              const SizedBox(height: 12),

              // ── Not now button ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text(
                    'Not Now',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Private helper widgets ────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;

  const _StepTile({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbered circle
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _PrivacyTile({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
