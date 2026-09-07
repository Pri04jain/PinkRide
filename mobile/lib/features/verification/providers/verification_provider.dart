import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_error.dart';
import '../../../core/providers/auth_provider.dart';
import '../verification_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// PART 1 — VERIFICATION STATUS
// Loads the current status from the backend when the status screen opens.
// Uses FutureProvider — the simplest Riverpod provider for one-time data loads.
// ════════════════════════════════════════════════════════════════════════════

// FutureProvider automatically handles 3 states for us:
//   loading  → AsyncLoading()   → show a spinner
//   success  → AsyncData(value) → show the status
//   error    → AsyncError(e)    → show an error message
//
// The screen uses ref.watch(verificationStatusProvider) and pattern-matches
// on these three cases. No manual state management needed.

final verificationStatusProvider =
    FutureProvider.autoDispose<VerificationStatus>((ref) {
  // autoDispose means: when the screen is gone, discard the cached result.
  // Next time the screen opens, it fetches fresh data instead of showing stale.
  return ref.watch(verificationServiceProvider).getStatus();
});

// ════════════════════════════════════════════════════════════════════════════
// PART 2 — CONSENT STATE
// ════════════════════════════════════════════════════════════════════════════

sealed class ConsentState {
  const ConsentState();
}

class ConsentIdle extends ConsentState {
  const ConsentIdle();
}

class ConsentRecording extends ConsentState {
  const ConsentRecording();
}

class ConsentRecorded extends ConsentState {
  const ConsentRecorded();
}

class ConsentError extends ConsentState {
  final String message;
  const ConsentError(this.message);
}

// ── ConsentNotifier ───────────────────────────────────────────────────────────
// Handles the single action on ConsentScreen:
// User taps "I Agree" → POST /users/face-consent → navigate to camera

class ConsentNotifier extends StateNotifier<ConsentState> {
  final VerificationService _service;

  ConsentNotifier(this._service) : super(const ConsentIdle());

  Future<void> recordConsent() async {
    state = const ConsentRecording(); // show loading spinner on button

    try {
      await _service.recordConsent();
      state = const ConsentRecorded(); // screen's ref.listen navigates forward
    } on AppError catch (e) {
      state = ConsentError(e.message);
    } catch (_) {
      state = const ConsentError('Failed to record consent. Please try again.');
    }
  }

  void reset() => state = const ConsentIdle();
}

final consentProvider =
    StateNotifierProvider.autoDispose<ConsentNotifier, ConsentState>((ref) {
  return ConsentNotifier(ref.watch(verificationServiceProvider));
});

// ════════════════════════════════════════════════════════════════════════════
// PART 3 — FACE REGISTRATION STATE
// Two-step flow: Validate → Confirm
// ════════════════════════════════════════════════════════════════════════════

// WHY TWO STEPS?
// Step 1 (validate): backend checks the photo quality — is it a real face?
//   eyes open? no sunglasses? good lighting? If yes, it holds the image
//   in memory for 60 seconds.
// Step 2 (confirm): backend indexes the face in AWS Rekognition.
//   Only runs if Step 1 passed. Stores only the faceId reference, never
//   the photo. Marks face_verified = true on the user account.
//
// Splitting into two steps lets us show the user feedback between them
// ("Your face looks good! Tap confirm to register") rather than one long wait.

sealed class FaceRegisterState {
  const FaceRegisterState();
}

// Camera is open, user hasn't taken a photo yet
class FaceRegisterIdle extends FaceRegisterState {
  const FaceRegisterIdle();
}

// Photo taken, waiting for backend liveness check (Step 1)
class FaceValidating extends FaceRegisterState {
  const FaceValidating();
}

// Liveness check passed — show the score and "Confirm" button
class FaceValidated extends FaceRegisterState {
  final double livenessScore; // 0.0 to 100.0
  const FaceValidated(this.livenessScore);
}

// Step 2 in progress — indexing face in Rekognition
class FaceConfirming extends FaceRegisterState {
  const FaceConfirming();
}

// Both steps done — face is registered
class FaceRegistered extends FaceRegisterState {
  const FaceRegistered();
}

// Something went wrong at either step
class FaceRegisterError extends FaceRegisterState {
  final String message;
  final bool canRetry; // if true, show "Try Again" which resets to Idle
  const FaceRegisterError({required this.message, this.canRetry = true});
}

// ── FaceRegisterNotifier ──────────────────────────────────────────────────────

class FaceRegisterNotifier extends StateNotifier<FaceRegisterState> {
  final VerificationService _service;
  final AuthStateNotifier _authNotifier;

  FaceRegisterNotifier(this._service, this._authNotifier)
      : super(const FaceRegisterIdle());

  // ── Step 1: Validate ─────────────────────────────────────────────────────
  // Called when user taps the capture button on the camera screen.
  // photoFile is the File object returned by the camera plugin.

  Future<void> validateFace(File photoFile) async {
    state = const FaceValidating();

    try {
      final livenessScore = await _service.validateFace(photoFile);

      // Liveness score below 70 means the photo quality is too poor
      // (bad lighting, blurry, face not clearly visible)
      if (livenessScore < 70) {
        state = const FaceRegisterError(
          message:
              'Face not clearly visible. Please ensure good lighting and look directly at the camera.',
          canRetry: true,
        );
        return;
      }

      // Good photo — show the score and wait for user to confirm
      state = FaceValidated(livenessScore);
    } on AppError catch (e) {
      state = FaceRegisterError(message: e.message, canRetry: e.isRetryable);
    } catch (_) {
      state = const FaceRegisterError(
        message: 'Failed to process photo. Please try again.',
        canRetry: true,
      );
    }
  }

  // ── Step 2: Confirm ───────────────────────────────────────────────────────
  // Called when user taps "Confirm & Register" after seeing their score.
  // Only valid when state is FaceValidated (liveness check passed).

  Future<void> confirmRegistration() async {
    if (state is! FaceValidated) return; // guard

    state = const FaceConfirming();

    try {
      await _service.confirmFaceRegistration();

      // Update the global AuthState so UserModel.faceVerified = true
      // This means the profile screen and router will reflect the change
      await _authNotifier.refreshProfile();

      state = const FaceRegistered();
    } on AppError catch (e) {
      state = FaceRegisterError(message: e.message, canRetry: false);
    } catch (_) {
      state = const FaceRegisterError(
        message: 'Registration failed. Please contact support.',
        canRetry: false,
      );
    }
  }

  // Reset to idle — user taps "Try Again" after an error
  void retry() => state = const FaceRegisterIdle();
}

final faceRegisterProvider =
    StateNotifierProvider.autoDispose<FaceRegisterNotifier, FaceRegisterState>(
        (ref) {
  return FaceRegisterNotifier(
    ref.watch(verificationServiceProvider),
    ref.read(authStateProvider.notifier),
  );
});

// ════════════════════════════════════════════════════════════════════════════
// PART 4 — PRE-RIDE FACE VERIFICATION STATE
// Same camera flow but calls a different endpoint with ridePassengerId.
// Shows attempt count — user gets 5 tries before the ride is cancelled.
// ════════════════════════════════════════════════════════════════════════════

sealed class PreRideFaceState {
  const PreRideFaceState();
}

class PreRideIdle extends PreRideFaceState {
  const PreRideIdle();
}

class PreRideVerifying extends PreRideFaceState {
  const PreRideVerifying();
}

// Verified successfully — screen navigates to OTP
class PreRideVerified extends PreRideFaceState {
  const PreRideVerified();
}

// Failed but can retry
class PreRideFailed extends PreRideFaceState {
  final String message;
  final int attemptsLeft; // shown to user: "3 attempts remaining"
  const PreRideFailed({required this.message, required this.attemptsLeft});
}

// 5 attempts exhausted — backend cancelled the ride
class PreRideCancelled extends PreRideFaceState {
  const PreRideCancelled();
}

class PreRideError extends PreRideFaceState {
  final String message;
  const PreRideError(this.message);
}

// ── PreRideFaceNotifier ───────────────────────────────────────────────────────

class PreRideFaceNotifier extends StateNotifier<PreRideFaceState> {
  final VerificationService _service;

  PreRideFaceNotifier(this._service) : super(const PreRideIdle());

  Future<void> verify({
    required String ridePassengerId,
    required File photoFile,
  }) async {
    state = const PreRideVerifying();

    try {
      final result = await _service.verifyForRide(
        ridePassengerId: ridePassengerId,
        photoFile: photoFile,
      );

      if (result.verified) {
        state = const PreRideVerified();
        // screen's ref.listen navigates to OTP screen
      } else if (result.attemptsLeft <= 0) {
        // Backend cancelled the ride — no more tries
        state = const PreRideCancelled();
      } else {
        // Failed but can retry
        state = PreRideFailed(
          message:
              'Face did not match. Please ensure you are in good lighting and looking at the camera.',
          attemptsLeft: result.attemptsLeft,
        );
      }
    } on AppError catch (e) {
      // AppError from backend with attemptsLeft embedded in message
      if (e.message.contains('cancelled') || e.statusCode == 403) {
        state = const PreRideCancelled();
      } else {
        state = PreRideError(e.message);
      }
    } catch (_) {
      state = const PreRideError('Verification failed. Please try again.');
    }
  }

  void retry() => state = const PreRideIdle();
}

final preRideFaceProvider =
    StateNotifierProvider.autoDispose<PreRideFaceNotifier, PreRideFaceState>(
        (ref) {
  return PreRideFaceNotifier(ref.watch(verificationServiceProvider));
});
