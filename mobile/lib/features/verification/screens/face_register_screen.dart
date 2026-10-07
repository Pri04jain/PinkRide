import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';

/// FaceRegisterScreen — captures a selfie for face registration.
/// Full implementation uses the `camera` package. This is a functional stub.
class FaceRegisterScreen extends StatelessWidget {
  const FaceRegisterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Register Your Face'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.primary, width: 3),
                borderRadius: BorderRadius.circular(130),
              ),
              child: const Icon(Icons.face_rounded,
                  size: 100, color: Colors.white54),
            ),
            const SizedBox(height: 32),
            const Text(
              'Position your face in the circle',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () =>
                  context.pushReplacement(AppRoutes.verificationStatus),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Take Selfie'),
            ),
          ],
        ),
      ),
    );
  }
}
