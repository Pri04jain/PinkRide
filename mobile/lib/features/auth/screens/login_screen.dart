import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';

/// LoginScreen — for returning users.
///
/// Two-step inline layout (no separate OTP screen):
///   Step 1: Enter phone number → "Send OTP"
///   Step 2: Enter 6-digit OTP  → verify (mode = 'login')
///
/// If the OTP comes back with isNewUser=true we show "no account" error
/// and offer a link to Sign Up.

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ── Step tracking ──────────────────────────────────────────────────────────
  bool _otpSent = false;
  String _phone = '';
  final String _countryCode = '+91';

  // ── Controllers ────────────────────────────────────────────────────────────
  final _phoneController = TextEditingController();
  final _otpController   = TextEditingController();
  final _phoneFocus      = FocusNode();

  // ── Resend timer ───────────────────────────────────────────────────────────
  Timer? _resendTimer;
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _phoneFocus.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendTimer?.cancel();
    setState(() => _countdown = AppConstants.otpResendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _countdown--; if (_countdown <= 0) t.cancel(); });
    });
  }

  // ── Send OTP ───────────────────────────────────────────────────────────────
  void _sendOtp() {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit number.')),
      );
      return;
    }
    setState(() { _phone = phone; });
    ref.read(otpRequestProvider.notifier).sendOtp(
      phone: phone,
      countryCode: _countryCode,
    );
  }

  // ── Verify OTP ─────────────────────────────────────────────────────────────
  void _verifyOtp(String otp) {
    if (otp.length != AppConstants.otpLength) return;
    ref.read(otpVerifyProvider.notifier).verifyOtp(
      phone: _phone,
      countryCode: _countryCode,
      otp: otp,
      mode: 'login',
    );
  }

  void _resend() {
    _otpController.clear();
    ref.read(otpVerifyProvider.notifier).reset();
    ref.read(otpRequestProvider.notifier).sendOtp(
      phone: _phone,
      countryCode: _countryCode,
    );
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    // OTP sent → switch to OTP step
    ref.listen<OtpRequestState>(otpRequestProvider, (_, next) {
      if (next is OtpRequestSent) {
        setState(() => _otpSent = true);
        _startCountdown();
      }
    });

    // OTP verified → existing user goes home; new user error is shown inline
    ref.listen<OtpVerifyState>(otpVerifyProvider, (_, next) {
      if (next is OtpVerifySuccess) {
        context.go(AppRoutes.splash); // router redirects to home
      }
    });

    final reqState  = ref.watch(otpRequestProvider);
    final verState  = ref.watch(otpVerifyProvider);
    final isSending  = reqState is OtpRequestSending;
    final isVerifying = verState is OtpVerifying;

    final reqError  = reqState  is OtpRequestError ? reqState.message  : null;
    final verError  = verState  is OtpVerifyError  ? verState.message  : null;
    final errorMsg  = reqError ?? verError;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Header ──────────────────────────────────────────────────
              const Text(
                'Welcome back',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _otpSent
                    ? 'Enter the code sent to $_countryCode $_phone'
                    : 'Enter your phone number to continue.',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 36),

              // ── Step 1: Phone ────────────────────────────────────────────
              if (!_otpSent) ...[
                _PhoneField(
                  controller: _phoneController,
                  countryCode: _countryCode,
                  onSubmitted: (_) => _sendOtp(),
                ),
                const SizedBox(height: 24),
                _BigButton(
                  label: 'Send OTP',
                  isLoading: isSending,
                  onPressed: _sendOtp,
                ),
              ],

              // ── Step 2: OTP ──────────────────────────────────────────────
              if (_otpSent) ...[
                _OtpField(
                  controller: _otpController,
                  onCompleted: isVerifying ? null : _verifyOtp,
                  hasError: verError != null,
                ),
                const SizedBox(height: 28),
                _BigButton(
                  label: 'Log In',
                  isLoading: isVerifying,
                  onPressed: () => _verifyOtp(_otpController.text),
                ),
                const SizedBox(height: 20),
                Center(
                  child: _countdown > 0
                      ? Text('Resend OTP in $_countdown s',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary))
                      : TextButton(
                          onPressed: _resend,
                          child: const Text('Resend OTP',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                ),
                const SizedBox(height: 8),
                // Change number
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false;
                      _otpController.clear();
                      ref.read(otpVerifyProvider.notifier).reset();
                    }),
                    child: const Text('Change phone number',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                  ),
                ),
              ],

              // ── Error banner ──────────────────────────────────────────────
              if (errorMsg != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: errorMsg),
                // If "no account found" → offer sign up
                if (verError != null && verError.contains('sign up')) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pushReplacement(AppRoutes.signUp),
                      child: const Text('Create an account instead →',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 40),

              // ── Sign up link ──────────────────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Don't have an account? ",
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14)),
                    GestureDetector(
                      onTap: () => context.pushReplacement(AppRoutes.signUp),
                      child: const Text('Sign Up',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ],
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
// SignUpScreen — same two-step layout, mode = 'signup'
// ─────────────────────────────────────────────────────────────────────────────

/// SignUpScreen — for new users.
/// Phone + OTP → photo capture → registration details.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  bool _otpSent = false;
  String _phone = '';
  final String _countryCode = '+91';

  final _phoneController = TextEditingController();
  final _otpController   = TextEditingController();

  Timer? _resendTimer;
  int _countdown = 0;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _resendTimer?.cancel();
    setState(() => _countdown = AppConstants.otpResendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() { _countdown--; if (_countdown <= 0) t.cancel(); });
    });
  }

  void _sendOtp() {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit number.')),
      );
      return;
    }
    setState(() => _phone = phone);
    ref.read(otpRequestProvider.notifier).sendOtp(
      phone: phone,
      countryCode: _countryCode,
    );
  }

  void _verifyOtp(String otp) {
    if (otp.length != AppConstants.otpLength) return;
    ref.read(otpVerifyProvider.notifier).verifyOtp(
      phone: _phone,
      countryCode: _countryCode,
      otp: otp,
      mode: 'signup',
    );
  }

  void _resend() {
    _otpController.clear();
    ref.read(otpVerifyProvider.notifier).reset();
    ref.read(otpRequestProvider.notifier).sendOtp(
      phone: _phone,
      countryCode: _countryCode,
    );
    _startCountdown();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OtpRequestState>(otpRequestProvider, (_, next) {
      if (next is OtpRequestSent) {
        setState(() => _otpSent = true);
        _startCountdown();
      }
    });

    ref.listen<OtpVerifyState>(otpVerifyProvider, (_, next) {
      if (next is OtpVerifySuccess) {
        // New user → go to photo capture
        context.pushReplacement(
          AppRoutes.photoCapture,
          extra: {'phone': next.phone},
        );
      }
    });

    final reqState   = ref.watch(otpRequestProvider);
    final verState   = ref.watch(otpVerifyProvider);
    final isSending   = reqState is OtpRequestSending;
    final isVerifying = verState is OtpVerifying;

    final reqError = reqState is OtpRequestError ? reqState.message : null;
    final verError = verState is OtpVerifyError  ? verState.message : null;
    final errorMsg = reqError ?? verError;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Progress indicator ────────────────────────────────────────
              _StepIndicator(step: _otpSent ? 2 : 1, total: 3),
              const SizedBox(height: 28),

              // ── Header ────────────────────────────────────────────────────
              Text(
                _otpSent ? 'Verify your\nnumber' : 'Create your\naccount',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.8,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _otpSent
                    ? 'Enter the code sent to $_countryCode $_phone'
                    : 'Enter your mobile number to get started.',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 36),

              // ── Step 1: Phone ─────────────────────────────────────────────
              if (!_otpSent) ...[
                _PhoneField(
                  controller: _phoneController,
                  countryCode: _countryCode,
                  onSubmitted: (_) => _sendOtp(),
                ),
                const SizedBox(height: 24),
                _BigButton(
                  label: 'Send OTP',
                  isLoading: isSending,
                  onPressed: _sendOtp,
                ),
              ],

              // ── Step 2: OTP ───────────────────────────────────────────────
              if (_otpSent) ...[
                _OtpField(
                  controller: _otpController,
                  onCompleted: isVerifying ? null : _verifyOtp,
                  hasError: verError != null,
                ),
                const SizedBox(height: 28),
                _BigButton(
                  label: 'Verify & Continue',
                  isLoading: isVerifying,
                  onPressed: () => _verifyOtp(_otpController.text),
                ),
                const SizedBox(height: 20),
                Center(
                  child: _countdown > 0
                      ? Text('Resend in $_countdown s',
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary))
                      : TextButton(
                          onPressed: _resend,
                          child: const Text('Resend OTP',
                              style: TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600)),
                        ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () => setState(() {
                      _otpSent = false;
                      _otpController.clear();
                      ref.read(otpVerifyProvider.notifier).reset();
                    }),
                    child: const Text('Change phone number',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary)),
                  ),
                ),
              ],

              // ── Error banner ───────────────────────────────────────────────
              if (errorMsg != null) ...[
                const SizedBox(height: 16),
                _ErrorBanner(message: errorMsg),
                if (verError != null && verError.contains('log in')) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: () => context.pushReplacement(AppRoutes.login),
                      child: const Text('Log in instead →',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 40),

              // ── Login link ────────────────────────────────────────────────
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 14)),
                    GestureDetector(
                      onTap: () => context.pushReplacement(AppRoutes.login),
                      child: const Text('Log In',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 14)),
                    ),
                  ],
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
// Shared sub-widgets used by both screens
// ─────────────────────────────────────────────────────────────────────────────

class _PhoneField extends StatelessWidget {
  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String>? onSubmitted;

  const _PhoneField({
    required this.controller,
    required this.countryCode,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Country code badge
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            '🇮🇳  $countryCode',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: onSubmitted,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: '98765 43210',
              counterText: '',
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppTheme.primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }
}

class _OtpField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool hasError;

  const _OtpField({
    required this.controller,
    this.onCompleted,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final defaultTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: AppTheme.textPrimary,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasError ? AppTheme.error : Colors.transparent,
          width: 1.5,
        ),
      ),
    );

    final focusedTheme = defaultTheme.copyWith(
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primary, width: 2),
      ),
    );

    return Center(
      child: Pinput(
        controller: controller,
        length: AppConstants.otpLength,
        defaultPinTheme: defaultTheme,
        focusedPinTheme: focusedTheme,
        autofocus: true,
        hapticFeedbackType: HapticFeedbackType.lightImpact,
        onCompleted: onCompleted,
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _BigButton({
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white),
              )
            : Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AppTheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 13,
                    height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _StepIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i < step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: active ? AppTheme.primary : const Color(0xFFE0E0E0),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
