import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/widgets/primary_button.dart';
import '../providers/verification_provider.dart';

/// FaceRegisterScreen — camera preview + two-step face registration.
///
/// CAMERA PLUGIN LIFECYCLE (important to understand):
///
///   1. Get available cameras list  → cameras[0] is usually the back camera
///                                    cameras[1] is the front (selfie) camera
///   2. Create CameraController     → tells the plugin which camera + resolution
///   3. Initialize controller       → async, must await before showing preview
///   4. Show CameraPreview widget   → live viewfinder
///   5. Call takePicture()          → returns XFile (has a path on disk)
///   6. ALWAYS dispose controller   → releases the camera hardware
///      in dispose() or you get camera "in use" errors on the next screen
///
/// TWO-STEP FLOW:
///
///   Camera open
///       ↓
///   User taps capture button
///       ↓
///   XFile → File → validateFace()   [FaceValidating state]
///       ↓
///   Liveness score shown            [FaceValidated state]
///       ↓
///   User taps "Confirm & Register"
///       ↓
///   confirmRegistration()           [FaceConfirming state]
///       ↓
///   face_verified = true            [FaceRegistered state]
///       ↓
///   Navigate to passenger/driver home

class FaceRegisterScreen extends ConsumerStatefulWidget {
  const FaceRegisterScreen({super.key});

  @override
  ConsumerState<FaceRegisterScreen> createState() => _FaceRegisterScreenState();
}

class _FaceRegisterScreenState extends ConsumerState<FaceRegisterScreen> {
  CameraController? _cameraController;
  bool _cameraReady = false;
  String? _cameraError;
  File? _capturedPhoto; // holds the photo after capture for preview

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    // CRITICAL: always dispose the camera controller.
    // If you don't, the camera stays locked and the next screen
    // that tries to open it will get a "Camera is already in use" error.
    _cameraController?.dispose();
    super.dispose();
  }

  // ── Camera initialisation ─────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      // Get the list of available cameras on this device
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        setState(() => _cameraError = 'No camera found on this device.');
        return;
      }

      // Find the front camera (selfie camera) for face verification
      // Direction.front = selfie camera, Direction.back = rear camera
      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        // Fall back to first available camera if no front camera found
        orElse: () => cameras.first,
      );

      // Create the controller — medium resolution is enough for face capture
      // Higher resolution = larger file = slower upload = no benefit for face ID
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        // Disable audio — we don't need it for photo capture
        enableAudio: false,
        // imageFormatGroup matters for processing — JPEG is universal
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      // Initialize — this is async and must complete before showing preview
      await _cameraController!.initialize();

      // Only update state if the widget is still mounted
      // (user might have navigated away while camera was initializing)
      if (mounted) {
        setState(() => _cameraReady = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cameraError =
            'Could not open camera. Please check camera permissions in Settings.');
      }
    }
  }

  // ── Capture photo ─────────────────────────────────────────────────────────

  Future<void> _capture() async {
    if (_cameraController == null || !_cameraReady) return;
    if (_cameraController!.value.isTakingPicture) return; // prevent double-tap

    try {
      // takePicture() saves the photo to a temp file on disk and returns XFile
      // XFile is a cross-platform file abstraction from the cross_file package
      final xFile = await _cameraController!.takePicture();

      // Convert XFile to dart:io File so we can read its bytes
      final photoFile = File(xFile.path);

      setState(() => _capturedPhoto = photoFile);

      // Kick off Step 1: send to backend for liveness check
      ref.read(faceRegisterProvider.notifier).validateFace(photoFile);
    } catch (e) {
      setState(() =>
          _cameraError = 'Failed to take photo. Please try again.');
    }
  }

  // ── Retry — reset everything back to camera ───────────────────────────────

  void _retry() {
    setState(() => _capturedPhoto = null);
    ref.read(faceRegisterProvider.notifier).retry();
  }

  @override
  Widget build(BuildContext context) {
    // Navigate away when registration is complete
    ref.listen<FaceRegisterState>(faceRegisterProvider, (_, next) {
      if (next is FaceRegistered) {
        // Capture router before the async gap to satisfy use_build_context_synchronously
        final router = GoRouter.of(context);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) router.go(AppRoutes.passengerHome);
        });
      }
    });

    final state = ref.watch(faceRegisterProvider);

    return Scaffold(
      backgroundColor: Colors.black, // full black for camera screens
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Register Your Face'),
        elevation: 0,
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(FaceRegisterState state) {
    // ── Camera error ───────────────────────────────────────────────────────
    if (_cameraError != null) {
      return _ErrorView(
        message: _cameraError!,
        onRetry: () {
          setState(() => _cameraError = null);
          _initCamera();
        },
      );
    }

    // ── Camera loading ─────────────────────────────────────────────────────
    if (!_cameraReady) {
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

    // ── Registration complete ──────────────────────────────────────────────
    if (state is FaceRegistered) {
      return const _SuccessView();
    }

    // ── Error after capture ────────────────────────────────────────────────
    if (state is FaceRegisterError) {
      return _ErrorView(
        message: state.message,
        onRetry: state.canRetry ? _retry : null,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Camera preview or captured photo ────────────────────────────
        _capturedPhoto != null
            ? Image.file(_capturedPhoto!, fit: BoxFit.cover)
            : CameraPreview(_cameraController!),

        // ── Face oval guide overlay ──────────────────────────────────────
        // Helps user position their face correctly
        CustomPaint(
          painter: _OvalOverlayPainter(),
        ),

        // ── Bottom panel ─────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomPanel(
            state: state,
            capturedPhoto: _capturedPhoto,
            onCapture: _capture,
            onConfirm: () =>
                ref.read(faceRegisterProvider.notifier).confirmRegistration(),
            onRetry: _retry,
          ),
        ),
      ],
    );
  }
}

// ── Bottom panel — changes based on state ────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  final FaceRegisterState state;
  final File? capturedPhoto;
  final VoidCallback onCapture;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;

  const _BottomPanel({
    required this.state,
    required this.capturedPhoto,
    required this.onCapture,
    required this.onConfirm,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.9),
            Colors.transparent,
          ],
        ),
      ),
      child: switch (state) {

        // ── Idle: show instructions + capture button ─────────────────────
        FaceRegisterIdle() => Column(
            children: [
              const Text(
                'Position your face inside the oval\nand look directly at the camera',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 24),
              _CaptureButton(onTap: onCapture),
            ],
          ),

        // ── Validating: photo taken, liveness check in progress ──────────
        FaceValidating() => const Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text(
                'Checking your photo...',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                'Checking lighting, face position and liveness',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),

        // ── Validated: show score + confirm button ───────────────────────
        FaceValidated(:final livenessScore) => Column(
            children: [
              // Score pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.success, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle,
                        color: AppTheme.success, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      'Photo quality: ${livenessScore.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Looks good! Tap confirm to register your face.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  // Retake button
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: onRetry,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white38),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Confirm button
                  Expanded(
                    flex: 2,
                    child: PrimaryButton(
                      label: 'Confirm & Register',
                      onPressed: onConfirm,
                    ),
                  ),
                ],
              ),
            ],
          ),

        // ── Confirming: indexing face in Rekognition ─────────────────────
        FaceConfirming() => const Column(
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text(
                'Registering your face...',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                'This only takes a moment',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),

        // ── All other states — shouldn't show bottom panel ───────────────
        _ => const SizedBox.shrink(),
      },
    );
  }
}

// ── Capture button — large circular shutter button ───────────────────────────

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

// ── Oval overlay painter — draws a face guide on top of the camera ────────────

class _OvalOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Draw a dark overlay over the full screen
    canvas.drawRect(Offset.zero & size, paint);

    // Cut out an oval in the center — this is where the face should go
    // The oval is 70% of the screen width and 55% of the screen height
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.42),
      width: size.width * 0.70,
      height: size.height * 0.55,
    );

    // BlendMode.clear "erases" the overlay inside the oval
    // showing the camera preview through
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.transparent
        ..blendMode = BlendMode.clear,
    );

    // Draw a white border around the oval
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

// ── Success view — full screen green confirmation ─────────────────────────────

class _SuccessView extends StatelessWidget {
  const _SuccessView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user, color: AppTheme.success, size: 80),
          SizedBox(height: 20),
          Text(
            'Face Registered!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Your identity is verified.\nYou can now book shared rides.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── Error view — shown on camera failure or registration error ────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorView({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
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
            if (onRetry != null) ...[
              const SizedBox(height: 28),
              PrimaryButton(label: 'Try Again', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
