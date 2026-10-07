import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/primary_button.dart';

/// PhoneInputScreen — first screen in the auth flow.
///
/// User enters their 10-digit Indian mobile number.
/// We prepend the country code (+91 default, selectable).
/// On submit → calls OtpRequestNotifier.sendOtp()
///           → on success, navigates to OtpVerifyScreen passing phone + code.

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _phoneController = TextEditingController();
  String _countryCode = '+91';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 10-digit number.')),
      );
      return;
    }
    ref.read(otpRequestProvider.notifier).sendOtp(
          phone: phone,
          countryCode: _countryCode,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<OtpRequestState>(otpRequestProvider, (_, next) {
      if (next is OtpRequestSent) {
        context.push(
          AppRoutes.otpVerify,
          extra: {
            'phone': next.phone,
            'countryCode': next.countryCode,
          },
        );
      }
    });

    final state = ref.watch(otpRequestProvider);
    final isSending = state is OtpRequestSending;
    final errorMessage = state is OtpRequestError ? state.message : null;

    return AuthLayout(
      icon: Icons.phone_android_rounded,
      title: 'Enter Your\nPhone Number',
      subtitle: 'We\'ll send a 6-digit code to verify it\'s you.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Phone field ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Country code selector
              _CountryCodeChip(
                code: _countryCode,
                onTap: () {
                  // For MVP, only +91. A full picker can be added later.
                },
              ),
              const SizedBox(width: 12),
              // Phone number input
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  maxLength: 10,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    hintText: '98765 43210',
                    counterText: '', // hides the default "0/10" counter
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Error banner ──────────────────────────────────────────────────
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: errorMessage),
          ],

          const SizedBox(height: 28),

          // ── Submit button ─────────────────────────────────────────────────
          PrimaryButton(
            label: 'Send OTP',
            icon: Icons.arrow_forward_rounded,
            isLoading: isSending,
            onPressed: _submit,
          ),

          const SizedBox(height: 24),

          // ── Terms note ────────────────────────────────────────────────────
          Text(
            'By continuing, you agree to PinkRide\'s Terms of Service '
            'and Privacy Policy.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textHint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Country code chip ─────────────────────────────────────────────────────────
class _CountryCodeChip extends StatelessWidget {
  final String code;
  final VoidCallback onTap;

  const _CountryCodeChip({required this.code, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Text('🇮🇳', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              code,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error banner ──────────────────────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
