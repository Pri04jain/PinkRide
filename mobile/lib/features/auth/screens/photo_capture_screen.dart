import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';

/// PhotoCaptureScreen — step 2 of new-user sign-up.
///
/// User takes a selfie with the front camera.
/// A T&C consent sheet must be accepted before the camera opens.
/// Skipping marks the user as unverified — co-passengers will see
/// an "Unverified" badge when browsing shared rides.
///
/// Gallery is intentionally removed — selfie only ensures liveness.
///
/// Navigation:
///   SignUpScreen → PhotoCaptureScreen → RegistrationDetailsScreen

class PhotoCaptureScreen extends ConsumerStatefulWidget {
  final String phone;
  const PhotoCaptureScreen({super.key, required this.phone});

  @override
  ConsumerState<PhotoCaptureScreen> createState() => _PhotoCaptureScreenState();
}

class _PhotoCaptureScreenState extends ConsumerState<PhotoCaptureScreen> {
  final _picker = ImagePicker();
  String? _localPath;
  bool _isProcessing = false;

  // ── Show consent sheet, then open camera ──────────────────────────────────
  Future<void> _requestPhotoWithConsent() async {
    final accepted = await _showConsentSheet();
    if (!accepted) return;
    await _takeSelfie();
  }

  // ── Consent bottom sheet ──────────────────────────────────────────────────
  Future<bool> _showConsentSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _PhotoConsentSheet(),
    );
    return result == true;
  }

  // ── Take selfie (front camera) ────────────────────────────────────────────
  Future<void> _takeSelfie() async {
    setState(() => _isProcessing = true);
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked != null) {
        setState(() => _localPath = picked.path);
        ref.read(photoCaptureProvider.notifier).setPhoto(picked.path);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Navigate to details ───────────────────────────────────────────────────
  void _continue() {
    context.push(
      AppRoutes.registrationDetails,
      extra: {'phone': widget.phone},
    );
  }

  // ── Skip — marks user as unverified ──────────────────────────────────────
  void _skipWithoutVerifying() {
    ref.read(photoCaptureProvider.notifier).clear();
    context.push(
      AppRoutes.registrationDetails,
      extra: {'phone': widget.phone},
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      icon: Icons.camera_alt_rounded,
      title: 'Add Your\nProfile Photo',
      subtitle: 'A selfie helps co-passengers and drivers verify your identity.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // ── Photo preview ─────────────────────────────────────────────────
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 164,
                  height: 164,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF5F5F5),
                    border: Border.all(
                      color: _localPath != null
                          ? AppTheme.primary
                          : AppTheme.divider,
                      width: 3,
                    ),
                  ),
                  child: ClipOval(
                    child: _localPath != null
                        ? Image.file(File(_localPath!), fit: BoxFit.cover)
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_rounded,
                                  size: 72, color: AppTheme.textHint),
                              SizedBox(height: 4),
                              Text('No photo yet',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textHint)),
                            ],
                          ),
                  ),
                ),
                // Retake badge
                if (_localPath != null)
                  GestureDetector(
                    onTap: _requestPhotoWithConsent,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.refresh_rounded,
                          size: 20, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Verification badge hint ───────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _localPath != null
                  ? AppTheme.success.withOpacity(0.1)
                  : AppTheme.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _localPath != null
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  size: 14,
                  color: _localPath != null
                      ? AppTheme.success
                      : AppTheme.warning,
                ),
                const SizedBox(width: 5),
                Text(
                  _localPath != null
                      ? 'Your profile will be Verified'
                      : 'Profile will appear as Unverified',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _localPath != null
                        ? AppTheme.success
                        : AppTheme.warning,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Take selfie button ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _requestPhotoWithConsent,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.camera_alt_rounded, size: 20),
              label: Text(
                _localPath != null ? 'Retake Selfie' : 'Take Selfie',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Continue (if photo taken) ─────────────────────────────────────
          if (_localPath != null) ...[
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: _continue,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Continue',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Skip link ─────────────────────────────────────────────────────
          TextButton(
            onPressed: _skipWithoutVerifying,
            child: const Text(
              'Continue without verifying',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Warning note ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.info_outline_rounded,
                    size: 15, color: AppTheme.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Without a photo, other passengers will see your profile as '
                    'Unverified when you request to share a ride.',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.warning,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Consent bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PhotoConsentSheet extends StatefulWidget {
  const _PhotoConsentSheet();

  @override
  State<_PhotoConsentSheet> createState() => _PhotoConsentSheetState();
}

class _PhotoConsentSheetState extends State<_PhotoConsentSheet> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          const Text(
            'Photo Consent',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 16),

          // Terms
          const _ConsentPoint(
            icon: Icons.people_rounded,
            text:
                'Your photo will be visible to co-passengers and drivers when '
                'you share or book a ride.',
          ),
          const _ConsentPoint(
            icon: Icons.lock_rounded,
            text:
                'Your photo is stored securely and used only for identity '
                'verification within PinkRide.',
          ),
          const _ConsentPoint(
            icon: Icons.block_rounded,
            text:
                'Your photo is never sold, shared with third parties, or used '
                'for advertising.',
          ),
          const _ConsentPoint(
            icon: Icons.delete_outline_rounded,
            text:
                'You can remove your photo at any time from your profile settings.',
          ),

          const SizedBox(height: 20),

          // Checkbox
          GestureDetector(
            onTap: () => setState(() => _agreed = !_agreed),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _agreed ? AppTheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                      color: _agreed ? AppTheme.primary : AppTheme.textHint,
                      width: 1.5,
                    ),
                  ),
                  child: _agreed
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'I have read and agree to PinkRide\'s photo usage terms '
                    'and consent to my photo being shared with co-passengers '
                    'and drivers during rides.',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Buttons
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed:
                  _agreed ? () => Navigator.pop(context, true) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _agreed ? AppTheme.primary : AppTheme.divider,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: const Text('I Agree — Take Photo',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ConsentPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }
}
