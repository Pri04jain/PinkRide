import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data model ────────────────────────────────────────────────────────────────

/// VerificationStatus — represents what the backend returns from
/// GET /verification/status
///
/// Three possible statuses from the backend:
///   'consent_required'      → user hasn't agreed yet
///   'verification_required' → consented but face not registered
///   'verified'              → fully set up, ready to ride
class VerificationStatus {
  final bool faceVerified;
  final bool consentGiven;
  final DateTime? consentGivenAt;
  final String status; // 'consent_required' | 'verification_required' | 'verified'

  const VerificationStatus({
    required this.faceVerified,
    required this.consentGiven,
    required this.status,
    this.consentGivenAt,
  });

  factory VerificationStatus.fromJson(Map<String, dynamic> json) {
    return VerificationStatus(
      faceVerified: json['faceVerified'] as bool? ?? false,
      consentGiven: json['consentGiven'] as bool? ?? false,
      status: json['status'] as String? ?? 'consent_required',
      consentGivenAt: json['consentGivenAt'] != null
          ? DateTime.tryParse(json['consentGivenAt'] as String)
          : null,
    );
  }

  // Convenience getters — used in the UI to decide what to show
  bool get needsConsent => status == 'consent_required';
  bool get needsRegistration => status == 'verification_required';
  bool get isVerified => status == 'verified';
}

// ── VerificationService ───────────────────────────────────────────────────────
//
// Contains all 6 API calls for the face verification feature.
// The provider calls these — screens never call ApiClient directly.
//
// HOW BASE64 WORKS HERE:
// The backend expects the photo as a base64 string (text representation
// of binary data). The camera gives us a File (path on disk).
// We read the file bytes, then call base64Encode() to convert
// bytes → string. That string gets sent in the request body as JSON.
//
// Example:
//   File at /path/to/photo.jpg
//       ↓  File.readAsBytesSync()
//   [255, 216, 255, 224, ...]   ← raw bytes (Uint8List)
//       ↓  base64Encode()
//   "/9j/4AAQSkZJRgAB..."       ← base64 string (safe to put in JSON)

class VerificationService {
  final ApiClient _api;
  const VerificationService(this._api);

  // ── 1. Get current verification status ───────────────────────────────────
  // Called when VerificationStatusScreen opens.
  // Returns what step the user is on.

  Future<VerificationStatus> getStatus() async {
    final data = await _api.get(ApiEndpoints.verificationStatus);
    return VerificationStatus.fromJson(data);
  }

  // ── 2. Record consent ─────────────────────────────────────────────────────
  // Called when user taps "I Agree" on ConsentScreen.
  // Required by DPDP Act before any biometric capture.
  // Must be called before validateFace() will work.

  Future<void> recordConsent() async {
    await _api.post(ApiEndpoints.faceConsent);
  }

  // ── 3. Validate face (Step 1 of registration) ────────────────────────────
  // Sends a base64 photo to the backend.
  // Backend runs liveness check: eyes open, no sunglasses, good pose.
  // Does NOT store the photo — just checks quality.
  // Returns livenessScore (0-100) so the UI can show feedback.
  // The backend keeps the image in memory for 60 seconds for step 2.

  Future<double> validateFace(File photoFile) async {
    // Read the photo file from disk into memory as raw bytes
    final bytes = await photoFile.readAsBytes();

    // Convert bytes to base64 string so it can travel as JSON text
    final base64Image = base64Encode(bytes);

    final data = await _api.post(
      ApiEndpoints.verificationValidate,
      data: {'image': base64Image},
    );

    // Backend returns { validated: true, livenessScore: 99.5 }
    return (data['livenessScore'] as num?)?.toDouble() ?? 0.0;
  }

  // ── 4. Confirm face registration (Step 2 of registration) ────────────────
  // Called immediately after validateFace() succeeds.
  // Backend indexes the face in AWS Rekognition and stores only the faceId.
  // The actual photo is NEVER persisted — only the reference ID.
  // After this call, faceVerified = true on the user's account.

  Future<void> confirmFaceRegistration() async {
    await _api.post(ApiEndpoints.verificationConfirm);
  }

  // ── 5. Verify face for a specific ride (pre-ride check) ──────────────────
  // Called just before the OTP screen during an active ride.
  // Compares the live selfie against the stored faceId.
  // Returns { verified: true/false, attemptsLeft: n }
  // After 5 failed attempts, the backend cancels the ride automatically.

  Future<({bool verified, int attemptsLeft})> verifyForRide({
    required String ridePassengerId,
    required File photoFile,
  }) async {
    final bytes = await photoFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final data = await _api.post(
      ApiEndpoints.verifyForRide(ridePassengerId),
      data: {'image': base64Image},
    );

    return (
      verified: data['verified'] as bool? ?? false,
      attemptsLeft: data['attemptsLeft'] as int? ?? 0,
    );
  }

  // ── 6. Delete face data (right to erasure — DPDP Act) ────────────────────
  // Deletes the face embedding from AWS Rekognition and clears
  // face_embedding_ref + face_verified on the user's account.
  // Can be called from Settings at any time.

  Future<void> deleteFaceData() async {
    await _api.delete('/verification/face-data');
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final verificationServiceProvider = Provider<VerificationService>((ref) {
  return VerificationService(ref.watch(apiClientProvider));
});
