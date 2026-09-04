import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/primary_button.dart';

/// OtpVerifyScreen — 6-digit OTP entry with auto-submit and resend countdown.
///
/// Receives phone + countryCode via go_router's `extra` map.
/// (Passed from PhoneInputScreen when navigating: context.push(..., extra: {...}))
///
/// What it does:
///   1. Shows a 6-box Pinput widget (each box = one digit)
///   2. Auto-submits when all 6 digits are filled
///   3. Runs a 60-second countdown before allowing resend
///   4. On OtpVerified → navigates to profile setup (new user) or home (returning)
///   5. On OtpError → shows the error and keeps the OTP field active for retry
///
/// WHY PINPUT PACKAGE?
/// Building 6 individual TextFields that move focus between themselves,
/// handle paste, handle backspace correctly, and look good takes ~150 lines.
/// Pinput does all of that in ~20 lines with full customisation.

class OtpVerifyScreen extends ConsumerStatefulWidget {
  // These come from go_router extra — set in PhoneInputScreen
  final String phone;
  final String countryCode;

  const OtpVerifyScreen({
    super.key,
    required this.phone,
    required this.countryCode,
  });

  @override
  ConsumerState<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends ConsumerState<OtpVerifyScreen> {
  final _pinController = TextEditingController();
  final _pinFocusNode = FocusNode();

  // Countdown state — how many seconds remain before "Resend" is active
  int _secondsLeft = AppConstants.otpResendSeconds; // 60
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _pinFocusNode.dispose();
    _countdownTimer?.cancel(); // IMPORTANT: always cancel timers on dispose
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = AppConstants.otpResendSeconds);

    // Timer.periodic fires every second until cancelled
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 0) {
        timer.cancel();
        return;
      }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  void _submit() {
    _pinFocusNode.unfocus();
    ref.read(otpFlowProvider.notifier).verifyOtp(otp: _pinController.text);
  }

  void _resend() {
    _pinController.clear(); // Clear the OTP field
    ref.read(otpFlowProvider.notifier).resendOtp();
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    // Navigate when OTP is verified
    ref.listen<OtpFlowState>(otpFlowProvider, (previous, next) {
      if (next is OtpVerified) {
        if (next.isNewUser) {
          // New user — must complete profile before using the app
          context.pushReplacement(AppRoutes.profileSetup);
        } else {
          // Returning user — router redirect will send them to correct home
          // pushReplacement so back button doesn't return to OTP screen
          context.go(AppRoutes.splash);
        }
      }

      // On error — clear the pin field so user can re-enter
      if (next is OtpError) {
        _pinController.clear();
        _pinFocusNode.requestFocus();
      }
    });

    final state = ref.watch(otpFlowProvider);
    final isVerifying = state is OtpVerifying;
    final errorMessage = state is OtpError ? state.message : null;

    // ── Pinput theme ──────────────────────────────────────────────────────
    // Defines what each digit box looks like in different states.
    // Pinput applies the right theme automatically based on focus/fill/error.
    const boxSize = Size(52, 60);
    const radius = BorderRadius.all(Radius.circular(12));

    final defaultTheme = PinTheme(
      width: boxSize.width,
      height: boxSize.height,
      textStyle: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: radius,
        border: Border.all(color: Colors.transparent, width: 1.5),
      ),
    );

    final focusedTheme = defaultTheme.copyDecorationWith(
      border: Border.all(color: AppTheme.primary, width: 1.5),
      color: Colors.white,
    );

    final submittedTheme = defaultTheme.copyDecorationWith(
      border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 1.5),
      color: AppTheme.primaryLight.withOpacity(0.15),
    );

    final errorTheme = defaultTheme.copyDecorationWith(
      border: Border.all(color: AppTheme.error, width: 1.5),
      color: AppTheme.error.withOpacity(0.05),
    );

    return AuthLayout(
      icon: Icons.lock_outline_rounded,
      title: 'Enter OTP',
      subtitle: 'We sent a 6-digit code to\n+91 ${widget.phone}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── OTP boxes ────────────────────────────────────────────────────
          Center(
            child: Pinput(
              controller: _pinController,
              focusNode: _pinFocusNode,
              length: AppConstants.otpLength, // 6

              // Auto-submit as soon as all 6 digits are filled
              // User doesn't need to tap the button
              onCompleted: (_) => _submit(),

              defaultPinTheme: defaultTheme,
              focusedPinTheme: focusedTheme,
              submittedPinTheme: submittedTheme,
              errorPinTheme: errorTheme,

              // Show error state on all boxes when there's an error
              forceErrorState: errorMessage != null,

              // Hides digits — shows dots instead (like a password field)
              // Set to false for OTPs since they're not sensitive
              obscureText: false,

              // Keyboard type — show number pad
              keyboardType: TextInputType.number,

              // Autofocus so keyboard opens immediately
              autofocus: true,

              // Called on every character — clear error as user types
              onChanged: (_) {
                if (state is OtpError) {
                  ref.read(otpFlowProvider.notifier).clearError(
                        phone: widget.phone,
                        countryCode: widget.countryCode,
                      );
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // ── Inline error message ─────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: errorMessage != null
                ? Container(
                    key: ValueKey(errorMessage),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: AppTheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: const TextStyle(
                              color: AppTheme.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('no-error')),
          ),

          const SizedBox(height: 28),

          // ── Verify button ────────────────────────────────────────────────
          PrimaryButton(
            label: 'Verify OTP',
            isLoading: isVerifying,
            onPressed: _pinController.text.length == AppConstants.otpLength
                ? _submit
                : null, // disabled until all 6 digits are entered
          ),

          const SizedBox(height: 24),

          // ── Resend row ───────────────────────────────────────────────────
          Center(
            child: _secondsLeft > 0
                ? RichText(
                    text: TextSpan(
                      text: "Didn't receive it? Resend in ",
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                      children: [
                        TextSpan(
                          text: '${_secondsLeft}s',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : TextButton(
                    onPressed: _resend,
                    child: const Text(
                      'Resend OTP',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
          ),

          const SizedBox(height: 12),

          // ── Change number link ───────────────────────────────────────────
          Center(
            child: TextButton.icon(
              onPressed: () {
                ref.read(otpFlowProvider.notifier).reset();
                context.pop(); // Back to phone input
              },
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  size: 14, color: AppTheme.textSecondary),
              label: const Text(
                'Change number',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
