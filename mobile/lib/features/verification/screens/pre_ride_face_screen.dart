import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../providers/verification_provider.dart';

/// PreRideFaceScreen — identity check just before a ride starts.
///
/// DIFFERENCE FROM FaceRegisterScreen:
///   Registration  → 2 steps (validate + confirm), happens once
///   Pre-ride      → 1 step (verify against stored faceId), happens every ride
///
/// This screen receives ridePassengerId via go_router extra.
/// On success  → navigates to the OTP screen (driver enters OTP to start trip)
/// On failure  → shows attempts remaining (max 5 total)
/// On 0 left   → shows "Ride Cancelled" screen (backend cancelled it)
///
/// The camera setup is identical to FaceRegisterScreen — same
/// CameraController lifecycle, same oval overlay, same capture button.
/// The only difference is what happens after the photo is taken.

class PreRideFaceScreen extends ConsumerStatefulWidget {
  final String ridePassengerId;
  final String rideId; // needed to navigate to OTP screen after verification

  const PreRideFaceScreen({
    super.key,
    required this.ridePassengerId,
    required this.rideId,
  });

  @override
  ConsumerState<PreRideFaceScreen> createState() => _PreRideFaceScreenState();
}

class _PreRideFaceScreenState extends ConsumerState<PreRideFaceScreen> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();

      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError =
            'Could not open camera. Please check camera permissions in Settings.');
      }
    }
  }

  Future<void> _capture() async {
    if (_cameraController == null || !_cameraReady) return;
    if (_cameraController!.value.isTakingPicture) return;

    try {
      final xFile = await _cameraController!.takePicture();
      final photoFile = File(xFile.path);

      // Single step — verify directly against stored faceId
      ref.read(preRideFaceProvider.notifier).verify(
            ridePassengerId: widget.ridePassengerId,
            photoFile: photoFile,
          );
    } catch (e) {
      setState(() => _cameraError = 'Failed to take photo. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen for state changes and navigate accordingly
    ref.listen<PreRideFaceState>(preRideFaceProvider, (_, next) {
      if (next is PreRideVerified) {
        // Face matched — go to OTP screen
        // rideId passed so driver can enter the OTP
        context.pushReplacement(
          AppRoutes.otpEntry,
          extra: {'rideId': widget.rideId},
        );
      }
    });

    final state = ref.watch(preRideFaceProvider);

    return PopScope(
      // Prevent accidental back navigation mid-verification
      // canPop: false means the back button is disabled
      canPop: state is PreRideIdle || state is PreRideFailed,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Confirm Your Identity'),
          elevation: 0,
          // Show back button only when user can actually go back
          automaticallyImplyLeading:
              state is PreRideIdle || state is PreRideFailed,
        ),
        body: _buildBody(state),
      ),
    );
  }

  Widget _buildBody(PreRideFaceState state) {
    // Camera error
    if (_cameraError != null) {
      return _buildErrorView(_cameraError!, canRetry: true, onRetry: () {
        setState(() => _cameraError = null);
        _initCamera();
      });
    }

    // Camera loading
    if (!_cameraReady && state is PreRideIdle) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Opening camera...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    // Ride cancelled — 5 failed attempts
    if (state is PreRideCancelled) {
      return _buildCancelledView();
    }

    // Generic error
    if (state is PreRideError) {
      return _buildErrorView(
        state.message,
        canRetry: true,
        onRetry: () => ref.read(preRideFaceProvider.notifier).retry(),
      );
    }

    // Camera + overlay + bottom panel
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live camera preview
        if (_cameraReady) CameraPreview(_cameraController!),

        // Oval face guide
        CustomPaint(painter: _OvalOverlayPainter()),

        // Attempt counter badge — top right corner
        if (state is PreRideFailed)
          Positioned(
            top: 12,
            right: 16,
            child: _AttemptBadge(attemptsLeft: state.attemptsLeft),
          ),

        // Bottom panel
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomPanel(state),
        ),
      ],
    );
  }

  Widget _buildBottomPanel(PreRideFaceState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.9), Colors.transparent],
        ),
      ),
      child: switch (state) {

        // Ready to capture
        PreRideIdle() => Column(
            children: [
              const Text(
                'Look directly at the camera\nand tap the button below',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              _CaptureButton(onTap: _capture),
            ],
          ),

        // Verifying — spinner
        PreRideVerifying() => const Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text(
                'Verifying your identity...',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ],
          ),

        // Failed — show error + retry
        PreRideFailed(:final message, :final attemptsLeft) => Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.error.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$attemptsLeft attempt${attemptsLeft == 1 ? '' : 's'} remaining',
                style: TextStyle(
                  color: attemptsLeft <= 1
                      ? AppTheme.error
                      : Colors.white54,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Try Again',
                icon: Icons.refresh_rounded,
                onPressed: () =>
                    ref.read(preRideFaceProvider.notifier).retry(),
              ),
            ],
          ),

        // Verified — brief success before navigation kicks in
        PreRideVerified() => const Column(
            children: [
              Icon(Icons.check_circle, color: AppTheme.success, size: 48),
              SizedBox(height: 12),
              Text(
                'Identity confirmed!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

        _ => const SizedBox.shrink(),
      },
    );
  }

  Widget _buildCancelledView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cancel_outlined, color: AppTheme.error, size: 72),
            const SizedBox(height: 20),
            const Text(
              'Ride Cancelled',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Face verification failed 5 times.\nThis ride has been cancelled for safety.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white70, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 32),
            PrimaryButton(
              label: 'Go to Home',
              onPressed: () => context.go(AppRoutes.passengerHome),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(
    String message, {
    required bool canRetry,
    VoidCallback? onRetry,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 15, height: 1.5),
            ),
            if (canRetry && onRetry != null) ...[
              const SizedBox(height: 28),
              PrimaryButton(label: 'Try Again', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Attempt counter badge ─────────────────────────────────────────────────────

class _AttemptBadge extends StatelessWidget {
  final int attemptsLeft;
  const _AttemptBadge({required this.attemptsLeft});

  @override
  Widget build(BuildContext context) {
    final color = attemptsLeft <= 1 ? AppTheme.error : AppTheme.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$attemptsLeft left',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Reused from FaceRegisterScreen (same oval guide + capture button) ─────────

class _OvalOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.black.withOpacity(0.5)
        ..style = PaintingStyle.fill,
    );

    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.70,
      height: size.height * 0.55,
    );

    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.transparent
        ..blendMode = BlendMode.clear,
    );

    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.white.withOpacity(0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CaptureButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CaptureButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
