import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../tracking/providers/tracking_provider.dart';
import '../../tracking/screens/live_tracking_screen.dart';
import '../providers/ride_provider.dart';
import '../ride_service.dart';

/// ActiveRideScreen — the main view once a ride is confirmed.
///
/// STATES:
///   searching        → spinner + "Finding your driver"
///   driver_assigned  → driver card + confirm face check CTA
///   driver_arriving  → live map (LiveTrackingScreen)
///   in_progress      → live map (LiveTrackingScreen) + safety strip
///   completed        → summary card → navigate to payment
///   cancelled        → cancellation screen
///
/// The screen polls via ActiveRideNotifier every 5s (existing logic) and
/// listens for socket-based location updates via TrackingNotifier.

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;

  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRideProvider.notifier).startTracking(widget.rideId);
      ref.read(trackingProvider.notifier).startTracking(widget.rideId);
    });
  }

  @override
  void dispose() {
    ref.read(trackingProvider.notifier).stopTracking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeRideProvider);

    // Navigate to payment when ride completes
    ref.listen<ActiveRideState>(activeRideProvider, (_, next) {
      if (next is ActiveRideLoaded && next.ride.isCompleted) {
        final ride = next.ride;
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          context.go(
            AppRoutes.payment.replaceAll(':rideId', ride.id),
            extra: {
              'paymentMethod': ride.paymentMethod ?? 'cash',
              'amount': ride.finalFare ?? 0,
            },
          );
        });
      }
    });

    return switch (state) {
      ActiveRideLoading() => const _LoadingScaffold(),
      ActiveRideNone()    => _NoRideScaffold(rideId: widget.rideId),
      ActiveRideCancelling(:final ride) => _CancellingScaffold(ride: ride),
      ActiveRideCancelled() => _CancelledScaffold(),
      ActiveRideError(:final message) => _ErrorScaffold(message: message),
      ActiveRideLoaded(:final ride) => _buildLoaded(context, ride),
    };
  }

  Widget _buildLoaded(BuildContext context, RideModel ride) {
    // Full-screen map for live tracking statuses
    if (ride.status == 'driver_arriving' || ride.status == 'in_progress') {
      return LiveTrackingScreen(rideId: widget.rideId, ride: ride);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Your Ride'),
        backgroundColor: AppTheme.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.sos_rounded, color: AppTheme.error),
            tooltip: 'SOS',
            onPressed: () => context.push(
              AppRoutes.sos,
              extra: {'rideId': widget.rideId},
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _StatusTimeline(status: ride.status),
            const SizedBox(height: 24),
            _RouteCard(ride: ride),
            const SizedBox(height: 16),
            if (ride.driverId != null) ...[
              _DriverCard(ride: ride, rideId: widget.rideId),
              const SizedBox(height: 16),
            ],
            if (ride.isCompleted) ...[
              _CompletionCard(ride: ride),
              const SizedBox(height: 16),
            ],
            if (!ride.isCompleted && !ride.isCancelled)
              _CancelButton(rideId: widget.rideId),
          ],
        ),
      ),
    );
  }
}

// ── Status timeline ───────────────────────────────────────────────────────────

class _StatusTimeline extends StatelessWidget {
  final String status;
  const _StatusTimeline({required this.status});

  static const _steps = [
    ('searching',        'Finding Driver'),
    ('driver_assigned',  'Driver Assigned'),
    ('driver_arriving',  'Driver Arriving'),
    ('in_progress',      'Ride in Progress'),
    ('completed',        'Completed'),
  ];

  int get _currentIndex =>
      _steps.indexWhere((s) => s.$1 == status).clamp(0, _steps.length - 1);

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: _steps.asMap().entries.map((entry) {
          final i = entry.key;
          final (_, label) = entry.value;
          final isDone    = i < current;
          final isCurrent = i == current;
          final isLast    = i == _steps.length - 1;

          return Column(
            children: [
              Row(
                children: [
                  // Circle indicator
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? AppTheme.success
                          : isCurrent
                              ? AppTheme.primary
                              : AppTheme.divider,
                    ),
                    child: Center(
                      child: isDone
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 16)
                          : isCurrent
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent
                          ? FontWeight.w700
                          : FontWeight.normal,
                      color: isDone || isCurrent
                          ? AppTheme.textPrimary
                          : AppTheme.textHint,
                    ),
                  ),
                  if (isCurrent) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'NOW',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (!isLast)
                Padding(
                  padding: const EdgeInsets.only(left: 13),
                  child: Container(
                    width: 2,
                    height: 20,
                    color: isDone ? AppTheme.success : AppTheme.divider,
                  ),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Route card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final RideModel ride;
  const _RouteCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your Route',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.radio_button_checked_rounded,
                  color: AppTheme.success, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pickup',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textHint)),
                    Text(
                      ride.pickupAddress,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 9),
            child: Container(width: 2, height: 16, color: AppTheme.divider),
          ),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppTheme.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Drop',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.textHint)),
                    Text(
                      ride.dropAddress,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (ride.finalFare != null) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fare',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 13)),
                Text(
                  '₹${ride.finalFare!.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Driver card ───────────────────────────────────────────────────────────────

class _DriverCard extends ConsumerWidget {
  final RideModel ride;
  final String rideId;
  const _DriverCard({required this.ride, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.primaryLight.withValues(alpha: 0.2),
            ),
            child: const Icon(Icons.person_rounded,
                color: AppTheme.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Your Driver',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textHint),
                ),
                Text(
                  ride.driverId ?? '—',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.star_rounded,
                        color: AppTheme.warning, size: 14),
                    const SizedBox(width: 3),
                    const Text('4.8',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          // Pre-ride face check CTA — shown when driver assigned but not yet verified
          if (ride.status == 'driver_assigned')
            ElevatedButton.icon(
              onPressed: () => context.push(
                AppRoutes.preRideFace,
                extra: {
                  'ridePassengerId': rideId,
                  'rideId': rideId,
                },
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.face_rounded, size: 16),
              label: const Text('Verify', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

// ── Completion card ───────────────────────────────────────────────────────────

class _CompletionCard extends StatelessWidget {
  final RideModel ride;
  const _CompletionCard({required this.ride});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.success, Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Ride Complete!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (ride.finalFare != null) ...[
            const SizedBox(height: 8),
            Text(
              'Fare: ₹${ride.finalFare!.toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 16),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'Redirecting to payment…',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Cancel button ─────────────────────────────────────────────────────────────

class _CancelButton extends ConsumerWidget {
  final String rideId;
  const _CancelButton({required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Cancel Ride?'),
              content: const Text(
                  'A cancellation fee may apply from your wallet.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Keep Ride'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Cancel',
                      style: TextStyle(color: AppTheme.error)),
                ),
              ],
            ),
          );
          if (confirm == true) {
            try {
              await ref
                  .read(activeRideProvider.notifier)
                  .cancelRide(reason: 'Cancelled by passenger');
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(e.toString()),
                  backgroundColor: AppTheme.error,
                ),
              );
            }
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.error,
          side: const BorderSide(color: AppTheme.error),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('Cancel Ride'),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scaffolds for non-loaded states
// ─────────────────────────────────────────────────────────────────────────────

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 20),
            Text('Finding your ride…',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _NoRideScaffold extends StatelessWidget {
  final String rideId;
  const _NoRideScaffold({required this.rideId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.directions_car_outlined,
                size: 72, color: AppTheme.textHint),
            const SizedBox(height: 20),
            const Text('Ride not found.',
                style: TextStyle(fontSize: 18, color: AppTheme.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.passengerHome),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancellingScaffold extends StatelessWidget {
  final RideModel ride;
  const _CancellingScaffold({required this.ride});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.error),
            SizedBox(height: 20),
            Text('Cancelling your ride…',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _CancelledScaffold extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cancel_outlined,
                  size: 72, color: AppTheme.error),
              const SizedBox(height: 20),
              const Text(
                'Ride Cancelled',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 10),
              const Text(
                'Any applicable cancellation fee has been\ndeducted from your wallet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go(AppRoutes.passengerHome),
                  child: const Text('Back to Home'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  final String message;
  const _ErrorScaffold({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline,
                  size: 64, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.passengerHome),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
