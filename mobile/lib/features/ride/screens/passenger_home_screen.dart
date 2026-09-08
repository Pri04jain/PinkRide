import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

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
/// LAYOUT (from top to bottom):
///   ┌─────────────────────────────┐
///   │  App bar (greeting + wallet)│
///   │                             │
///   │      Google Map             │ ← full screen behind everything
///   │                             │
///   └─────────────────────────────┘
///   ┌─────────────────────────────┐
///   │  White bottom card          │
///   │  ─ Pickup input             │
///   │  ─ Drop input               │
///   │  ─ Ride type chips          │
///   │  ─ Fare estimate card       │
///   │  ─ Book Ride button         │
///   └─────────────────────────────┘
///
/// HOW GoogleMap WORKS:
///   GoogleMap is a widget that renders a native map view.
///   It needs:
///     - initialCameraPosition: where the map starts (lat/lng + zoom)
///     - onMapCreated: callback that gives us the GoogleMapController
///       (we store it so we can animate the camera later)
///     - markers: a Set<Marker> for pickup/drop pins
///
///   Moving the camera (animating to user location):
///     _mapController.animateCamera(
///       CameraUpdate.newLatLngZoom(LatLng(lat, lng), 15)
///     )
///
/// GEOLOCATOR:
///   Gets the device GPS position.
///   We call it in initState via BookingNotifier.getCurrentLocation().
///   Result is used to:
///     1. Move the map camera to the user's location
///     2. Set the default pickup location

class PassengerHomeScreen extends ConsumerStatefulWidget {
  const PassengerHomeScreen({super.key});

  @override
  ConsumerState<PassengerHomeScreen> createState() =>
      _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends ConsumerState<PassengerHomeScreen> {
  GoogleMapController? _mapController;

  // Jaipur city centre — default camera position before GPS loads
  static const _defaultPosition = CameraPosition(
    target: LatLng(26.9124, 75.7873),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    // Run after first frame so ref is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      // Check if there's an active ride already (app relaunch mid-ride)
      ref.read(activeRideProvider.notifier).checkForActiveRide();
    });
  }

  Future<void> _initLocation() async {
    final position =
        await ref.read(bookingProvider.notifier).getCurrentLocation();
    if (position == null || !mounted) return;

    // Move map camera to user's actual location
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(
        LatLng(position.latitude, position.longitude),
        15,
      ),
    );

    // Pre-fill pickup with current GPS coordinates
    // Address is "Current Location" — a real app would reverse-geocode this
    ref.read(bookingProvider.notifier).setPickup(
          RideLocation(
            lat: position.latitude,
            lng: position.longitude,
            address: 'Current Location',
          ),
        );
  }

  // Build map markers for pickup and drop pins
  Set<Marker> _buildMarkers(BookingFormState form) {
    final markers = <Marker>{};

    if (form.pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(form.pickup!.lat, form.pickup!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup', snippet: form.pickup!.address),
      ));
    }

    if (form.drop != null) {
      markers.add(Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(form.drop!.lat, form.drop!.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Drop', snippet: form.drop!.address),
      ));
    }

    return markers;
  }

  // When both pickup and drop are set, animate map to show both markers
  void _fitMapToBothLocations(BookingFormState form) {
    if (form.pickup == null || form.drop == null) return;
    if (_mapController == null) return;

    final bounds = LatLngBounds(
      southwest: LatLng(
        form.pickup!.lat < form.drop!.lat ? form.pickup!.lat : form.drop!.lat,
        form.pickup!.lng < form.drop!.lng ? form.pickup!.lng : form.drop!.lng,
      ),
      northeast: LatLng(
        form.pickup!.lat > form.drop!.lat ? form.pickup!.lat : form.drop!.lat,
        form.pickup!.lng > form.drop!.lng ? form.pickup!.lng : form.drop!.lng,
      ),
    );

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80), // 80px padding
    );
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(bookingFormProvider);
    final bookingState = ref.watch(bookingProvider);
    final user = ref.watch(currentUserProvider);
    // Watch activeRideProvider so the screen rebuilds when ride state changes
    ref.watch(activeRideProvider);

    // Navigate to active ride screen when a booking succeeds
    ref.listen<BookingState>(bookingProvider, (_, next) {
      if (next is BookingSuccess) {
        ref.read(activeRideProvider.notifier).startTracking(next.ride.id);
        context.push(
          AppRoutes.activeRide.replaceAll(':rideId', next.ride.id),
        );
        ref.read(bookingProvider.notifier).reset();
      }
    });

    // Navigate to active ride screen if there's already an active ride
    ref.listen<ActiveRideState>(activeRideProvider, (_, next) {
      if (next is ActiveRideLoaded && !next.ride.isCompleted) {
        // Only auto-navigate if we're still on the home screen
        final location = GoRouterState.of(context).matchedLocation;
        if (location == AppRoutes.passengerHome) {
          context.push(
            AppRoutes.activeRide.replaceAll(':rideId', next.ride.id),
          );
        }
      }
    });

    // Fit map to show both markers when drop is set
    if (form.pickup != null && form.drop != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _fitMapToBothLocations(form),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // ── Full-screen Google Map ───────────────────────────────────────
          GoogleMap(
            initialCameraPosition: _defaultPosition,
            onMapCreated: (controller) => _mapController = controller,
            markers: _buildMarkers(form),
            myLocationEnabled: true,      // blue dot on user's position
            myLocationButtonEnabled: false, // we have our own button
            zoomControlsEnabled: false,    // cleaner UI without zoom buttons
            mapToolbarEnabled: false,
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
                    // Greeting card
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

                    // Wallet balance button
                    _WalletBadge(balance: user?.walletBalance ?? 0),
                  ],
                ),
              ),
            ),
          ),

          // ── My location button ───────────────────────────────────────────
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

  // Approximate height of bottom card — used to position FAB above it
  double _bottomCardHeight(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return 320 + mediaQuery.padding.bottom;
  }

  void _showBookingSheet(BuildContext context, BookingFormState form) {
    if (!form.canBook) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,     // lets the sheet be full height
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
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
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
              16,
              0,
              16,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Location inputs ────────────────────────────────────
                LocationInputField(
                  hint: 'Pickup location',
                  icon: Icons.radio_button_checked,
                  iconColor: AppTheme.success,
                  value: form.pickup?.address,
                  onLocationSelected: onPickupChanged,
                ),
                const SizedBox(height: 2),

                // Dotted connector between pickup and drop
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

                // ── Ride type selector ─────────────────────────────────
                RideTypeSelector(
                  selected: form.rideType,
                  onChanged: onRideTypeChanged,
                ),

                const SizedBox(height: 14),

                // ── Fare estimate card ─────────────────────────────────
                FareEstimateCard(
                  estimate: form.estimate,
                  isLoading: form.isEstimating,
                  errorMessage: form.estimateError,
                ),

                const SizedBox(height: 14),

                // ── Book button ────────────────────────────────────────
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
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: bookingState is BookingInProgress
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
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
            offset: const Offset(0, 2),
          ),
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
