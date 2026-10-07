import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../../core/utils/storage_service.dart';

// ── Driver location model ─────────────────────────────────────────────────────

class DriverLocation {
  final double lat;
  final double lng;
  final double? heading;      // direction the driver is facing (degrees)
  final double? speedKmh;     // optional speed
  final DateTime updatedAt;

  const DriverLocation({
    required this.lat,
    required this.lng,
    this.heading,
    this.speedKmh,
    required this.updatedAt,
  });

  factory DriverLocation.fromJson(Map<String, dynamic> json) {
    return DriverLocation(
      lat:       (json['lat']     as num?)?.toDouble() ?? 0,
      lng:       (json['lng']     as num?)?.toDouble() ?? 0,
      heading:   (json['heading'] as num?)?.toDouble(),
      speedKmh:  (json['speed']   as num?)?.toDouble(),
      updatedAt: DateTime.now(),
    );
  }
}

// ── Deviation alert model ─────────────────────────────────────────────────────

class DeviationAlert {
  final String rideId;
  final double deviationMetres;
  final DateTime detectedAt;
  bool dismissed;

  DeviationAlert({
    required this.rideId,
    required this.deviationMetres,
    required this.detectedAt,
    this.dismissed = false,
  });
}

// ── Tracking state ────────────────────────────────────────────────────────────

class TrackingState {
  final DriverLocation? driverLocation;
  final bool isConnected;
  final bool isConnecting;
  final DeviationAlert? deviationAlert;   // non-null when driver deviated
  final String? errorMessage;

  const TrackingState({
    this.driverLocation,
    this.isConnected = false,
    this.isConnecting = false,
    this.deviationAlert,
    this.errorMessage,
  });

  TrackingState copyWith({
    DriverLocation? driverLocation,
    bool? isConnected,
    bool? isConnecting,
    DeviationAlert? deviationAlert,
    String? errorMessage,
    bool clearDeviation = false,
    bool clearError = false,
  }) =>
      TrackingState(
        driverLocation: driverLocation ?? this.driverLocation,
        isConnected:    isConnected    ?? this.isConnected,
        isConnecting:   isConnecting   ?? this.isConnecting,
        deviationAlert: clearDeviation ? null : (deviationAlert ?? this.deviationAlert),
        errorMessage:   clearError     ? null : (errorMessage   ?? this.errorMessage),
      );
}

// ── TrackingNotifier ──────────────────────────────────────────────────────────
//
// Manages the Socket.io connection for live driver location during a ride.
//
// LIFECYCLE:
//   startTracking(rideId)  → connects, joins room, receives location events
//   stopTracking()         → disconnects socket, releases resources
//
// SOCKET EVENTS (emitted by backend):
//   driver_location   → { lat, lng, heading, speed }
//   route_deviation   → { rideId, deviationMetres }
//   ride_update       → { status } (e.g. driver_arrived, in_progress, completed)
//
// WHY SOCKET.IO INSTEAD OF POLLING?
//   Driver location updates every 5 seconds. Polling every 5s from the client
//   means a new HTTP request per poll. With 100 active rides that's 20 req/s
//   hitting the server. Socket.io uses one persistent TCP connection per client —
//   the server pushes updates the moment they arrive, costing almost nothing.

class TrackingNotifier extends StateNotifier<TrackingState> {
  io.Socket? _socket;
  String? _rideId;

  TrackingNotifier() : super(const TrackingState());

  // ── Connect and start receiving location updates ──────────────────────────

  Future<void> startTracking(String rideId) async {
    if (_rideId == rideId && state.isConnected) return; // already tracking
    await stopTracking(); // cleanly disconnect any previous session

    _rideId = rideId;
    state = state.copyWith(isConnecting: true, clearError: true);

    try {
      final token     = await StorageService.getAccessToken() ?? '';
      final serverUrl = dotenv.env['SOCKET_URL']
          ?? dotenv.env['API_BASE_URL']?.replaceFirst('/api/v1', '')
          ?? 'http://localhost:3000';

      _socket = io.io(
        serverUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .setAuth({'token': token})
            .disableAutoConnect()   // we connect manually below
            .enableForceNewConnection()
            .build(),
      );

      // ── Register event handlers before connecting ─────────────────────────

      _socket!.on('connect', (_) {
        state = state.copyWith(isConnected: true, isConnecting: false);
        // Tell the server we want updates for this ride
        _socket!.emit('join_ride_room', {'rideId': rideId});
      });

      _socket!.on('disconnect', (_) {
        state = state.copyWith(isConnected: false);
      });

      _socket!.on('connect_error', (err) {
        state = state.copyWith(
          isConnecting: false,
          isConnected: false,
          errorMessage: 'Could not connect to live tracking.',
        );
      });

      // Driver sends their location every 5s — we update the map pin
      _socket!.on('driver_location', (data) {
        if (data is Map<String, dynamic>) {
          state = state.copyWith(
            driverLocation: DriverLocation.fromJson(data),
          );
        }
      });

      // Backend detected the driver went off-route
      _socket!.on('route_deviation', (data) {
        if (data is Map<String, dynamic>) {
          state = state.copyWith(
            deviationAlert: DeviationAlert(
              rideId:           data['rideId']          as String? ?? rideId,
              deviationMetres:  (data['deviationMetres'] as num?)?.toDouble() ?? 0,
              detectedAt:       DateTime.now(),
            ),
          );
        }
      });

      _socket!.connect();
    } catch (_) {
      state = state.copyWith(
        isConnecting: false,
        errorMessage: 'Live tracking unavailable.',
      );
    }
  }

  /// Dismiss the deviation alert (user tapped "I'm Safe").
  void dismissDeviation() {
    state = state.copyWith(clearDeviation: true);
  }

  /// Disconnect and clean up.
  Future<void> stopTracking() async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _rideId = null;
    state = const TrackingState();
  }

  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────
// Not autoDispose — tracking must survive screen navigations (e.g. user opens
// SOS screen then comes back to the active ride screen).

final trackingProvider =
    StateNotifierProvider<TrackingNotifier, TrackingState>((ref) {
  return TrackingNotifier();
});

// ── Driver's own GPS sender (for driver side) ─────────────────────────────────
//
// Separate provider used on the DriverHomeScreen.
// Sends the driver's GPS coordinates to the backend every 5 seconds via
// Socket.io so the passenger can see them on the map.

class DriverLocationSenderNotifier extends StateNotifier<bool> {
  io.Socket? _socket;
  StreamSubscription<Position>? _gpsSubscription;
  String? _rideId;

  DriverLocationSenderNotifier() : super(false);

  Future<void> startSending(String rideId) async {
    if (_rideId == rideId && state) return;
    await stopSending();

    _rideId = rideId;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    final token     = await StorageService.getAccessToken() ?? '';
    final serverUrl = dotenv.env['SOCKET_URL']
        ?? dotenv.env['API_BASE_URL']?.replaceFirst('/api/v1', '')
        ?? 'http://localhost:3000';

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .enableForceNewConnection()
          .build(),
    );

    _socket!.on('connect', (_) {
      state = true;
      _socket!.emit('join_ride_room', {'rideId': rideId});
    });

    _socket!.on('disconnect', (_) => state = false);
    _socket!.connect();

    // Emit GPS every 5 seconds
    _gpsSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // only emit if moved >10m
      ),
    ).listen((position) {
      if (_socket?.connected == true) {
        _socket!.emit('driver_location', {
          'rideId':  rideId,
          'lat':     position.latitude,
          'lng':     position.longitude,
          'heading': position.heading,
          'speed':   position.speed * 3.6, // m/s → km/h
        });
      }
    });
  }

  Future<void> stopSending() async {
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _rideId = null;
    state = false;
  }

  @override
  void dispose() {
    _gpsSubscription?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    super.dispose();
  }
}

final driverLocationSenderProvider =
    StateNotifierProvider<DriverLocationSenderNotifier, bool>((ref) {
  return DriverLocationSenderNotifier();
});
