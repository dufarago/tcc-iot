import 'package:flutter/material.dart';

import '../models/vital_reading.dart';
import '../services/vitals_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_header.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.service});

  final VitalsService service;

  String _formatTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final readings = service.history;

    return ColoredBox(
      color: AppTheme.surface,
      child: Column(
        children: [
          GradientHeader(
            title: 'Histórico',
            subtitle: '${readings.length} leituras recentes',
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: readings.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final VitalReading r = readings[index];
                final bool valid = r.isValid;

                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: (valid ? AppTheme.success : AppTheme.danger)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        valid ? Icons.favorite_rounded : Icons.block,
                        color: valid ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                    title: Text(
                      _formatTime(r.timestamp),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: valid
                          ? Text(
                              'BPM ${r.bpm}  ·  SpO₂ ${r.spo2}%  ·  ${r.temperature.toStringAsFixed(1).replaceAll('.', ',')} °C',
                            )
                          : Text(
                              '${r.isPpgValid ? 'BPM ${r.bpm}  ·  SpO₂ ${r.spo2}%' : 'BPM --  ·  SpO₂ --'}  ·  '
                              '${r.isTempValid ? '${r.temperature.toStringAsFixed(1).replaceAll('.', ',')} °C' : '-- °C'}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (valid ? AppTheme.success : AppTheme.danger)
                            .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        valid ? 'OK' : 'Inválida',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: valid ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
