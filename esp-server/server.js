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
  const { temp, hum, device_id } = req.body;

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
    online: true
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
    notifyTelegram(`${device_id} رجع متصل`);
  }

  broadcast('data', devices[device_id]);
  res.json({ ok: true, serverTime: Date.now() });
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
      notifyTelegram(
        `${d.device_id} فصل!\nآخر إشارة: ${new Date(d.lastSeen).toLocaleTimeString()}`
      );
    }
  });
}, CHECK_INTERVAL);

// ===== تيليجرام =====
const TG_TOKEN = process.env.TG_TOKEN;
const TG_CHAT  = process.env.TG_CHAT;

async function notifyTelegram(msg) {
  if (!TG_TOKEN || !TG_CHAT) return;
  try {
    await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: TG_CHAT, text: msg })
    });
  } catch (e) {
    console.error('Telegram error:', e.message);
  }
}

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
