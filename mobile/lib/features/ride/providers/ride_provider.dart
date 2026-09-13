import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/models/app_error.dart';
import '../ride_service.dart';

// ════════════════════════════════════════════════════════════════════════════
// PART 1 — BOOKING STATE
//
// Tracks every step of the home screen → booking flow:
//   User opens app
//     → GPS located (or manual entry)
//     → Drop location picked
//     → Fare estimated
//     → Ride type selected
//     → Booking confirmed
//     → Ride created (ID returned)
// ════════════════════════════════════════════════════════════════════════════

// ── Location model ────────────────────────────────────────────────────────────
// A simple lat/lng + address pair.
// Used for both pickup and drop points.

class RideLocation {
  final double lat;
  final double lng;
  final String address;

  const RideLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });

  @override
  String toString() => address;
}

// ── Booking form state ────────────────────────────────────────────────────────
// Holds all the data the user is filling in on the home screen.
// Immutable — every change creates a new copy via copyWith().
//
// WHY IMMUTABLE STATE?
// Riverpod rebuilds widgets when state changes. If you mutate state
// in place, Riverpod can't detect the change and the UI won't update.
// Creating a new object on every change ensures the widget tree always
// sees the latest values.

class BookingFormState {
  final RideLocation? pickup;      // null = user hasn't set it yet
  final RideLocation? drop;        // null = user hasn't set it yet
  final String rideType;           // 'private' | 'shared' | 'women_only_shared'
  final String paymentMethod;      // 'cash' | 'upi'
  final DateTime scheduledAt;      // defaults to now (immediate ride)
  final FareEstimate? estimate;    // null until both locations are set
  final bool isEstimating;         // true while API call is in progress
  final String? estimateError;     // shown under the fare card

  const BookingFormState({
    this.pickup,
    this.drop,
    this.rideType = 'private',
    this.paymentMethod = 'cash',
    required this.scheduledAt,
    this.estimate,
    this.isEstimating = false,
    this.estimateError,
  });

  // Returns true only when everything needed to book is set
  bool get canBook =>
      pickup != null && drop != null && estimate != null && !isEstimating;

  BookingFormState copyWith({
    RideLocation? pickup,
    RideLocation? drop,
    String? rideType,
    String? paymentMethod,
    DateTime? scheduledAt,
    FareEstimate? estimate,
    bool? isEstimating,
    String? estimateError,
    bool clearEstimate = false,
    bool clearPickup = false,
    bool clearDrop = false,
  }) {
    return BookingFormState(
      pickup: clearPickup ? null : (pickup ?? this.pickup),
      drop: clearDrop ? null : (drop ?? this.drop),
      rideType: rideType ?? this.rideType,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      estimate: clearEstimate ? null : (estimate ?? this.estimate),
      isEstimating: isEstimating ?? this.isEstimating,
      estimateError: estimateError,
    );
  }
}

// ── Booking flow state ────────────────────────────────────────────────────────
// Separate from BookingFormState — this tracks whether the booking
// API call itself is loading/done/failed.

sealed class BookingState {
  const BookingState();
}

class BookingIdle extends BookingState {
  const BookingIdle();
}

class BookingInProgress extends BookingState {
  const BookingInProgress();
}

class BookingSuccess extends BookingState {
  final RideModel ride; // the created ride — has rideId for the next screen
  const BookingSuccess(this.ride);
}

class BookingError extends BookingState {
  final String message;
  const BookingError(this.message);
}

// ── BookingNotifier ───────────────────────────────────────────────────────────
// Manages the entire home screen form.
// Two pieces of state:
//   1. BookingFormState — the form data (locations, ride type, estimate)
//   2. BookingState — the booking API call status

class BookingNotifier extends StateNotifier<BookingState> {
  final RideService _service;

  // Form state is stored separately from the sealed class
  // so the home screen can watch them independently
  BookingFormState _form = BookingFormState(
    scheduledAt: DateTime.now().add(const Duration(minutes: 2)),
  );

  BookingFormState get form => _form;

  // Debounce timer — prevents calling fare estimate on every character
  // typed in the address field. Waits 800ms after the last change.
  Timer? _estimateDebounce;

  BookingNotifier(this._service) : super(const BookingIdle());

  // ── GPS: get current location ─────────────────────────────────────────────
  // Called when the home screen opens or user taps "Use my location".
  // Uses Geolocator to get the device's GPS coordinates.
  // Returns the Position or null if permission denied.

  Future<Position?> getCurrentLocation() async {
    // Check if location services are enabled on the device
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    // Check/request permission
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    // Get the current position
    // accuracy: best → uses GPS. Medium → uses network (faster, less accurate).
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  // ── Set pickup location ───────────────────────────────────────────────────
  // Called when user picks their pickup from autocomplete or "use my location".
  // After setting, immediately recalculates the fare if drop is also set.

  void setPickup(RideLocation location) {
    _form = _form.copyWith(pickup: location, clearEstimate: true);
    _triggerEstimate();
    // Notify listeners — form changed even if booking state didn't
    state = state; // triggers rebuild via StateNotifier
  }

  // ── Set drop location ─────────────────────────────────────────────────────

  void setDrop(RideLocation location) {
    _form = _form.copyWith(drop: location, clearEstimate: true);
    _triggerEstimate();
    state = state;
  }

  // ── Set ride type ─────────────────────────────────────────────────────────
  // 'private' | 'shared' | 'women_only_shared'
  // Fare changes based on ride type — recalculate estimate.

  void setRideType(String type) {
    _form = _form.copyWith(rideType: type, clearEstimate: true);
    _triggerEstimate();
    state = state;
  }

  // ── Set payment method ────────────────────────────────────────────────────

  void setPaymentMethod(String method) {
    _form = _form.copyWith(paymentMethod: method);
    state = state;
  }

  // ── Set scheduled time ────────────────────────────────────────────────────

  void setScheduledAt(DateTime time) {
    _form = _form.copyWith(scheduledAt: time);
    state = state;
  }

  // ── Fare estimate — debounced ─────────────────────────────────────────────
  // Waits 800ms after the last location change before calling the API.
  // This prevents a new API call on every pixel of map drag.
  //
  // WHY DEBOUNCE?
  // If the user types "Malviya Nagar" in the drop field, without debouncing
  // we'd fire an API call for every keystroke: "M", "Ma", "Mal"...
  // With debounce we wait until they stop typing and only call once.

  void _triggerEstimate() {
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 800), _fetchEstimate);
  }

  Future<void> _fetchEstimate() async {
    final pickup = _form.pickup;
    final drop = _form.drop;
    if (pickup == null || drop == null) return;

    _form = _form.copyWith(isEstimating: true, estimateError: null);
    state = state; // trigger rebuild to show loading indicator on fare card

    try {
      final estimate = await _service.getFareEstimate(
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        dropLat: drop.lat,
        dropLng: drop.lng,
        rideType: _form.rideType,
      );
      _form = _form.copyWith(estimate: estimate, isEstimating: false);
    } on AppError catch (e) {
      _form = _form.copyWith(
        isEstimating: false,
        estimateError: e.message,
      );
    } catch (_) {
      _form = _form.copyWith(
        isEstimating: false,
        estimateError: 'Could not estimate fare. Check your connection.',
      );
    }

    state = state; // trigger final rebuild
  }

  // ── Confirm booking ───────────────────────────────────────────────────────
  // Called when user taps "Confirm Booking" in the bottom sheet.
  // Uses all the data from _form to create the ride on the backend.

  Future<void> confirmBooking() async {
    final pickup = _form.pickup;
    final drop = _form.drop;
    if (pickup == null || drop == null) return;

    state = const BookingInProgress();

    try {
      final ride = await _service.bookRide(BookingData(
        rideType: _form.rideType,
        pickupLat: pickup.lat,
        pickupLng: pickup.lng,
        pickupAddress: pickup.address,
        dropLat: drop.lat,
        dropLng: drop.lng,
        dropAddress: drop.address,
        scheduledAt: _form.scheduledAt.toIso8601String(),
        paymentMethod: _form.paymentMethod,
      ));

      state = BookingSuccess(ride);
    } on AppError catch (e) {
      state = BookingError(e.message);
    } catch (_) {
      state = const BookingError('Booking failed. Please try again.');
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  // Called after successful booking or when user cancels.
  // Resets both the form and the booking state.

  void reset() {
    _estimateDebounce?.cancel();
    _form = BookingFormState(
      scheduledAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    state = const BookingIdle();
  }

  @override
  void dispose() {
    _estimateDebounce?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final bookingProvider =
    StateNotifierProvider<BookingNotifier, BookingState>((ref) {
  return BookingNotifier(ref.watch(rideServiceProvider));
});

// ── Form state provider ───────────────────────────────────────────────────────
// Separate provider just for the form data.
// Screens that only need the form fields (fare card, location inputs)
// watch this instead of bookingProvider — avoids unnecessary rebuilds
// when the booking API call state changes.

final bookingFormProvider = Provider<BookingFormState>((ref) {
  // Watch bookingProvider to trigger rebuild when form changes
  ref.watch(bookingProvider);
  return ref.read(bookingProvider.notifier).form;
});

// ════════════════════════════════════════════════════════════════════════════
// PART 2 — ACTIVE RIDE STATE
//
// After a ride is booked, the passenger needs to see live status updates:
//   searching → driver assigned → driver arriving → in progress → completed
//
// We poll the backend every 5 seconds via a Timer.
// In Task 6 we'll add Socket.io for real-time driver location updates.
// Polling handles the status transitions (they come from the backend DB).
// ════════════════════════════════════════════════════════════════════════════

sealed class ActiveRideState {
  const ActiveRideState();
}

// Loading on first open or refresh
class ActiveRideLoading extends ActiveRideState {
  const ActiveRideLoading();
}

// A ride is active — holds the latest data
class ActiveRideLoaded extends ActiveRideState {
  final RideModel ride;
  const ActiveRideLoaded(this.ride);
}

// No active ride found (passenger is on home screen)
class ActiveRideNone extends ActiveRideState {
  const ActiveRideNone();
}

// Cancellation in progress
class ActiveRideCancelling extends ActiveRideState {
  final RideModel ride;
  const ActiveRideCancelling(this.ride);
}

// Cancelled successfully
class ActiveRideCancelled extends ActiveRideState {
  const ActiveRideCancelled();
}

class ActiveRideError extends ActiveRideState {
  final String message;
  const ActiveRideError(this.message);
}

// ── ActiveRideNotifier ────────────────────────────────────────────────────────

class ActiveRideNotifier extends StateNotifier<ActiveRideState> {
  final RideService _service;
  Timer? _pollingTimer;
  String? _rideId; // the ID we're currently tracking

  static const _pollInterval = Duration(seconds: 5);

  ActiveRideNotifier(this._service) : super(const ActiveRideLoading());

  // ── Start tracking a specific ride ────────────────────────────────────────
  // Called after a successful booking or when the active ride screen opens.
  // Immediately fetches once, then polls every 5 seconds.

  void startTracking(String rideId) {
    _rideId = rideId;
    _fetchRide(); // immediate first fetch
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollInterval, (_) => _fetchRide());
  }

  // ── Check for any existing active ride on app startup ─────────────────────
  // Called by PassengerHomeScreen.initState().
  // If a ride is already in progress (e.g. app was killed mid-ride),
  // we resume tracking it automatically.

  Future<void> checkForActiveRide() async {
    state = const ActiveRideLoading();
    try {
      final ride = await _service.getActiveRide();
      if (ride != null) {
        state = ActiveRideLoaded(ride);
        startTracking(ride.id); // begin polling
      } else {
        state = const ActiveRideNone();
      }
    } catch (_) {
      state = const ActiveRideNone(); // treat error as no active ride
    }
  }

  // ── Poll: fetch latest ride state ─────────────────────────────────────────

  Future<void> _fetchRide() async {
    if (_rideId == null) return;

    try {
      final ride = await _service.getRideById(_rideId!);

      // Stop polling once the ride is in a terminal state
      if (ride.isCompleted || ride.isCancelled) {
        _pollingTimer?.cancel();
        if (ride.isCompleted) {
          state = ActiveRideLoaded(ride); // show completion briefly
        } else {
          state = const ActiveRideCancelled();
        }
        return;
      }

      state = ActiveRideLoaded(ride);
    } catch (_) {
      // Silently fail — keep last known state, try again on next poll
    }
  }

  // ── Cancel ride ───────────────────────────────────────────────────────────

  Future<void> cancelRide({String reason = 'Cancelled by passenger'}) async {
    final current = state;
    if (current is! ActiveRideLoaded) return;

    state = ActiveRideCancelling(current.ride);

    try {
      await _service.cancelRide(current.ride.id, reason: reason);
      _pollingTimer?.cancel();
      state = const ActiveRideCancelled();
    } on AppError catch (e) {
      // Restore previous state if cancel fails
      state = ActiveRideLoaded(current.ride);
      // Re-throw so the UI can show the error
      throw AppError(
        message: e.message,
        type: e.type,
        statusCode: e.statusCode,
      );
    }
  }

  // ── Stop tracking ─────────────────────────────────────────────────────────
  // Called when the passenger navigates away from the active ride screen.

  void stopTracking() {
    _pollingTimer?.cancel();
    _rideId = null;
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
// Not autoDispose — we want tracking to persist across screen navigations.
// The polling continues even if the user briefly visits another screen.

final activeRideProvider =
    StateNotifierProvider<ActiveRideNotifier, ActiveRideState>((ref) {
  return ActiveRideNotifier(ref.watch(rideServiceProvider));
});
