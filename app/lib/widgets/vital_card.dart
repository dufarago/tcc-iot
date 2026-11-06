import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum VitalLevel { normal, warning, danger }

class VitalCard extends StatelessWidget {
  const VitalCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.level,
    this.compact = false,
  });

  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final VitalLevel level;
  final bool compact;

  Color get _accent {
    switch (level) {
      case VitalLevel.normal:
        return AppTheme.success;
      case VitalLevel.warning:
        return AppTheme.warning;
      case VitalLevel.danger:
        return AppTheme.danger;
    }
  }

  String get _statusLabel {
    switch (level) {
      case VitalLevel.normal:
        return 'Normal';
      case VitalLevel.warning:
        return 'Atenção';
      case VitalLevel.danger:
        return 'Alerta';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 14 : 18),
        child: compact
            ? _buildCompact(context)
            : _buildExpanded(context),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: _accent, size: 22),
            const Spacer(),
            _StatusPill(label: _statusLabel, color: _accent),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
              ),
        ),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryDark,
                    ),
              ),
              TextSpan(
                text: ' $unit',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExpanded(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_accent.withValues(alpha: 0.2), _accent.withValues(alpha: 0.05)],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: _accent, size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Colors.grey.shade700,
                          ),
                    ),
                  ),
                  _StatusPill(label: _statusLabel, color: _accent),
                ],
              ),
              const SizedBox(height: 6),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: value,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryDark,
                            height: 1.1,
                          ),
                    ),
                    TextSpan(
                      text: ' $unit',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
