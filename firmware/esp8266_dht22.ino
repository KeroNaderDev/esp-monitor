#include <ESP8266WiFi.h> // مكتبة الواي فاي الخاصة بشريحة ESP8266
#include <ESP8266HTTPClient.h> // مكتبة إرسال طلبات HTTP (POST للسيرفر)
#include <WiFiClientSecure.h> // عميل اتصال مشفر HTTPS (السيرفر يستخدم https)
#include <LittleFS.h> // نظام ملفات الفلاش الداخلي (لتخزين القراءات وقت انقطاع النت)
#include <DHT.h> // مكتبة حساس الحرارة والرطوبة DHT
#include <ArduinoJson.h> // مكتبة بناء وتحليل رسائل JSON

// ===== الحساس ===== // عنوان قسم إعدادات الحساس
#define DHTPIN 4 // رقم البن المتصل به طرف الداتا في الحساس (GPIO4)
#define DHTTYPE DHT22 // نوع الحساس المستخدم (DHT22 أدق من DHT11)
DHT dht(DHTPIN, DHTTYPE); // إنشاء كائن الحساس بالبن والنوع المحددين

// ===== الواي فاي ===== // عنوان قسم بيانات الشبكة
const char* ssid     = "Devoz phone"; // اسم شبكة الواي فاي التي سيتصل بها الجهاز
const char* password = "devo1234"; // كلمة سر شبكة الواي فاي

// ===== السيرفر ===== // عنوان قسم روابط السيرفر
const char* serverURL = "https://esp-monitor-production.up.railway.app/api/data"; // رابط إرسال القراءة الحية الواحدة
const char* batchURL  = "https://esp-monitor-production.up.railway.app/api/data/batch"; // رابط مزامنة القراءات المخزنة دفعة واحدة

// ⚠️ غيّر ده في كل ESP (esp01_room / esp02_kitchen / esp03_salon ...) // تنبيه: كل جهاز لازم له اسم مختلف قبل التفليش
const char* deviceId  = "esp01_room"; // الاسم الفريد لهذا الجهاز (يظهر به في التطبيق)

// ===== التخزين المؤقت (offline buffer) ===== // عنوان قسم شرح فكرة التخزين
// عند انقطاع النت: كل قراءة تتسجل في /buffer.csv كسطر: millis,temp,hum // شرح سطر التخزين
// عند عودة النت: تتبعت دفعات لـ /api/data/batch مع عمر كل قراءة (age) // شرح المزامنة
// ثم تتمسح من الفلاش بعد نجاح الإرسال. // شرح المسح بعد النجاح
#define BUFFER_FILE "/buffer.csv" // اسم ملف التخزين داخل الفلاش
const unsigned long interval = 5000; // المدة بين كل قراءة والتي بعدها بالمللي ثانية (5 ثواني)
const int MAX_BUFFER_LINES = 2000; // أقصى عدد سطور مخزنة (≈ 2000 قراءة ≈ 2.7 ساعة)
const int BATCH_CHUNK = 30; // عدد القراءات المرسلة في طلب المزامنة الواحد

unsigned long lastSend = 0; // وقت آخر إرسال (لحساب هل مرت 5 ثواني أم لا)

WiFiClientSecure client; // كائن الاتصال المشفر المستخدم في كل طلبات HTTPS
HTTPClient http; // كائن طلبات HTTP الذي يبني ويرسل الـ POST

struct BufEntry { // تعريف هيكل يمثل قراءة واحدة مخزنة في الذاكرة
  unsigned long ms; // وقت أخذ القراءة بعدّاد millis (ل Basel حساب عمرها لاحقًا)
  float temp; // درجة الحرارة المخزنة
  float hum; // نسبة الرطوبة المخزنة
}; // نهاية تعريف الهيكل

// ---------- أدوات البافر ---------- // عنوان قسم الدوال المساعدة للتخزين

int countBufferLines() { // دالة تحسب عدد السطور (القراءات) المخزنة في الملف
  File f = LittleFS.open(BUFFER_FILE, "r"); // فتح ملف التخزين بوضع القراءة
  if (!f) return 0; // لو الملف غير موجود (فشل الفتح) فالعدد صفر
  int n = 0; // عداد السطور يبدأ من صفر
  while (f.available()) { // التكرار مادام يوجد بايتات لم تُقرأ في الملف
    if (f.read() == '\n') n++; // كل سطر ينتهي بـ newline فنزيد العداد عندها
  } // نهاية حلقة العد
  f.close(); // إغلاق الملف بعد الانتهاء من القراءة
  return n; // إرجاع عدد السطور المخزنة
} // نهاية دالة العد

// يمسح أول n سطر (اللي اتبعتوا بنجاح) // شرح وظيفة الدالة التالية
void dropOldestLines(int n) { // دالة تمسح أول n سطر من الملف (الأقدم = المُرسل بنجاح)
  File src = LittleFS.open(BUFFER_FILE, "r"); // فتح الملف الأصلي للقراءة
  if (!src) return; // لو لا يوجد ملف فلا يوجد ما يُمسح
  File tmp = LittleFS.open("/buffer.tmp", "w"); // إنشاء ملف مؤقت للكتابة فيه
  if (!tmp) { src.close(); return; } // لو فشل إنشاء المؤقت نغلق الأصلي ونخرج بأمان
  int skipped = 0; // عداد السطور المتخطاة (المحذوفة)
  while (src.available() && skipped < n) { // تخطَّ أول n سطر دون نسخها
    if (src.read() == '\n') skipped++; // نهاية كل سطر متخطى تزيد العداد
  } // نهاية حلقة التخطي
  uint8_t buf[256]; // مصفوفة بايتات مؤقتة لنقل الباقي على دفعات
  size_t r; // متغير يستقبل عدد البايتات المقروءة في كل مرة
  while ((r = src.read(buf, sizeof(buf))) > 0) tmp.write(buf, r); // نسخ باقي الملف للمؤقت
  src.close(); // إغلاق الملف الأصلي
  tmp.close(); // إغلاق الملف المؤقت
  LittleFS.remove(BUFFER_FILE); // حذف ملف التخزين الأصلي
  LittleFS.rename("/buffer.tmp", BUFFER_FILE); // إعادة تسمية المؤقت ليصبح ملف التخزين الجديد
} // نهاية دالة المسح

void bufferAppend(unsigned long ms, float t, float h) { // دالة تحفظ قراءة واحدة في ملف التخزين
  if (countBufferLines() >= MAX_BUFFER_LINES) dropOldestLines(100); // لو الملف امتلأ امسح أقدم 100 سطر أولًا
  File f = LittleFS.open(BUFFER_FILE, "a"); // فتح الملف بوضع الإلحاق (إضافة في النهاية)
  if (!f) { // لو فشل فتح الملف
    Serial.println("buffer open failed"); // طباعة رسالة خطأ على المونيتور
    return; // الخروج دون حفظ
  } // نهاية حالة فشل الفتح
  f.printf("%lu,%.1f,%.1f\n", ms, t, h); // كتابة سطر: الوقت,الحرارة,الرطوبة
  f.close(); // إغلاق الملف لحفظ البيانات فعليًا على الفلاش
  Serial.println("saved to buffer (offline)"); // إعلام المستخدم أن القراءة اتخزنت لعدم وجود نت
} // نهاية دالة الحفظ

// ---------- الإرسال ---------- // عنوان قسم دوال إرسال البيانات

bool sendLive(float t, float h) { // دالة ترسل قراءة حية واحدة للسيرفر وتُرجع نجح أم لا
  StaticJsonDocument<256> doc; // مستند JSON ثابت بسعة 256 بايت لبناء الرسالة
  doc["device_id"] = deviceId; // إضافة اسم الجهاز للرسالة
  doc["temp"] = serialized(String(t, 1)); // إضافة الحرارة برقم عشري واحد كقيمة خام
  doc["hum"]  = serialized(String(h, 1)); // إضافة الرطوبة برقم عشري واحد كقيمة خام

  String payload; // متغير نصي سيحمل الرسالة النهائية
  serializeJson(doc, payload); // تحويل مستند JSON إلى نص جاهز للإرسال

  http.begin(client, serverURL); // بدء الاتصال برابط القراءة الحية باستخدام العميل المشفر
  http.addHeader("Content-Type", "application/json"); // إخبار السيرفر أن الجسم بصيغة JSON
  http.setTimeout(10000); // مهلة الانتظار 10 ثواني قبل اعتبار الطلب فاشلًا

  int code = http.POST(payload); // إرسال الـ POST وتخزين كود استجابة السيرفر
  http.end(); // إنهاء الاتصال وتحرير الموارد

  if (code > 0 && code < 300) { // لو الكود موجب وأقل من 300 فهو نجاح (مثل 200 OK)
    Serial.printf("live sent: %s\n", payload.c_str()); // طباعة الرسالة المرسلة بنجاح
    return true; // إرجاع نجاح الإرسال
  } // نهاية حالة النجاح
  Serial.printf("live failed: %d\n", code); // طباعة كود الفشل لتشخيص المشكلة
  return false; // إرجاع فشل الإرسال
} // نهاية دالة الإرسال الحي

// يقرأ أول chunk من الملف // شرح وظيفة الدالة التالية
int readChunk(BufEntry* buf, int maxN) { // دالة تقرأ أول دفعة سطور من الملف لمصفوفة وترجع عددها
  File f = LittleFS.open(BUFFER_FILE, "r"); // فتح ملف التخزين للقراءة
  if (!f) return -1; // لا يوجد ملف = لا يوجد مخزن (قيمة مميزة -1)
  int n = 0; // عداد القراءات المقروءة في هذه الدفعة
  while (n < maxN && f.available()) { // اقرأ حتى تمتلئ الدفعة أو ينتهي الملف
    String line = f.readStringUntil('\n'); // قراءة سطر كامل حتى نهاية السطر
    line.trim(); // إزالة المسافات والرموز الزائدة من طرفي السطر
    if (line.length() == 0) continue; // تجاهل السطور الفارغة
    int c1 = line.indexOf(','); // موقع أول فاصلة (بعد الوقت)
    int c2 = line.indexOf(',', c1 + 1); // موقع ثاني فاصلة (بعد الحرارة)
    if (c1 < 0 || c2 < 0) continue; // سطر تالف (ناقص فواصل) فيُتجاهل
    buf[n].ms   = line.substring(0, c1).toInt(); // استخراج الوقت وتحويله لرقم
    buf[n].temp = line.substring(c1 + 1, c2).toFloat(); // استخراج الحرارة وتحويلها لرقم عشري
    buf[n].hum  = line.substring(c2 + 1).toFloat(); // استخراج الرطوبة وتحويلها لرقم عشري
    n++; // زيادة عداد الدفعة بعد قراءة سطر سليم
  } // نهاية حلقة قراءة الدفعة
  f.close(); // إغلاق الملف
  return n; // إرجاع عدد القراءات المقروءة
} // نهاية دالة قراءة الدفعة

bool postBatch(BufEntry* buf, int n) { // دالة ترسل دفعة قراءات مخزنة لرابط المزامنة
  DynamicJsonDocument doc(4096); // مستند JSON ديناميكي بسعة 4KB يتسع للدفعة
  doc["device_id"] = deviceId; // إضافة اسم الجهاز للرسالة
  JsonArray arr = doc.createNestedArray("readings"); // إنشاء مصفوفة readings داخل الرسالة
  unsigned long nowMs = millis(); // الوقت الحالي لحساب عمر كل قراءة مخزنة
  for (int i = 0; i < n; i++) { // المرور على كل قراءة في الدفعة
    JsonObject r = arr.createNestedObject(); // إنشاء كائن قراءة جديد داخل المصفوفة
    r["temp"] = serialized(String(buf[i].temp, 1)); // إضافة حرارة القراءة برقم عشري واحد
    r["hum"]  = serialized(String(buf[i].hum, 1)); // إضافة رطوبة القراءة برقم عشري واحد
    r["age"]  = (unsigned long)(nowMs - buf[i].ms); // عمر القراءة = الآن ناقص وقت تخزينها (السيرفر يحسب وقتها)
  } // نهاية حلقة بناء الدفعة

  String payload; // متغير نصي للرسالة النهائية
  serializeJson(doc, payload); // تحويل المستند إلى نص JSON

  http.begin(client, batchURL); // بدء الاتصال برابط المزامنة الجماعية
  http.addHeader("Content-Type", "application/json"); // تحديد نوع الجسم كـ JSON
  http.setTimeout(15000); // مهلة أطول (15 ثانية) لأن الدفعة أكبر من القراءة الواحدة

  int code = http.POST(payload); // إرسال الدفعة وتخزين كود الاستجابة
  http.end(); // إنهاء الاتصال

  if (code > 0 && code < 300) { // لو الاستجابة نجاح
    Serial.printf("flushed %d buffered readings\n", n); // طباعة عدد القراءات المتزامنة
    return true; // إرجاع نجاح المزامنة
  } // نهاية حالة النجاح
  Serial.printf("flush failed: %d\n", code); // طباعة كود الفشل
  return false; // إرجاع فشل المزامنة (لنُبقي الملف ونحاول لاحقًا)
} // نهاية دالة إرسال الدفعة

// يبعت كل المخزن دفعات، ويمسح اللي اتبعت // شرح وظيفة الدالة التالية
void flushBuffer() { // دالة تزامن كامل المخزن: ترسل دفعة دفعة وتمسح المُرسل
  BufEntry chunk[BATCH_CHUNK]; // مصفوفة مؤقتة تتسع لدفعة واحدة (30 قراءة)
  while (true) { // حلقة مستمرة حتى يفرغ الملف أو يفشل إرسال
    int n = readChunk(chunk, BATCH_CHUNK); // قراءة الدفعة التالية من الملف
    if (n <= 0) { // لو لا يوجد سطور (ملف فارغ أو غير موجود)
      LittleFS.remove(BUFFER_FILE); // حذف الملف لعدم الحاجة إليه
      return; // انتهت المزامنة
    } // نهاية حالة الفراغ
    if (!postBatch(chunk, n)) return; // فشل الإرسال — نحتفظ بالملف ونحاول لاحقًا
    dropOldestLines(n); // نجح الإرسال — امسح السطور المُرسلة من الملف
  } // نهاية حلقة المزامنة
} // نهاية دالة تفريغ المخزن

// ---------- setup / loop ---------- // عنوان قسم دالتي التشغيل الأساسيتين

void setup() { // دالة الإعداد وتعمل مرة واحدة عند تشغيل الجهاز
  Serial.begin(9600); // بدء التواصل التسلسلي بسرعة 9600 لعرض الرسائل
  delay(100); // انتظار بسيط لاستقرار المنفذ التسلسلي
  Serial.printf("\n\n=== ESP8266 buffered [%s] ===\n", deviceId); // طباعة اسم الجهاز في بداية التشغيل

  dht.begin(); // تهيئة حساس DHT وبدء قراءاته

  if (!LittleFS.begin()) { // محاولة تشغيل نظام ملفات الفلاش
    Serial.println("LittleFS mount failed, formatting..."); // إعلام المستخدم بفشل التشغيل وبدء التهيئة
    LittleFS.format(); // تهيئة (فورمات) مساحة الملفات
    LittleFS.begin(); // إعادة محاولة التشغيل بعد التهيئة
  } // نهاية معالجة فشل نظام الملفات
  int pending = countBufferLines(); // حساب القراءات المخزنة الباقية من قبل إعادة التشغيل
  if (pending > 0) Serial.printf("%d buffered readings kept from before reboot\n", pending); // إعلام المستخدم بعددها

  WiFi.persistent(true); // حفظ بيانات الواي فاي في الفلاش للاتصال التلقائي بعد الانقطاع
  WiFi.setAutoReconnect(true); // تفعيل إعادة الاتصال التلقائي عند سقوط الشبكة
  WiFi.mode(WIFI_STA); // ضبط الجهاز كعميل (Station) يتصل براوتر
  WiFi.begin(ssid, password); // بدء الاتصال باسم الشبكة وكلمة السر

  // محاولة اتصال محدودة — لو مفيش شبكة نكمل offline والتخزين شغال // شرح سبب المهلة التالية
  Serial.print("Connecting WiFi"); // طباعة بداية محاولة الاتصال
  unsigned long w0 = millis(); // تسجيل وقت بداية المحاولة
  while (WiFi.status() != WL_CONNECTED && millis() - w0 < 15000) { // حاول لمدة 15 ثانية كحد أقصى
    delay(500); // انتظار نصف ثانية بين كل فحص
    Serial.print("."); // طباعة نقطة لتوضيح أن المحاولة مستمرة
  } // نهاية حلقة انتظار الاتصال
  Serial.println(WiFi.status() == WL_CONNECTED ? "\nConnected!" : "\nOffline mode - buffering"); // إعلان النتيجة: متصل أم وضع تخزين

  client.setInsecure(); // قبول شهادة HTTPS دون تحقق (تبسيط مناسب لهذا المشروع)
  client.setTimeout(10000); // مهلة 10 ثواني لأي عملية اتصال قبل اعتبارها فاشلة
} // نهاية دالة الإعداد

void loop() { // الدالة الرئيسية وتتكرر باستمرار طوال تشغيل الجهاز
  if (millis() - lastSend < interval) return; // لو لم تمر 5 ثواني بعد اخرج وانتظر
  lastSend = millis(); // تحديث وقت آخر قراءة بالوقت الحالي

  float h = dht.readHumidity(); // قراءة نسبة الرطوبة من الحساس
  float t = dht.readTemperature(); // قراءة درجة الحرارة من الحساس

  if (isnan(h) || isnan(t)) { // لو أي قراءة غير صالحة (فشل الحساس)
    Serial.println("DHT read failed"); // طباعة رسالة فشل القراءة
    return; // تجاهل هذه الدورة دون إرسال أو تخزين
  } // نهاية معالجة فشل الحساس
  Serial.printf("%.1f C | %.1f %%\n", t, h); // طباعة القراءتين على المونيتور للمتابعة

  if (WiFi.status() != WL_CONNECTED) { // لو الواي فاي غير متصل الآن
    Serial.println("offline -> buffering"); // إعلام المستخدم بالتحويل لوضع التخزين
    bufferAppend(millis(), t, h); // حفظ القراءة في ملف التخزين مع وقتها
    WiFi.reconnect(); // محاولة إعادة الاتصال بالشبكة
    return; // انتهاء هذه الدورة
  } // نهاية حالة عدم الاتصال

  if (sendLive(t, h)) { // لو الواي فاي متصل: أرسل القراءة حية واختبر نجاحها
    flushBuffer(); // نجح الإرسال الحي — ابعت المخزن القديم بعده
  } else { // لو فشل الإرسال الحي (السيرفر واقع مثلًا)
    bufferAppend(millis(), t, h); // السيرفر واقع — خزن القراءة لترسل لاحقًا
  } // نهاية معالجة نتيجة الإرسال الحي
} // نهاية الدالة الرئيسية
