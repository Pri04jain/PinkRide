import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data models ───────────────────────────────────────────────────────────────

/// Fare estimate returned from /rides/estimate
class FareEstimate {
  final double distanceKm;
  final double baseFare;
  final double platformFee;
  final double totalFare;
  final int durationMinutes;

  const FareEstimate({
    required this.distanceKm,
    required this.baseFare,
    required this.platformFee,
    required this.totalFare,
    required this.durationMinutes,
  });

  factory FareEstimate.fromJson(Map<String, dynamic> json) {
    return FareEstimate(
      distanceKm:      (json['distanceKm']      as num?)?.toDouble() ?? 0,
      baseFare:        (json['baseFare']         as num?)?.toDouble() ?? 0,
      platformFee:     (json['platformFee']      as num?)?.toDouble() ?? 0,
      totalFare:       (json['totalFare']        as num?)?.toDouble() ?? 0,
      durationMinutes: (json['durationMinutes']  as num?)?.toInt()    ?? 0,
    );
  }
}

/// Booking data sent to POST /rides
class BookingData {
  final String rideType;
  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;
  final double dropLat;
  final double dropLng;
  final String dropAddress;
  final String scheduledAt;  // ISO-8601
  final String paymentMethod;

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
        'rideType':      rideType,
        'pickupLat':     pickupLat,
        'pickupLng':     pickupLng,
        'pickupAddress': pickupAddress,
        'dropLat':       dropLat,
        'dropLng':       dropLng,
        'dropAddress':   dropAddress,
        'scheduledAt':   scheduledAt,
        'paymentMethod': paymentMethod,
      };
}

/// Ride returned from the backend — used throughout the active ride flow.
class RideModel {
  final String id;
  final String status;
  final String rideType;
  final String pickupAddress;
  final String dropAddress;
  final double? finalFare;
  final String? paymentMethod;
  final String? driverId;
  final String scheduledAt;

  const RideModel({
    required this.id,
    required this.status,
    required this.rideType,
    required this.pickupAddress,
    required this.dropAddress,
    this.finalFare,
    this.paymentMethod,
    this.driverId,
    required this.scheduledAt,
  });

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isInProgress => status == 'in_progress';

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id:             json['id']              as String? ?? '',
      status:         json['status']          as String? ?? '',
      rideType:       json['ride_type']        as String? ?? 'private',
      pickupAddress:  json['pickup_address']   as String? ?? '',
      dropAddress:    json['drop_address']     as String? ?? '',
      finalFare:      (json['final_fare']      as num?)?.toDouble(),
      paymentMethod:  json['payment_method']   as String?,
      driverId:       json['driver_id']        as String?,
      scheduledAt:    json['scheduled_at']     as String? ?? '',
    );
  }
}

// ── RideService ───────────────────────────────────────────────────────────────

class RideService {
  final ApiClient _api;
  RideService(this._api);

  /// Estimate fare for the given route + ride type.
  Future<FareEstimate> getFareEstimate({
    required double pickupLat,
    required double pickupLng,
    required double dropLat,
    required double dropLng,
    required String rideType,
  }) async {
    final data = await _api.get(ApiEndpoints.fareEstimate, queryParams: {
      'pickupLat':  pickupLat.toString(),
      'pickupLng':  pickupLng.toString(),
      'dropLat':    dropLat.toString(),
      'dropLng':    dropLng.toString(),
      'rideType':   rideType,
    });
    return FareEstimate.fromJson(data);
  }

  /// Create a new ride booking.
  Future<RideModel> bookRide(BookingData booking) async {
    final data = await _api.post(ApiEndpoints.bookRide, data: booking.toJson());
    return RideModel.fromJson(data['ride'] as Map<String, dynamic>? ?? data);
  }

  /// Get the current user's active ride (if any).
  Future<RideModel?> getActiveRide() async {
    try {
      final data = await _api.get(ApiEndpoints.activeRide);

      // Backend returns { ride: {...} } or { ride: null } when no active ride
      final rideJson = data['ride'] as Map<String, dynamic>?;
      if (rideJson == null) return null;

      final ride = RideModel.fromJson(rideJson);
      // Extra safety — don't return a ride with no ID
      if (ride.id.isEmpty) return null;
      return ride;
    } catch (_) {
      return null;
    }
  }

  /// Fetch a specific ride by ID.
  Future<RideModel> getRideById(String rideId) async {
    final data = await _api.get(ApiEndpoints.rideById(rideId));
    return RideModel.fromJson(data['ride'] as Map<String, dynamic>? ?? data);
  }

  /// Cancel a ride.
  Future<void> cancelRide(String rideId, {String reason = ''}) async {
    await _api.post(ApiEndpoints.cancelRide(rideId), data: {'reason': reason});
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final rideServiceProvider =
    Provider<RideService>((ref) => RideService(ref.watch(apiClientProvider)));
