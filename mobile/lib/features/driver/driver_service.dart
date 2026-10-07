import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';
import 'models/driver_model.dart';
import 'models/ride_request_model.dart';

// ── DriverService ─────────────────────────────────────────────────────────────
//
// Handles all driver-related HTTP calls. Thin layer between the API and the
// providers — maps raw JSON maps into typed models, throws AppError on failure.

class DriverService {
  final ApiClient _api;
  DriverService(this._api);

  // ── Get profile ───────────────────────────────────────────────────────────
  // Returns the full driver record joined with the user row.
  // Called on DriverHomeScreen mount and after registration.

  Future<DriverModel> getProfile() async {
    final data = await _api.get(ApiEndpoints.driverProfile);
    return DriverModel.fromJson(data);
  }

  // ── Register driver ───────────────────────────────────────────────────────
  // Creates the drivers row in Supabase.
  // Backend validates: face_verified, DL format, vehicleYear ≥ 2005, etc.

  Future<DriverModel> registerDriver({
    required String licenseNumber,
    required String licenseExpiry, // 'YYYY-MM-DD'
    required String vehicleNumber,
    required String vehicleType,   // Hatchback | Sedan | SUV | MUV | Van
    required String vehicleMake,
    required String vehicleModel,
    required String vehicleColor,
    required int vehicleYear,
  }) async {
    final data = await _api.post(ApiEndpoints.driverRegister, data: {
      'licenseNumber': licenseNumber,
      'licenseExpiry': licenseExpiry,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      'vehicleMake': vehicleMake,
      'vehicleModel': vehicleModel,
      'vehicleColor': vehicleColor,
      'vehicleYear': vehicleYear,
    });
    return DriverModel.fromJson(data);
  }

  // ── Upload document ───────────────────────────────────────────────────────
  // docType: 'license' | 'rc' | 'insurance'
  // filePath: local file path on device

  Future<void> uploadDocument({
    required String docType,
    required String filePath,
  }) async {
    await _api.uploadFile(
      ApiEndpoints.uploadDocument(docType),
      filePath: filePath,
      fieldName: 'file',
    );
  }

  // ── Set availability ──────────────────────────────────────────────────────
  // Toggles driver online/offline.
  // Backend rejects if approval_status != 'approved'.

  Future<bool> setAvailability({required bool isAvailable}) async {
    final data = await _api.patch(
      ApiEndpoints.driverAvailability,
      data: {'isAvailable': isAvailable},
    );
    return (data['isAvailable'] as bool?) ?? isAvailable;
  }

  // ── Update location ───────────────────────────────────────────────────────
  // Sends current GPS coordinates to the backend.
  // Called periodically while driver is online.

  Future<void> updateLocation({
    required double lat,
    required double lng,
  }) async {
    await _api.patch(
      ApiEndpoints.driverLocation,
      data: {'lat': lat, 'lng': lng},
    );
  }

  // ── Get nearby ride requests ───────────────────────────────────────────────
  // Returns open rides within the driver's configured radius (default 5 km).
  // Backend rejects if driver is offline or not approved.

  Future<NearbyRidesResult> getNearbyRideRequests() async {
    final data = await _api.get(ApiEndpoints.driverRideRequests);
    final list = (data['requests'] as List<dynamic>? ?? [])
        .map((e) => RideRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return NearbyRidesResult(
      requests: list,
      radiusKm: (data['radiusKm'] as num?)?.toDouble() ?? 5.0,
      driverLat: (data['driverLocation']?['lat'] as num?)?.toDouble(),
      driverLng: (data['driverLocation']?['lng'] as num?)?.toDouble(),
    );
  }

  // ── Accept ride ───────────────────────────────────────────────────────────
  // Atomic — backend uses IS NULL guard to prevent double-accept.
  // On success: ride is assigned to this driver, passengers notified via FCM.

  Future<void> acceptRide(String rideId) async {
    await _api.post(ApiEndpoints.acceptRideById(rideId));
  }
}

// ── NearbyRidesResult ─────────────────────────────────────────────────────────
// Wrapper returned by getNearbyRideRequests — includes driver location and
// radius for display in the UI.

class NearbyRidesResult {
  final List<RideRequestModel> requests;
  final double radiusKm;
  final double? driverLat;
  final double? driverLng;

  const NearbyRidesResult({
    required this.requests,
    required this.radiusKm,
    this.driverLat,
    this.driverLng,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────────

final driverServiceProvider = Provider<DriverService>((ref) {
  return DriverService(ref.watch(apiClientProvider));
});
