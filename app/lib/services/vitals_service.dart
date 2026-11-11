import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/firebase_config.dart';
import '../models/alert_item.dart';
import '../models/vital_reading.dart';
import 'alert_rules.dart';

enum VitalsSource { firebase, simulation }

/// Lê sinais do Firebase Realtime Database via REST (compatível com Chrome).
class VitalsService extends ChangeNotifier {
  VitalsService({required this.useFirebase}) {
    if (useFirebase) {
      source = VitalsSource.firebase;
      connected = false;
      errorMessage = 'Conectando ao Firebase...';
      _pollFirebase();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _pollFirebase());
    } else {
      source = VitalsSource.simulation;
      connected = true;
      _seedHistory();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tickMock());
    }
  }

  final bool useFirebase;

  VitalsSource source = VitalsSource.simulation;
  String? errorMessage;

  VitalReading? current;
  final List<VitalReading> history = [];
  final List<AlertItem> alerts = [];
  bool connected = false;

  final _random = Random();
  final _client = http.Client();
  Timer? _timer;
  bool _polling = false;

  /// Tempo máximo sem leitura válida nova antes do alerta de ausência de sinal.
  static const Duration noSignalTimeout = Duration(seconds: 30);

  final DateTime _startedAt = DateTime.now();
  DateTime? _lastValidAt; // horário do app em que chegou a última leitura válida
  bool _noSignalActive = false;
  final List<AlertItem> _signalAlerts = [];
  // Alertas gerados pelas leituras do nó latest. São guardados à parte porque
  // o histórico é relido a cada consulta e não contém valores inseridos só no
  // latest (por exemplo, nos testes de alerta feitos pelo Console do Firebase).
  final List<AlertItem> _readingAlerts = [];

  Uri get _latestUri {
    final base = FirebaseConfig.databaseURL.replaceAll(RegExp(r'/$'), '');
    return Uri.parse('$base/${FirebaseConfig.latestPath}.json');
  }

  Uri get _historyUri {
    final base = FirebaseConfig.databaseURL.replaceAll(RegExp(r'/$'), '');
    return Uri.parse(
      '$base/${FirebaseConfig.historyPath}.json?orderBy="\$key"&limitToLast=40',
    );
  }

  Future<void> _pollFirebase() async {
    if (_polling) return;
    _polling = true;
    try {
      final latestRes = await _client.get(_latestUri).timeout(const Duration(seconds: 8));
      if (latestRes.statusCode != 200) {
        connected = false;
        errorMessage =
            'Firebase HTTP ${latestRes.statusCode}. Confira as regras do banco.';
        notifyListeners();
        return;
      }

      final latestBody = latestRes.body;
      if (latestBody == 'null' || latestBody.isEmpty) {
        connected = false;
        errorMessage =
            'Aguardando dados... Crie o nó devices/${FirebaseConfig.deviceId}/latest no Console.';
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(latestBody);
      if (decoded is! Map) {
        connected = false;
        errorMessage = 'Formato inválido em latest.';
        notifyListeners();
        return;
      }

      final reading = VitalReading.fromMap(
        Map<dynamic, dynamic>.from(decoded),
        fallbackDeviceId: FirebaseConfig.deviceId,
      );
      _applyReading(reading);
      connected = true;
      errorMessage = null;

      // Histórico (opcional — se index/rules falharem, ignora)
      try {
        final histRes =
            await _client.get(_historyUri).timeout(const Duration(seconds: 8));
        if (histRes.statusCode == 200 && histRes.body != 'null') {
          final histDecoded = jsonDecode(histRes.body);
          if (histDecoded is Map) {
            final items = <VitalReading>[];
            histDecoded.forEach((_, raw) {
              if (raw is Map) {
                items.add(
                  VitalReading.fromMap(
                    Map<dynamic, dynamic>.from(raw),
                    fallbackDeviceId: FirebaseConfig.deviceId,
                  ),
                );
              }
            });
            items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            history
              ..clear()
              ..addAll(items);
            _rebuildAlertsFromHistory();
          }
        }
      } catch (_) {
        // histórico opcional
      }

      notifyListeners();
    } catch (e) {
      connected = false;
      errorMessage = 'Erro ao ler Firebase: $e';
      notifyListeners();
    } finally {
      _polling = false;
      _checkNoSignal();
    }
  }

  /// Gera um alerta quando nenhuma leitura válida nova chega por mais de
  /// [noSignalTimeout] (ESP32 desligado, sem rede ou sensor sem contato).
  void _checkNoSignal() {
    final reference = _lastValidAt ?? _startedAt;
    final silent = DateTime.now().difference(reference);
    if (silent <= noSignalTimeout) {
      _noSignalActive = false;
      return;
    }
    if (_noSignalActive) return;

    _noSignalActive = true;
    final alert = AlertItem(
      type: AlertType.noSignal,
      message:
          'Nenhuma leitura válida recebida há mais de ${noSignalTimeout.inSeconds} s.',
      timestamp: DateTime.now(),
      valueLabel: '> ${noSignalTimeout.inSeconds} s',
    );
    _signalAlerts.insert(0, alert);
    if (_signalAlerts.length > 10) _signalAlerts.removeLast();
    alerts.insert(0, alert);
    if (alerts.length > 40) {
      alerts.removeRange(40, alerts.length);
    }
    notifyListeners();
  }

  void _rebuildAlertsFromHistory() {
    alerts.clear();
    for (final reading in history.reversed) {
      alerts.insertAll(0, AlertRules.evaluate(reading));
    }
    for (final alerta in _readingAlerts) {
      final repetido = alerts.any((outro) =>
          outro.type == alerta.type &&
          outro.timestamp == alerta.timestamp &&
          outro.valueLabel == alerta.valueLabel);
      if (!repetido) alerts.add(alerta);
    }
    alerts.addAll(_signalAlerts);
    alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (alerts.length > 40) {
      alerts.removeRange(40, alerts.length);
    }
  }

  void _applyReading(VitalReading reading) {
    final isDuplicate = current != null &&
        current!.timestamp == reading.timestamp &&
        current!.bpm == reading.bpm &&
        current!.spo2 == reading.spo2 &&
        current!.temperature == reading.temperature;

    current = reading;

    if (!isDuplicate && reading.isValid) {
      _lastValidAt = DateTime.now();
      _noSignalActive = false;
    }

    // Latência: diferença entre o horário da medição (NTP, no ESP32) e a
    // chegada da leitura ao app. Aparece no console do `flutter run`.
    if (!isDuplicate && source == VitalsSource.firebase) {
      final latency = DateTime.now().difference(reading.timestamp);
      debugPrint('Latencia da leitura: ${latency.inMilliseconds} ms');
    }

    if (!isDuplicate) {
      // Se ainda não veio histórico do Firebase, mantém lista local
      if (history.isEmpty ||
          history.first.timestamp != reading.timestamp ||
          history.first.bpm != reading.bpm) {
        history.insert(0, reading);
        if (history.length > 40) history.removeLast();
      }

      final newAlerts = AlertRules.evaluate(reading);
      if (newAlerts.isNotEmpty) {
        alerts.insertAll(0, newAlerts);
        if (alerts.length > 40) {
          alerts.removeRange(40, alerts.length);
        }
        _readingAlerts.insertAll(0, newAlerts);
        if (_readingAlerts.length > 20) {
          _readingAlerts.removeRange(20, _readingAlerts.length);
        }
      }
    }
  }

  void _seedHistory() {
    final now = DateTime.now();
    final seeds = <VitalReading>[
      VitalReading(
        deviceId: FirebaseConfig.deviceId,
        timestamp: now.subtract(const Duration(minutes: 5)),
        bpm: 78,
        spo2: 97,
        temperature: 36.4,
        status: 'valid',
      ),
      VitalReading(
        deviceId: FirebaseConfig.deviceId,
        timestamp: now.subtract(const Duration(minutes: 3)),
        bpm: 124,
        spo2: 92,
        temperature: 36.5,
        status: 'valid',
      ),
      VitalReading(
        deviceId: FirebaseConfig.deviceId,
        timestamp: now.subtract(const Duration(minutes: 1)),
        bpm: 72,
        spo2: 98,
        temperature: 38.1,
        status: 'valid',
      ),
    ];

    for (final reading in seeds) {
      history.insert(0, reading);
      alerts.insertAll(0, AlertRules.evaluate(reading));
    }
    current = seeds.last;
  }

  void _tickMock() {
    final invalid = _random.nextDouble() < 0.1;
    late VitalReading reading;
    if (invalid) {
      reading = VitalReading(
        deviceId: FirebaseConfig.deviceId,
        timestamp: DateTime.now(),
        bpm: 0,
        spo2: 0,
        temperature: 0,
        status: 'invalid',
      );
    } else {
      var bpm = 70 + _random.nextInt(20);
      var spo2 = 96 + _random.nextInt(4);
      var temp = 36.2 + _random.nextDouble() * 0.8;
      final roll = _random.nextDouble();
      if (roll < 0.08) bpm = 45 + _random.nextInt(8);
      if (roll > 0.92) bpm = 121 + _random.nextInt(15);
      if (_random.nextDouble() < 0.08) spo2 = 88 + _random.nextInt(5);
      if (_random.nextDouble() < 0.08) temp = 37.9 + _random.nextDouble() * 0.6;

      reading = VitalReading(
        deviceId: FirebaseConfig.deviceId,
        timestamp: DateTime.now(),
        bpm: bpm,
        spo2: spo2,
        temperature: double.parse(temp.toStringAsFixed(1)),
        status: 'valid',
      );
    }

    _applyReading(reading);
    connected = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _client.close();
    super.dispose();
  }
}
