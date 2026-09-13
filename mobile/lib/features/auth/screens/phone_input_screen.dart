import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_flow_provider.dart';
import '../widgets/auth_layout.dart';
import '../widgets/primary_button.dart';

/// PhoneInputScreen — the first screen a new or returning user sees.
///
/// What it does:
///   1. Shows +91 country code (fixed for Jaipur MVP) + 10-digit phone field
///   2. Validates that exactly 10 digits are entered
///   3. Calls OtpFlowNotifier.requestOtp()
///   4. Listens to OtpFlowState — when OtpSent, navigates to OTP screen
///   5. Shows errors inline below the input field
///
/// WHY ConsumerStatefulWidget INSTEAD OF ConsumerWidget?
/// We need a TextEditingController (to read the phone field value) and
/// to dispose it when the screen leaves the tree. StatefulWidget gives us
/// initState() and dispose() for that lifecycle management.
/// ConsumerStatefulWidget = StatefulWidget + Riverpod's ref access.

class PhoneInputScreen extends ConsumerStatefulWidget {
  const PhoneInputScreen({super.key});

  @override
  ConsumerState<PhoneInputScreen> createState() => _PhoneInputScreenState();
}

class _PhoneInputScreenState extends ConsumerState<PhoneInputScreen> {
  final _phoneController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    // ALWAYS dispose controllers and focus nodes to prevent memory leaks
    _phoneController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    // Dismiss keyboard before API call
    _focusNode.unfocus();

    ref.read(otpFlowProvider.notifier).requestOtp(
          phone: _phoneController.text.trim(),
          countryCode: '+91',
        );
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen reacts to state changes WITHOUT rebuilding the whole widget.
    // Ideal for one-time side effects like navigation.
    // ref.watch would rebuild the whole widget tree on every state change —
    // we only want to navigate once when OtpSent arrives.
    ref.listen<OtpFlowState>(otpFlowProvider, (previous, next) {
      if (next is OtpSent) {
        // Navigate to OTP screen, passing phone as query param for display
        context.push(
          AppRoutes.otpVerify,
          extra: {'phone': next.phone, 'countryCode': next.countryCode},
        );
      }
    });

    // ref.watch rebuilds this widget whenever OtpFlowState changes.
    // Used to show/hide the loading spinner and error message.
    final state = ref.watch(otpFlowProvider);
    final isLoading = state is OtpSending;
    final errorMessage = state is OtpError ? (state).message : null;

    return AuthLayout(
      icon: Icons.phone_android_rounded,
      title: 'Welcome to\nPinkRide',
      subtitle: 'Enter your mobile number to\nget started.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section label ────────────────────────────────────────────────
          const Text(
            'Mobile Number',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),

          // ── Phone input row ──────────────────────────────────────────────
          // Country code prefix + phone number in one visual row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Country code badge — tappable for future multi-country support
              Container(
                height: 54,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🇮🇳',
                      style: TextStyle(fontSize: 20),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '+91',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Phone number field
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  focusNode: _focusNode,
                  // On submit (keyboard done button), trigger the same action
                  onFieldSubmitted: (_) => _submit(),
                  keyboardType: TextInputType.phone,
                  // Only allow digits, max 10 characters
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '98765 43210',
                    hintStyle: const TextStyle(
                      fontSize: 18,
                      letterSpacing: 1,
                      color: AppTheme.textHint,
                      fontWeight: FontWeight.normal,
                    ),
                    // Red border when there's an error
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: errorMessage != null
                            ? AppTheme.error
                            : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  // Clear error as soon as user starts editing
                  onChanged: (_) {
                    if (state is OtpError) {
                      ref.read(otpFlowProvider.notifier).reset();
                    }
                  },
                ),
              ),
            ],
          ),

          // ── Inline error message ─────────────────────────────────────────
          // AnimatedSwitcher smoothly fades error in and out
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: errorMessage != null
                ? Padding(
                    key: ValueKey(errorMessage),
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 14, color: AppTheme.error),
                        const SizedBox(width: 6),
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

          // ── Submit button ────────────────────────────────────────────────
          PrimaryButton(
            label: 'Send OTP',
            icon: Icons.send_rounded,
            isLoading: isLoading,
            onPressed: _submit,
          ),

          const SizedBox(height: 24),

          // ── Terms note ───────────────────────────────────────────────────
          Center(
            child: Text(
              'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary.withOpacity(0.7),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
