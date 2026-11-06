import 'package:flutter/material.dart';

import '../models/vital_reading.dart';
import '../services/alert_rules.dart';
import '../services/vitals_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_header.dart';
import '../widgets/vital_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.service});

  final VitalsService service;

  VitalLevel _bpmLevel(int bpm) {
    if (bpm < AlertRules.bpmMin || bpm > AlertRules.bpmMax) {
      return VitalLevel.danger;
    }
    if (bpm > AlertRules.bpmAttention) return VitalLevel.warning;
    return VitalLevel.normal;
  }

  VitalLevel _spo2Level(int spo2) {
    if (spo2 < AlertRules.spo2Min) return VitalLevel.danger;
    if (spo2 < AlertRules.spo2Attention) return VitalLevel.warning;
    return VitalLevel.normal;
  }

  VitalLevel _tempLevel(double temp) {
    if (temp >= AlertRules.tempMax) return VitalLevel.danger;
    if (temp > AlertRules.tempAttention) return VitalLevel.warning;
    return VitalLevel.normal;
  }

  String _formatTimestamp(DateTime ts) {
    return '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}:${ts.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final VitalReading? reading = service.current;

    return ColoredBox(
      color: AppTheme.surface,
      child: Column(
        children: [
          GradientHeader(
            title: 'Monitoramento',
            subtitle: 'Monitoramento remoto de sinais vitais',
            trailing: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.monitor_heart, color: Colors.white),
            ),
          ),
          Expanded(
            child: reading == null
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -20),
                        child: _DeviceCard(
                          reading: reading,
                          connected: service.connected,
                          timeLabel: _formatTimestamp(reading.timestamp),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: VitalCard(
                              title: 'Frequência',
                              value: reading.isPpgValid ? '${reading.bpm}' : '--',
                              unit: 'BPM',
                              icon: Icons.favorite_rounded,
                              level: reading.isPpgValid
                                  ? _bpmLevel(reading.bpm)
                                  : VitalLevel.danger,
                              compact: true,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: VitalCard(
                              title: 'SpO₂',
                              value: reading.isPpgValid ? '${reading.spo2}' : '--',
                              unit: '%',
                              icon: Icons.air_rounded,
                              level: reading.isPpgValid
                                  ? _spo2Level(reading.spo2)
                                  : VitalLevel.danger,
                              compact: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      VitalCard(
                        title: 'Temperatura corporal',
                        value: reading.isTempValid
                            ? reading.temperature
                                .toStringAsFixed(1)
                                .replaceAll('.', ',')
                            : '--',
                        unit: '°C',
                        icon: Icons.thermostat_rounded,
                        level: reading.isTempValid
                            ? _tempLevel(reading.temperature)
                            : VitalLevel.danger,
                      ),
                      const SizedBox(height: 16),
                      _InfoBanner(
                        icon: service.source == VitalsSource.firebase
                            ? Icons.cloud_done_outlined
                            : Icons.sensors,
                        text: service.source == VitalsSource.firebase
                            ? (service.errorMessage ??
                                'Conectado ao Firebase — recebendo sinais do ESP32.')
                            : 'Modo simulação — configure o Firebase em lib/config/firebase_config.dart.',
                        isError: service.errorMessage != null &&
                            service.source == VitalsSource.firebase &&
                            !service.connected,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.reading,
    required this.connected,
    required this.timeLabel,
  });

  final VitalReading reading;
  final bool connected;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shadowColor: AppTheme.primary.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.memory, color: AppTheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        connected ? 'Dispositivo conectado' : 'Dispositivo offline',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                      Text(
                        reading.deviceId,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryDark,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  connected ? Icons.wifi : Icons.wifi_off,
                  color: connected ? AppTheme.success : Colors.grey,
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  reading.isValid
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  size: 18,
                  color: reading.isValid ? AppTheme.success : AppTheme.danger,
                ),
                const SizedBox(width: 8),
                Text(
                  reading.isValid ? 'Leitura válida' : 'Leitura inválida',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  timeLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.danger : AppTheme.accent;
    final fg = isError ? AppTheme.danger : AppTheme.primaryDark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: isError ? AppTheme.danger : AppTheme.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: fg,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
