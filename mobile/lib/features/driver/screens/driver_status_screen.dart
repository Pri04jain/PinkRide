import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../models/driver_model.dart';
import '../providers/driver_provider.dart';

/// DriverStatusScreen — shown when a driver's application is not yet approved.
///
/// Covers four sub-states:
///   pending       → Checklist of what's still needed (doc uploads)
///   under_review  → "We're reviewing" holding screen
///   rejected      → Rejection reason + contact support
///   suspended     → Suspension reason + contact support
///
/// Document upload cards appear in 'pending' state, letting the driver
/// upload their license / RC / insurance directly from this screen.

class DriverStatusScreen extends ConsumerWidget {
  const DriverStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(driverHomeProvider);

    // Extract driver from either PendingApproval or Ready states
    final DriverModel? driver = switch (homeState) {
      DriverHomePendingApproval(driver: final d) => d,
      DriverHomeReady(driver: final d) => d,
      _ => null,
    };

    if (driver == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Application Status')),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Application Status')),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: () =>
            ref.read(driverHomeProvider.notifier).loadProfile(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status header
            _StatusHeader(driver: driver),
            const SizedBox(height: 20),

            // Body depends on status
            if (driver.approvalStatus == 'pending')
              _PendingChecklist(driver: driver)
            else if (driver.approvalStatus == 'under_review')
              _UnderReviewBody()
            else if (driver.isRejected)
              _RejectedBody(reason: driver.rejectionReason)
            else if (driver.isSuspended)
              _SuspendedBody(reason: driver.rejectionReason),
          ],
        ),
      ),
    );
  }
}

// ── Status header ─────────────────────────────────────────────────────────────

class _StatusHeader extends StatelessWidget {
  final DriverModel driver;
  const _StatusHeader({required this.driver});

  @override
  Widget build(BuildContext context) {
    final Color statusColor = switch (driver.approvalStatus) {
      'under_review' => AppTheme.warning,
      'approved' => AppTheme.success,
      'rejected' || 'suspended' => AppTheme.error,
      _ => AppTheme.textSecondary,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _statusIcon(driver.approvalStatus),
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver.statusLabel,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  driver.vehicleDisplay,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
        'under_review' => Icons.hourglass_top_rounded,
        'approved' => Icons.verified_rounded,
        'rejected' => Icons.cancel_outlined,
        'suspended' => Icons.block_outlined,
        _ => Icons.pending_outlined,
      };
}

// ── Pending checklist (doc uploads) ──────────────────────────────────────────

class _PendingChecklist extends StatelessWidget {
  final DriverModel driver;
  const _PendingChecklist({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Documents Required',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upload all required documents to submit your\napplication for admin review.',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        _DocUploadCard(
          title: 'Driving License',
          subtitle: 'Front side, clear photo',
          icon: Icons.credit_card_outlined,
          docType: 'license',
          uploaded: driver.hasLicenseDoc,
        ),
        const SizedBox(height: 10),

        _DocUploadCard(
          title: 'Vehicle RC',
          subtitle: 'Registration Certificate',
          icon: Icons.article_outlined,
          docType: 'rc',
          uploaded: driver.hasRcDoc,
        ),
        const SizedBox(height: 10),

        _DocUploadCard(
          title: 'Insurance',
          subtitle: 'Vehicle insurance document (optional)',
          icon: Icons.shield_outlined,
          docType: 'insurance',
          uploaded: driver.hasInsuranceDoc,
          optional: true,
        ),

        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Once license and RC are uploaded, your application moves to review automatically.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Doc upload card ───────────────────────────────────────────────────────────

class _DocUploadCard extends ConsumerWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String docType;
  final bool uploaded;
  final bool optional;

  const _DocUploadCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.docType,
    required this.uploaded,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uploadState = ref.watch(docUploadProvider(docType));
    final isUploading = uploadState is DocUploading;
    final justUploaded = uploadState is DocUploadSuccess;
    final isDone = uploaded || justUploaded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone
              ? AppTheme.success.withOpacity(0.3)
              : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDone
                  ? AppTheme.success.withOpacity(0.1)
                  : AppTheme.primaryLight.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isDone ? Icons.check_circle_outline : icon,
              color: isDone ? AppTheme.success : AppTheme.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Labels
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (optional) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.textHint.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Optional',
                          style: TextStyle(
                              fontSize: 9, color: AppTheme.textHint),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (uploadState is DocUploadError) ...[
                  const SizedBox(height: 2),
                  Text(
                    uploadState.message,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.error),
                  ),
                ],
              ],
            ),
          ),

          // Action
          if (isUploading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            )
          else if (isDone)
            const Icon(Icons.check_circle,
                color: AppTheme.success, size: 24)
          else
            TextButton(
              onPressed: () => _pickAndUpload(context, ref),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
              ),
              child: const Text('Upload',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickAndUpload(
      BuildContext context, WidgetRef ref) async {
    // Show source picker: Camera or Gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Upload $title',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E5F5),
                  child: Icon(Icons.camera_alt_outlined,
                      color: AppTheme.primary),
                ),
                title: const Text('Take a photo'),
                onTap: () =>
                    Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF3E5F5),
                  child: Icon(Icons.photo_library_outlined,
                      color: AppTheme.primary),
                ),
                title: const Text('Choose from gallery'),
                onTap: () =>
                    Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return; // user dismissed

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      imageQuality: 85,   // reduce file size while keeping legibility
      maxWidth: 1600,     // enough resolution for document verification
    );

    if (picked == null) return; // user cancelled picker

    // Upload via the docUploadProvider for this docType
    if (context.mounted) {
      await ref.read(docUploadProvider(docType).notifier).upload(picked.path);

      // After upload succeeds, reload the driver profile so
      // the "uploaded" checkmarks reflect the new state
      final uploadState = ref.read(docUploadProvider(docType));
      if (uploadState is DocUploadSuccess && context.mounted) {
        ref.read(driverHomeProvider.notifier).loadProfile();
      }
    }
  }
}

// ── Under review ──────────────────────────────────────────────────────────────

class _UnderReviewBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.hourglass_top_rounded,
                size: 48,
                color: AppTheme.warning,
              ),
              SizedBox(height: 16),
              Text(
                'Under Review',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Our team is reviewing your documents.\nThis usually takes 1–2 business days.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              SizedBox(height: 20),
              _TimelineItem(
                icon: Icons.check_circle,
                color: AppTheme.success,
                label: 'Application submitted',
                done: true,
              ),
              _TimelineItem(
                icon: Icons.hourglass_top_rounded,
                color: AppTheme.warning,
                label: 'Document verification',
                done: false,
              ),
              _TimelineItem(
                icon: Icons.verified_rounded,
                color: AppTheme.textHint,
                label: 'Account approved',
                done: false,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SupportNote(),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool done;
  const _TimelineItem(
      {required this.icon,
      required this.color,
      required this.label,
      required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: done ? AppTheme.textPrimary : AppTheme.textHint,
              fontWeight:
                  done ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rejected ──────────────────────────────────────────────────────────────────

class _RejectedBody extends StatelessWidget {
  final String? reason;
  const _RejectedBody({this.reason});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.error.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.cancel_outlined,
                      color: AppTheme.error, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Application Rejected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Reason:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SupportNote(),
      ],
    );
  }
}

// ── Suspended ─────────────────────────────────────────────────────────────────

class _SuspendedBody extends StatelessWidget {
  final String? reason;
  const _SuspendedBody({this.reason});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.error.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.error.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.block_outlined,
                      color: AppTheme.error, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'Account Suspended',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.error,
                    ),
                  ),
                ],
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Reason:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  reason!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SupportNote(),
      ],
    );
  }
}

// ── Support note ──────────────────────────────────────────────────────────────

class _SupportNote extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Row(
        children: [
          Icon(Icons.support_agent_outlined,
              size: 20, color: AppTheme.accent),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'For questions, email support@pinkride.in\nor call +91-XXXXXXXXXX.',
              style: TextStyle(
                fontSize: 12,
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
