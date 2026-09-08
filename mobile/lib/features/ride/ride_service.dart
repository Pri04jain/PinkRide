import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data models ───────────────────────────────────────────────────────────────

/// FareEstimate — what the backend returns from GET /rides/fare-estimate
/// Shown on the home screen before the user confirms a booking.
class FareEstimate {
  final double subtotal;
  final double platformFee;
  final double totalFare;
  final double distanceKm;
  final int durationMin;

  const FareEstimate({
    required this.subtotal,
    required this.platformFee,
    required this.totalFare,
    required this.distanceKm,
    required this.durationMin,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    return FareEstimate(
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platformFee'] as num?)?.toDouble() ?? 0,
      totalFare: (json['totalFare'] as num?)?.toDouble() ?? 0,
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      durationMin: (json['durationMin'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedFare => '₹${totalFare.toStringAsFixed(0)}';
  String get formattedDistance => '${distanceKm.toStringAsFixed(1)} km';
  String get formattedDuration => '$durationMin min';
}

/// RideModel — represents a ride record returned by the backend.
/// Used for both the active ride screen and ride history.
class RideModel {
  final String id;
  final String rideType;      // 'private' | 'shared' | 'women_only_shared'
  final String status;        // searching | confirmed | in_progress | completed...
  final String pickupAddress;
  final String dropAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropLat;
  final double dropLng;
  final double finalFare;
  final String paymentMethod; // 'cash' | 'upi'
  final String scheduledAt;
  final double distanceKm;
  final DriverInfo? driver;   // null until a driver is assigned

  const RideModel({
    required this.id,
    required this.rideType,
    required this.status,
    required this.pickupAddress,
    required this.dropAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropLat,
    required this.dropLng,
    required this.finalFare,
    required this.paymentMethod,
    required this.scheduledAt,
    required this.distanceKm,
    this.driver,
  });

  factory RideModel.fromJson(Map<String, dynamic> json) {
    // Driver info comes nested under 'drivers' join in the backend response
    final driverJson = json['drivers'] as Map<String, dynamic>?;
    return RideModel(
      id: json['id'] as String? ?? '',
      rideType: json['ride_type'] as String? ?? 'private',
      status: json['status'] as String? ?? 'searching',
      pickupAddress: json['pickup_address'] as String? ?? '',
      dropAddress: json['drop_address'] as String? ?? '',
      pickupLat: (json['pickup_lat'] as num?)?.toDouble() ?? 0,
      pickupLng: (json['pickup_lng'] as num?)?.toDouble() ?? 0,
      dropLat: (json['drop_lat'] as num?)?.toDouble() ?? 0,
      dropLng: (json['drop_lng'] as num?)?.toDouble() ?? 0,
      finalFare: (json['final_fare'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      scheduledAt: json['scheduled_at'] as String? ?? '',
      distanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0,
      driver: driverJson != null ? DriverInfo.fromJson(driverJson) : null,
    );
  }

  // Convenience getters used by the UI
  bool get isSearching => status == 'searching' || status == 'matching';
  bool get isConfirmed => status == 'confirmed' || status == 'driver_arriving';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get canCancel => !isInProgress && !isCompleted && !isCancelled;

  String get statusLabel {
    switch (status) {
      case 'searching':    return 'Finding a driver...';
      case 'matching':     return 'Finding a co-passenger...';
      case 'confirmed':    return 'Driver assigned';
      case 'driver_arriving': return 'Driver is on the way';
      case 'otp_pending':  return 'Ready to board';
      case 'in_progress':  return 'Trip in progress';
      case 'completed':    return 'Trip completed';
      case 'cancelled':    return 'Cancelled';
      default:             return status;
    }
  }
}

/// DriverInfo — nested inside RideModel once a driver is assigned.
class DriverInfo {
  final String userId;
  final String fullName;
  final String phone;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleNumber;
  final String vehicleColor;
  final double reliabilityScore;

  const DriverInfo({
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleNumber,
    required this.vehicleColor,
    required this.reliabilityScore,
  });

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    // The backend joins users table — name/phone come from users!inner
    final userJson = json['users'] as Map<String, dynamic>?;
    return DriverInfo(
      userId: json['user_id'] as String? ?? '',
      fullName: userJson?['full_name'] as String? ?? 'Your Driver',
      phone: userJson?['phone'] as String? ?? '',
      vehicleMake: json['vehicle_make'] as String? ?? '',
      vehicleModel: json['vehicle_model'] as String? ?? '',
      vehicleNumber: json['vehicle_number'] as String? ?? '',
      vehicleColor: json['vehicle_color'] as String? ?? '',
      reliabilityScore:
          (userJson?['reliability_score'] as num?)?.toDouble() ?? 5.0,
    );
  }

  String get vehicleDisplay => '$vehicleColor $vehicleMake $vehicleModel';
}

// ── BookingData ───────────────────────────────────────────────────────────────
// Passed from PassengerHomeScreen → RideBookingSheet → RideService.bookRide()
// Holds everything needed to create a ride on the backend.

class BookingData {
  final String rideType;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropLat;
  final double dropLng;
  final String dropAddress;
  final String scheduledAt;   // ISO string
  final String paymentMethod; // 'cash' | 'upi'

  const BookingData({
    required this.rideType,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropLat,
    required this.dropLng,
    required this.dropAddress,
    required this.scheduledAt,
    required this.paymentMethod,
  });

  Map<String, dynamic> toJson() => {
    'rideType': rideType,
    'pickupLat': pickupLat,
    'pickupLng': pickupLng,
    'pickupAddress': pickupAddress,
    'dropLat': dropLat,
    'dropLng': dropLng,
    'dropAddress': dropAddress,
    'scheduledAt': scheduledAt,
    'paymentMethod': paymentMethod,
  };
}

// ── RideService ───────────────────────────────────────────────────────────────

class RideService {
  final ApiClient _api;
  const RideService(this._api);

  // ── 1. Fare estimate ──────────────────────────────────────────────────────
  // Called whenever pickup/drop coordinates change.
  // Server calculates real driving distance via Google Maps (or Haversine fallback).
  // Returns subtotal, platformFee, totalFare, distanceKm, durationMin.

  Future<FareEstimate> getFareEstimate({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    String rideType = 'private',
  }) async {
    final data = await _api.get(
      ApiEndpoints.fareEstimate,
      queryParams: {
        'pickupLat': pickupLat,
        'pickupLng': pickupLng,
        'dropLat': dropLat,
        'dropLng': dropLng,
        'rideType': rideType,
      },
    );
    return FareEstimate.fromJson(data);
  }

  // ── 2. Book ride ──────────────────────────────────────────────────────────
  // Creates the ride record on the backend.
  // Returns rideId and initial status ('searching').
  // The backend then looks for a driver (or co-passenger for shared rides).

  Future<RideModel> bookRide(BookingData booking) async {
    final data = await _api.post(
      ApiEndpoints.bookRide,
      data: booking.toJson(),
    );
    return RideModel.fromJson(data);
  }

  // ── 3. Get active ride ────────────────────────────────────────────────────
  // Returns the passenger's current active ride (if any).
  // Called on app startup and after booking to check if a ride is in progress.
  // Returns null if no active ride exists.

  Future<RideModel?> getActiveRide() async {
    try {
      final data = await _api.get(ApiEndpoints.fareEstimate.replaceAll(
        '/fare-estimate', '/active',
      ));
      final ride = data['ride'];
      if (ride == null) return null;
      return RideModel.fromJson(ride as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  // ── 4. Get ride by ID ─────────────────────────────────────────────────────
  // Polls for the latest status of a specific ride.
  // Used by ActiveRideNotifier to track status changes.

  Future<RideModel> getRideById(String rideId) async {
    final data = await _api.get(ApiEndpoints.rideDetail(rideId));
    return RideModel.fromJson(data['ride'] as Map<String, dynamic>? ?? data);
  }

  // ── 5. Cancel ride ────────────────────────────────────────────────────────
  // Passenger cancels before the trip starts.
  // If confirmed, a cancellation fine is deducted from the wallet.

  Future<void> cancelRide(String rideId, {String reason = 'Cancelled by passenger'}) async {
    await _api.post(
      ApiEndpoints.cancelRide(rideId),
      data: {'reason': reason},
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final rideServiceProvider = Provider<RideService>((ref) {
  return RideService(ref.watch(apiClientProvider));
});
