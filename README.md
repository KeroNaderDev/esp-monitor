# ESP Multi-Device Monitor 📡

مرجع كامل لمشروع مراقبة أجهزة ESP8266 + DHT22 — يدعم أجهزة متعددة.

## المكونات

| المجلد | الوظيفة |
|---|---|
| `firmware/` | كود ESP8266 (نفس الكود لكل الأجهزة، الفرق في `deviceId`) |
| `esp-server/` | سيرفر Node + Express (Railway) مع SSE |
| `flutter_app/` | تطبيق Flutter لعرض كل الأجهزة لحظيًا |

## الفكرة

- كل ESP له `device_id` فريد (مثال: `esp01_room`, `esp02_kitchen`) ويبعت POST كل 5 ثواني لـ `/api/data`
- السيرفر يخزن Map للأجهزة، ويفحص offline لكل جهاز مستقل (12 ثانية)
- SSE يبعت أحداث: `init`, `data`, `status`, `device_added`, `device_removed`
- Flutter يعرض قائمة الأجهزة + تفاصيل كل جهاز + إشعار محلي مستقل لكل جهاز
- Telegram (اختياري عبر `TG_TOKEN` + `TG_CHAT`)

## التشغيل

### 1. السيرفر (Railway)

```bash
cd esp-server
npm install
npm start
```

1. ارفع المجلد على GitHub
2. railway.app → New Project → Deploy from GitHub
3. Settings → Networking → Generate Domain
4. (اختياري) Variables: `TG_TOKEN`, `TG_CHAT`

API:
- `POST /api/data` → `{ device_id, temp, hum }`
- `GET /api/stream` → SSE
- `GET /api/devices`
- `GET /api/devices/:id`
- `DELETE /api/devices/:id`
- `GET /health`

### 2. كل ESP

1. غيّر `deviceId` لاسم فريد
2. غيّر `serverURL` بالرابط
3. ارفع الكود من `firmware/esp8266_dht22.ino`

المكتبات المطلوبة في Arduino IDE:
- ESP8266WiFi / ESP8266HTTPClient
- DHT sensor library
- ArduinoJson

### 3. Flutter

```bash
flutter create esp_monitor
cd esp_monitor
# انسخ محتويات flutter_app/ فوق المشروع
flutter pub get
flutter run
```

- غيّر `serverUrl` في `lib/main.dart`
- أضف الأذونات من `android_permissions_snippet.xml` في `AndroidManifest.xml`

> شاشة التفاصيل مشتركة مع القائمة عبر `ValueNotifier<Map<String, DeviceState>>`
> فالتحديث لحظي بدون polling.

## إضافة جهاز جديد

أول POST من `device_id` جديد → يظهر تلقائيًا في التطبيق. لا حاجة لتعديل السيرفر أو التطبيق.
