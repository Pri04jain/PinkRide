import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../providers/verification_provider.dart';
import '../verification_service.dart';

/// VerificationStatusScreen — shows the user's current face verification
/// state and gives them the right action button for their situation.
///
/// THREE POSSIBLE STATES FROM THE BACKEND:
///
///   consent_required      → user hasn't agreed to biometric collection yet
///                           Action: "Set Up Face Verification" → ConsentScreen
///
///   verification_required → consented but selfie not taken yet
///                           Action: "Take Selfie Now" → FaceRegisterScreen
///
///   verified              → fully set up
///                           Action: "Remove Face Data" → delete + refresh
///
/// USES FutureProvider:
/// verificationStatusProvider is a FutureProvider.autoDispose.
/// ref.watch() gives us AsyncValue<VerificationStatus> which has 3 states:
///   AsyncLoading() → show skeleton/spinner
///   AsyncData(status) → show the status UI
///   AsyncError(e, st) → show error with retry button
///
/// WHY FutureProvider AND NOT StateNotifier HERE?
/// We're just loading read-only data once when the screen opens.
/// No user actions change this state directly — actions navigate away
/// to other screens which modify the data. FutureProvider is simpler
/// and cleaner for this one-way read pattern.

class VerificationStatusScreen extends ConsumerWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ref.watch on a FutureProvider returns AsyncValue<T>
    // AsyncValue has 3 cases: loading, data, error
    final asyncStatus = ref.watch(verificationStatusProvider);

    return Scaffold(
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: const Text('Face Verification'),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: asyncStatus.when(
        // ── Loading ────────────────────────────────────────────────────────
        // when() automatically picks the right callback
        loading: () => const _LoadingView(),

        // ── Error ──────────────────────────────────────────────────────────
        error: (error, _) => _ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(verificationStatusProvider),
          // ref.invalidate forces the FutureProvider to re-fetch
          // same as calling the API again — useful for "Try Again" buttons
        ),

        // ── Data ───────────────────────────────────────────────────────────
        data: (status) => _StatusView(status: status),
      ),
    );
  }
}

// ── Status view — the main content ───────────────────────────────────────────

class _StatusView extends ConsumerWidget {
  final VerificationStatus status;
  const _StatusView({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status badge card ────────────────────────────────────────────
          _StatusBadgeCard(status: status),
          const SizedBox(height: 28),

          // ── What this means section ──────────────────────────────────────
          _WhatThisMeansSection(status: status),
          const SizedBox(height: 28),

          // ── Action button ────────────────────────────────────────────────
          _ActionButton(status: status),

          // ── Delete face data (only shown when verified) ──────────────────
          if (status.isVerified) ...[
            const SizedBox(height: 16),
            const _DeleteFaceDataButton(),
          ],

          const SizedBox(height: 32),

          // ── Info footer ──────────────────────────────────────────────────
          const _InfoFooter(),
        ],
      ),
    );
  }
}

// ── Status badge card ─────────────────────────────────────────────────────────

class _StatusBadgeCard extends StatelessWidget {
  final VerificationStatus status;
  const _StatusBadgeCard({required this.status});

  @override
  Widget build(BuildContext context) {
    // Each status maps to a different colour + icon + label
    final (Color color, IconData icon, String label, String description) =
        switch (status.status) {
      'verified' => (
          AppTheme.success,
          Icons.verified_user,
          'Verified',
          'Your identity is confirmed. You can use all PinkRide features.',
        ),
      'verification_required' => (
          AppTheme.warning,
          Icons.face_outlined,
          'Selfie Required',
          'You agreed to face verification but haven\'t taken your selfie yet.',
        ),
      _ => (
          // consent_required
          AppTheme.textSecondary,
          Icons.shield_outlined,
          'Not Set Up',
          'Face verification is not enabled on your account.',
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          // Status icon circle
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
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

// ── What this means section ───────────────────────────────────────────────────

class _WhatThisMeansSection extends StatelessWidget {
  final VerificationStatus status;
  const _WhatThisMeansSection({required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'What this means for you',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),

        // Show different capabilities based on status
        const _CapabilityRow(
          icon: Icons.directions_car_outlined,
          label: 'Private rides',
          available: true,
        ),
        _CapabilityRow(
          icon: Icons.people_outline,
          label: 'Shared rides',
          available: status.isVerified,
        ),
        _CapabilityRow(
          icon: Icons.female,
          label: 'Women-only shared rides',
          available: status.isVerified,
        ),
        _CapabilityRow(
          icon: Icons.verified_user_outlined,
          label: 'Board rides without delay',
          available: status.isVerified,
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool available;

  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.available,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: available ? AppTheme.success : AppTheme.textHint,
          ),
          const SizedBox(width: 12),
          Icon(icon,
              size: 18,
              color: available ? AppTheme.textPrimary : AppTheme.textHint),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: available ? AppTheme.textPrimary : AppTheme.textHint,
              decoration:
                  available ? null : TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Action button — different per status ─────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final VerificationStatus status;
  const _ActionButton({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status.isVerified) {
      // Already verified — no primary action needed
      return const SizedBox.shrink();
    }

    if (status.needsConsent) {
      return PrimaryButton(
        label: 'Set Up Face Verification',
        icon: Icons.face_outlined,
        onPressed: () => context.push(AppRoutes.faceConsent),
      );
    }

    // needsRegistration — consented but no selfie yet
    return PrimaryButton(
      label: 'Take Selfie Now',
      icon: Icons.camera_alt_outlined,
      onPressed: () => context.push(AppRoutes.faceRegister),
    );
  }
}

// ── Delete face data button ───────────────────────────────────────────────────

class _DeleteFaceDataButton extends ConsumerStatefulWidget {
  const _DeleteFaceDataButton();

  @override
  ConsumerState<_DeleteFaceDataButton> createState() =>
      _DeleteFaceDataButtonState();
}

class _DeleteFaceDataButtonState
    extends ConsumerState<_DeleteFaceDataButton> {
  bool _isDeleting = false;

  Future<void> _delete() async {
    // Show a confirmation dialog first — this is irreversible
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Face Data?'),
        content: const Text(
          'This will delete your face verification data permanently. '
          'You will need to register your face again to use shared rides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      await ref.read(verificationServiceProvider).deleteFaceData();
      // Refresh the status so the screen updates
      ref.invalidate(verificationStatusProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove face data. Please try again.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isDeleting ? null : _delete,
        icon: _isDeleting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.error),
              )
            : const Icon(Icons.delete_outline, size: 18),
        label: Text(_isDeleting ? 'Removing...' : 'Remove Face Data'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

// ── Info footer ───────────────────────────────────────────────────────────────

class _InfoFooter extends StatelessWidget {
  const _InfoFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 16, color: AppTheme.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your biometric data is protected under India\'s DPDP Act 2025. '
              'Only a reference ID is stored — never the photo. '
              'You have the right to delete it at any time.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Shimmer-style placeholder for the badge card
          Container(
            width: double.infinity,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFEEEEEE),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const SizedBox(height: 24),
          // Placeholder lines
          ...List.generate(
            4,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                height: 16,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEEEEE),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error view ────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 64, color: AppTheme.textHint),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 28),
            PrimaryButton(label: 'Try Again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
