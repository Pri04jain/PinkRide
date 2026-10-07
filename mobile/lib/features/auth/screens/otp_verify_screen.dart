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

/// OtpVerifyScreen — shown after a successful OTP request.
///
/// Receives phone + countryCode from PhoneInputScreen via go_router extras.
/// User enters the 6-digit OTP; auto-submits when all 6 digits are filled.
/// Shows a countdown timer before allowing "Resend OTP".
///
/// On success → router's redirect handles navigation based on isNewUser:
///   isNewUser=true  → router sees incomplete profile → /auth/profile
///   isNewUser=false → router sees role → /passenger/home or /driver/home

class OtpVerifyScreen extends ConsumerStatefulWidget {
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
  final _otpController = TextEditingController();
  Timer? _resendTimer;
  int _resendCountdown = AppConstants.otpResendSeconds;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = AppConstants.otpResendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCountdown--;
        if (_resendCountdown <= 0) timer.cancel();
      });
    });
  }

  void _verify(String otp) {
    if (otp.length != AppConstants.otpLength) return;
    ref.read(otpVerifyProvider.notifier).verifyOtp(
          phone: widget.phone,
          countryCode: widget.countryCode,
          otp: otp,
          mode: 'login', // legacy screen — treat as login
        );
  }

  void _resend() {
    _otpController.clear();
    ref.read(otpRequestProvider.notifier).sendOtp(
          phone: widget.phone,
          countryCode: widget.countryCode,
        );
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    // After successful verification, navigate based on isNewUser:
    //   new user  → photo capture → registration details
    //   returning → splash → router redirect to role home
    ref.listen<OtpVerifyState>(otpVerifyProvider, (_, next) {
      if (next is OtpVerifySuccess) {
        if (next.isNewUser) {
          context.pushReplacement(
            AppRoutes.photoCapture,
            extra: {'phone': next.phone},
          );
        } else {
          context.go(AppRoutes.splash);
        }
      }
    });

    final state = ref.watch(otpVerifyProvider);
    final isVerifying = state is OtpVerifying;
    final errorMessage = state is OtpVerifyError ? state.message : null;

    // Pinput theme — the 6-box OTP input style
    final defaultPinTheme = PinTheme(
      width: 48,
      height: 52,
      textStyle: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary, width: 1.5),
      ),
    );

    final errorPinTheme = defaultPinTheme.copyWith(
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error, width: 1.5),
      ),
    );

    return AuthLayout(
      icon: Icons.lock_outline_rounded,
      title: 'Verify\nYour Number',
      subtitle: 'Code sent to ${widget.countryCode} ${widget.phone}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),

          // ── OTP input ──────────────────────────────────────────────────────
          Pinput(
            controller: _otpController,
            length: AppConstants.otpLength,
            defaultPinTheme: defaultPinTheme,
            focusedPinTheme: focusedPinTheme,
            errorPinTheme: errorPinTheme,
            autofocus: true,
            hapticFeedbackType: HapticFeedbackType.lightImpact,
            // Auto-submit when all digits are entered
            onCompleted: isVerifying ? null : _verify,
            errorText: errorMessage,
          ),

          const SizedBox(height: 32),

          // ── Verify button ──────────────────────────────────────────────────
          PrimaryButton(
            label: 'Verify',
            icon: Icons.check_rounded,
            isLoading: isVerifying,
            onPressed: () => _verify(_otpController.text),
          ),

          const SizedBox(height: 24),

          // ── Resend timer / button ──────────────────────────────────────────
          _resendCountdown > 0
              ? Text(
                  'Resend OTP in $_resendCountdown s',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
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

          const SizedBox(height: 16),

          // ── Change number ──────────────────────────────────────────────────
          TextButton(
            onPressed: () => context.pop(),
            child: const Text(
              'Change phone number',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
