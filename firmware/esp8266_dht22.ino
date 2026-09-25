#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <DHT.h>
#include <ArduinoJson.h>

// ===== الحساس =====
#define DHTPIN 4
#define DHTTYPE DHT22
DHT dht(DHTPIN, DHTTYPE);

// ===== الواي فاي =====
const char* ssid     = "Devoz phone";
const char* password = "devo1234";

// ===== السيرفر =====
const char* serverURL = "https://your-app.up.railway.app/api/data";

// ⚠️ غيّر ده في كل ESP
// ESP الأول:   "esp01_room"
// ESP التاني:  "esp02_kitchen"
// ESP التالت:  "esp03_salon"
const char* deviceId  = "esp01_room";

// ===== التوقيت =====
const unsigned long interval = 5000;
unsigned long lastSend = 0;

// ===== العملاء =====
WiFiClientSecure client;
HTTPClient http;

void setup() {
  Serial.begin(9600);
  delay(100);
  Serial.printf("\n\n=== ESP8266 [%s] ===\n", deviceId);

  dht.begin();

  WiFi.persistent(true);
  WiFi.setAutoReconnect(true);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected!");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());

  client.setInsecure();
  client.setTimeout(10000);
}

void sendData(float temperature, float humidity) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi down");
    return;
  }

  StaticJsonDocument<200> doc;
  doc["device_id"] = deviceId;
  doc["temp"]      = serialized(String(temperature, 1));
  doc["hum"]       = serialized(String(humidity, 1));

  String payload;
  serializeJson(doc, payload);

  http.begin(client, serverURL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(10000);

  int code = http.POST(payload);

  if (code > 0) {
    Serial.printf("HTTP %d | %s\n", code, payload.c_str());
  } else {
    Serial.printf("ERR %s\n", http.errorToString(code).c_str());
  }

  http.end();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("Reconnecting WiFi...");
    WiFi.reconnect();
    delay(2000);
    return;
  }

  if (millis() - lastSend < interval) return;
  lastSend = millis();

  float humidity    = dht.readHumidity();
  float temperature = dht.readTemperature();

  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("DHT read failed");
    return;
  }

  Serial.printf("%.1f C | %.1f %%\n", temperature, humidity);

  if (temperature > 32 || temperature < 28 || humidity > 70 || humidity < 60) {
    Serial.println("Out of range");
  }

  sendData(temperature, humidity);
}
