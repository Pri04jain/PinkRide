import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/constants/api_endpoints.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String? relation;
  final bool isPrimary;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation,
    this.isPrimary = false,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      relation: json['relation'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
    );
  }
}

// ── SafetyService ─────────────────────────────────────────────────────────────

class SafetyService {
  final ApiClient _api;
  const SafetyService(this._api);

  Future<List<EmergencyContact>> getContacts() async {
    final data = await _api.get(ApiEndpoints.emergencyContacts);
    final list = data['contacts'] as List<dynamic>? ?? [];
    return list
        .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<EmergencyContact> addContact({
    required String name,
    required String phone,
    String? relation,
    bool isPrimary = false,
  }) async {
    final data = await _api.post(
      ApiEndpoints.emergencyContacts,
      data: {
        'name': name,
        'phone': phone,
        if (relation != null) 'relation': relation,
        'isPrimary': isPrimary,
      },
    );
    return EmergencyContact.fromJson(
        data['contact'] as Map<String, dynamic>? ?? data);
  }

  Future<void> deleteContact(String contactId) async {
    await _api.delete('${ApiEndpoints.emergencyContacts}/$contactId');
  }
}

final safetyServiceProvider = Provider<SafetyService>((ref) {
  return SafetyService(ref.watch(apiClientProvider));
});
