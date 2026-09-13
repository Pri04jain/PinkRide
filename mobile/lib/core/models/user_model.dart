

enum UserRole { passenger, driver, admin, unknown }

class UserModel {
  final String id;
  final String phone;
  final UserRole role;
  final String? fullName;
  final String? gender;
  final String? profilePhotoUrl;
  final bool faceVerified;
  final bool isPhoneVerified;
  final double reliabilityScore;
  final double walletBalance;
  final String city;

  const UserModel({
    required this.id,
    required this.phone,
    required this.role,
    this.fullName,
    this.gender,
    this.profilePhotoUrl,
    this.faceVerified = false,
    this.isPhoneVerified = false,
    this.reliabilityScore = 5.0,
    this.walletBalance = 0.0,
    this.city = 'Jaipur',
  });

  // ── fromJson ───────────────────────────────────────────────────────────────
  // Converts the backend JSON response into a UserModel.
  // Called once after login — result is stored in AuthStateNotifier.

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      role: _parseRole(json['role'] as String?),
      fullName: json['full_name'] as String?,
      gender: json['gender'] as String?,
      profilePhotoUrl: json['profile_photo_url'] as String?,
      faceVerified: json['face_verified'] as bool? ?? false,
      isPhoneVerified: json['is_phone_verified'] as bool? ?? false,
      reliabilityScore:
          (json['reliability_score'] as num?)?.toDouble() ?? 5.0,
      walletBalance:
          (json['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      city: json['city'] as String? ?? 'Jaipur',
    );
  }


  UserModel copyWith({
    String? fullName,
    String? profilePhotoUrl,
    bool? faceVerified,
    double? walletBalance,
    double? reliabilityScore,
  }) {
    return UserModel(
      id: id,
      phone: phone,
      role: role,
      fullName: fullName ?? this.fullName,
      gender: gender,
      profilePhotoUrl: profilePhotoUrl ?? this.profilePhotoUrl,
      faceVerified: faceVerified ?? this.faceVerified,
      isPhoneVerified: isPhoneVerified,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      walletBalance: walletBalance ?? this.walletBalance,
      city: city,
    );
  }

  // ── Convenience getters ───────────────────────────────────────────────────

  bool get isPassenger => role == UserRole.passenger;
  bool get isDriver => role == UserRole.driver;
  bool get isAdmin => role == UserRole.admin;

  /// Display name — full name if set, otherwise formatted phone number.
  String get displayName {
    if (fullName?.isNotEmpty == true) return fullName!;
    if (phone.length >= 10) {
      return '+91 ${phone.substring(phone.length - 10)}';
    }
    return phone.isNotEmpty ? phone : 'Passenger';
  }

  static UserRole _parseRole(String? raw) {
    switch (raw) {
      case 'passenger':
        return UserRole.passenger;
      case 'driver':
        return UserRole.driver;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.unknown;
    }
  }

  @override
  String toString() => 'UserModel(id: $id, role: ${role.name}, name: $fullName)';
}
