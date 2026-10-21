class UserModel {
  final String id;
  final String username;
  final String email;
  final String role;
  final String fullName;
  final int coins;
  final int tickets;
  final double accuracy;
  final String vipTier;
  final String? vipExpiresAt;
  final bool isVerified;
  final String? createdAt;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.role = 'user',
    this.fullName = '',
    this.coins = 200,
    this.tickets = 0,
    this.accuracy = 0.0,
    this.vipTier = 'none',
    this.vipExpiresAt,
    required this.isVerified,
    this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      fullName: json['full_name'] as String? ?? '',
      coins: (json['coins'] as num?)?.toInt() ?? 200,
      tickets: (json['tickets'] as num?)?.toInt() ?? 0,
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      vipTier: json['vip_tier'] as String? ?? 'none',
      vipExpiresAt: json['vip_expires_at'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'full_name': fullName,
      'coins': coins,
      'tickets': tickets,
      'accuracy': accuracy,
      'vip_tier': vipTier,
      'vip_expires_at': vipExpiresAt,
      'is_verified': isVerified,
      'created_at': createdAt,
    };
  }

  bool get hasPredictionAccess {
    if (role.toLowerCase() == 'admin') return true;
    final expiry = DateTime.tryParse(vipExpiresAt ?? '');
    return vipTier.toLowerCase() != 'none' &&
        expiry != null &&
        expiry.isAfter(DateTime.now());
  }

  UserModel copyWith({int? coins, int? tickets}) {
    return UserModel(
      id: id,
      username: username,
      email: email,
      role: role,
      fullName: fullName,
      coins: coins ?? this.coins,
      tickets: tickets ?? this.tickets,
      accuracy: accuracy,
      vipTier: vipTier,
      vipExpiresAt: vipExpiresAt,
      isVerified: isVerified,
      createdAt: createdAt,
    );
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) {
    return AuthTokens(
      accessToken: json['access_token'] as String? ?? '',
      refreshToken: json['refresh_token'] as String? ?? '',
      expiresIn: json['expires_in'] as int? ?? 900,
    );
  }
}
