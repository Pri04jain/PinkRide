import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../../core/api/api_client.dart';
import '../../../core/models/app_error.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

// ── State ─────────────────────────────────────────────────────────────────────

enum OtpEntryStatus { idle, verifying, success, error }

class OtpEntryState {
  final OtpEntryStatus status;
  final String? errorMessage;

  const OtpEntryState({
    this.status = OtpEntryStatus.idle,
    this.errorMessage,
  });

  OtpEntryState copyWith({OtpEntryStatus? status, String? errorMessage}) =>
      OtpEntryState(
        status: status ?? this.status,
        errorMessage: errorMessage,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class OtpEntryNotifier extends StateNotifier<OtpEntryState> {
  final ApiClient _api;
  final String rideId;

  OtpEntryNotifier(this._api, {required this.rideId})
      : super(const OtpEntryState());

  Future<void> verifyOtp(String otp) async {
    if (otp.length != 6) return;
    state = state.copyWith(status: OtpEntryStatus.verifying);

    try {
      // POST /rides/:id/start  { otp }
      await _api.post('/rides/$rideId/start', data: {'otp': otp});
      state = state.copyWith(status: OtpEntryStatus.success);
    } on AppError catch (e) {
      state = state.copyWith(
        status: OtpEntryStatus.error,
        errorMessage: e.message,
      );
    } catch (_) {
      state = state.copyWith(
        status: OtpEntryStatus.error,
        errorMessage: 'Could not verify OTP. Please try again.',
      );
    }
  }

  void reset() => state = const OtpEntryState();
}

final otpEntryProvider = StateNotifierProvider.family
    .autoDispose<OtpEntryNotifier, OtpEntryState, String>((ref, rideId) {
  return OtpEntryNotifier(ref.watch(apiClientProvider), rideId: rideId);
});

// ─────────────────────────────────────────────────────────────────────────────
// OtpEntryScreen — shown to the DRIVER to enter the passenger's OTP.
//
// FLOW:
//   Passenger completes pre-ride face check → OTP shown to passenger
//   Driver asks for OTP → enters here → /rides/:id/start is called
//   Backend validates OTP → sets ride status to 'in_progress'
//   Both driver and passenger move to the active-ride / tracking screen.
// ─────────────────────────────────────────────────────────────────────────────

class OtpEntryScreen extends ConsumerStatefulWidget {
  final String rideId;

  const OtpEntryScreen({super.key, required this.rideId});

  @override
  ConsumerState<OtpEntryScreen> createState() => _OtpEntryScreenState();
}

class _OtpEntryScreenState extends ConsumerState<OtpEntryScreen> {
  final _otpController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(otpEntryProvider(widget.rideId));
    final notifier = ref.read(otpEntryProvider(widget.rideId).notifier);

    // Navigate on success
    ref.listen<OtpEntryState>(otpEntryProvider(widget.rideId), (_, next) {
      if (next.status == OtpEntryStatus.success) {
        context.go(AppRoutes.activeRide.replaceAll(':rideId', widget.rideId));
      }
    });

    final isVerifying = state.status == OtpEntryStatus.verifying;

    // Pinput theme
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 60,
      textStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: AppTheme.primary, width: 2),
        color: AppTheme.primaryLight.withValues(alpha: 0.08),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration!.copyWith(
        border: Border.all(color: AppTheme.error, width: 2),
        color: AppTheme.error.withValues(alpha: 0.05),
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Enter Ride OTP'),
        backgroundColor: AppTheme.surface,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),

              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pin_rounded,
                    color: AppTheme.primary, size: 40),
              ),

              const SizedBox(height: 24),

              const Text(
                'Ask the passenger for their 6-digit OTP',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The OTP is shown on the passenger\'s app '
                'after they complete the face check.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 40),

              // OTP boxes
              Pinput(
                length: 6,
                controller: _otpController,
                focusNode: _focusNode,
                autofocus: true,
                defaultPinTheme: defaultPinTheme,
                focusedPinTheme: focusedPinTheme,
                errorPinTheme: errorPinTheme,
                forceErrorState:
                    state.status == OtpEntryStatus.error,
                keyboardType: TextInputType.number,
                onCompleted: (pin) => notifier.verifyOtp(pin),
                onChanged: (_) {
                  if (state.status == OtpEntryStatus.error) {
                    notifier.reset();
                  }
                },
              ),

              // Error message
              if (state.errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.error, size: 16),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Verify button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isVerifying
                      ? null
                      : () => notifier.verifyOtp(_otpController.text),
                  child: isVerifying
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Start Ride'),
                ),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => context.pop(),
                child: const Text(
                  'Back',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RideOtpDisplayScreen — shown to the PASSENGER after face check passes.
//
// Displays the 6-digit OTP the driver needs to enter.
// Auto-refreshes every 60 seconds (OTPs expire server-side).
// ─────────────────────────────────────────────────────────────────────────────

class RideOtpDisplayScreen extends ConsumerStatefulWidget {
  final String ridePassengerId;
  final String rideId;
  final String otp; // passed as extra from pre-ride face screen

  const RideOtpDisplayScreen({
    super.key,
    required this.ridePassengerId,
    required this.rideId,
    required this.otp,
  });

  @override
  ConsumerState<RideOtpDisplayScreen> createState() =>
      _RideOtpDisplayScreenState();
}

class _RideOtpDisplayScreenState
    extends ConsumerState<RideOtpDisplayScreen> {
  @override
  Widget build(BuildContext context) {
    final digits = widget.otp.split('');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Your Ride OTP'),
        automaticallyImplyLeading: false, // can't go back — show OTP screen
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 32),

              // Face verified badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: AppTheme.success, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Identity Verified',
                      style: TextStyle(
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                'Show this OTP to your driver',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The driver enters this code to start your ride.',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
              ),

              const SizedBox(height: 40),

              // OTP digit boxes
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: digits.asMap().entries.map((entry) {
                  return Container(
                    width: 52,
                    height: 64,
                    margin: EdgeInsets.only(
                        right: entry.key < digits.length - 1 ? 8 : 0),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primary, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        entry.value,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              const Spacer(),

              // Safety reminder
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppTheme.warning, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Only share this OTP with your assigned driver. '
                        'Never share it with anyone else.',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.warning,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () =>
                      context.push(AppRoutes.emergencyContacts),
                  child: const Text('Emergency Contacts'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
