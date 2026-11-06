import 'package:flutter/material.dart';

import 'config/firebase_config.dart';
import 'screens/home_shell.dart';
import 'services/vitals_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final useFirebase = FirebaseConfig.isReady;
  if (!useFirebase) {
    debugPrint(
      'FirebaseConfig incompleto — modo simulação. '
      'Edite lib/config/firebase_config.dart',
    );
  }

  runApp(MonitoramentoIoTApp(service: VitalsService(useFirebase: useFirebase)));
}

class MonitoramentoIoTApp extends StatefulWidget {
  const MonitoramentoIoTApp({super.key, required this.service});

  final VitalsService service;

  @override
  State<MonitoramentoIoTApp> createState() => _MonitoramentoIoTAppState();
}

class _MonitoramentoIoTAppState extends State<MonitoramentoIoTApp> {
  @override
  void dispose() {
    widget.service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Monitoramento IoT',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeShell(service: widget.service),
    );
  }
}
