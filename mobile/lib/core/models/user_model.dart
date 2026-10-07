/// UserModel — the logged-in user's data.
///
/// Populated from the backend's /auth/login response and stored in AuthState.
/// All fields map directly to the `users` table in Supabase.

enum UserRole {
  passenger,
  driver,
  admin,
  unknown; // fallback for unrecognised values

  static UserRole fromString(String? value) {
    switch (value) {
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

  String get value {
    switch (this) {
      case UserRole.passenger:
        return 'passenger';
      case UserRole.driver:
        return 'driver';
      case UserRole.admin:
        return 'admin';
      case UserRole.unknown:
        return 'unknown';
    }
  }
}

class UserModel {
  final String id;
  final String phone;
  final String? countryCode;
  final String? email;
  final UserRole role;
  final String? fullName;
  final String? gender;
  final bool faceVerified;
  final bool isActive;
  final String? city;
  final String? profilePhotoUrl;
  final double? reliabilityScore;
  final double? walletBalance;

  const UserModel({
    required this.id,
    required this.phone,
    this.countryCode,
    this.email,
    required this.role,
    this.fullName,
    this.gender,
    this.faceVerified = false,
    this.isActive = true,
    this.city,
    this.profilePhotoUrl,
    this.reliabilityScore,
    this.walletBalance,
  });

  // ── Convenience getters ───────────────────────────────────────────────────
  bool get isPassenger => role == UserRole.passenger;
  bool get isDriver    => role == UserRole.driver;
  bool get isAdmin     => role == UserRole.admin;

  /// Returns fullName if set, otherwise phone number as fallback.
  String get displayName =>
      (fullName != null && fullName!.trim().isNotEmpty) ? fullName! : phone;

  // ── JSON deserialization ──────────────────────────────────────────────────
  // Maps the backend snake_case keys to Dart camelCase.
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id:               json['id']               as String? ?? '',
      phone:            json['phone']             as String? ?? '',
      countryCode:      json['country_code']      as String?,
      email:            json['email']             as String?,
      role:             UserRole.fromString(json['role'] as String?),
      fullName:         json['full_name']          as String?,
      gender:           json['gender']             as String?,
      faceVerified:     json['face_verified']      as bool? ?? false,
      isActive:         json['is_active']          as bool? ?? true,
      city:             json['city']               as String?,
      profilePhotoUrl:  json['profile_photo_url']  as String?,
      reliabilityScore: (json['reliability_score'] as num?)?.toDouble(),
      walletBalance:    (json['wallet_balance']    as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'country_code': countryCode,
        'email': email,
        'role': role.value,
        'full_name': fullName,
        'gender': gender,
        'face_verified': faceVerified,
        'is_active': isActive,
        'city': city,
        'profile_photo_url': profilePhotoUrl,
        'reliability_score': reliabilityScore,
        'wallet_balance': walletBalance,
      };

  UserModel copyWith({
    String? id,
    String? phone,
    String? countryCode,
    String? email,
    UserRole? role,
    String? fullName,
    String? gender,
    bool? faceVerified,
    bool? isActive,
    String? city,
    String? profilePhotoUrl,
    double? reliabilityScore,
    double? walletBalance,
  }) {
    return UserModel(
      id:               id               ?? this.id,
      phone:            phone            ?? this.phone,
      countryCode:      countryCode      ?? this.countryCode,
      email:            email            ?? this.email,
      role:             role             ?? this.role,
      fullName:         fullName         ?? this.fullName,
      gender:           gender           ?? this.gender,
      faceVerified:     faceVerified     ?? this.faceVerified,
      isActive:         isActive         ?? this.isActive,
      city:             city             ?? this.city,
      profilePhotoUrl:  profilePhotoUrl  ?? this.profilePhotoUrl,
      reliabilityScore: reliabilityScore ?? this.reliabilityScore,
      walletBalance:    walletBalance    ?? this.walletBalance,
    );
  }

  @override
  String toString() =>
      'UserModel(id: $id, phone: $phone, role: ${role.value}, name: $fullName)';
}
