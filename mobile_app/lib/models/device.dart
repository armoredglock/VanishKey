class PairedDevice {
  final String deviceId;
  final String deviceName;
  final String osType; // 'windows' or 'macos'
  final DateTime pairedAt;
  final bool isOnline;

  PairedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.osType,
    required this.pairedAt,
    this.isOnline = false,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String? ?? 'Unknown Laptop',
      osType: json['osType'] as String? ?? 'windows',
      pairedAt: json['pairedAt'] != null
          ? DateTime.tryParse(json['pairedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isOnline: json['isOnline'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'osType': osType,
    'pairedAt': pairedAt.toIso8601String(),
    'isOnline': isOnline,
  };
}
