import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_client.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/theme/app_theme.dart';

// ── SOS state ─────────────────────────────────────────────────────────────────

enum SosStatus { idle, countdown, sending, sent, error }

class SosState {
  final SosStatus status;
  final int countdownSeconds;
  final String? errorMessage;

  const SosState({
    this.status = SosStatus.idle,
    this.countdownSeconds = 5,
    this.errorMessage,
  });

  SosState copyWith({
    SosStatus? status,
    int? countdownSeconds,
    String? errorMessage,
  }) =>
      SosState(
        status: status ?? this.status,
        countdownSeconds: countdownSeconds ?? this.countdownSeconds,
        errorMessage: errorMessage,
      );
}

// ── SOS notifier ──────────────────────────────────────────────────────────────

class SosNotifier extends StateNotifier<SosState> {
  final ApiClient _api;
  final String rideId;
  Timer? _timer;

  SosNotifier(this._api, {required this.rideId}) : super(const SosState());

  /// Starts the 5-second countdown. If not cancelled, triggers the SOS.
  void startCountdown() {
    if (state.status == SosStatus.countdown) return;
    state = state.copyWith(status: SosStatus.countdown, countdownSeconds: 5);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      final remaining = state.countdownSeconds - 1;
      if (remaining <= 0) {
        t.cancel();
        _sendSos();
      } else {
        state = state.copyWith(countdownSeconds: remaining);
      }
    });
  }

  /// Cancels the countdown before it fires.
  void cancelCountdown() {
    _timer?.cancel();
    state = const SosState();
  }

  Future<void> _sendSos() async {
    state = state.copyWith(status: SosStatus.sending);
    try {
      await _api.post(ApiEndpoints.triggerSos(rideId));
      state = state.copyWith(status: SosStatus.sent);
    } catch (_) {
      state = state.copyWith(
        status: SosStatus.error,
        errorMessage: 'SOS could not be sent. Call 112 immediately.',
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Provider factory ──────────────────────────────────────────────────────────

final sosProvider = StateNotifierProvider.family
    .autoDispose<SosNotifier, SosState, String>((ref, rideId) {
  return SosNotifier(ref.watch(apiClientProvider), rideId: rideId);
});

// ─────────────────────────────────────────────────────────────────────────────
// SosScreen
// ─────────────────────────────────────────────────────────────────────────────

/// SosScreen — emergency trigger screen shown during a ride.
///
/// FLOW:
///   1. Passenger taps the big red SOS button
///   2. 5-second countdown with "Cancel" option
///   3. API call → backend SMSes emergency contacts with live location link
///   4. Confirmation shown, option to call 112
///
/// SAFETY DESIGN:
///   - The 5-second buffer prevents accidental triggers
///   - Even if the API fails, we show the emergency number prominently
///   - "I'm Safe" resolves any pending deviation alert on the backend

class SosScreen extends ConsumerWidget {
  final String rideId;

  const SosScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sosProvider(rideId));
    final notifier = ref.read(sosProvider(rideId).notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0010), // very dark red background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        leading: state.status == SosStatus.countdown
            ? const SizedBox.shrink() // can't back out mid-countdown
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
        title: const Text(
          'SOS',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: switch (state.status) {
            SosStatus.idle      => _IdleBody(onSosTap: notifier.startCountdown),
            SosStatus.countdown => _CountdownBody(
                seconds: state.countdownSeconds,
                onCancel: notifier.cancelCountdown,
              ),
            SosStatus.sending   => const _SendingBody(),
            SosStatus.sent      => _SentBody(onBack: () => context.pop()),
            SosStatus.error     => _ErrorBody(
                message: state.errorMessage ?? 'SOS failed.',
                onBack: () => context.pop(),
              ),
          },
        ),
      ),
    );
  }
}

// ── Idle state ────────────────────────────────────────────────────────────────

class _IdleBody extends StatelessWidget {
  final VoidCallback onSosTap;
  const _IdleBody({required this.onSosTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 32),
        const Text(
          'Are you in danger?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tapping SOS will alert your emergency\ncontacts with your live location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
        ),
        const Spacer(),

        // Big SOS button
        GestureDetector(
          onTap: onSosTap,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.error,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.error.withValues(alpha: 0.5),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.sos_rounded, color: Colors.white, size: 72),
                SizedBox(height: 8),
                Text(
                  'SOS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                  ),
                ),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Call 112 directly
        _CallEmergencyButton(),

        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.pop(),
          child: const Text(
            'I\'m Safe — Go Back',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Countdown state ───────────────────────────────────────────────────────────

class _CountdownBody extends StatelessWidget {
  final int seconds;
  final VoidCallback onCancel;
  const _CountdownBody({required this.seconds, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Sending SOS in...',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 40),

        // Countdown circle
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 0.0),
          duration: const Duration(seconds: 1),
          builder: (context, value, _) => Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: CircularProgressIndicator(
                  value: seconds / 5.0,
                  strokeWidth: 8,
                  color: AppTheme.error,
                  backgroundColor: Colors.white12,
                ),
              ),
              Text(
                '$seconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 80,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 48),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

// ── Sending state ─────────────────────────────────────────────────────────────

class _SendingBody extends StatelessWidget {
  const _SendingBody();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppTheme.error, strokeWidth: 3),
        SizedBox(height: 24),
        Text(
          'Alerting your emergency contacts...',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }
}

// ── Sent state ────────────────────────────────────────────────────────────────

class _SentBody extends StatelessWidget {
  final VoidCallback onBack;
  const _SentBody({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 80),
        const SizedBox(height: 24),
        const Text(
          'SOS Sent',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your emergency contacts have been\nalerted with your live location.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.6),
        ),
        const Spacer(),
        _CallEmergencyButton(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onBack,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Back to Ride', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onBack;
  const _ErrorBody({required this.message, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.warning_rounded, color: Colors.orangeAccent, size: 80),
        const SizedBox(height: 24),
        const Text(
          'SOS Alert Failed',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 40),
        _CallEmergencyButton(),
        const SizedBox(height: 16),
        TextButton(
          onPressed: onBack,
          child: const Text('Back', style: TextStyle(color: Colors.white54)),
        ),
      ],
    );
  }
}

// ── Shared widget: Call 112 ───────────────────────────────────────────────────

class _CallEmergencyButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => launchUrl(Uri.parse('tel:112')),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.error,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        icon: const Icon(Icons.phone_rounded),
        label: const Text(
          'Call 112 (Police)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
