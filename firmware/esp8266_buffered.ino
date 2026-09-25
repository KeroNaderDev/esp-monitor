#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <WiFiClientSecure.h>
#include <LittleFS.h>
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
const char* serverURL = "https://esp-monitor-production.up.railway.app/api/data";
const char* batchURL  = "https://esp-monitor-production.up.railway.app/api/data/batch";

// ⚠️ غيّر ده في كل ESP (esp01_room / esp02_kitchen / esp03_salon ...)
const char* deviceId  = "esp01_room";

// ===== التخزين المؤقت (offline buffer) =====
// عند انقطاع النت: كل قراءة تتسجل في /buffer.csv كسطر: millis,temp,hum
// عند عودة النت: تتبعت دفعات لـ /api/data/batch مع عمر كل قراءة (age)
// ثم تتمسح من الفلاش بعد نجاح الإرسال.
#define BUFFER_FILE "/buffer.csv"
const unsigned long interval = 5000; // قراءة كل 5 ثواني
const int MAX_BUFFER_LINES = 2000;   // السقف ≈ 2000 قراءة ≈ 2.7 ساعة
const int BATCH_CHUNK = 30;          // قراءات كل طلب مزامنة

unsigned long lastSend = 0;

WiFiClientSecure client;
HTTPClient http;

struct BufEntry {
  unsigned long ms;
  float temp;
  float hum;
};

// ---------- أدوات البافر ----------

int countBufferLines() {
  File f = LittleFS.open(BUFFER_FILE, "r");
  if (!f) return 0;
  int n = 0;
  while (f.available()) {
    if (f.read() == '\n') n++;
  }
  f.close();
  return n;
}

// يمسح أول n سطر (اللي اتبعتوا بنجاح)
void dropOldestLines(int n) {
  File src = LittleFS.open(BUFFER_FILE, "r");
  if (!src) return;
  File tmp = LittleFS.open("/buffer.tmp", "w");
  if (!tmp) { src.close(); return; }
  int skipped = 0;
  while (src.available() && skipped < n) {
    if (src.read() == '\n') skipped++;
  }
  uint8_t buf[256];
  size_t r;
  while ((r = src.read(buf, sizeof(buf))) > 0) tmp.write(buf, r);
  src.close();
  tmp.close();
  LittleFS.remove(BUFFER_FILE);
  LittleFS.rename("/buffer.tmp", BUFFER_FILE);
}

void bufferAppend(unsigned long ms, float t, float h) {
  if (countBufferLines() >= MAX_BUFFER_LINES) dropOldestLines(100); // امسح الأقدم عند الامتلاء
  File f = LittleFS.open(BUFFER_FILE, "a");
  if (!f) {
    Serial.println("buffer open failed");
    return;
  }
  f.printf("%lu,%.1f,%.1f\n", ms, t, h);
  f.close();
  Serial.println("saved to buffer (offline)");
}

// ---------- الإرسال ----------

bool sendLive(float t, float h) {
  StaticJsonDocument<256> doc;
  doc["device_id"] = deviceId;
  doc["temp"] = serialized(String(t, 1));
  doc["hum"]  = serialized(String(h, 1));

  String payload;
  serializeJson(doc, payload);

  http.begin(client, serverURL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(10000);

  int code = http.POST(payload);
  http.end();

  if (code > 0 && code < 300) {
    Serial.printf("live sent: %s\n", payload.c_str());
    return true;
  }
  Serial.printf("live failed: %d\n", code);
  return false;
}

// يقرأ أول chunk من الملف
int readChunk(BufEntry* buf, int maxN) {
  File f = LittleFS.open(BUFFER_FILE, "r");
  if (!f) return -1; // لا يوجد ملف = لا يوجد مخزن
  int n = 0;
  while (n < maxN && f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) continue;
    int c1 = line.indexOf(',');
    int c2 = line.indexOf(',', c1 + 1);
    if (c1 < 0 || c2 < 0) continue; // سطر تالف
    buf[n].ms   = line.substring(0, c1).toInt();
    buf[n].temp = line.substring(c1 + 1, c2).toFloat();
    buf[n].hum  = line.substring(c2 + 1).toFloat();
    n++;
  }
  f.close();
  return n;
}

bool postBatch(BufEntry* buf, int n) {
  DynamicJsonDocument doc(4096);
  doc["device_id"] = deviceId;
  JsonArray arr = doc.createNestedArray("readings");
  unsigned long nowMs = millis();
  for (int i = 0; i < n; i++) {
    JsonObject r = arr.createNestedObject();
    r["temp"] = serialized(String(buf[i].temp, 1));
    r["hum"]  = serialized(String(buf[i].hum, 1));
    r["age"]  = (unsigned long)(nowMs - buf[i].ms); // عمر القراءة — السيرفر يحسب وقتها
  }

  String payload;
  serializeJson(doc, payload);

  http.begin(client, batchURL);
  http.addHeader("Content-Type", "application/json");
  http.setTimeout(15000);

  int code = http.POST(payload);
  http.end();

  if (code > 0 && code < 300) {
    Serial.printf("flushed %d buffered readings\n", n);
    return true;
  }
  Serial.printf("flush failed: %d\n", code);
  return false;
}

// يبعت كل المخزن دفعات، ويمسح اللي اتبعت
void flushBuffer() {
  BufEntry chunk[BATCH_CHUNK];
  while (true) {
    int n = readChunk(chunk, BATCH_CHUNK);
    if (n <= 0) {
      LittleFS.remove(BUFFER_FILE);
      return;
    }
    if (!postBatch(chunk, n)) return; // فشل — نحتفظ بالملف ونحاول لاحقًا
    dropOldestLines(n);
  }
}

// ---------- setup / loop ----------

void setup() {
  Serial.begin(9600);
  delay(100);
  Serial.printf("\n\n=== ESP8266 buffered [%s] ===\n", deviceId);

  dht.begin();

  if (!LittleFS.begin()) {
    Serial.println("LittleFS mount failed, formatting...");
    LittleFS.format();
    LittleFS.begin();
  }
  int pending = countBufferLines();
  if (pending > 0) Serial.printf("%d buffered readings kept from before reboot\n", pending);

  WiFi.persistent(true);
  WiFi.setAutoReconnect(true);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  // محاولة اتصال محدودة — لو مفيش شبكة نكمل offline والتخزين شغال
  Serial.print("Connecting WiFi");
  unsigned long w0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - w0 < 15000) {
    delay(500);
    Serial.print(".");
  }
  Serial.println(WiFi.status() == WL_CONNECTED ? "\nConnected!" : "\nOffline mode - buffering");

  client.setInsecure();
  client.setTimeout(10000);
}

void loop() {
  if (millis() - lastSend < interval) return;
  lastSend = millis();

  float h = dht.readHumidity();
  float t = dht.readTemperature();

  if (isnan(h) || isnan(t)) {
    Serial.println("DHT read failed");
    return;
  }
  Serial.printf("%.1f C | %.1f %%\n", t, h);

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("offline -> buffering");
    bufferAppend(millis(), t, h);
    WiFi.reconnect();
    return;
  }

  if (sendLive(t, h)) {
    flushBuffer(); // ابعت المخزن القديم بعد القراءة الحية
  } else {
    bufferAppend(millis(), t, h); // السيرفر واقع — خزن القراءة
  }
}
