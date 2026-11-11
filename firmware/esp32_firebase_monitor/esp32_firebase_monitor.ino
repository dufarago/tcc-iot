/*
 * ESP32 + MAX30102 + DS18B20 + OLED -> Firebase Realtime Database
 * Envia BPM, SpO2 e temperatura para o app Flutter (latest + history).
 *
 * Versao 4 (08/11/2026):
 *   - o BPM passa a ser calculado por autocorrelacao do sinal infravermelho
 *     (funcao bpmAutocorrelacao), escrita pelo autor. O algoritmo da Maxim
 *     contava dois picos por batimento (por exemplo, 150 BPM para um pulso
 *     de 75) e continua sendo usado so para a SpO2. A autocorrelacao mede de
 *     quanto em quanto tempo o sinal se repete, o que nao depende de achar
 *     cada pico, e devolve uma qualidade de 0 a 1 (leituras com qualidade
 *     abaixo de 0,4 sao descartadas).
 *
 * Versao 3 (08/11/2026):
 *   - as amostras passam a ser lidas com getFIFORed()/getFIFOIR(). O exemplo
 *     Example8_SPO2 usa getRed()/getIR(), que esperam uma amostra NOVA a cada
 *     chamada: cada valor guardado descartava as amostras seguintes, o
 *     buffer recebia cerca de 10 amostras/s em vez de 25 e, como o algoritmo
 *     supoe 25 amostras/s, o BPM saia cerca de 2,5 vezes maior (60 -> 150).
 *     Alem disso, o vermelho e o infravermelho de cada posicao vinham de
 *     amostras diferentes. Com a correcao, cada ciclo de 25 amostras leva
 *     cerca de 1 s (valor "ciclo=" no Monitor Serial).
 *
 * Versao 2 (07/11/2026):
 *   - o envio ao Firebase roda em uma tarefa separada, no nucleo 0 do ESP32,
 *     e nao interrompe mais a leitura do MAX30102 (antes, cada envio HTTPS
 *     parava a leitura por alguns segundos e as amostras perdidas faziam o
 *     BPM saltar, por exemplo de 100 para 166);
 *   - o DS18B20 e lido sem bloqueio (a conversao de 750 ms acontece enquanto
 *     o MAX30102 continua sendo lido) e a temperatura enviada e a media das
 *     ultimas 5 leituras; os valores 85 C (sonda reiniciando) e -127 C
 *     (sonda desconectada) sao descartados;
 *   - BPM e SpO2 enviados sao a mediana das ultimas 5 janelas validas, com
 *     faixa plausivel e rejeicao de saltos bruscos isolados.
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
 *     mesmos parametros de configuracao do sensor, mas le cada amostra com
 *     getFIFORed()/getFIFOIR() (ver Versao 3).
 *   - bpmAutocorrelacao(), filtros, validacao das leituras, montagem do
 *     JSON, envio ao Firebase e
 *     exibicao no OLED foram escritos pelo autor deste trabalho.
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
// Fora dela a leitura de temperatura e marcada como invalida; o valor
// continua aparecendo no Monitor Serial e no OLED (com "*") para os testes
// de bancada.
#define TEMP_MIN_C 30.0
#define TEMP_MAX_C 43.0
#define TEMP_CONV_MS 800   // conversao de 12 bits do DS18B20: ate 750 ms
#define N_TEMP 5           // media movel das ultimas 5 leituras (~4 s)

// Filtro do MAX30102
#define FINGER_IR 50000    // nivel de IR que indica dedo sobre o sensor
#define BPM_MIN 40
#define BPM_MAX 180
#define SPO2_MIN 70
#define N_MEDIANA 5        // mediana das ultimas 5 janelas validas (~5 s)
#define MIN_JANELAS 3      // janelas validas antes de enviar como "valid"
#define SALTO_MAX_BPM 25   // salto maior que isso e tratado como suspeito
#define SALTOS_PARA_ACEITAR 3
#define QUALIDADE_MIN 0.4f // qualidade minima da autocorrelacao
#define INVALIDAS_PARA_LIMPAR 3

Adafruit_SSD1306 display(128, 64, &Wire, -1);
MAX30105 particleSensor;
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature tempSensor(&oneWire);
DeviceAddress tempAddr;
bool tempAddrOk = false;

uint32_t irBuffer[100];
uint32_t redBuffer[100];
int32_t spo2 = 0;
int8_t validSPO2 = 0;
int32_t heartRate = 0;
int8_t validHeartRate = 0;

unsigned long lastSendMs = 0;
bool buffersReady = false;
bool oledOk = false;

// ----- Filtro de mediana do BPM e da SpO2 -----
int histBpm[N_MEDIANA];
int nBpm = 0, posBpm = 0;
int histSpo2[N_MEDIANA];
int nSpo2 = 0, posSpo2 = 0;
int bpmFiltrado = 0;
int spo2Filtrado = 0;
int saltosSeguidos = 0;
int invalidasSeguidas = 0;
int bpmAuto = 0;
float qualidadeBpm = 0;

// ----- Temperatura -----
float histTemp[N_TEMP];
int nTemp = 0, posTemp = 0;
float tempFiltrada = 0;
bool tempConnected = false;
unsigned long tempPedidoMs = 0;

// ----- Envio em segundo plano -----
struct Leitura {
  int bpm;
  int spo2;
  float temp;
  bool ppgOk;
  bool tempOk;
  time_t quando;
};
QueueHandle_t filaEnvio;  // guarda so a leitura mais recente

String latestUrl() {
  return String(DATABASE_URL) + "/devices/" + DEVICE_ID + "/latest.json";
}

String historyUrl() {
  return String(DATABASE_URL) + "/devices/" + DEVICE_ID + "/history.json";
}

// Data e hora em UTC (ISO 8601 com sufixo Z), obtidas por NTP.
String isoTime(time_t t) {
  if (t < 100000) return String("1970-01-01T00:00:00Z");
  struct tm tmUtc;
  gmtime_r(&t, &tmUtc);
  char buf[25];
  strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tmUtc);
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

String montarJson(const Leitura& l) {
  const char* ppgStatus = l.ppgOk ? "valid" : "invalid";
  const char* tempStatus = l.tempOk ? "valid" : "invalid";
  const char* status = (l.ppgOk && l.tempOk) ? "valid" : "invalid";

  String body = "{";
  body += "\"deviceId\":\"" + String(DEVICE_ID) + "\",";
  body += "\"timestamp\":\"" + isoTime(l.quando) + "\",";
  body += "\"bpm\":" + String(l.bpm) + ",";
  body += "\"spo2\":" + String(l.spo2) + ",";
  body += "\"temperature\":" + String(l.temp, 1) + ",";
  body += "\"status\":\"" + String(status) + "\",";
  body += "\"ppgStatus\":\"" + String(ppgStatus) + "\",";
  body += "\"tempStatus\":\"" + String(tempStatus) + "\"";
  body += "}";
  return body;
}

// Tarefa no nucleo 0: envia ao Firebase a leitura mais recente da fila.
// Assim, as requisicoes HTTPS (que levam alguns segundos) nao interrompem
// a leitura dos sensores, que continua no loop() do nucleo 1.
void tarefaEnvio(void*) {
  Leitura l;
  for (;;) {
    if (xQueueReceive(filaEnvio, &l, portMAX_DELAY) != pdTRUE) continue;

    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("WiFi caiu, tentando reconectar...");
      WiFi.reconnect();
      vTaskDelay(pdMS_TO_TICKS(2000));
      continue;
    }

    String body = montarJson(l);
    Serial.println(body);
    unsigned long t0 = millis();
    bool okLatest = putJson(latestUrl(), body);
    bool okHistory = postJson(historyUrl(), body);
    Serial.printf("Envio %s em %lu ms\n",
                  (okLatest && okHistory) ? "OK" : "com falha", millis() - t0);
  }
}

void setupWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
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

// ----- BPM por autocorrelacao -----
// O sinal do pulso se repete a cada batimento. A autocorrelacao compara a
// janela de 4 s com ela mesma deslocada de k amostras; o deslocamento com a
// maior semelhanca e o periodo do pulso, e BPM = 60 * 25 / periodo.
#define FS_HZ 25.0f
#define LAG_MIN 8    // 25*60/8  = 187 BPM
#define LAG_MAX 38   // 25*60/38 = 39 BPM

// Retorna o BPM (0 se nao houver periodicidade clara) e a qualidade (0 a 1).
float bpmAutocorrelacao(const uint32_t* ir, int n, float* qualidade) {
  static float x[100];
  static float r[LAG_MAX + 2];
  if (n > 100) n = 100;
  // 1) remove a tendencia linear (linha de base que sobe ou desce)
  float sx = 0, sy = 0, sxx = 0, sxy = 0;
  for (int i = 0; i < n; i++) {
    float v = (float)ir[i];
    sx += i; sy += v; sxx += (float)i * i; sxy += i * v;
  }
  float b = (n * sxy - sx * sy) / (n * sxx - sx * sx);
  float a = (sy - b * sx) / n;
  for (int i = 0; i < n; i++) x[i] = (float)ir[i] - (a + b * i);
  // 2) filtro passa-alta de 1a ordem (corte ~0,4 Hz), aplicado para frente e
  //    para tras (sem atraso de fase): tira a oscilacao lenta da linha de base
  //    causada por respiracao e pressao do dedo
  const float alfa = 0.9f;
  static float y[100];
  y[0] = 0;
  for (int i = 1; i < n; i++) y[i] = alfa * (y[i - 1] + x[i] - x[i - 1]);
  x[n - 1] = 0;
  for (int i = n - 2; i >= 0; i--) x[i] = alfa * (x[i + 1] + y[i] - y[i + 1]);
  // 3) suaviza com media movel de 5 amostras (0,2 s): reduz o ruido sem
  //    apagar o pulso (o batimento mais rapido aceito dura 0,32 s)
  for (int i = 0; i < n; i++) {
    float s = 0; int c = 0;
    for (int j = i - 2; j <= i + 2; j++) if (j >= 0 && j < n) { s += x[j]; c++; }
    y[i] = s / c;
  }
  for (int i = 0; i < n; i++) x[i] = y[i];
  // 4) autocorrelacao normalizada para os atrasos de LAG_MIN-1 a LAG_MAX+1
  for (int k = LAG_MIN - 1; k <= LAG_MAX + 1; k++) {
    float s = 0, e1 = 0, e2 = 0;
    for (int i = 0; i + k < n; i++) {
      s += x[i] * x[i + k];
      e1 += x[i] * x[i];
      e2 += x[i + k] * x[i + k];
    }
    r[k] = (e1 > 0 && e2 > 0) ? s / sqrtf(e1 * e2) : 0;
  }
  // 5) picos locais dentro da faixa de 39 a 187 BPM. O maior pico pode ser
  //    um multiplo do periodo (2 batimentos); por isso escolhe-se o primeiro
  //    pico (menor atraso) com pelo menos 85% da altura do maior.
  float rMax = -1;
  for (int k = LAG_MIN; k <= LAG_MAX; k++) {
    if (r[k] > r[k - 1] && r[k] >= r[k + 1] && r[k] > rMax) rMax = r[k];
  }
  int melhor = -1;
  for (int k = LAG_MIN; k <= LAG_MAX && rMax > 0; k++) {
    if (r[k] > r[k - 1] && r[k] >= r[k + 1] && r[k] >= 0.85f * rMax) { melhor = k; break; }
  }
  if (melhor < 0) { *qualidade = 0; return 0; }
  // 6) interpolacao parabolica para um atraso fracionario
  float y0 = r[melhor - 1], y1 = r[melhor], y2 = r[melhor + 1];
  float den = y0 - 2 * y1 + y2;
  float d = (den != 0) ? 0.5f * (y0 - y2) / den : 0;
  if (d > 0.5f) d = 0.5f;
  if (d < -0.5f) d = -0.5f;
  *qualidade = y1;
  return 60.0f * FS_HZ / (melhor + d);
}

// ----- Funcoes do filtro de mediana -----
void inserir(int* v, int& n, int& pos, int x) {
  v[pos] = x;
  pos = (pos + 1) % N_MEDIANA;
  if (n < N_MEDIANA) n++;
}

int mediana(const int* v, int n) {
  int t[N_MEDIANA];
  for (int i = 0; i < n; i++) t[i] = v[i];
  for (int i = 1; i < n; i++) {  // ordenacao por insercao (no maximo 5 valores)
    int x = t[i];
    int j = i - 1;
    while (j >= 0 && t[j] > x) {
      t[j + 1] = t[j];
      j--;
    }
    t[j + 1] = x;
  }
  return t[n / 2];
}

void limparPpg() {
  nBpm = posBpm = 0;
  nSpo2 = posSpo2 = 0;
  bpmFiltrado = spo2Filtrado = 0;
  saltosSeguidos = 0;
  invalidasSeguidas = 0;
}

// Chamada a cada nova janela do algoritmo (cerca de 1 vez por segundo).
void atualizarFiltroPpg(bool finger) {
  if (!finger) {
    limparPpg();
    return;
  }

  bool bpmPlausivel = qualidadeBpm >= QUALIDADE_MIN &&
                      bpmAuto >= BPM_MIN && bpmAuto <= BPM_MAX;
  bool spo2Plausivel = validSPO2 && spo2 >= SPO2_MIN && spo2 <= 100;

  if (!bpmPlausivel || !spo2Plausivel) {
    // Janelas invalidas seguidas: descarta o historico antigo
    if (++invalidasSeguidas >= INVALIDAS_PARA_LIMPAR) limparPpg();
  } else {
    invalidasSeguidas = 0;
  }

  if (bpmPlausivel) {
    if (nBpm >= MIN_JANELAS && abs(bpmAuto - bpmFiltrado) > SALTO_MAX_BPM) {
      // Salto brusco: geralmente pico falso ou movimento do dedo. So e
      // aceito se se repetir em janelas seguidas (mudanca real do pulso).
      if (++saltosSeguidos >= SALTOS_PARA_ACEITAR) {
        nBpm = posBpm = 0;
        saltosSeguidos = 0;
        inserir(histBpm, nBpm, posBpm, bpmAuto);
      }
    } else {
      saltosSeguidos = 0;
      inserir(histBpm, nBpm, posBpm, bpmAuto);
    }
    if (nBpm > 0) bpmFiltrado = mediana(histBpm, nBpm);
  }

  if (spo2Plausivel) {
    inserir(histSpo2, nSpo2, posSpo2, spo2);
    spo2Filtrado = mediana(histSpo2, nSpo2);
  }
}

// ----- Temperatura sem bloqueio -----
void iniciarSondaTemp() {
  tempSensor.begin();
  tempAddrOk = tempSensor.getAddress(tempAddr, 0);
  if (tempAddrOk) tempSensor.setResolution(tempAddr, 12);
  tempSensor.setWaitForConversion(false);  // requestTemperatures() nao espera
  tempSensor.requestTemperatures();
  tempPedidoMs = millis();
}

void atualizarTemperatura() {
  if (millis() - tempPedidoMs < TEMP_CONV_MS) return;

  if (!tempAddrOk) {  // sonda nao encontrada: tenta de novo
    tempConnected = false;
    nTemp = posTemp = 0;
    iniciarSondaTemp();
    return;
  }

  float t = tempSensor.getTempC(tempAddr);
  tempSensor.requestTemperatures();  // ja pede a proxima conversao
  tempPedidoMs = millis();

  if (t == DEVICE_DISCONNECTED_C) {  // -127: sonda desconectada ou mal ligada
    tempConnected = false;
    tempAddrOk = false;
    nTemp = posTemp = 0;
    return;
  }
  if (t == 85.0) return;  // valor de reinicio da sonda, nao e uma medida

  tempConnected = true;
  histTemp[posTemp] = t;
  posTemp = (posTemp + 1) % N_TEMP;
  if (nTemp < N_TEMP) nTemp++;
  float soma = 0;
  for (int i = 0; i < nTemp; i++) soma += histTemp[i];
  tempFiltrada = soma / nTemp;
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

  iniciarSondaTemp();
  if (!tempAddrOk) Serial.println("DS18B20 nao encontrado! Confira D4 e o resistor de 4,7k.");

  if (!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
    Serial.println("MAX30102 nao encontrado! Confira SDA/SCL/3V3/GND.");
    showOled("MAX30102 falhou", "Confira fios I2C");
    while (true) delay(1000);
  }

  // ledBrightness, sampleAverage, ledMode, sampleRate, pulseWidth, adcRange
  // 100 amostras/s com media de 4 = 25 amostras/s, a taxa usada pelo algoritmo
  particleSensor.setup(60, 4, 2, 100, 411, 4096);
  Serial.println("Sensores OK");

  showOled("WiFi...");
  setupWifi();

  filaEnvio = xQueueCreate(1, sizeof(Leitura));
  xTaskCreatePinnedToCore(tarefaEnvio, "envio", 16384, nullptr, 1, nullptr, 0);

  showOled("WiFi OK", "Coloque o dedo");
  Serial.println("Pronto. Coloque o dedo no MAX30102.");
}

// Le 25 amostras novas (cerca de 1 s) e recalcula BPM e SpO2 na janela de
// 100 amostras. O loop() nao pode ficar parado mais que ~150 ms entre as
// leituras, porque a biblioteca guarda so 4 amostras; por isso nada que
// demore (HTTPS, conversao do DS18B20) e feito aqui.
void readMax30102() {
  const int32_t bufferLength = 100;

  if (!buffersReady) {
    for (byte i = 0; i < bufferLength; i++) {
      while (!particleSensor.available()) particleSensor.check();
      redBuffer[i] = particleSensor.getFIFORed();
      irBuffer[i] = particleSensor.getFIFOIR();
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
    redBuffer[i] = particleSensor.getFIFORed();
    irBuffer[i] = particleSensor.getFIFOIR();
    particleSensor.nextSample();
    if ((i % 5) == 0) atualizarTemperatura();  // rapido: so le o resultado
  }
  maxim_heart_rate_and_oxygen_saturation(
      irBuffer, bufferLength, redBuffer,
      &spo2, &validSPO2, &heartRate, &validHeartRate);
}

void loop() {
  unsigned long inicioCiclo = millis();
  readMax30102();
  atualizarTemperatura();

  bpmAuto = (int)lroundf(bpmAutocorrelacao(irBuffer, 100, &qualidadeBpm));

  long irValue = (long)irBuffer[99];
  bool finger = irValue >= FINGER_IR;
  atualizarFiltroPpg(finger);

  bool tempOk = tempConnected && nTemp > 0 &&
                tempFiltrada >= TEMP_MIN_C && tempFiltrada <= TEMP_MAX_C;
  bool ppgOk = finger && nBpm >= MIN_JANELAS && nSpo2 >= MIN_JANELAS;

  // Valores enviados ao Firebase: zero quando a leitura do sensor e invalida
  int bpmOut = ppgOk ? bpmFiltrado : 0;
  int spo2Out = ppgOk ? spo2Filtrado : 0;
  float tempOut = tempOk ? tempFiltrada : 0;

  Serial.printf(
      "IR=%ld BPMmaxim=%ld BPMjanela=%d(q=%.2f) BPM=%d SpO2janela=%ld(%s) SpO2=%d "
      "Temp=%.2f ppg=%s temp=%s ciclo=%lums\n",
      irValue, (long)heartRate, bpmAuto, qualidadeBpm, bpmOut,
      (long)spo2, validSPO2 ? "ok" : "inv", spo2Out, tempConnected ? tempFiltrada : -127.0,
      ppgOk ? "valid" : "invalid", tempOk ? "valid" : "invalid",
      millis() - inicioCiclo);

  // --- OLED ---
  if (oledOk) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    if (!finger) {
      display.println("Coloque o dedo");
    } else {
      display.println(ppgOk ? "MAX30102+Firebase" : "Medindo... fique parado");
      display.setTextSize(2);
      display.setCursor(0, 14);
      display.print("BPM:");
      display.println(ppgOk ? String(bpmOut) : "--");
      display.setCursor(0, 36);
      display.print("SpO2:");
      display.println(ppgOk ? String(spo2Out) + "%" : "--");
    }
    display.setTextSize(1);
    display.setCursor(0, 56);
    display.print("T:");
    if (!tempConnected) {
      display.print("--");
    } else {
      display.print(String(tempFiltrada, 1));
      if (!tempOk) display.print("*");  // fora da faixa corporal
    }
    display.print("C ");
    display.print(WiFi.status() == WL_CONNECTED ? "WiFi" : "...");
    display.display();
  }

  // --- Firebase a cada 3 s (o envio em si roda na tarefaEnvio) ---
  if (millis() - lastSendMs < SEND_INTERVAL_MS) return;
  lastSendMs = millis();

  Leitura l = {bpmOut, spo2Out, tempOut, ppgOk, tempOk, time(nullptr)};
  xQueueOverwrite(filaEnvio, &l);  // substitui a leitura que ainda nao saiu
}
