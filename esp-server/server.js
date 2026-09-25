const express = require('express');
const cors = require('cors');
const path = require('path');

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ===== الإعدادات =====
const OFFLINE_THRESHOLD = 12000; // 12 ثانية
const CHECK_INTERVAL    = 2000;

// ===== تخزين الأجهزة =====
// { "esp01_room": { device_id, temp, hum, lastSeen, online }, ... }
let devices = {};
let sseClients = [];

function broadcast(event, data) {
  const payload = `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
  sseClients = sseClients.filter(c => {
    try {
      c.res.write(payload);
      return true;
    } catch (e) {
      return false;
    }
  });
}

// ===== استقبال من ESP =====
app.post('/api/data', (req, res) => {
  const { temp, hum, device_id, ts } = req.body;

  if (temp === undefined || hum === undefined || !device_id) {
    return res.status(400).json({ error: 'temp, hum, device_id required' });
  }

  const existing = devices[device_id];
  const wasOnline = existing ? existing.online : false;

  devices[device_id] = {
    device_id,
    temp: parseFloat(temp),
    hum:  parseFloat(hum),
    lastSeen: Date.now(),
    online: true,
    ts: ts ? parseInt(ts) || null : null
  };

  console.log(`[${new Date().toLocaleTimeString()}] ${device_id} -> ${temp}C / ${hum}%`);

  if (!existing) {
    console.log(`New device: ${device_id}`);
    broadcast('device_added', devices[device_id]);
  } else if (!wasOnline) {
    console.log(`${device_id} back ONLINE`);
    broadcast('status', {
      device_id,
      online: true,
      timestamp: Date.now(),
      lastSeen: devices[device_id].lastSeen
    });
  }

  broadcast('data', devices[device_id]);
  res.json({ ok: true, serverTime: Date.now() });
});

// ===== استقبال قراءات مخزنة (offline buffer من ESP) =====
// Body: { device_id, readings: [{ temp, hum, age?, ts? }, ...] }
// age = عمر القراءة بالمللي ثانية وقت الإرسال (السيرفر يحسب ts = now - age)
// ts  = وقت القراءة المباشر (ms epoch) — بديل اختياري.
// lastSeen تبقى دائمًا وقت الوصول (الجهاز متصل الآن)، و ts للسجل فقط.
app.post('/api/data/batch', (req, res) => {
  const { device_id, readings } = req.body;

  if (!device_id || !Array.isArray(readings) || readings.length === 0) {
    return res.status(400).json({ error: 'device_id and non-empty readings[] required' });
  }
  if (readings.length > 500) {
    return res.status(400).json({ error: 'max 500 readings per batch' });
  }

  const now = Date.now();
  const valid = readings
    .filter(r => r && r.temp !== undefined && r.hum !== undefined)
    .map(r => ({
      temp: parseFloat(r.temp),
      hum: parseFloat(r.hum),
      ts: r.ts
        ? parseInt(r.ts) || null
        : (r.age !== undefined && r.age !== null ? now - parseInt(r.age) : null)
    }))
    .filter(r => !isNaN(r.temp) && !isNaN(r.hum));

  if (!valid.length) {
    return res.status(400).json({ error: 'no valid readings' });
  }

  const existing = devices[device_id];
  const wasOnline = existing ? existing.online : false;
  const latest = valid[valid.length - 1];

  devices[device_id] = {
    device_id,
    temp: latest.temp,
    hum: latest.hum,
    lastSeen: now,
    online: true,
    backfilled: ((existing && existing.backfilled) || 0) + valid.length
  };

  const oldest = valid[0].ts ? new Date(valid[0].ts).toLocaleTimeString() : '?';
  console.log(`[batch] ${device_id}: +${valid.length} buffered readings (oldest: ${oldest})`);

  if (!existing) {
    console.log(`New device: ${device_id}`);
    broadcast('device_added', devices[device_id]);
  } else if (!wasOnline) {
    console.log(`${device_id} back ONLINE (+${valid.length} buffered)`);
    broadcast('status', {
      device_id,
      online: true,
      timestamp: now,
      lastSeen: devices[device_id].lastSeen
    });
  }

  broadcast('data', devices[device_id]);
  res.json({ ok: true, received: valid.length, serverTime: now });
});

// ===== SSE =====
app.get('/api/stream', (req, res) => {
  res.set({
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
    'X-Accel-Buffering': 'no'
  });
  res.flushHeaders();

  // ابعت كل الأجهزة الحالية فورًا
  res.write(`event: init\ndata: ${JSON.stringify(Object.values(devices))}\n\n`);

  const client = { res };
  sseClients.push(client);
  console.log(`SSE clients: ${sseClients.length}`);

  req.on('close', () => {
    sseClients = sseClients.filter(c => c !== client);
    console.log(`SSE clients: ${sseClients.length}`);
  });
});

// ===== كل الأجهزة =====
app.get('/api/devices', (req, res) => {
  const now = Date.now();
  const list = Object.values(devices).map(d => ({
    ...d,
    online: (now - d.lastSeen) < OFFLINE_THRESHOLD
  }));
  res.json({ count: list.length, devices: list, serverTime: now });
});

// ===== جهاز واحد =====
app.get('/api/devices/:id', (req, res) => {
  const d = devices[req.params.id];
  if (!d) return res.status(404).json({ error: 'not found' });
  const now = Date.now();
  res.json({
    ...d,
    online: (now - d.lastSeen) < OFFLINE_THRESHOLD,
    serverTime: now
  });
});

// ===== حذف جهاز =====
app.delete('/api/devices/:id', (req, res) => {
  if (!devices[req.params.id]) {
    return res.status(404).json({ error: 'not found' });
  }
  delete devices[req.params.id];
  broadcast('device_removed', { device_id: req.params.id });
  res.json({ ok: true });
});

// ===== فحص Offline لكل الأجهزة =====
setInterval(() => {
  const now = Date.now();
  Object.values(devices).forEach(d => {
    if (d.online && now - d.lastSeen > OFFLINE_THRESHOLD) {
      d.online = false;
      console.log(`${d.device_id} went OFFLINE`);
      broadcast('status', {
        device_id: d.device_id,
        online: false,
        timestamp: now,
        lastSeen: d.lastSeen
      });
    }
  });
}, CHECK_INTERVAL);

// ===== Health =====
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    devicesCount: Object.keys(devices).length
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
