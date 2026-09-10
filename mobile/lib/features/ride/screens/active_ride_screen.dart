import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';
import '../providers/socket_provider.dart';
import '../ride_service.dart';

/// ActiveRideScreen — shown after a ride is booked.
///
/// Task 6 additions over Task 5:
///   - Connects to Socket.io on mount, disconnects on dispose
///   - Driver marker moves in real time via driver_location_update events
///   - Deviation alert bottom sheet appears when route_deviation arrives
///   - SOS button always visible during in_progress — 5s countdown then fires
///   - SOS banner shown after SOS is triggered

class ActiveRideScreen extends ConsumerStatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  final _mapController = MapController();
  bool _deviationSheetOpen = false; // guard against opening the sheet twice

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Start polling (status updates)
      ref.read(activeRideProvider.notifier).startTracking(widget.rideId);
      // Start socket (live location + safety events)
      ref.read(driverLocationProvider.notifier).startListening(widget.rideId);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    // Stop socket listeners and disconnect when screen is gone
    ref.read(driverLocationProvider.notifier).stopListening();
    super.dispose();
  }

  // ── Build marker list ─────────────────────────────────────────────────────
  // Pickup + drop are always shown.
  // Driver marker is added only when we have a live location from the socket.

  List<Marker> _buildMarkers(RideModel ride, DriverLocation? driverLoc) {
    return [
      // Pickup — green
      Marker(
        point: LatLng(ride.pickupLat, ride.pickupLng),
        width: 40,
        height: 40,
        child: const Icon(Icons.radio_button_checked,
            color: AppTheme.success, size: 28,
            shadows: [Shadow(blurRadius: 4, color: Colors.black26)]),
      ),
      // Drop — pink
      Marker(
        point: LatLng(ride.dropLat, ride.dropLng),
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on,
            color: AppTheme.primary, size: 36,
            shadows: [Shadow(blurRadius: 4, color: Colors.black26)]),
      ),
      // Driver — blue car icon, only when socket has sent a location
      if (driverLoc != null)
        Marker(
          point: driverLoc.position,
          width: 48,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.secondary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: AppTheme.secondary.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 2)
              ],
            ),
            child: const Icon(Icons.directions_car,
                color: Colors.white, size: 24),
          ),
        ),
    ];
  }

  void _fitMap(RideModel ride) {
    final bounds = LatLngBounds.fromPoints([
      LatLng(ride.pickupLat, ride.pickupLng),
      LatLng(ride.dropLat, ride.dropLng),
    ]);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
    );
  }

  // Pan camera to follow driver when a new location arrives
  void _followDriver(LatLng position) {
    _mapController.move(position, _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(activeRideProvider);
    final socketState = ref.watch(driverLocationProvider);

    // ── Terminal ride state navigation ────────────────────────────────────
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

    // ── Driver location: follow on map ────────────────────────────────────
    ref.listen<DriverLocationState>(driverLocationProvider, (prev, next) {
      final newLoc = next.driverLocation;
      final oldLoc = prev?.driverLocation;
      if (newLoc != null && newLoc != oldLoc) {
        _followDriver(newLoc.position);
      }

      // ── Deviation alert sheet ─────────────────────────────────────────
      if (next.deviationAlert != null &&
          prev?.deviationAlert == null &&
          !_deviationSheetOpen) {
        _deviationSheetOpen = true;
        _showDeviationSheet(context, next.deviationAlert!);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) => _showCancelDialog(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: switch (rideState) {
          ActiveRideLoading() => const _LoadingView(),
          ActiveRideError(:final message) => _ErrorView(message: message),
          ActiveRideCancelled() => const _CancelledView(),
          ActiveRideCancelling(:final ride) => _RideView(
              ride: ride,
              mapController: _mapController,
              onFitMap: () => _fitMap(ride),
              markers: _buildMarkers(ride, socketState.driverLocation),
              isCancelling: true,
              onCancelTap: () {},
              sosTriggered: socketState.sosTriggered,
              onSosTap: () => ref
                  .read(driverLocationProvider.notifier)
                  .triggerSos(),
            ),
          ActiveRideLoaded(:final ride) => _RideView(
              ride: ride,
              mapController: _mapController,
              onFitMap: () => WidgetsBinding.instance
                  .addPostFrameCallback((_) => _fitMap(ride)),
              markers: _buildMarkers(ride, socketState.driverLocation),
              isCancelling: false,
              onCancelTap: () => _showCancelDialog(context),
              sosTriggered: socketState.sosTriggered,
              onSosTap: () => ref
                  .read(driverLocationProvider.notifier)
                  .triggerSos(),
            ),
          _ => const _LoadingView(),
        },
      ),
    );
  }

  // ── Deviation alert bottom sheet ──────────────────────────────────────────
  // Slides up when the server detects the driver went off route.
  // Passenger has two options: "I'm okay" or "Alert my contacts".

  void _showDeviationSheet(BuildContext context, DeviationAlert alert) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,   // force the passenger to make a choice
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeviationAlertSheet(
        alert: alert,
        onOk: () {
          Navigator.of(context).pop();
          _deviationSheetOpen = false;
          ref.read(driverLocationProvider.notifier).respondToDeviation('ok');
        },
        onAlert: () {
          Navigator.of(context).pop();
          _deviationSheetOpen = false;
          ref
              .read(driverLocationProvider.notifier)
              .respondToDeviation('alert');
        },
      ),
    ).whenComplete(() => _deviationSheetOpen = false);
  }

  // ── Cancel dialog ─────────────────────────────────────────────────────────

  Future<void> _showCancelDialog(BuildContext context) async {
    final state = ref.read(activeRideProvider);
    if (state is! ActiveRideLoaded) return;
    if (!state.ride.canCancel) return;

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
          messenger.showSnackBar(SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
          ));
        }
      }
    }
  }
}

// ── Main ride view ────────────────────────────────────────────────────────────

class _RideView extends StatelessWidget {
  final RideModel ride;
  final MapController mapController;
  final VoidCallback onFitMap;
  final List<Marker> markers;
  final bool isCancelling;
  final VoidCallback onCancelTap;
  final bool sosTriggered;
  final VoidCallback onSosTap;

  const _RideView({
    required this.ride,
    required this.mapController,
    required this.onFitMap,
    required this.markers,
    required this.isCancelling,
    required this.onCancelTap,
    required this.sosTriggered,
    required this.onSosTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // ── OpenStreetMap ─────────────────────────────────────────────────
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: LatLng(ride.pickupLat, ride.pickupLng),
            initialZoom: 14,
            onMapReady: onFitMap,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.pinkride.pinkride',
            ),
            MarkerLayer(markers: markers),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),

        // ── SOS triggered banner ──────────────────────────────────────────
        if (sosTriggered)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.error,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'SOS alert sent. Emergency contacts have been notified.',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // ── Status banner ─────────────────────────────────────────────────
        Positioned(
          top: sosTriggered ? 80 : 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _StatusBanner(ride: ride),
            ),
          ),
        ),

        // ── SOS button — always visible during in_progress ────────────────
        if (ride.isInProgress && !sosTriggered)
          Positioned(
            right: 16,
            bottom: 280,
            child: _SosButton(onTap: onSosTap),
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

// ── SOS button ────────────────────────────────────────────────────────────────
// Pulsing red circle. Tapping starts a 5-second countdown — if the user
// doesn't cancel within 5 seconds, the SOS fires.

class _SosButton extends StatefulWidget {
  final VoidCallback onTap;
  const _SosButton({required this.onTap});

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  bool _counting = false;
  int _countdown = 5;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    setState(() {
      _counting = true;
      _countdown = 5;
    });
    _tick();
  }

  void _tick() {
    if (!mounted || !_counting) return;
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || !_counting) return;
      setState(() => _countdown--);
      if (_countdown <= 0) {
        widget.onTap();
      } else {
        _tick();
      }
    });
  }

  void _cancel() {
    setState(() {
      _counting = false;
      _countdown = 5;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _counting ? _cancel : _startCountdown,
      child: ScaleTransition(
        scale: _counting ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: _counting ? AppTheme.warning : AppTheme.error,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (_counting ? AppTheme.warning : AppTheme.error)
                    .withOpacity(0.5),
                blurRadius: 12,
                spreadRadius: 3,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_counting)
                const Icon(Icons.sos, color: Colors.white, size: 28)
              else ...[
                Text(
                  '$_countdown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'TAP TO\nCANCEL',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Deviation alert bottom sheet ──────────────────────────────────────────────

class _DeviationAlertSheet extends StatefulWidget {
  final DeviationAlert alert;
  final VoidCallback onOk;
  final VoidCallback onAlert;

  const _DeviationAlertSheet({
    required this.alert,
    required this.onOk,
    required this.onAlert,
  });

  @override
  State<_DeviationAlertSheet> createState() => _DeviationAlertSheetState();
}

class _DeviationAlertSheetState extends State<_DeviationAlertSheet> {
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.alert.responseDeadlineSeconds;
    _tick();
  }

  void _tick() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft > 0) _tick();
      // At 0 the server auto-alerts contacts — sheet stays open but
      // the countdown label changes to "Contacts alerted"
    });
  }

  @override
  Widget build(BuildContext context) {
    final distanceText =
        '${widget.alert.deviationMeters.toStringAsFixed(0)} m off route';

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Alert header ───────────────────────────────────────────────
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded,
                color: AppTheme.error, size: 28),
          ),
          const SizedBox(height: 14),
          const Text(
            'Route Deviation Detected',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            widget.alert.message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 6),
          Text(
            distanceText,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.error),
          ),

          const SizedBox(height: 16),

          // ── Countdown ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _secondsLeft > 0
                  ? AppTheme.warning.withOpacity(0.1)
                  : AppTheme.error.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _secondsLeft > 0
                  ? 'Auto-alerting contacts in ${_secondsLeft}s'
                  : 'Emergency contacts have been alerted',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _secondsLeft > 0 ? AppTheme.warning : AppTheme.error,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Action buttons ─────────────────────────────────────────────
          Row(
            children: [
              // Alert contacts
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.onAlert,
                  icon: const Icon(Icons.notifications_active,
                      size: 16, color: AppTheme.error),
                  label: const Text('Alert Contacts',
                      style: TextStyle(
                          color: AppTheme.error, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // I'm okay
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onOk,
                  icon: const Icon(Icons.check_circle_outline,
                      size: 16, color: Colors.white),
                  label: const Text("I'm Okay",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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
      'confirmed' ||
      'driver_arriving' => (AppTheme.success, Icons.directions_car),
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
              offset: const Offset(0, 4)),
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
                  fontSize: 15),
            ),
          ),
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
          BoxShadow(
              color: Colors.black12,
              blurRadius: 16,
              offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2)),
          ),

          // Trip addresses + fare
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _AddressRow(
                        icon: Icons.radio_button_checked,
                        color: AppTheme.success,
                        address: ride.pickupAddress),
                    const SizedBox(height: 4),
                    _AddressRow(
                        icon: Icons.location_on,
                        color: AppTheme.primary,
                        address: ride.dropAddress),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '₹${ride.finalFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary),
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

          // Driver card
          if (ride.driver != null) ...[
            const SizedBox(height: 16),
            const Divider(color: AppTheme.divider, height: 1),
            const SizedBox(height: 14),
            _DriverCard(driver: ride.driver!),
          ],

          // OTP hint
          if (ride.status == 'otp_pending') ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.primary.withOpacity(0.3)),
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

          // Cancel button
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
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: isCancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppTheme.error),
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
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: AppTheme.primaryLight.withOpacity(0.3),
              shape: BoxShape.circle),
          child: const Icon(Icons.person, color: AppTheme.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(driver.fullName,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary)),
              Text('${driver.vehicleDisplay} • ${driver.vehicleNumber}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
        Row(
          children: [
            const Icon(Icons.star_rounded,
                size: 14, color: AppTheme.warning),
            const SizedBox(width: 2),
            Text(driver.reliabilityScore.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
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

  const _AddressRow(
      {required this.icon, required this.color, required this.address});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(address,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ── Pulsing dot ───────────────────────────────────────────────────────────────

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
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: Container(
        width: 8,
        height: 8,
        decoration:
            BoxDecoration(color: widget.color, shape: BoxShape.circle),
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
              const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
              const SizedBox(height: 16),
              Text(message,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppTheme.textSecondary)),
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
              const Text('Ride Cancelled',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              const Text('Your ride has been cancelled.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
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
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
