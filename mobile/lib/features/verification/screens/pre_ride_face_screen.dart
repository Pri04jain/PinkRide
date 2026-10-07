import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// PreRideFaceScreen — face check immediately before boarding.
/// Full implementation uses the camera + backend verification API.
class PreRideFaceScreen extends StatelessWidget {
  final String ridePassengerId;
  final String rideId;

  const PreRideFaceScreen({
    super.key,
    required this.ridePassengerId,
    required this.rideId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Pre-Ride Check'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.accent, width: 3),
                borderRadius: BorderRadius.circular(120),
              ),
              child: const Icon(Icons.face_rounded,
                  size: 80, color: Colors.white54),
            ),
            const SizedBox(height: 32),
            const Text(
              'Quick face check before your ride',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.camera_alt_rounded),
              label: const Text('Verify & Board'),
            ),
          ],
        ),
      ),
    );
  }
}
