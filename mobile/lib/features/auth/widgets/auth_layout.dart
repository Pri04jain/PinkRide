import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// AuthLayout — shared scaffold for all three auth screens.
///
/// Gives every auth screen the same structure:
///   - Pink gradient header with icon + title + subtitle
///   - White rounded bottom sheet with the form content
///
/// WHY EXTRACT THIS TO A WIDGET?
/// PhoneInputScreen, OtpVerifyScreen, and ProfileSetupScreen all need
/// the same visual shell. Without this, you'd copy-paste 60 lines of
/// identical scaffold code three times. If the design changes (e.g. logo
/// colour), you'd need to update it in three places.
/// Extracted once → maintained once.

class AuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child; // the form content — different for each screen

  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // No app bar — full screen layout
      backgroundColor: AppTheme.primary,
      body: Column(
        children: [
          // ── Pink header ─────────────────────────────────────────────────
          Expanded(
            flex: 2,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // App icon
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 20),

                    // Screen title
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Screen subtitle
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── White form card ──────────────────────────────────────────────
          // flex: 5 means this takes 5/7 of the screen height
          Expanded(
            flex: 5,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(32),
                ),
              ),
              child: SingleChildScrollView(
                // Padding ensures content isn't hidden behind the keyboard
                padding: EdgeInsets.fromLTRB(
                  24,
                  32,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 32,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
