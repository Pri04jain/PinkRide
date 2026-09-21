// ── RideRequestModel ──────────────────────────────────────────────────────────
//
// Maps each item in the GET /drivers/ride-requests → requests[] array.
// Backend adds a computed `distanceToPickupKm` field before sending.
//
//   {
//     id, ride_type, status,
//     pickup_lat, pickup_lng, pickup_address,
//     drop_lat, drop_lng, drop_address,
//     scheduled_at, final_fare, payment_method, max_passengers,
//     distanceToPickupKm,
//     ride_passengers: [{ id, passenger_id, total_fare }]
//   }

class RideRequestModel {
  final String id;
  final String rideType;     // 'shared' | 'private'
  final String status;       // 'searching' | 'matching'

  final double pickupLat;
  final double pickupLng;
  final String pickupAddress;

  final double dropLat;
  final double dropLng;
  final String dropAddress;

  final DateTime? scheduledAt;
  final double? finalFare;
  final String paymentMethod; // 'cash' | 'upi' | 'wallet'
  final int maxPassengers;

  /// Distance from driver's current location to the pickup point.
  /// Pre-computed by the backend (Haversine).
  final double distanceToPickupKm;

  /// Number of passengers already booked on this ride.
  final int passengerCount;

  const RideRequestModel({
    required this.id,
    required this.rideType,
    required this.status,
    required this.pickupLat,
    required this.pickupLng,
    required this.pickupAddress,
    required this.dropLat,
    required this.dropLng,
    required this.dropAddress,
    this.scheduledAt,
    this.finalFare,
    required this.paymentMethod,
    required this.maxPassengers,
    required this.distanceToPickupKm,
    required this.passengerCount,
  });

  factory RideRequestModel.fromJson(Map<String, dynamic> json) {
    final passengers = json['ride_passengers'] as List<dynamic>? ?? [];

    return RideRequestModel(
      id: json['id'] as String? ?? '',
      rideType: json['ride_type'] as String? ?? 'shared',
      status: json['status'] as String? ?? 'searching',

      pickupLat: (json['pickup_lat'] as num?)?.toDouble() ?? 0.0,
      pickupLng: (json['pickup_lng'] as num?)?.toDouble() ?? 0.0,
      pickupAddress: json['pickup_address'] as String? ?? '',

      dropLat: (json['drop_lat'] as num?)?.toDouble() ?? 0.0,
      dropLng: (json['drop_lng'] as num?)?.toDouble() ?? 0.0,
      dropAddress: json['drop_address'] as String? ?? '',

      scheduledAt: _parseDate(json['scheduled_at']),
      finalFare: (json['final_fare'] as num?)?.toDouble(),
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      maxPassengers: (json['max_passengers'] as num?)?.toInt() ?? 1,

      distanceToPickupKm:
          (json['distanceToPickupKm'] as num?)?.toDouble() ?? 0.0,
      passengerCount: passengers.length,
    );
  }

  // ── Convenience getters ───────────────────────────────────────────────────

  /// Distance string shown on the ride card, e.g. "1.2 km away".
  String get distanceLabel {
    if (distanceToPickupKm < 1.0) {
      return '${(distanceToPickupKm * 1000).round()} m away';
    }
    return '${distanceToPickupKm.toStringAsFixed(1)} km away';
  }

  /// Fare display string. Falls back to "Fare TBD" if not calculated yet.
  String get fareLabel {
    if (finalFare == null || finalFare == 0) return 'Fare TBD';
    return '₹${finalFare!.toStringAsFixed(0)}';
  }

  /// Payment method icon / label.
  String get paymentLabel => switch (paymentMethod) {
        'upi' => 'UPI',
        'wallet' => 'Wallet',
        _ => 'Cash',
      };

  bool get isShared => rideType == 'shared';

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw as String);
    } catch (_) {
      return null;
    }
  }
}
