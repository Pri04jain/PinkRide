import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../utils/storage_service.dart';

// ── SocketService ─────────────────────────────────────────────────────────────
//
// HOW SOCKET.IO WORKS (vs REST):
//
//   REST (what ApiClient does):
//     Flutter → sends request → waits → server replies → connection closes
//     One request = one response. Connection closes after each.
//
//   Socket.io (what this does):
//     Flutter → connects once → connection STAYS OPEN
//     Server can push data to Flutter AT ANY TIME without Flutter asking.
//     Flutter can also send data to the server at any time.
//     This is how the driver's location reaches the passenger in real time.
//
// THE CONNECTION LIFECYCLE:
//   1. connect()      → open the WebSocket connection, attach JWT
//   2. joinRide()     → tell server "I'm watching this rideId"
//   3. listen events  → receive driver_location_update, route_deviation, etc.
//   4. emit events    → send sos_triggered, deviation_response, etc.
//   5. leaveRide()    → tell server "I'm leaving this ride room"
//   6. disconnect()   → close the connection
//
// JWT AUTHENTICATION:
//   The backend's socket server reads the token from:
//     socket.handshake.auth.token
//   We pass it when creating the socket (in the auth option).
//   If the token is invalid, the server rejects the connection.
//
// EVENTS WE LISTEN TO (server → passenger):
//   driver_location_update  → { lat, lng, heading, speedKmh, timestamp }
//   route_deviation         → { deviationId, deviationMeters, ... }
//   sos_alert               → { triggeredBy, rideId, timestamp }
//   contacts_alerted        → { deviationId, reason }
//   deviation_acknowledged  → { passengerId, response, timestamp }
//   joined_ride             → { rideId } (confirmation)
//
// EVENTS WE EMIT (passenger → server):
//   join_ride        → { rideId }
//   leave_ride       → { rideId }
//   sos_triggered    → { rideId, lat?, lng? }
//   deviation_response → { rideId, response: 'ok' | 'alert' }

class SocketService {
  io.Socket? _socket;
  String? _currentRideId;

  // ── Connect ───────────────────────────────────────────────────────────────
  // Opens the WebSocket connection to the backend.
  // Called when the active ride screen mounts.

  Future<void> connect() async {
    if (_socket?.connected == true) return; // already connected

    final token = await StorageService.getAccessToken();
    if (token == null) return;

    final baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:3000/api/v1';
    // Socket.io connects to the server root, not the /api/v1 path
    final serverUrl = baseUrl.replaceAll('/api/v1', '');

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling']) // websocket first, polling fallback
          .setAuth({'token': token})               // JWT for authentication
          .disableAutoConnect()                    // we call connect() manually
          .enableReconnection()                    // auto-reconnect on disconnect
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)              // wait 2s between retries
          .build(),
    );

    _socket!.connect();

    // Log connection events in debug — useful for diagnosing issues
    _socket!.onConnect((_) {
      // ignore: avoid_print
      print('[Socket] Connected: ${_socket?.id}');
    });

    _socket!.onConnectError((err) {
      // ignore: avoid_print
      print('[Socket] Connect error: $err');
    });

    _socket!.onDisconnect((_) {
      // ignore: avoid_print
      print('[Socket] Disconnected');
    });
  }

  // ── Join ride room ────────────────────────────────────────────────────────
  // Tells the server we want to receive events for this specific ride.
  // The server validates that we actually belong to this ride before
  // adding us to the room — so we can't spy on other rides.

  void joinRide(String rideId) {
    if (_socket?.connected != true) return;
    _currentRideId = rideId;
    _socket!.emit('join_ride', {'rideId': rideId});
  }

  // ── Leave ride room ───────────────────────────────────────────────────────
  // Called when the active ride screen unmounts or ride completes.

  void leaveRide(String rideId) {
    if (_socket?.connected != true) return;
    _socket!.emit('leave_ride', {'rideId': rideId});
    _currentRideId = null;
  }

  // ── Emit SOS ──────────────────────────────────────────────────────────────
  // Passenger triggers SOS — sends to server which calls safetyService.triggerSOS()
  // (DB record + SMS to emergency contacts + FCM push to driver).

  void triggerSos(String rideId, {double? lat, double? lng}) {
    if (_socket?.connected != true) return;
    _socket!.emit('sos_triggered', {
      'rideId': rideId,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
    });
  }

  // ── Respond to deviation ──────────────────────────────────────────────────
  // Called when passenger taps "I'm okay" or "Alert contacts".

  void respondToDeviation(String rideId, String response) {
    if (_socket?.connected != true) return;
    _socket!.emit('deviation_response', {
      'rideId': rideId,
      'response': response, // 'ok' | 'alert'
    });
  }

  // ── Listen for events ─────────────────────────────────────────────────────
  // Register a callback for a specific event.
  // The callback receives the data Map the server sent.
  // Called from socket_provider.dart to wire up state updates.

  void on(String event, Function(dynamic) callback) {
    _socket?.on(event, callback);
  }

  // ── Remove listener ───────────────────────────────────────────────────────
  // Always remove listeners when the screen unmounts to prevent
  // callbacks firing on a dead widget.

  void off(String event) {
    _socket?.off(event);
  }

  // ── Disconnect ────────────────────────────────────────────────────────────
  // Close the connection. Called when the user leaves the active ride screen
  // and there's no reason to stay connected.

  void disconnect() {
    if (_currentRideId != null) {
      leaveRide(_currentRideId!);
    }
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _currentRideId = null;
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  bool get isConnected => _socket?.connected == true;
  String? get currentRideId => _currentRideId;
}

// ── Provider ──────────────────────────────────────────────────────────────────
// Not autoDispose — the socket must persist across widget rebuilds.
// Only disconnected explicitly when the ride ends.

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  // Dispose when provider is removed (app closed)
  ref.onDispose(service.disconnect);
  return service;
});
