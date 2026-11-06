/*
 * ESP32 + MAX30102 + DS18B20 + OLED -> Firebase Realtime Database
 * Envia BPM, SpO2 e temperatura para o app Flutter (latest + history).
 *
 * Ligacao (protoboard):
 *   OLED/MAX30102 I2C -> SDA=21, SCL=22
 *   DS18B20 DATA -> D4 (+ resistor 4,7k entre DATA e 3V3)
 *
 * Bibliotecas (Arduino IDE -> Gerenciar Bibliotecas) e versoes usadas:
 *   - Adafruit SSD1306 2.5.17 e Adafruit GFX 1.12.6 (Adafruit, licenca BSD)
 *   - SparkFun MAX3010x Pulse and Proximity Sensor Library 1.1.2
 *     (SparkFun Electronics; licencas indicadas no repositorio da biblioteca)
 *   - OneWire 2.3.8 (Paul Stoffregen / PJRC)
 *   - DallasTemperature 4.0.6 (Miles Burton, licenca MIT)
 *
 * Creditos:
 *   - maxim_heart_rate_and_oxygen_saturation() e spo2_algorithm.h fazem parte
 *     da biblioteca SparkFun MAX3010x e foram adaptados pela SparkFun do
 *     projeto de referencia MAXREFDES117 da Maxim Integrated (a licenca da
 *     Maxim esta no cabecalho do proprio arquivo spo2_algorithm.h).
 *   - readMax30102() segue a estrutura do exemplo Example8_SPO2 da mesma
 *     biblioteca (janela de 100 amostras, deslocamento de 25 amostras) e os
 *     mesmos parametros de configuracao do sensor.
 *   - Validacao das leituras, montagem do JSON, envio ao Firebase e exibicao
 *     no OLED foram escritos pelo autor deste trabalho.
 *
 * Placa: ESP32 Dev Module (pacote esp32 3.3.11, Arduino IDE 2.3.10)
 * Upload Speed: 115200
 */

#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Wire.h>
#include <time.h>

#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include "MAX30105.h"
#include "spo2_algorithm.h"
#include <OneWire.h>
#include <DallasTemperature.h>

// ===== CONFIGURE =====
const char* WIFI_SSID = "SUA_REDE_WIFI";
const char* WIFI_PASSWORD = "SUA_SENHA_WIFI";
const char* DATABASE_URL =
    "https://SEU-PROJETO-default-rtdb.firebaseio.com";
const char* DEVICE_ID = "esp32_monitor_01";
// =====================

#define SDA_PIN 21
#define SCL_PIN 22
#define SCREEN_ADDRESS 0x3C
#define ONE_WIRE_BUS 4
#define SEND_INTERVAL_MS 3000

// Faixa aceita como temperatura corporal plausivel (graus Celsius).
// Fora dela a leitura de temperatura e marcada como invalida; o valor bruto
// continua aparecendo no Monitor Serial e no OLED (com "*") para os testes
// de bancada.
#define TEMP_MIN_C 30.0
#define TEMP_MAX_C 43.0

Adafruit_SSD1306 display(128, 64, &Wire, -1);
MAX30105 particleSensor;
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature tempSensor(&oneWire);

uint32_t irBuffer[100];
uint32_t redBuffer[100];
int32_t spo2 = 0;
int8_t validSPO2 = 0;
int32_t heartRate = 0;
int8_t validHeartRate = 0;

unsigned long lastSendMs = 0;
bool buffersReady = false;
bool oledOk = false;

String latestUrl() {
  return String(DATABASE_URL) + "/devices/" + DEVICE_ID + "/latest.json";
}

String historyUrl() {
  return String(DATABASE_URL) + "/devices/" + DEVICE_ID + "/history.json";
}

// Data e hora em UTC (ISO 8601 com sufixo Z), obtidas por NTP.
String isoNow() {
  time_t now = time(nullptr);
  if (now < 100000) return String("1970-01-01T00:00:00Z");
  struct tm t;
  gmtime_r(&now, &t);
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &t);
  return String(buf);
}

bool putJson(const String& url, const String& body) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  if (!http.begin(client, url)) return false;
  http.addHeader("Content-Type", "application/json");
  int code = http.PUT(body);
  Serial.printf("Firebase PUT latest -> %d\n", code);
  if (code > 0) Serial.println(http.getString());
  http.end();
  return code >= 200 && code < 300;
}

bool postJson(const String& url, const String& body) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient http;
  if (!http.begin(client, url)) return false;
  http.addHeader("Content-Type", "application/json");
  int code = http.POST(body);
  Serial.printf("Firebase POST history -> %d\n", code);
  http.end();
  return code >= 200 && code < 300;
}

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print(".");
  }
  Serial.println(" OK");
  Serial.println(WiFi.localIP());
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
}

void showOled(const String& line1, const String& line2 = "") {
  if (!oledOk) return;
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println(line1);
  if (line2.length() > 0) {
    display.setCursor(0, 16);
    display.println(line2);
  }
  display.display();
}

void setup() {
  Serial.begin(115200);
  delay(500);

  Wire.begin(SDA_PIN, SCL_PIN);

  oledOk = display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS);
  if (!oledOk) {
    Serial.println("OLED nao encontrado (seguindo sem display)");
  } else {
    showOled("Iniciando...", "MAX30102 + DS18B20");
  }

  tempSensor.begin();

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 nao encontrado! Confira SDA/SCL/3V3/GND.");
    showOled("MAX30102 falhou", "Confira fios I2C");
    while (true) delay(1000);
  }

  // ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange
  particleSensor.setup(60, 4, 2, 100, 411, 4096);
  Serial.println("Sensores OK");

  showOled("WiFi...");
  setupWifi();
  showOled("WiFi OK", "Coloque o dedo");
  Serial.println("Pronto. Coloque o dedo no MAX30102.");
}

void readMax30102() {
  const int32_t bufferLength = 100;

  if (!buffersReady) {
    for (byte i = 0; i < bufferLength; i++) {
      while (!particleSensor.available()) particleSensor.check();
      redBuffer[i] = particleSensor.getRed();
      irBuffer[i] = particleSensor.getIR();
      particleSensor.nextSample();
    }
    maxim_heart_rate_and_oxygen_saturation(
        irBuffer, bufferLength, redBuffer,
        &spo2, &validSPO2, &heartRate, &validHeartRate);
    buffersReady = true;
    return;
  }

  for (byte i = 25; i < 100; i++) {
    redBuffer[i - 25] = redBuffer[i];
    irBuffer[i - 25] = irBuffer[i];
  }
  for (byte i = 75; i < 100; i++) {
    while (!particleSensor.available()) particleSensor.check();
    redBuffer[i] = particleSensor.getRed();
    irBuffer[i] = particleSensor.getIR();
    particleSensor.nextSample();
  }
  maxim_heart_rate_and_oxygen_saturation(
      irBuffer, bufferLength, redBuffer,
      &spo2, &validSPO2, &heartRate, &validHeartRate);
}

void loop() {
  readMax30102();

  long irValue = particleSensor.getIR();
  tempSensor.requestTemperatures();
  float tempC = tempSensor.getTempCByIndex(0);

  bool finger = irValue >= 50000;
  bool tempConnected = (tempC != DEVICE_DISCONNECTED_C);
  bool tempOk = tempConnected && tempC >= TEMP_MIN_C && tempC <= TEMP_MAX_C;
  bool ppgOk = finger && validHeartRate && validSPO2;

  // Valores enviados ao Firebase: zero quando a leitura do sensor e invalida
  int bpmOut = ppgOk ? (int)heartRate : 0;
  int spo2Out = ppgOk ? (int)spo2 : 0;
  float tempOut = tempOk ? tempC : 0;
  // Validade de cada sensor e validade geral da leitura
  const char* ppgStatus = ppgOk ? "valid" : "invalid";
  const char* tempStatus = tempOk ? "valid" : "invalid";
  const char* status = (ppgOk && tempOk) ? "valid" : "invalid";

  Serial.printf("IR=%ld BPM=%d SpO2=%d Temp=%.2f (bruta) ppg=%s temp=%s status=%s\n",
                irValue, bpmOut, spo2Out, tempC, ppgStatus, tempStatus, status);

  // --- OLED ---
  if (oledOk) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    if (!finger) {
      display.println("Coloque o dedo");
    } else {
      display.println("MAX30102+Firebase");
      display.setTextSize(2);
      display.setCursor(0, 14);
      display.print("BPM:");
      display.println(validHeartRate ? String(heartRate) : "--");
      display.setCursor(0, 36);
      display.print("SpO2:");
      display.println(validSPO2 ? String(spo2) + "%" : "--");
    }
    display.setTextSize(1);
    display.setCursor(0, 56);
    display.print("T:");
    if (!tempConnected) {
      display.print("--");
    } else {
      display.print(String(tempC, 1));
      if (!tempOk) display.print("*");  // fora da faixa corporal
    }
    display.print("C ");
    display.print(WiFi.status() == WL_CONNECTED ? "WiFi" : "...");
    display.display();
  }

  // --- Firebase a cada 3s ---
  if (millis() - lastSendMs < SEND_INTERVAL_MS) return;
  lastSendMs = millis();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi caiu, reconectando...");
    setupWifi();
    return;
  }

  String body = "{";
  body += "\"deviceId\":\"" + String(DEVICE_ID) + "\",";
  body += "\"timestamp\":\"" + isoNow() + "\",";
  body += "\"bpm\":" + String(bpmOut) + ",";
  body += "\"spo2\":" + String(spo2Out) + ",";
  body += "\"temperature\":" + String(tempOut, 1) + ",";
  body += "\"status\":\"" + String(status) + "\",";
  body += "\"ppgStatus\":\"" + String(ppgStatus) + "\",";
  body += "\"tempStatus\":\"" + String(tempStatus) + "\"";
  body += "}";

  Serial.println(body);
  putJson(latestUrl(), body);
  postJson(historyUrl(), body);
}
