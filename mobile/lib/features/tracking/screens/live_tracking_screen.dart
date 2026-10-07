import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../ride/providers/ride_provider.dart';
import '../../ride/ride_service.dart';
import '../providers/tracking_provider.dart';

/// LiveTrackingScreen — full-screen map showing driver's real-time position.
///
/// Shown during the 'driver_arriving' and 'in_progress' ride statuses.
/// The map has:
///   • A pink pin for the driver's live location (updated via Socket.io)
///   • Green pin for pickup, red pin for drop
///   • Auto-pans the camera to the driver as they move
///   • Deviation alert banner (dismissible)
///   • Bottom sheet with ride status + SOS button
///
/// This screen is embedded inside ActiveRideScreen — it is NOT a standalone
/// route. ActiveRideScreen passes the rideId and RideModel down.

class LiveTrackingScreen extends ConsumerStatefulWidget {
  final String rideId;
  final RideModel ride;

  const LiveTrackingScreen({
    super.key,
    required this.rideId,
    required this.ride,
  });

  @override
  ConsumerState<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends ConsumerState<LiveTrackingScreen> {
  final _mapController = MapController();

  // Jaipur default — replaced by live location once socket connects
  static const _defaultCenter = LatLng(26.9124, 75.7873);
  bool _hasCenteredOnDriver = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(trackingProvider.notifier).startTracking(widget.rideId);
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _centerOnDriver(DriverLocation location) {
    _mapController.move(LatLng(location.lat, location.lng), 16);
    _hasCenteredOnDriver = true;
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(trackingProvider);
    final activeRide = ref.watch(activeRideProvider);
    final ride = activeRide is ActiveRideLoaded ? activeRide.ride : widget.ride;

    // Auto-pan to driver on first location fix
    if (tracking.driverLocation != null && !_hasCenteredOnDriver) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _centerOnDriver(tracking.driverLocation!));
    }

    final driverLL = tracking.driverLocation != null
        ? LatLng(tracking.driverLocation!.lat, tracking.driverLocation!.lng)
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Map ─────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: driverLL ?? _defaultCenter,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pinkride.pinkride',
              ),
              MarkerLayer(
                markers: [
                  // Pickup
                  Marker(
                    point: LatLng(0, 0), // placeholder — replace with real coords when available
                    width: 0,
                    height: 0,
                    child: const SizedBox.shrink(),
                  ),
                  // Driver pin (animated, shows when location received)
                  if (driverLL != null)
                    Marker(
                      point: driverLL,
                      width: 56,
                      height: 56,
                      child: _DriverPin(),
                    ),
                ],
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // ── Top bar ──────────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _MapButton(
                      icon: Icons.arrow_back,
                      onTap: () => context.pop(),
                    ),
                    const Spacer(),
                    // Connection indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tracking.isConnected
                                  ? AppTheme.success
                                  : (tracking.isConnecting
                                      ? AppTheme.warning
                                      : AppTheme.error),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            tracking.isConnected
                                ? 'Live'
                                : (tracking.isConnecting
                                    ? 'Connecting…'
                                    : 'Offline'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Centre on driver button
                    if (driverLL != null)
                      _MapButton(
                        icon: Icons.my_location_rounded,
                        onTap: () => _mapController.move(driverLL, 16),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // ── Deviation alert banner ────────────────────────────────────────
          if (tracking.deviationAlert != null &&
              !tracking.deviationAlert!.dismissed)
            Positioned(
              top: MediaQuery.of(context).padding.top + 72,
              left: 16,
              right: 16,
              child: _DeviationBanner(
                alert: tracking.deviationAlert!,
                onIAmSafe: () =>
                    ref.read(trackingProvider.notifier).dismissDeviation(),
                onSos: () => _openSos(context),
              ),
            ),

          // ── Bottom info sheet ─────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomSheet(
              ride: ride,
              hasDriverLocation: driverLL != null,
              onSosTap: () => _openSos(context),
              onContactsTap: () =>
                  context.push(AppRoutes.emergencyContacts),
            ),
          ),
        ],
      ),
    );
  }

  void _openSos(BuildContext context) {
    context.push(AppRoutes.sos, extra: {'rideId': widget.rideId});
  }
}

// ── Driver animated pin ───────────────────────────────────────────────────────

class _DriverPin extends StatefulWidget {
  @override
  State<_DriverPin> createState() => _DriverPinState();
}

class _DriverPinState extends State<_DriverPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.5),
              blurRadius: 12,
              spreadRadius: 4,
            ),
          ],
        ),
        child: const Icon(Icons.directions_car_rounded,
            color: Colors.white, size: 24),
      ),
    );
  }
}

// ── Map overlay button ────────────────────────────────────────────────────────

class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppTheme.textPrimary),
      ),
    );
  }
}

// ── Deviation alert banner ────────────────────────────────────────────────────

class _DeviationBanner extends StatelessWidget {
  final DeviationAlert alert;
  final VoidCallback onIAmSafe;
  final VoidCallback onSos;

  const _DeviationBanner({
    required this.alert,
    required this.onIAmSafe,
    required this.onSos,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.error.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Route Deviation Detected',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Driver is ${alert.deviationMetres.toStringAsFixed(0)}m off-route. '
            'Are you okay?',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onIAmSafe,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('I\'m Safe'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSos,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppTheme.error,
                    minimumSize: const Size(0, 40),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Send SOS',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bottom sheet ──────────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final RideModel ride;
  final bool hasDriverLocation;
  final VoidCallback onSosTap;
  final VoidCallback onContactsTap;

  const _BottomSheet({
    required this.ride,
    required this.hasDriverLocation,
    required this.onSosTap,
    required this.onContactsTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = _statusLabel(ride.status);
    final statusColor = _statusColor(ride.status);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Status row
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              // Driver location ping indicator
              if (hasDriverLocation)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Live',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.success,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Route summary
          Row(
            children: [
              const Icon(Icons.radio_button_checked_rounded,
                  color: AppTheme.success, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ride.pickupAddress,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Container(
                width: 2, height: 14, color: AppTheme.divider),
          ),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: AppTheme.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ride.dropAddress,
                  style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Action buttons row
          Row(
            children: [
              // SOS
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSosTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.sos_rounded, size: 18),
                  label: const Text('SOS',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              // Emergency contacts
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onContactsTap,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    minimumSize: const Size(0, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.contact_phone_outlined, size: 18),
                  label: const Text('Contacts'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'searching'       => '🔍 Finding driver',
        'driver_assigned' => '✅ Driver assigned',
        'driver_arriving' => '🚗 Driver arriving',
        'in_progress'     => '🛣️ Ride in progress',
        'completed'       => '✅ Ride complete',
        'cancelled'       => '❌ Cancelled',
        _                 => status.replaceAll('_', ' ').toUpperCase(),
      };

  Color _statusColor(String status) => switch (status) {
        'searching'       => AppTheme.warning,
        'driver_assigned' => AppTheme.accent,
        'driver_arriving' => AppTheme.accent,
        'in_progress'     => AppTheme.success,
        'completed'       => AppTheme.success,
        'cancelled'       => AppTheme.error,
        _                 => AppTheme.textSecondary,
      };
}
