import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Em telas largas (Chrome/PC), exibe o app dentro de uma moldura de celular.
/// Em dispositivo real ou emulador, usa a tela inteira.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  static const double phoneWidth = 390;
  static const double phoneHeight = 844;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final showFrame = size.width > 520;

    if (!showFrame) {
      return child;
    }

    return ColoredBox(
      color: const Color(0xFF0F1419),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const bezel = 12.0;
            const labelHeight = 52.0;
            final frameWidth = phoneWidth + bezel * 2;
            final frameHeight = phoneHeight + bezel * 2 + labelHeight;

            final scale = math.min(
              1.0,
              math.min(
                constraints.maxWidth / (frameWidth + 24),
                constraints.maxHeight / (frameHeight + 16),
              ),
            );

            return Center(
              child: Transform.scale(
                scale: scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pré-visualização — Monitoramento IoT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: frameWidth,
                      height: phoneHeight + bezel * 2,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(48),
                        gradient: LinearGradient(
                          colors: [
                            Colors.grey.shade700,
                            Colors.grey.shade900,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 48,
                            offset: const Offset(0, 20),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(bezel),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(color: Colors.black, width: 2),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: const Size(phoneWidth, phoneHeight),
                            padding: const EdgeInsets.only(top: 44, bottom: 8),
                          ),
                          child: SizedBox(
                            width: phoneWidth,
                            height: phoneHeight,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
