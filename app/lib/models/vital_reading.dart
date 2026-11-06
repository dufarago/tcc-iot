class VitalReading {
  const VitalReading({
    required this.deviceId,
    required this.timestamp,
    required this.bpm,
    required this.spo2,
    required this.temperature,
    required this.status,
    this.ppgStatus,
    this.tempStatus,
  });

  final String deviceId;
  final DateTime timestamp;
  final int bpm;
  final int spo2;
  final double temperature;

  /// Validade geral da leitura (MAX30102 e DS18B20 válidos ao mesmo tempo).
  final String status;

  /// Validade de cada sensor. Registros antigos, sem esses campos,
  /// usam o valor de [status].
  final String? ppgStatus;
  final String? tempStatus;

  bool get isValid => status == 'valid';
  bool get isPpgValid => (ppgStatus ?? status) == 'valid';
  bool get isTempValid => (tempStatus ?? status) == 'valid';

  factory VitalReading.fromMap(Map<dynamic, dynamic> map, {String? fallbackDeviceId}) {
    final rawTs = map['timestamp'];
    DateTime ts;
    if (rawTs is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(rawTs);
    } else if (rawTs is String && rawTs.isNotEmpty) {
      // O ESP32 envia o horário em UTC (sufixo Z); a tela usa o horário local.
      ts = DateTime.tryParse(rawTs)?.toLocal() ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }

    return VitalReading(
      deviceId: (map['deviceId'] ?? fallbackDeviceId ?? 'esp32_monitor_01').toString(),
      timestamp: ts,
      bpm: _asInt(map['bpm']),
      spo2: _asInt(map['spo2']),
      temperature: _asDouble(map['temperature']),
      status: (map['status'] ?? 'valid').toString(),
      ppgStatus: map['ppgStatus']?.toString(),
      tempStatus: map['tempStatus']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'deviceId': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'bpm': bpm,
        'spo2': spo2,
        'temperature': temperature,
        'status': status,
        'ppgStatus': ppgStatus ?? status,
        'tempStatus': tempStatus ?? status,
      };

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.')) ?? 0;
    return 0;
  }
}
