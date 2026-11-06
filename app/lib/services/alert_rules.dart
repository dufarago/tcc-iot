import '../models/alert_item.dart';
import '../models/vital_reading.dart';

/// Limiares do TCC (cap. metodologia — alertas automáticos).
abstract final class AlertRules {
  // Limiares de alerta
  static const int spo2Min = 94;
  static const int bpmMin = 50;
  static const int bpmMax = 120;
  static const double tempMax = 37.8;

  // Faixas de atenção (cor amarela na tela Início, sem gerar alerta)
  static const int spo2Attention = 96;
  static const int bpmAttention = 100;
  static const double tempAttention = 37.2;

  static List<AlertItem> evaluate(VitalReading reading) {
    final alerts = <AlertItem>[];

    if (!reading.isPpgValid || !reading.isTempValid) {
      alerts.add(
        AlertItem(
          type: AlertType.invalidReading,
          message: _invalidMessage(reading),
          timestamp: reading.timestamp,
          valueLabel: 'Inválida',
        ),
      );
    }

    if (reading.isPpgValid) {
      if (reading.spo2 < spo2Min) {
        alerts.add(
          AlertItem(
            type: AlertType.spo2Low,
            message: 'Saturação abaixo de $spo2Min%.',
            timestamp: reading.timestamp,
            valueLabel: '${reading.spo2}%',
          ),
        );
      }

      if (reading.bpm > bpmMax) {
        alerts.add(
          AlertItem(
            type: AlertType.bpmHigh,
            message: 'Frequência acima do limite de $bpmMax BPM.',
            timestamp: reading.timestamp,
            valueLabel: '${reading.bpm} BPM',
          ),
        );
      } else if (reading.bpm < bpmMin) {
        alerts.add(
          AlertItem(
            type: AlertType.bpmLow,
            message: 'Frequência abaixo do limite de $bpmMin BPM.',
            timestamp: reading.timestamp,
            valueLabel: '${reading.bpm} BPM',
          ),
        );
      }
    }

    if (reading.isTempValid && reading.temperature >= tempMax) {
      alerts.add(
        AlertItem(
          type: AlertType.temperatureHigh,
          message: 'Temperatura igual ou acima de ${tempMax.toStringAsFixed(1).replaceAll('.', ',')} °C.',
          timestamp: reading.timestamp,
          valueLabel: '${reading.temperature.toStringAsFixed(1).replaceAll('.', ',')} °C',
        ),
      );
    }

    return alerts;
  }

  static String _invalidMessage(VitalReading reading) {
    if (!reading.isPpgValid && !reading.isTempValid) {
      return 'MAX30102 e DS18B20 sem leitura válida.';
    }
    if (!reading.isPpgValid) {
      return 'MAX30102 sem contato adequado ou leitura inconsistente.';
    }
    return 'DS18B20 desconectado ou fora da faixa de 30 a 43 °C.';
  }
}
