// ── DriverModel ───────────────────────────────────────────────────────────────
//
// Maps the backend GET /drivers/profile response.
// The backend returns the drivers row joined with the users row:
//
//   {
//     id, user_id,
//     license_number, license_expiry,
//     vehicle_number, vehicle_type, vehicle_make, vehicle_model,
//     vehicle_color, vehicle_year,
//     approval_status, rejection_reason,
//     is_available, total_trips, cancellation_count,
//     license_doc_url, vehicle_rc_url, vehicle_insurance_url,
//     created_at, updated_at,
//     users: { full_name, phone, face_verified, reliability_score }
//   }

class DriverModel {
  final String id;
  final String userId;

  // License
  final String licenseNumber;
  final String licenseExpiry;
  final String? licenseDocUrl;

  // Vehicle
  final String vehicleNumber;
  final String vehicleType;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleColor;
  final int vehicleYear;
  final String? vehicleRcUrl;
  final String? vehicleInsuranceUrl;

  // Status
  final String approvalStatus; // pending | under_review | approved | rejected | suspended
  final String? rejectionReason;

  // Operational
  final bool isAvailable;
  final int totalTrips;
  final int cancellationCount;

  // From joined users row
  final String? fullName;
  final String? phone;
  final bool faceVerified;
  final double reliabilityScore;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DriverModel({
    required this.id,
    required this.userId,
    required this.licenseNumber,
    required this.licenseExpiry,
    this.licenseDocUrl,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehicleYear,
    this.vehicleRcUrl,
    this.vehicleInsuranceUrl,
    required this.approvalStatus,
    this.rejectionReason,
    required this.isAvailable,
    required this.totalTrips,
    required this.cancellationCount,
    this.fullName,
    this.phone,
    this.faceVerified = false,
    this.reliabilityScore = 5.0,
    this.createdAt,
    this.updatedAt,
  });

  factory DriverModel.fromJson(Map<String, dynamic> json) {
    // The users join can come back as a nested map OR flattened at the top level
    // depending on which endpoint returned the data.
    final users = json['users'] as Map<String, dynamic>?;

    return DriverModel(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',

      licenseNumber: json['license_number'] as String? ?? '',
      licenseExpiry: json['license_expiry'] as String? ?? '',
      licenseDocUrl: _docUrl(json['license_doc_url']),

      vehicleNumber: json['vehicle_number'] as String? ?? '',
      vehicleType: json['vehicle_type'] as String? ?? '',
      vehicleMake: json['vehicle_make'] as String? ?? '',
      vehicleModel: json['vehicle_model'] as String? ?? '',
      vehicleColor: json['vehicle_color'] as String? ?? '',
      vehicleYear: (json['vehicle_year'] as num?)?.toInt() ?? 0,
      vehicleRcUrl: _docUrl(json['vehicle_rc_url']),
      vehicleInsuranceUrl: _docUrl(json['vehicle_insurance_url']),

      approvalStatus: json['approval_status'] as String? ?? 'pending',
      rejectionReason: json['rejection_reason'] as String?,

      isAvailable: json['is_available'] as bool? ?? false,
      totalTrips: (json['total_trips'] as num?)?.toInt() ?? 0,
      cancellationCount: (json['cancellation_count'] as num?)?.toInt() ?? 0,

      fullName: (users?['full_name'] ?? json['full_name']) as String?,
      phone: (users?['phone'] ?? json['phone']) as String?,
      faceVerified:
          (users?['face_verified'] ?? json['face_verified']) as bool? ?? false,
      reliabilityScore:
          ((users?['reliability_score'] ?? json['reliability_score']) as num?)
                  ?.toDouble() ??
              5.0,

      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  // ── Convenience getters ───────────────────────────────────────────────────

  /// Human-readable approval status label.
  String get statusLabel => switch (approvalStatus) {
        'pending' => 'Pending',
        'under_review' => 'Under Review',
        'approved' => 'Approved',
        'rejected' => 'Rejected',
        'suspended' => 'Suspended',
        _ => approvalStatus,
      };

  /// True only when the driver is fully approved and can go online.
  bool get isApproved => approvalStatus == 'approved';

  /// True when the application is waiting for admin action.
  bool get isPendingReview =>
      approvalStatus == 'pending' || approvalStatus == 'under_review';

  bool get isRejected => approvalStatus == 'rejected';
  bool get isSuspended => approvalStatus == 'suspended';

  /// One-line vehicle description shown in cards.
  String get vehicleDisplay =>
      '$vehicleColor $vehicleMake $vehicleModel ($vehicleYear) · $vehicleNumber';

  /// Whether the license document has been uploaded (not still a placeholder).
  bool get hasLicenseDoc =>
      licenseDocUrl != null && licenseDocUrl!.isNotEmpty;

  bool get hasRcDoc =>
      vehicleRcUrl != null && vehicleRcUrl!.isNotEmpty;

  bool get hasInsuranceDoc =>
      vehicleInsuranceUrl != null && vehicleInsuranceUrl!.isNotEmpty;

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns null for 'pending_upload' placeholder values.
  static String? _docUrl(dynamic raw) {
    if (raw == null) return null;
    final s = raw as String;
    return s == 'pending_upload' || s.isEmpty ? null : s;
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw as String);
    } catch (_) {
      return null;
    }
  }

  DriverModel copyWith({bool? isAvailable, String? approvalStatus}) {
    return DriverModel(
      id: id,
      userId: userId,
      licenseNumber: licenseNumber,
      licenseExpiry: licenseExpiry,
      licenseDocUrl: licenseDocUrl,
      vehicleNumber: vehicleNumber,
      vehicleType: vehicleType,
      vehicleMake: vehicleMake,
      vehicleModel: vehicleModel,
      vehicleColor: vehicleColor,
      vehicleYear: vehicleYear,
      vehicleRcUrl: vehicleRcUrl,
      vehicleInsuranceUrl: vehicleInsuranceUrl,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      rejectionReason: rejectionReason,
      isAvailable: isAvailable ?? this.isAvailable,
      totalTrips: totalTrips,
      cancellationCount: cancellationCount,
      fullName: fullName,
      phone: phone,
      faceVerified: faceVerified,
      reliabilityScore: reliabilityScore,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
