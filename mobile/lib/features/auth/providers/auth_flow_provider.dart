import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/models/app_error.dart';
import '../../../core/models/user_model.dart';
import '../../../core/providers/auth_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
// OTP REQUEST STATE
// ════════════════════════════════════════════════════════════════════════════

sealed class OtpRequestState { const OtpRequestState(); }
class OtpRequestIdle    extends OtpRequestState { const OtpRequestIdle(); }
class OtpRequestSending extends OtpRequestState { const OtpRequestSending(); }

class OtpRequestSent extends OtpRequestState {
  final String phone;
  final String countryCode;
  const OtpRequestSent({required this.phone, required this.countryCode});
}

class OtpRequestError extends OtpRequestState {
  final String message;
  const OtpRequestError(this.message);
}

class OtpRequestNotifier extends StateNotifier<OtpRequestState> {
  final ApiClient _api;

  OtpRequestNotifier(this._api) : super(const OtpRequestIdle());

  Future<void> sendOtp({
    required String phone,
    required String countryCode,
  }) async {
    if (state is OtpRequestSending) return;
    state = const OtpRequestSending();

    try {
      await _api.post(ApiEndpoints.requestOtp, data: {
        'phone': phone,
        'countryCode': countryCode,
        'purpose': 'login',
      });
      state = OtpRequestSent(phone: phone, countryCode: countryCode);
    } on AppError catch (e) {
      state = OtpRequestError(e.message);
    } catch (_) {
      state = const OtpRequestError('Could not send OTP. Check your connection.');
    }
  }

  void reset() => state = const OtpRequestIdle();
}

final otpRequestProvider =
    StateNotifierProvider.autoDispose<OtpRequestNotifier, OtpRequestState>(
        (ref) => OtpRequestNotifier(ref.watch(apiClientProvider)));

// ════════════════════════════════════════════════════════════════════════════
// OTP VERIFY STATE
// ════════════════════════════════════════════════════════════════════════════

sealed class OtpVerifyState { const OtpVerifyState(); }
class OtpVerifyIdle    extends OtpVerifyState { const OtpVerifyIdle(); }
class OtpVerifying     extends OtpVerifyState { const OtpVerifying(); }

class OtpVerifySuccess extends OtpVerifyState {
  final bool isNewUser;
  final String phone; // passed forward to photo/details screens
  const OtpVerifySuccess({required this.isNewUser, required this.phone});
}

class OtpVerifyError extends OtpVerifyState {
  final String message;
  const OtpVerifyError(this.message);
}

class OtpVerifyNotifier extends StateNotifier<OtpVerifyState> {
  final ApiClient _api;
  final Ref _ref;

  OtpVerifyNotifier(this._api, this._ref) : super(const OtpVerifyIdle());

  /// [mode] = 'login' | 'signup'
  /// login  → expects isNewUser=false. Shows error if account not found.
  /// signup → expects isNewUser=true.  Shows error if account already exists.
  Future<void> verifyOtp({
    required String phone,
    required String countryCode,
    required String otp,
    required String mode, // 'login' or 'signup'
  }) async {
    if (state is OtpVerifying) return;
    state = const OtpVerifying();

    try {
      final data = await _api.post(ApiEndpoints.verifyOtp, data: {
        'phone': phone,
        'countryCode': countryCode,
        'otp': otp,
        'purpose': 'login',
      });

      final isNewUser    = data['isNewUser']    as bool?   ?? false;
      final tokensJson   = data['tokens']       as Map<String, dynamic>? ?? {};
      final accessToken  = tokensJson['accessToken']  as String? ?? '';
      final refreshToken = tokensJson['refreshToken'] as String? ?? '';
      final userJson     = data['user']         as Map<String, dynamic>? ?? {};
      final user         = UserModel.fromJson(userJson);

      // ── Mode guard ────────────────────────────────────────────────────────
      if (mode == 'login' && isNewUser) {
        // Tried to log in but no account exists — prompt to sign up instead
        state = const OtpVerifyError(
          'No account found for this number. Please sign up first.',
        );
        return;
      }
      if (mode == 'signup' && !isNewUser) {
        // Tried to sign up but account already exists — prompt to log in
        state = const OtpVerifyError(
          'An account already exists for this number. Please log in instead.',
        );
        return;
      }

      await _ref.read(authStateProvider.notifier).saveSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user,
          );

      state = OtpVerifySuccess(isNewUser: isNewUser, phone: phone);
    } on AppError catch (e) {
      state = OtpVerifyError(e.message);
    } catch (_) {
      state = const OtpVerifyError('Verification failed. Please try again.');
    }
  }

  void reset() => state = const OtpVerifyIdle();
}

final otpVerifyProvider =
    StateNotifierProvider.autoDispose<OtpVerifyNotifier, OtpVerifyState>(
        (ref) => OtpVerifyNotifier(ref.watch(apiClientProvider), ref));

// ════════════════════════════════════════════════════════════════════════════
// PHOTO CAPTURE STATE
// Stores the local file path of the selfie taken on PhotoCaptureScreen.
// Passed forward to RegistrationDetailsScreen via the provider.
// ════════════════════════════════════════════════════════════════════════════

class PhotoCaptureNotifier extends StateNotifier<String?> {
  PhotoCaptureNotifier() : super(null);

  void setPhoto(String filePath) => state = filePath;
  void clear()                   => state = null;
}

final photoCaptureProvider =
    StateNotifierProvider.autoDispose<PhotoCaptureNotifier, String?>(
        (_) => PhotoCaptureNotifier());

// ════════════════════════════════════════════════════════════════════════════
// PROFILE SETUP STATE  (registration details for new users)
// ════════════════════════════════════════════════════════════════════════════

sealed class ProfileSetupState { const ProfileSetupState(); }
class ProfileSetupIdle       extends ProfileSetupState { const ProfileSetupIdle(); }
class ProfileSetupSubmitting extends ProfileSetupState { const ProfileSetupSubmitting(); }
class ProfileSetupDone       extends ProfileSetupState { const ProfileSetupDone(); }

class ProfileSetupError extends ProfileSetupState {
  final String message;
  const ProfileSetupError(this.message);
}

class ProfileSetupNotifier extends StateNotifier<ProfileSetupState> {
  final ApiClient _api;
  final Ref _ref;

  ProfileSetupNotifier(this._api, this._ref) : super(const ProfileSetupIdle());

  Future<void> submit({
    required String fullName,
    required String gender,
    required DateTime dateOfBirth,
    required String role,
    String? email,
    String? profilePhotoUrl,
  }) async {
    if (state is ProfileSetupSubmitting) return;
    state = const ProfileSetupSubmitting();

    try {
      // POST /users/register — accepts fullName, gender, dateOfBirth, role,
      // email (optional), profilePhotoUrl (optional).
      // Sets face_consent_given=true automatically (DPDP compliance).
      await _api.post(ApiEndpoints.registerUser, data: {
        'fullName':    fullName,
        'gender':      gender,
        'dateOfBirth': dateOfBirth.toIso8601String().split('T').first,
        'role':        role,
        if (email != null && email.isNotEmpty)           'email': email,
        if (profilePhotoUrl != null && profilePhotoUrl.isNotEmpty)
          'profilePhotoUrl': profilePhotoUrl,
      });

      // Refresh global auth state so router sees profileIncomplete = false
      await _ref.read(authStateProvider.notifier).refreshProfile();

      state = const ProfileSetupDone();
    } on AppError catch (e) {
      state = ProfileSetupError(e.message);
    } catch (_) {
      state = const ProfileSetupError('Could not save your profile. Please try again.');
    }
  }

  void clearError() {
    if (state is ProfileSetupError) state = const ProfileSetupIdle();
  }
}

final profileSetupProvider =
    StateNotifierProvider.autoDispose<ProfileSetupNotifier, ProfileSetupState>(
        (ref) => ProfileSetupNotifier(ref.watch(apiClientProvider), ref));
