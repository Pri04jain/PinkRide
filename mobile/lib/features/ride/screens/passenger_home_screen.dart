import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/ride_provider.dart';
import '../widgets/fare_estimate_card.dart';
import '../widgets/location_input_field.dart';
import '../widgets/ride_type_selector.dart';
import 'ride_booking_sheet.dart';

/// PassengerHomeScreen — the main screen for passengers.
///
/// LAYOUT:
///   Full-screen OpenStreetMap (flutter_map — free, no API key)
///   Top overlay: greeting card + wallet badge
///   Bottom card: pickup/drop inputs, ride type, fare estimate, book button
///
/// flutter_map vs google_maps_flutter:
///   flutter_map uses OpenStreetMap tiles — completely free, no account needed.
///   The API is similar: MapController ≈ GoogleMapController,
///   LatLng from latlong2 ≈ LatLng from google_maps_flutter,
///   Marker widget ≈ Marker object.
///   Main difference: markers are widgets in a MarkerLayer, not a Set<Marker>.

class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  // MapController gives us programmatic control (move camera, zoom, etc.)
  final _mapController = MapController();

  // Jaipur city centre — camera starts here before GPS loads
  static const _defaultCenter = LatLng(26.9124, 75.7873);
  static const _defaultZoom = 13.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      ref.read(activeRideProvider.notifier).checkForActiveRide();
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final position =
        await ref.read(bookingProvider.notifier).getCurrentLocation();
    if (position == null || !mounted) return;

    // Move camera to user's GPS position
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      15,
    );

    ref.read(bookingProvider.notifier).setPickup(
          RideLocation(
            lat: position.latitude,
            lng: position.longitude,
            address: 'Current Location',
          ),
        );
  }

  // Animate camera to show both pickup and drop markers
  void _fitMapToBothLocations(BookingFormState form) {
    if (form.pickup == null || form.drop == null) return;

    // LatLngBounds from latlong2 takes a list of LatLng points
    final bounds = LatLngBounds.fromPoints([
      LatLng(form.pickup!.lat, form.pickup!.lng),
      LatLng(form.drop!.lat, form.drop!.lng),
    ]);

    // fitBounds pads the view so both markers are visible
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(80)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(bookingFormProvider);
    final bookingState = ref.watch(bookingProvider);
    final user = ref.watch(currentUserProvider);
    ref.watch(activeRideProvider);

    ref.listen<BookingState>(bookingProvider, (_, next) {
      if (next is BookingSuccess) {
        ref.read(activeRideProvider.notifier).startTracking(next.ride.id);
        context.push(
            AppRoutes.activeRide.replaceAll(':rideId', next.ride.id));
        ref.read(bookingProvider.notifier).reset();
      }
    });

    ref.listen<ActiveRideState>(activeRideProvider, (_, next) {
      if (next is ActiveRideLoaded && !next.ride.isCompleted) {
        final location = GoRouterState.of(context).matchedLocation;
        if (location == AppRoutes.passengerHome) {
          context.push(
              AppRoutes.activeRide.replaceAll(':rideId', next.ride.id));
        }
      }
    });

    if (form.pickup != null && form.drop != null) {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _fitMapToBothLocations(form));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // ── OpenStreetMap (flutter_map) ──────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _defaultCenter,
              initialZoom: _defaultZoom,
              interactionOptions: InteractionOptions(
                // Allow pinch zoom and pan — disable rotation (not needed)
                flags: InteractiveFlag.pinchZoom |
                    InteractiveFlag.drag |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              // Tile layer — fetches map images from OpenStreetMap servers
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // User agent required by OSM tile usage policy
                userAgentPackageName: 'com.pinkride.pinkride',
              ),

              // Marker layer — pickup (green) and drop (pink) pins
              MarkerLayer(
                markers: [
                  if (form.pickup != null)
                    Marker(
                      point: LatLng(form.pickup!.lat, form.pickup!.lng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: AppTheme.success,
                        size: 36,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black26)
                        ],
                      ),
                    ),
                  if (form.drop != null)
                    Marker(
                      point: LatLng(form.drop!.lat, form.drop!.lng),
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: AppTheme.primary,
                        size: 36,
                        shadows: [
                          Shadow(blurRadius: 4, color: Colors.black26)
                        ],
                      ),
                    ),
                ],
              ),

              // OSM attribution — required by OpenStreetMap tile usage policy
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            ],
          ),

          // ── Top bar overlay ──────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.wb_sunny_outlined,
                                size: 18, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Hi, ${user?.displayName ?? 'there'} 👋',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _WalletBadge(balance: user?.walletBalance ?? 0),
                  ],
                ),
              ),
            ),
          ),

          // ── My location FAB ──────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: _bottomCardHeight(context) + 16,
            child: FloatingActionButton.small(
              onPressed: _initLocation,
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.primary,
              elevation: 4,
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // ── Bottom booking card ──────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBookingCard(
              form: form,
              bookingState: bookingState,
              onPickupChanged: (loc) =>
                  ref.read(bookingProvider.notifier).setPickup(loc),
              onDropChanged: (loc) =>
                  ref.read(bookingProvider.notifier).setDrop(loc),
              onRideTypeChanged: (type) =>
                  ref.read(bookingProvider.notifier).setRideType(type),
              onBookTap: () => _showBookingSheet(context, form),
            ),
          ),
        ],
      ),
    );
  }

  double _bottomCardHeight(BuildContext context) =>
      320 + MediaQuery.of(context).padding.bottom;

  void _showBookingSheet(BuildContext context, BookingFormState form) {
    if (!form.canBook) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const RideBookingSheet(),
    );
  }
}

// ── Bottom booking card ───────────────────────────────────────────────────────

class _BottomBookingCard extends StatelessWidget {
  final BookingFormState form;
  final BookingState bookingState;
  final ValueChanged<RideLocation> onPickupChanged;
  final ValueChanged<RideLocation> onDropChanged;
  final ValueChanged<String> onRideTypeChanged;
  final VoidCallback onBookTap;

  const _BottomBookingCard({
    required this.form,
    required this.bookingState,
    required this.onPickupChanged,
    required this.onDropChanged,
    required this.onRideTypeChanged,
    required this.onBookTap,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10, bottom: 16),
            decoration: BoxDecoration(
              color: AppTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16, 0, 16,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LocationInputField(
                  hint: 'Pickup location',
                  icon: Icons.radio_button_checked,
                  iconColor: AppTheme.success,
                  value: form.pickup?.address,
                  onLocationSelected: onPickupChanged,
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 19),
                  child: Column(
                    children: List.generate(
                      3,
                      (_) => Container(
                        width: 2,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        color: AppTheme.divider,
                      ),
                    ),
                  ),
                ),
                LocationInputField(
                  hint: 'Where to?',
                  icon: Icons.location_on,
                  iconColor: AppTheme.primary,
                  value: form.drop?.address,
                  onLocationSelected: onDropChanged,
                ),
                const SizedBox(height: 16),
                RideTypeSelector(
                    selected: form.rideType, onChanged: onRideTypeChanged),
                const SizedBox(height: 14),
                FareEstimateCard(
                  estimate: form.estimate,
                  isLoading: form.isEstimating,
                  errorMessage: form.estimateError,
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: form.canBook ? onBookTap : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      disabledBackgroundColor:
                          AppTheme.primaryLight.withOpacity(0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: bookingState is BookingInProgress
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : const Text(
                            'Book Ride',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Wallet badge ──────────────────────────────────────────────────────────────

class _WalletBadge extends StatelessWidget {
  final double balance;
  const _WalletBadge({required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 16, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            '₹${balance.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
