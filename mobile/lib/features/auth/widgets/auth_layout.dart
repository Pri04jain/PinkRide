import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// AuthLayout — shared scaffold for all auth screens.
///
/// Provides:
///   - Pink header bar with icon + title + subtitle
///   - Scrollable content area (so keyboard doesn't clip the form)
///   - Consistent horizontal padding
///
/// Usage:
///   AuthLayout(
///     icon: Icons.phone_android,
///     title: 'Enter Your\nPhone Number',
///     subtitle: 'We\'ll send you a verification code.',
///     child: <your form widgets>,
///   )

class AuthLayout extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  const AuthLayout({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      // resizeToAvoidBottomInset: true (default) — scaffold shrinks when
      // the keyboard appears, pushing content up so the button is visible.
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            _AuthHeader(icon: icon, title: title, subtitle: subtitle),

            // ── Content ────────────────────────────────────────────────────
            // Expanded + SingleChildScrollView:
            // Expanded fills remaining space; SingleChildScrollView lets
            // content scroll when the keyboard is open.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AuthHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
      decoration: const BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon in a white circle
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
