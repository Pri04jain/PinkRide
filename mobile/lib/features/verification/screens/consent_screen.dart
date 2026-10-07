import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// ConsentScreen — shown before face registration.
/// User must explicitly consent to face data being collected.
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Face Verification')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.face_retouching_natural_rounded,
                size: 64, color: AppTheme.primary),
            const SizedBox(height: 24),
            const Text(
              'Secure Face Verification',
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              'PinkRide uses face verification to ensure every ride '
              'is taken by the registered passenger. Your face data is '
              'encrypted and never shared with third parties.',
              style: TextStyle(
                  fontSize: 15, color: AppTheme.textSecondary, height: 1.6),
            ),
            const SizedBox(height: 32),
            _ConsentPoint(
              icon: Icons.security_rounded,
              text: 'Your biometric data is encrypted end-to-end.',
            ),
            _ConsentPoint(
              icon: Icons.delete_outline_rounded,
              text: 'You can delete your face data at any time.',
            ),
            _ConsentPoint(
              icon: Icons.visibility_off_outlined,
              text: 'We never store raw photos — only a secure reference.',
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => context.push(AppRoutes.faceRegister),
                child: const Text('I Agree — Continue'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('Not Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentPoint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ConsentPoint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
          ),
        ],
      ),
    );
  }
}
