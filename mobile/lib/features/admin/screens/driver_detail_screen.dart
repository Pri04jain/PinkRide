import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../admin_service.dart';

/// DriverDetailScreen — full driver profile for admin review.
///
/// Receives a DriverQueueItem via go_router extra.
/// Shows all documents + vehicle info + face verification status.
/// Admin can: Approve, Reject (with reason), or Suspend.
///
/// Document URLs are shown as links — tapping opens the document
/// in the device browser (url_launcher).

class DriverDetailScreen extends ConsumerStatefulWidget {
  final DriverQueueItem driver;
  const DriverDetailScreen({super.key, required this.driver});

  @override
  ConsumerState<DriverDetailScreen> createState() =>
      _DriverDetailScreenState();
}

class _DriverDetailScreenState
    extends ConsumerState<DriverDetailScreen> {
  bool _approving = false;
  bool _rejecting = false;
  String? _error;

  Future<void> _approve() async {
    setState(() {
      _approving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminServiceProvider)
          .approveDriver(widget.driver.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Driver approved ✓'),
          backgroundColor: AppTheme.success,
        ));
        Navigator.of(context).pop(true); // pop with refresh signal
      }
    } on AppError catch (e) {
      setState(() {
        _approving = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _approving = false;
        _error = 'Failed to approve. Please try again.';
      });
    }
  }

  Future<void> _showRejectDialog() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Application'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Provide a reason (min 10 characters).\n'
              'This will be sent to the driver.',
              style: TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Documents are unclear or expired',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (reasonCtrl.text.trim().length < 10) return;
              Navigator.of(ctx).pop(true);
            },
            style:
                TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _rejecting = true;
      _error = null;
    });
    try {
      await ref
          .read(adminServiceProvider)
          .rejectDriver(widget.driver.id, reasonCtrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Driver rejected'),
          backgroundColor: AppTheme.error,
        ));
        Navigator.of(context).pop(true);
      }
    } on AppError catch (e) {
      setState(() {
        _rejecting = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _rejecting = false;
        _error = 'Failed to reject. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.driver;
    final canAct = d.approvalStatus == 'under_review';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(d.fullName),
        backgroundColor: AppTheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profile header ─────────────────────────────────────────
            _ProfileHeader(driver: d),
            const SizedBox(height: 20),

            // ── Vehicle info ───────────────────────────────────────────
            _Section(
              title: 'Vehicle',
              children: [
                _InfoRow('Number', d.vehicleNumber),
                _InfoRow('Type', d.vehicleType),
                _InfoRow('Make & Model',
                    '${d.vehicleMake} ${d.vehicleModel}'),
                _InfoRow('Color', d.vehicleColor),
                _InfoRow('Year', '${d.vehicleYear}'),
              ],
            ),
            const SizedBox(height: 16),

            // ── License ─────────────────────────────────────────────────
            _Section(
              title: 'License',
              children: [
                _InfoRow('License No.', d.licenseNumber),
              ],
            ),
            const SizedBox(height: 16),

            // ── Documents ───────────────────────────────────────────────
            _Section(
              title: 'Documents',
              children: [
                _DocRow(
                  label: 'License Photo',
                  url: d.licenseDocUrl,
                ),
                _DocRow(
                  label: 'RC (Registration)',
                  url: d.vehicleRcUrl,
                ),
                if (d.vehicleInsuranceUrl != null)
                  _DocRow(
                    label: 'Insurance',
                    url: d.vehicleInsuranceUrl!,
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Rejection reason (if rejected) ──────────────────────────
            if (d.rejectionReason != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.error.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Rejection Reason',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      d.rejectionReason!,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Error ───────────────────────────────────────────────────
            if (_error != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_error!,
                    style: const TextStyle(
                        color: AppTheme.error, fontSize: 13)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Action buttons (only for under_review) ──────────────────
            if (canAct) ...[
              PrimaryButton(
                label: 'Approve Driver',
                icon: Icons.check_circle_outline,
                isLoading: _approving,
                onPressed: _approving || _rejecting ? null : _approve,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      _approving || _rejecting ? null : _showRejectDialog,
                  icon: _rejecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.error),
                        )
                      : const Icon(Icons.cancel_outlined,
                          size: 18, color: AppTheme.error),
                  label: Text(
                    _rejecting ? 'Rejecting...' : 'Reject Application',
                    style: const TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ── Profile header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final DriverQueueItem driver;
  const _ProfileHeader({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person_outline,
              color: AppTheme.primary, size: 32),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    driver.fullName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (driver.faceVerified) ...[
                    const SizedBox(width: 6),
                    const Tooltip(
                      message: 'Face verified',
                      child: Icon(Icons.verified,
                          size: 16, color: AppTheme.success),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '+91 ${driver.phone}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    driver.faceVerified
                        ? Icons.verified_user_outlined
                        : Icons.warning_amber_outlined,
                    size: 13,
                    color: driver.faceVerified
                        ? AppTheme.success
                        : AppTheme.warning,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    driver.faceVerified
                        ? 'Face verified'
                        : 'Face NOT verified — cannot approve',
                    style: TextStyle(
                      fontSize: 12,
                      color: driver.faceVerified
                          ? AppTheme.success
                          : AppTheme.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Section wrapper ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Document row ──────────────────────────────────────────────────────────────

class _DocRow extends StatelessWidget {
  final String label;
  final String url;
  const _DocRow({required this.label, required this.url});

  bool get _isUploaded =>
      url.isNotEmpty && url != 'pending_upload';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            _isUploaded
                ? Icons.check_circle_outline
                : Icons.upload_file_outlined,
            size: 16,
            color: _isUploaded ? AppTheme.success : AppTheme.textHint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
          if (_isUploaded)
            const Text(
              'Uploaded',
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.success,
                  fontWeight: FontWeight.w500),
            )
          else
            const Text(
              'Not uploaded',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textHint),
            ),
        ],
      ),
    );
  }
}
