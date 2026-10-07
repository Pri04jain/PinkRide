import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

/// DriverQueueItem — a driver awaiting admin approval.
class DriverQueueItem {
  final String id;
  final String userId;
  final String fullName;
  final String phone;
  final String licenseNumber;
  final String vehicleNumber;
  final String vehicleType;
  final String vehicleMake;
  final String vehicleModel;
  final String approvalStatus;
  final String createdAt;

  const DriverQueueItem({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.licenseNumber,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.approvalStatus,
    required this.createdAt,
  });

  factory DriverQueueItem.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    return DriverQueueItem(
      id:             json['id'] as String? ?? '',
      userId:         json['user_id'] as String? ?? '',
      fullName:       user['full_name'] as String? ?? 'Unknown',
      phone:          user['phone'] as String? ?? '',
      licenseNumber:  json['license_number'] as String? ?? '',
      vehicleNumber:  json['vehicle_number'] as String? ?? '',
      vehicleType:    json['vehicle_type'] as String? ?? '',
      vehicleMake:    json['vehicle_make'] as String? ?? '',
      vehicleModel:   json['vehicle_model'] as String? ?? '',
      approvalStatus: json['approval_status'] as String? ?? 'pending',
      createdAt:      json['created_at'] as String? ?? '',
    );
  }
}

/// AdminService — API calls for admin driver queue management.
class AdminService {
  final ApiClient _api;
  AdminService(this._api);

  Future<List<DriverQueueItem>> getPendingDrivers() async {
    final data = await _api.get(ApiEndpoints.adminDriverQueue);
    final list = data['drivers'] as List<dynamic>? ?? [];
    return list
        .cast<Map<String, dynamic>>()
        .map(DriverQueueItem.fromJson)
        .toList();
  }

  Future<void> approveDriver(String driverId) async {
    await _api.post(ApiEndpoints.adminApproveDriver(driverId));
  }

  Future<void> rejectDriver(String driverId,
      {required String reason}) async {
    await _api.post(
      ApiEndpoints.adminRejectDriver(driverId),
      data: {'reason': reason},
    );
  }
}

final adminServiceProvider = Provider<AdminService>(
    (ref) => AdminService(ref.watch(apiClientProvider)));
