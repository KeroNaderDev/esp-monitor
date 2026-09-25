class DeviceState {
  final String deviceId;
  final double? temp;
  final double? hum;
  final int lastSeen;
  final bool online;
  final int backfilled;

  DeviceState({
    required this.deviceId,
    required this.temp,
    required this.hum,
    required this.lastSeen,
    required this.online,
    this.backfilled = 0,
  });

  factory DeviceState.fromJson(Map<String, dynamic> json) {
    return DeviceState(
      deviceId: json['device_id'] ?? 'unknown',
      temp: json['temp'] != null ? (json['temp'] as num).toDouble() : null,
      hum: json['hum'] != null ? (json['hum'] as num).toDouble() : null,
      lastSeen: json['lastSeen'] ?? 0,
      online: json['online'] ?? false,
      backfilled: json['backfilled'] ?? 0,
    );
  }

  DeviceState copyWith({
    String? deviceId,
    double? temp,
    double? hum,
    int? lastSeen,
    bool? online,
    int? backfilled,
  }) {
    return DeviceState(
      deviceId: deviceId ?? this.deviceId,
      temp: temp ?? this.temp,
      hum: hum ?? this.hum,
      lastSeen: lastSeen ?? this.lastSeen,
      online: online ?? this.online,
      backfilled: backfilled ?? this.backfilled,
    );
  }

  bool get isTempOutOfRange => temp != null && (temp! > 32 || temp! < 28);
  bool get isHumOutOfRange => hum != null && (hum! > 70 || hum! < 60);
}
