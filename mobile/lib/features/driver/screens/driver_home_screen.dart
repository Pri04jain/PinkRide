import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/driver_provider.dart';
import '../widgets/availability_toggle.dart';
import '../widgets/driver_stats_bar.dart';
import '../widgets/ride_request_card.dart';

/// DriverHomeScreen — the main screen for approved drivers.
///
/// STATE MACHINE (driven by DriverHomeState):
///   Loading           → spinner (initial profile fetch)
///   NoProfile         → CTA to register as a driver
///   PendingApproval   → hand-off to DriverStatusScreen sub-widget
///   Ready             → full dashboard (toggle + requests + stats)
///   Error             → error with retry (transient errors show snackbar)
///
/// The screen uses ref.listen to catch transient DriverHomeError states
/// and show a SnackBar, then the notifier automatically reloads.

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Listen for transient errors (toggle/accept failures) → show snackbar
    ref.listen<DriverHomeState>(driverHomeProvider, (_, next) {
      if (next is DriverHomeError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    final state = ref.watch(driverHomeProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🌸',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(width: 6),
            Text('PinkRide Driver'),
          ],
        ),
        actions: [
          // Profile / logout menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'logout') {
                await ref.read(authStateProvider.notifier).logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppTheme.error),
                    SizedBox(width: 8),
                    Text('Log out',
                        style: TextStyle(color: AppTheme.error)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: switch (state) {
        DriverHomeLoading() => const Center(
            child: CircularProgressIndicator(color: AppTheme.primary),
          ),

        DriverHomeError(:final message) => _ErrorBody(
            message: message,
            onRetry: () =>
                ref.read(driverHomeProvider.notifier).loadProfile(),
          ),

        DriverHomeNoProfile() => _NoProfileBody(
            onRegister: () => context.push(AppRoutes.driverRegister),
          ),

        DriverHomePendingApproval(:final driver) => _PendingBody(
            driver: driver,
            onViewStatus: () => context.push(AppRoutes.driverStatus),
          ),

        DriverHomeReady() => _DashboardBody(
            state: state,
            onToggle: () =>
                ref.read(driverHomeProvider.notifier).toggleAvailability(),
            onRefresh: () =>
                ref.read(driverHomeProvider.notifier).refreshRideRequests(),
            onAccept: (rideId) =>
                ref.read(driverHomeProvider.notifier).acceptRide(rideId),
          ),
      },
    );
  }
}

// ── Dashboard body (approved driver) ─────────────────────────────────────────

class _DashboardBody extends StatelessWidget {
  final DriverHomeReady state;
  final VoidCallback onToggle;
  final Future<void> Function() onRefresh;
  final void Function(String rideId) onAccept;

  const _DashboardBody({
    required this.state,
    required this.onToggle,
    required this.onRefresh,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final driver = state.driver;

    return RefreshIndicator(
      color: AppTheme.primary,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting
          Text(
            'Hello, ${driver.fullName?.split(' ').first ?? 'Driver'} 👋',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            driver.vehicleDisplay,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),

          const SizedBox(height: 16),

          // Online / offline toggle
          AvailabilityToggle(
            isOnline: driver.isAvailable,
            isLoading: state.isTogglingAvailability,
            onToggle: onToggle,
          ),

          const SizedBox(height: 16),

          // Stats row
          DriverStatsBar(driver: driver),

          const SizedBox(height: 24),

          // Ride requests section
          if (driver.isAvailable) ...[
            Row(
              children: [
                const Text(
                  'Nearby Requests',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                if (state.isLoadingRequests)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onRefresh,
                    child: const Icon(
                      Icons.refresh,
                      size: 20,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (!state.isLoadingRequests && state.rideRequests.isEmpty)
              _EmptyRequests()
            else
              ...state.rideRequests.map(
                (ride) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RideRequestCard(
                    ride: ride,
                    onAccept: () => onAccept(ride.id),
                  ),
                ),
              ),
          ] else ...[
            // Offline state hint
            _OfflineHint(),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _EmptyRequests extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Column(
        children: [
          Icon(Icons.search_off_outlined, size: 40, color: AppTheme.textHint),
          SizedBox(height: 10),
          Text(
            'No ride requests nearby',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Pull down to refresh',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }
}

class _OfflineHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.power_settings_new_rounded,
            size: 44,
            color: AppTheme.textHint,
          ),
          SizedBox(height: 12),
          Text(
            'You are offline',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Toggle the switch above to go online\nand start receiving ride requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }
}

// ── No profile CTA ────────────────────────────────────────────────────────────

class _NoProfileBody extends StatelessWidget {
  final VoidCallback onRegister;
  const _NoProfileBody({required this.onRegister});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.drive_eta_outlined,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Become a PinkRide Driver',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'Register your vehicle and driving license to\nstart accepting rides and earn with PinkRide.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: onRegister,
              icon: const Icon(Icons.app_registration_outlined, size: 20),
              label: const Text('Register as Driver'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending approval ──────────────────────────────────────────────────────────

class _PendingBody extends StatelessWidget {
  final dynamic driver; // DriverModel
  final VoidCallback onViewStatus;
  const _PendingBody({required this.driver, required this.onViewStatus});

  @override
  Widget build(BuildContext context) {
    final isUnderReview = driver.approvalStatus == 'under_review';
    final isRejected = driver.approvalStatus == 'rejected';
    final isSuspended = driver.approvalStatus == 'suspended';

    final Color statusColor = isUnderReview
        ? AppTheme.warning
        : isRejected || isSuspended
            ? AppTheme.error
            : AppTheme.textSecondary;

    final IconData statusIcon = isUnderReview
        ? Icons.hourglass_top_rounded
        : isRejected
            ? Icons.cancel_outlined
            : isSuspended
                ? Icons.block_outlined
                : Icons.pending_outlined;

    final String title = isUnderReview
        ? 'Application Under Review'
        : isRejected
            ? 'Application Rejected'
            : isSuspended
                ? 'Account Suspended'
                : 'Application Pending';

    final String subtitle = isUnderReview
        ? 'Our team is reviewing your documents.\nThis usually takes 1–2 business days.'
        : isRejected
            ? 'Your application was not approved.\nTap below to see the reason and next steps.'
            : isSuspended
                ? 'Your account has been temporarily suspended.\nContact support for assistance.'
                : 'Complete your document uploads to submit\nyour application for review.';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, size: 40, color: statusColor),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: onViewStatus,
              icon: const Icon(Icons.info_outline, size: 18),
              label: const Text('View Application Status'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Error body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 52, color: AppTheme.textHint),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 160,
            height: 48,
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Try Again'),
            ),
          ),
        ],
      ),
    );
  }
}
