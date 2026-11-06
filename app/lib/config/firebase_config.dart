/// Configuração do Firebase. Substitua os marcadores pelos dados do seu projeto.
abstract final class FirebaseConfig {
  static const bool enabled = true;

  static const String apiKey = 'SUA_API_KEY';
  static const String appId = 'SEU_APP_ID';
  static const String messagingSenderId = 'SEU_SENDER_ID';
  static const String projectId = 'SEU-PROJETO';
  static const String authDomain = 'SEU-PROJETO.firebaseapp.com';
  static const String storageBucket = 'SEU-PROJETO.firebasestorage.app';
  static const String databaseURL =
      'https://SEU-PROJETO-default-rtdb.firebaseio.com';

  static const String deviceId = 'esp32_monitor_01';

  static String get latestPath => 'devices/$deviceId/latest';
  static String get historyPath => 'devices/$deviceId/history';

  static bool get isReady =>
      enabled &&
      apiKey.isNotEmpty &&
      projectId.isNotEmpty &&
      databaseURL.startsWith('https://');
}
