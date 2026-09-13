import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/app_error.dart';
import '../../../core/providers/auth_provider.dart';
import '../auth_service.dart';

// ── OTP Flow State ──────────────────────────────────────────────────────────
// Represents every possible state of the phone → OTP screen pair.
//
// WHY A SEALED CLASS AGAIN (not just a bool isLoading)?
// The OTP flow has 5 distinct states and the UI needs to render
// something different for each one. Tracking them with multiple booleans
// leads to impossible combinations (e.g. isSending=true AND isVerified=true).
// A sealed class makes each state explicit and mutually exclusive.

sealed class OtpFlowState {
  const OtpFlowState();
}

// User is on the phone input screen, nothing happening yet
class OtpIdle extends OtpFlowState {
  const OtpIdle();
}

// Waiting for the backend to send the OTP
class OtpSending extends OtpFlowState {
  const OtpSending();
}

// OTP was sent — now show the OTP input screen
// We keep the phone here so OtpVerifyScreen can display it
class OtpSent extends OtpFlowState {
  final String phone;
  final String countryCode;
  const OtpSent({required this.phone, required this.countryCode});
}

// Waiting for the backend to verify the OTP the user typed
class OtpVerifying extends OtpFlowState {
  const OtpVerifying();
}

// OTP verified — session established
// isNewUser tells the router whether to go to profile setup or home
class OtpVerified extends OtpFlowState {
  final bool isNewUser;
  const OtpVerified({required this.isNewUser});
}

// Something went wrong — show this message to the user
class OtpError extends OtpFlowState {
  final String message;
  final bool isRetryable;
  const OtpError({required this.message, this.isRetryable = true});
}

// ── OtpFlowNotifier ─────────────────────────────────────────────────────────

class OtpFlowNotifier extends StateNotifier<OtpFlowState> {
  final AuthService _authService;
  final AuthStateNotifier _authNotifier;

  OtpFlowNotifier(this._authService, this._authNotifier)
      : super(const OtpIdle());

  // ── Step 1: Request OTP ──────────────────────────────────────────────────
  // Called when user taps "Send OTP" on PhoneInputScreen.
  // Validates the phone number first, then calls the backend.

  Future<void> requestOtp({
    required String phone,
    required String countryCode,
  }) async {
    // Basic validation before hitting the network
    if (phone.length != 10) {
      state = const OtpError(
        message: 'Please enter a valid 10-digit mobile number.',
        isRetryable: false,
      );
      return;
    }

    state = const OtpSending();

    try {
      await _authService.requestOtp(phone: phone, countryCode: countryCode);
      state = OtpSent(phone: phone, countryCode: countryCode);
    } on AppError catch (e) {
      state = OtpError(message: e.message, isRetryable: e.isRetryable);
    } catch (_) {
      state = const OtpError(message: 'Failed to send OTP. Please try again.');
    }
  }

  // ── Step 2: Verify OTP ───────────────────────────────────────────────────
  // Called when user enters all 6 digits on OtpVerifyScreen.
  // On success: calls authNotifier.login() to establish the session,
  // then transitions to OtpVerified so the router can navigate.

  Future<void> verifyOtp({required String otp}) async {
    final current = state;
    // Guard: can only verify if we're in OtpSent state
    if (current is! OtpSent) return;

    if (otp.length != 6) {
      state = const OtpError(
        message: 'Please enter the complete 6-digit OTP.',
        isRetryable: false,
      );
      return;
    }

    state = const OtpVerifying();

    try {
      final result = await _authService.verifyOtp(
        phone: current.phone,
        countryCode: current.countryCode,
        otp: otp,
      );

      // Establish session in the core auth provider
      // This triggers AppRouter's redirect to run again
      await _authNotifier.login(
        accessToken: result.accessToken,
        refreshToken: result.refreshToken,
        userJson: result.user,
      );

      state = OtpVerified(isNewUser: result.isNewUser);
    } on AppError catch (e) {
      // Stay in OtpSent-equivalent so user can retry
      // We re-emit OtpSent so the screen stays on the OTP input
      state = OtpError(message: e.message, isRetryable: e.isRetryable);
    } catch (_) {
      state = const OtpError(message: 'Verification failed. Please try again.');
    }
  }

  // ── Resend OTP ───────────────────────────────────────────────────────────
  // Called when user taps "Resend" after the countdown expires.
  // Only valid when we already have the phone number (OtpSent or OtpError after sent).

  Future<void> resendOtp() async {
    // Find the phone we sent to — could be in OtpSent or OtpError state
    final OtpSent? sentState = switch (state) {
      OtpSent() => state as OtpSent,
      _ => null,
    };

    if (sentState == null) return;

    await requestOtp(
      phone: sentState.phone,
      countryCode: sentState.countryCode,
    );
  }

  // ── Reset ────────────────────────────────────────────────────────────────
  // Called when user taps "Change number" — goes back to phone input.

  void reset() => state = const OtpIdle();

  // ── Clear error ──────────────────────────────────────────────────────────
  // Called when user starts typing again after an error.
  // Restores OtpSent state so the screen stays on OTP input.

  void clearError({required String phone, required String countryCode}) {
    if (state is OtpError) {
      state = OtpSent(phone: phone, countryCode: countryCode);
    }
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final otpFlowProvider =
    StateNotifierProvider<OtpFlowNotifier, OtpFlowState>((ref) {
  return OtpFlowNotifier(
    ref.watch(authServiceProvider),
    ref.read(authStateProvider.notifier),
  );
});

// ── Profile Setup State ─────────────────────────────────────────────────────

sealed class ProfileSetupState {
  const ProfileSetupState();
}

class ProfileSetupIdle extends ProfileSetupState {
  const ProfileSetupIdle();
}

class ProfileSetupSubmitting extends ProfileSetupState {
  const ProfileSetupSubmitting();
}

class ProfileSetupDone extends ProfileSetupState {
  const ProfileSetupDone();
}

class ProfileSetupError extends ProfileSetupState {
  final String message;
  const ProfileSetupError(this.message);
}

// ── ProfileSetupNotifier ─────────────────────────────────────────────────────

class ProfileSetupNotifier extends StateNotifier<ProfileSetupState> {
  final AuthService _authService;
  final AuthStateNotifier _authNotifier;

  ProfileSetupNotifier(this._authService, this._authNotifier)
      : super(const ProfileSetupIdle());

  Future<void> submit({
    required String fullName,
    required String gender,
    required DateTime dateOfBirth,
    required String role,
  }) async {
    // Validate
    if (fullName.trim().length < 2) {
      state = const ProfileSetupError('Please enter your full name.');
      return;
    }

    state = const ProfileSetupSubmitting();

    try {
      // ISO date format the backend expects: 2000-05-15
      final dob =
          '${dateOfBirth.year}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

      await _authService.completeRegistration(
        fullName: fullName.trim(),
        gender: gender,
        dateOfBirth: dob,
        role: role,
      );

      // Refresh the session so the router sees the updated profile
      // (the user might now have a role that changes which home screen they see)
      await _authNotifier.refreshProfile();

      state = const ProfileSetupDone();
    } on AppError catch (e) {
      state = ProfileSetupError(e.message);
    } catch (_) {
      state = const ProfileSetupError(
        'Failed to save profile. Please try again.',
      );
    }
  }

  void clearError() {
    if (state is ProfileSetupError) state = const ProfileSetupIdle();
  }
}

// ── Provider ────────────────────────────────────────────────────────────────

final profileSetupProvider =
    StateNotifierProvider<ProfileSetupNotifier, ProfileSetupState>((ref) {
  return ProfileSetupNotifier(
    ref.watch(authServiceProvider),
    ref.read(authStateProvider.notifier),
  );
});
