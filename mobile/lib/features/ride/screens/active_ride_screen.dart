import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';
import '../ride_service.dart';

/// ActiveRideScreen — shown after a ride is booked.
///
/// WHAT THIS SCREEN DOES:
///   - Shows the Google Map with pickup + drop markers
///   - Polls ride status every 5 seconds (via ActiveRideNotifier)
///   - Updates the status banner in real time:
///       searching → "Finding your driver..."
///       confirmed → "Driver assigned" + driver card
///       driver_arriving → "Driver is on the way" + ETA
///       otp_pending → "Ready to board — show your OTP"
///       in_progress → "Trip in progress"
///       completed → navigates to rating screen
///       cancelled → shows cancellation screen
///   - Cancel button (visible until trip starts)
///
/// SOCKET.IO FOR LIVE LOCATION:
///   In Task 6 we add the socket connection so the driver marker
///   moves in real time. For now the map shows static pickup/drop markers.
///   The status updates (searching → confirmed) come from polling.
///
/// The screen receives rideId via go_router path parameter (:rideId).
/// It starts tracking as soon as it mounts.

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    // Start polling this specific ride
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeRideProvider.notifier).startTracking(widget.rideId);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Set<Marker> _buildMarkers(RideModel ride) {
    return {
      // Pickup — green marker
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(ride.pickupLat, ride.pickupLng),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
            title: 'Pickup', snippet: ride.pickupAddress),
      ),
      // Drop — red marker
      Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(ride.dropLat, ride.dropLng),
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow:
            InfoWindow(title: 'Drop', snippet: ride.dropAddress),
      ),
    };
  }

  // Fit the camera to show both pickup and drop
  void _fitMap(RideModel ride) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            ride.pickupLat < ride.dropLat ? ride.pickupLat : ride.dropLat,
            ride.pickupLng < ride.dropLng ? ride.pickupLng : ride.dropLng,
          ),
          northeast: LatLng(
            ride.pickupLat > ride.dropLat ? ride.pickupLat : ride.dropLat,
            ride.pickupLng > ride.dropLng ? ride.pickupLng : ride.dropLng,
          ),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeRideProvider);

    // Handle terminal states — navigate away
    ref.listen<ActiveRideState>(activeRideProvider, (_, next) {
      if (next is ActiveRideCancelled) {
        context.go(AppRoutes.passengerHome);
      }
      if (next is ActiveRideLoaded && next.ride.isCompleted) {
        final router = GoRouter.of(context);
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            router.pushReplacement(
              AppRoutes.rating.replaceAll(':rideId', widget.rideId),
            );
          }
        });
      }
    });

    return PopScope(
      // Prevent accidental back press during an active ride
      canPop: false,
      onPopInvokedWithResult: (_, __) => _showCancelDialog(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (state) {
          ActiveRideLoading() => const _LoadingView(),
          ActiveRideError(:final message) => _ErrorView(message: message),
          ActiveRideCancelled() => const _CancelledView(),
          ActiveRideCancelling(:final ride) => _RideView(
              ride: ride,
              mapController: _mapController,
              onMapCreated: (c) {
                _mapController = c;
                _fitMap(ride);
              },
              markers: _buildMarkers(ride),
              isCancelling: true,
              onCancelTap: () {},
            ),
          ActiveRideLoaded(:final ride) => _RideView(
              ride: ride,
              mapController: _mapController,
              onMapCreated: (c) {
                _mapController = c;
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _fitMap(ride));
              },
              markers: _buildMarkers(ride),
              isCancelling: false,
              onCancelTap: () => _showCancelDialog(context),
            ),
          _ => const _LoadingView(),
        },
      ),
    );
  }

  Future<void> _showCancelDialog(BuildContext context) async {
    final state = ref.read(activeRideProvider);
    if (state is! ActiveRideLoaded) return;
    if (!state.ride.canCancel) return;

    // Capture before any async gaps to satisfy use_build_context_synchronously
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: Text(
          state.ride.isConfirmed
              ? 'Cancelling after a driver is assigned will deduct ₹50 from your wallet.'
              : 'Are you sure you want to cancel this ride?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await ref.read(activeRideProvider.notifier).cancelRide();
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(e.toString()),
              backgroundColor: AppTheme.error,
            ),
          );
        }
      }
    }
  }
}

// ── Main ride view — map + bottom card ───────────────────────────────────────

class _RideView extends StatelessWidget {
  final RideModel ride;
  final GoogleMapController? mapController;
  final void Function(GoogleMapController) onMapCreated;
  final Set<Marker> markers;
  final bool isCancelling;
  final VoidCallback onCancelTap;

  const _RideView({
    required this.ride,
    required this.mapController,
    required this.onMapCreated,
    required this.markers,
    required this.isCancelling,
    required this.onCancelTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Map ──────────────────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(ride.pickupLat, ride.pickupLng),
            zoom: 14,
          ),
          onMapCreated: onMapCreated,
          markers: markers,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          myLocationEnabled: false,
        ),

        // ── Top status banner ─────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _StatusBanner(ride: ride),
            ),
          ),
        ),

        // ── Bottom card ───────────────────────────────────────────────────
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomCard(
            ride: ride,
            isCancelling: isCancelling,
            onCancelTap: onCancelTap,
          ),
        ),
      ],
    );
  }
}

// ── Status banner ─────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final RideModel ride;
  const _StatusBanner({required this.ride});

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon) = switch (ride.status) {
      'searching' || 'matching' => (AppTheme.warning, Icons.search_rounded),
      'confirmed' || 'driver_arriving' => (AppTheme.success, Icons.directions_car),
      'otp_pending' => (AppTheme.primary, Icons.lock_open_rounded),
      'in_progress' => (AppTheme.accent, Icons.navigation_rounded),
      'completed' => (AppTheme.success, Icons.check_circle),
      _ => (AppTheme.textSecondary, Icons.info_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              ride.statusLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          // Pulsing indicator for active states
          if (ride.isSearching || ride.isConfirmed)
            _PulsingDot(color: Colors.white.withOpacity(0.8)),
        ],
      ),
    );
  }
}

// ── Bottom card ───────────────────────────────────────────────────────────────

class _BottomCard extends StatelessWidget {
  final RideModel ride;
  final bool isCancelling;
  final VoidCallback onCancelTap;

  const _BottomCard({
    required this.ride,
    required this.isCancelling,
    required this.onCancelTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20, MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── Trip info row ────────────────────────────────────────────
          Row(
            children: [
              // Pickup/drop column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AddressRow(
                      icon: Icons.radio_button_checked,
                      color: AppTheme.success,
                      address: ride.pickupAddress,
                    ),
                    const SizedBox(height: 4),
                    _AddressRow(
                      icon: Icons.location_on,
                      color: AppTheme.primary,
                      address: ride.dropAddress,
                    ),
                  ],
                ),
              ),

              // Fare
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${ride.finalFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    ride.paymentMethod == 'cash' ? 'Cash' : 'UPI',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ],
          ),

          // ── Driver card (shown once assigned) ────────────────────────
          if (ride.driver != null) ...[
            const SizedBox(height: 16),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 14),
            _DriverCard(driver: ride.driver!),
          ],

          // ── OTP hint ─────────────────────────────────────────────────
          if (ride.status == 'otp_pending') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_open_rounded,
                      size: 16, color: AppTheme.primary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Show your OTP to the driver to start the trip.',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Cancel button ────────────────────────────────────────────
          if (ride.canCancel) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: isCancelling ? null : onCancelTap,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: const BorderSide(color: AppTheme.error),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isCancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.error,
                        ),
                      )
                    : const Text('Cancel Ride'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Driver card ───────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final DriverInfo driver;
  const _DriverCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Avatar
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, color: AppTheme.primary, size: 24),
        ),
        const SizedBox(width: 12),

        // Name + vehicle
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                driver.fullName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '${driver.vehicleDisplay} • ${driver.vehicleNumber}',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),

        // Rating + call button
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded,
                    size: 14, color: AppTheme.warning),
                const SizedBox(width: 2),
                Text(
                  driver.reliabilityScore.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

// ── Address row ───────────────────────────────────────────────────────────────

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String address;

  const _AddressRow({
    required this.icon,
    required this.color,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            address,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Pulsing dot — animated for active states ──────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // AnimationController drives the animation from 0.0 to 1.0
    // repeat(reverse: true) makes it ping-pong back and forth
    _controller = AnimationController(
      vsync: this, // vsync = this because we mixin SingleTickerProviderStateMixin
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose(); // always dispose animation controllers
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Terminal state screens ────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primary),
            SizedBox(height: 16),
            Text('Loading your ride...',
                style: TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});

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
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.passengerHome),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary),
                child: const Text('Go Home',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CancelledView extends StatelessWidget {
  const _CancelledView();

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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your ride has been cancelled.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go(AppRoutes.passengerHome),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Book Another Ride',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
