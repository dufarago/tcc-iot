import 'package:flutter/material.dart';

enum AlertType {
  spo2Low,
  bpmHigh,
  bpmLow,
  temperatureHigh,
  noSignal,
  invalidReading,
}

class AlertItem {
  const AlertItem({
    required this.type,
    required this.message,
    required this.timestamp,
    required this.valueLabel,
  });

  final AlertType type;
  final String message;
  final DateTime timestamp;
  final String valueLabel;

  String get title {
    switch (type) {
      case AlertType.spo2Low:
        return 'Oxigenação baixa';
      case AlertType.bpmHigh:
        return 'Frequência cardíaca elevada';
      case AlertType.bpmLow:
        return 'Frequência cardíaca baixa';
      case AlertType.temperatureHigh:
        return 'Temperatura elevada';
      case AlertType.noSignal:
        return 'Sem leitura do dispositivo';
      case AlertType.invalidReading:
        return 'Leitura inválida';
    }
  }

  IconData get icon {
    switch (type) {
      case AlertType.spo2Low:
        return Icons.air;
      case AlertType.bpmHigh:
      case AlertType.bpmLow:
        return Icons.favorite;
      case AlertType.temperatureHigh:
        return Icons.thermostat;
      case AlertType.noSignal:
        return Icons.wifi_off;
      case AlertType.invalidReading:
        return Icons.warning_amber;
    }
  }
}
