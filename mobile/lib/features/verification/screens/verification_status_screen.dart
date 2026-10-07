import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// VerificationStatusScreen — shown after face registration attempt.
class VerificationStatusScreen extends ConsumerWidget {
  const VerificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isVerified = user?.faceVerified ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isVerified
                  ? Icons.verified_user_rounded
                  : Icons.pending_rounded,
              size: 80,
              color: isVerified ? AppTheme.success : AppTheme.warning,
            ),
            const SizedBox(height: 24),
            Text(
              isVerified ? 'Verified!' : 'Verification Pending',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              isVerified
                  ? 'Your face has been verified. You\'re ready to ride!'
                  : 'Your verification is being processed. '
                      'This usually takes a few minutes.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: AppTheme.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.go(AppRoutes.passengerHome),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
