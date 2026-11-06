import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:monitoramento_iot/main.dart';
import 'package:monitoramento_iot/services/vitals_service.dart';

void main() {
  testWidgets('App abre na tela Início', (tester) async {
    final service = VitalsService(useFirebase: false);

    await tester.pumpWidget(MonitoramentoIoTApp(service: service));
    await tester.pump();

    expect(find.text('Monitoramento'), findsOneWidget);
    expect(find.text('Início'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
