import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/socket_service.dart';

// ── Driver Location State ─────────────────────────────────────────────────────
//
// Holds the driver's latest GPS position received from the socket.
// null = no location received yet (driver hasn't sent one).
//
// WHY A SEPARATE STATE CLASS AND NOT JUST A LatLng?
// The backend sends heading and speed alongside lat/lng.
// We store them all so the UI can show a direction arrow on the marker
// and a speed badge when we polish the UI later.

class DriverLocation {
  final LatLng position;
  final double heading;   // degrees 0–360, 0 = north
  final double speedKmh;
  final DateTime updatedAt;

  const DriverLocation({
    required this.position,
    this.heading = 0,
    this.speedKmh = 0,
    required this.updatedAt,
  });
}

// ── Deviation Alert State ─────────────────────────────────────────────────────
//
// Holds the current route deviation alert if one is active.
// null = no active deviation.
//
// WHEN IS THIS SET?
//   Server → 'route_deviation' event arrives → DeviationAlert is created.
//   Passenger taps "I'm okay" → respondToDeviation('ok') → cleared.
//   Passenger taps "Alert contacts" → respondToDeviation('alert') → cleared.
//   Timer on server expires (120s no response) → 'contacts_alerted' event → cleared.

class DeviationAlert {
  final String deviationId;
  final double deviationMeters;
  final double currentLat;
  final double currentLng;
  final String message;
  final int responseDeadlineSeconds;
  final DateTime receivedAt;

  const DeviationAlert({
    required this.deviationId,
    required this.deviationMeters,
    required this.currentLat,
    required this.currentLng,
    required this.message,
    required this.responseDeadlineSeconds,
    required this.receivedAt,
  });
}

// ── DriverLocationState ───────────────────────────────────────────────────────
// Combined state for the active ride screen's socket-driven UI.

class DriverLocationState {
  final DriverLocation? driverLocation;  // null until first update arrives
  final DeviationAlert? deviationAlert;  // null when no active deviation
  final bool sosTriggered;               // true after SOS is sent

  const DriverLocationState({
    this.driverLocation,
    this.deviationAlert,
    this.sosTriggered = false,
  });

  DriverLocationState copyWith({
    DriverLocation? driverLocation,
    DeviationAlert? deviationAlert,
    bool clearDeviation = false,
    bool? sosTriggered,
  }) {
    return DriverLocationState(
      driverLocation: driverLocation ?? this.driverLocation,
      deviationAlert: clearDeviation ? null : (deviationAlert ?? this.deviationAlert),
      sosTriggered: sosTriggered ?? this.sosTriggered,
    );
  }
}

// ── DriverLocationNotifier ────────────────────────────────────────────────────
//
// Lifecycle:
//   1. startListening(rideId) — called when ActiveRideScreen mounts
//      a. connects to socket server
//      b. joins the ride room
//      c. registers event listeners
//   2. State updates on each incoming event
//   3. stopListening() — called when screen unmounts
//      a. removes event listeners
//      b. leaves ride room
//      c. disconnects socket

class DriverLocationNotifier extends StateNotifier<DriverLocationState> {
  final SocketService _socket;
  String? _rideId;

  DriverLocationNotifier(this._socket)
      : super(const DriverLocationState());

  // ── Start listening ───────────────────────────────────────────────────────

  Future<void> startListening(String rideId) async {
    _rideId = rideId;

    // Connect and join the ride room
    await _socket.connect();
    _socket.joinRide(rideId);

    // ── driver_location_update ────────────────────────────────────────────
    // Fires every ~5 seconds while the driver is in_progress.
    // Payload: { lat, lng, heading, speedKmh, timestamp }
    _socket.on('driver_location_update', (data) {
      if (data is! Map) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      state = state.copyWith(
        driverLocation: DriverLocation(
          position: LatLng(lat, lng),
          heading: (data['heading'] as num?)?.toDouble() ?? 0,
          speedKmh: (data['speedKmh'] as num?)?.toDouble() ?? 0,
          updatedAt: DateTime.now(),
        ),
      );
    });

    // ── route_deviation ───────────────────────────────────────────────────
    // Server detected driver went off expected route.
    // Payload: { deviationId, deviationMeters, currentLat, currentLng,
    //            message, responseDeadlineSeconds }
    _socket.on('route_deviation', (data) {
      if (data is! Map) return;
      state = state.copyWith(
        deviationAlert: DeviationAlert(
          deviationId: data['deviationId'] as String? ?? '',
          deviationMeters:
              (data['deviationMeters'] as num?)?.toDouble() ?? 0,
          currentLat: (data['currentLat'] as num?)?.toDouble() ?? 0,
          currentLng: (data['currentLng'] as num?)?.toDouble() ?? 0,
          message: data['message'] as String? ??
              'Your driver appears to have taken an unexpected route.',
          responseDeadlineSeconds:
              (data['responseDeadlineSeconds'] as num?)?.toInt() ?? 120,
          receivedAt: DateTime.now(),
        ),
      );
    });

    // ── contacts_alerted ──────────────────────────────────────────────────
    // Server auto-alerted emergency contacts after passenger didn't respond.
    // Clear the deviation alert from the UI.
    _socket.on('contacts_alerted', (_) {
      state = state.copyWith(clearDeviation: true);
    });

    // ── deviation_acknowledged ────────────────────────────────────────────
    // Another passenger in the same ride acknowledged the deviation.
    _socket.on('deviation_acknowledged', (_) {
      state = state.copyWith(clearDeviation: true);
    });

    // ── sos_alert ─────────────────────────────────────────────────────────
    // SOS was triggered (by this passenger or another in a shared ride).
    _socket.on('sos_alert', (_) {
      state = state.copyWith(sosTriggered: true);
    });
  }

  // ── Respond to deviation ──────────────────────────────────────────────────
  // Called when passenger taps "I'm okay" or "Alert contacts".
  // Emits the response to the server and clears the alert from the UI.

  void respondToDeviation(String response) {
    final rideId = _rideId;
    final alert = state.deviationAlert;
    if (rideId == null || alert == null) return;

    _socket.respondToDeviation(rideId, response);
    state = state.copyWith(clearDeviation: true);
  }

  // ── Trigger SOS ───────────────────────────────────────────────────────────
  // Sends SOS to the server which triggers the full safety response:
  // DB record + SMS to emergency contacts + FCM push to driver.

  void triggerSos({double? lat, double? lng}) {
    final rideId = _rideId;
    if (rideId == null) return;

    _socket.triggerSos(rideId, lat: lat, lng: lng);
    state = state.copyWith(sosTriggered: true);
  }

  // ── Stop listening ────────────────────────────────────────────────────────
  // Remove all listeners, leave the ride room, disconnect.
  // Called when ActiveRideScreen disposes.

  void stopListening() {
    _socket.off('driver_location_update');
    _socket.off('route_deviation');
    _socket.off('contacts_alerted');
    _socket.off('deviation_acknowledged');
    _socket.off('sos_alert');

    if (_rideId != null) _socket.leaveRide(_rideId!);
    _socket.disconnect();
    _rideId = null;
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
// autoDispose — created fresh for each active ride, cleaned up when screen leaves.

final driverLocationProvider = StateNotifierProvider
    .autoDispose<DriverLocationNotifier, DriverLocationState>((ref) {
  return DriverLocationNotifier(ref.watch(socketServiceProvider));
});
