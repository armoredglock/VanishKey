class EphemeralCredential {
  final String username;
  final String password;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int durationSeconds;

  EphemeralCredential({
    required this.username,
    required this.password,
    required this.createdAt,
    required this.expiresAt,
    required this.durationSeconds,
  });

  factory EphemeralCredential.fromJson(Map<String, dynamic> json) {
    return EphemeralCredential(
      username: json['username'] as String,
      password: json['password'] as String,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString()) ?? DateTime.now().add(const Duration(minutes: 3))
          : DateTime.now().add(const Duration(minutes: 3)),
      durationSeconds: json['duration_seconds'] as int? ?? 180,
    );
  }

  int get remainingSeconds {
    final diff = expiresAt.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  bool get isExpired => remainingSeconds <= 0;
}
