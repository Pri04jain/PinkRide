import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

// ── Data models ───────────────────────────────────────────────────────────────

class DriverQueueItem {
  final String id;
  final String userId;
  final String fullName;
  final String phone;
  final String gender;
  final bool faceVerified;
  final String licenseNumber;
  final String vehicleNumber;
  final String vehicleType;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleColor;
  final int vehicleYear;
  final String approvalStatus;
  final String? rejectionReason;
  final String licenseDocUrl;
  final String vehicleRcUrl;
  final String? vehicleInsuranceUrl;
  final DateTime createdAt;

  const DriverQueueItem({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.gender,
    required this.faceVerified,
    required this.licenseNumber,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleColor,
    required this.vehicleYear,
    required this.approvalStatus,
    this.rejectionReason,
    required this.licenseDocUrl,
    required this.vehicleRcUrl,
    this.vehicleInsuranceUrl,
    required this.createdAt,
  });

  factory DriverQueueItem.fromJson(Map<String, dynamic> json) {
    final user = json['users'] as Map<String, dynamic>? ?? {};
    return DriverQueueItem(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      fullName: user['full_name'] as String? ?? 'Unknown',
      phone: user['phone'] as String? ?? '',
      gender: user['gender'] as String? ?? '',
      faceVerified: user['face_verified'] as bool? ?? false,
      licenseNumber: json['license_number'] as String? ?? '',
      vehicleNumber: json['vehicle_number'] as String? ?? '',
      vehicleType: json['vehicle_type'] as String? ?? '',
      vehicleMake: json['vehicle_make'] as String? ?? '',
      vehicleModel: json['vehicle_model'] as String? ?? '',
      vehicleColor: json['vehicle_color'] as String? ?? '',
      vehicleYear: (json['vehicle_year'] as num?)?.toInt() ?? 0,
      approvalStatus: json['approval_status'] as String? ?? 'pending',
      rejectionReason: json['rejection_reason'] as String?,
      licenseDocUrl: json['license_doc_url'] as String? ?? '',
      vehicleRcUrl: json['vehicle_rc_url'] as String? ?? '',
      vehicleInsuranceUrl: json['vehicle_insurance_url'] as String?,
      createdAt: DateTime.tryParse(
              json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  String get vehicleDisplay => '$vehicleColor $vehicleMake $vehicleModel ($vehicleYear)';

  String get statusLabel {
    switch (approvalStatus) {
      case 'under_review': return 'Under Review';
      case 'approved':     return 'Approved';
      case 'rejected':     return 'Rejected';
      case 'suspended':    return 'Suspended';
      default:             return 'Pending';
    }
  }
}

class AdminStats {
  final int pending;
  final int underReview;
  final int approved;
  final int onlineNow;
  final int totalPassengers;
  final int newThisWeek;

  const AdminStats({
    required this.pending,
    required this.underReview,
    required this.approved,
    required this.onlineNow,
    required this.totalPassengers,
    required this.newThisWeek,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) {
    final drivers = json['drivers'] as Map<String, dynamic>? ?? {};
    final users   = json['users']   as Map<String, dynamic>? ?? {};
    return AdminStats(
      pending:        (drivers['pending'] as num?)?.toInt() ?? 0,
      underReview:    (drivers['under_review'] as num?)?.toInt() ?? 0,
      approved:       (drivers['approved'] as num?)?.toInt() ?? 0,
      onlineNow:      (drivers['online_now'] as num?)?.toInt() ?? 0,
      totalPassengers:(users['passengers'] as num?)?.toInt() ?? 0,
      newThisWeek:    (users['new_this_week'] as num?)?.toInt() ?? 0,
    );
  }
}

// ── AdminService ──────────────────────────────────────────────────────────────

class AdminService {
  final ApiClient _api;
  const AdminService(this._api);

  Future<List<DriverQueueItem>> getQueue({
    String status = 'under_review',
    int page = 1,
  }) async {
    final data = await _api.get(
      '/drivers/admin/queue',
      queryParams: {'status': status, 'page': page},
    );
    final list = data['drivers'] as List<dynamic>? ?? [];
    return list
        .map((e) => DriverQueueItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AdminStats> getStats() async {
    final data = await _api.get('/drivers/admin/stats');
    return AdminStats.fromJson(data);
  }

  Future<void> approveDriver(String driverId) async {
    await _api.post('/drivers/admin/$driverId/approve');
  }

  Future<void> rejectDriver(String driverId, String reason) async {
    await _api.post(
      '/drivers/admin/$driverId/reject',
      data: {'reason': reason},
    );
  }

  Future<void> suspendDriver(String driverId, String reason) async {
    await _api.post(
      '/drivers/admin/$driverId/suspend',
      data: {'reason': reason},
    );
  }
}

final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService(ref.watch(apiClientProvider));
});
