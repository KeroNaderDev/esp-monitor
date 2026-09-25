import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device limits + notification preferences, stored locally.
class DevicePrefs {
  double minTemp;
  double maxTemp;
  double minHum;
  double maxHum;
  bool notifyThreshold;
  bool notifyOffline;
  bool notifyOnline;
  bool alarmSound;
  bool vibration;
  bool repeatAlarm;

  DevicePrefs({
    this.minTemp = 28,
    this.maxTemp = 32,
    this.minHum = 60,
    this.maxHum = 70,
    this.notifyThreshold = true,
    this.notifyOffline = true,
    this.notifyOnline = true,
    this.alarmSound = true,
    this.vibration = true,
    this.repeatAlarm = false,
  });

  factory DevicePrefs.fromJson(Map<String, dynamic> j) {
    num n(dynamic v, num fb) => (v ?? fb) as num;
    return DevicePrefs(
      minTemp: n(j['minTemp'], 28).toDouble(),
      maxTemp: n(j['maxTemp'], 32).toDouble(),
      minHum: n(j['minHum'], 60).toDouble(),
      maxHum: n(j['maxHum'], 70).toDouble(),
      notifyThreshold: j['notifyThreshold'] ?? true,
      notifyOffline: j['notifyOffline'] ?? true,
      notifyOnline: j['notifyOnline'] ?? true,
      alarmSound: j['alarmSound'] ?? true,
      vibration: j['vibration'] ?? true,
      repeatAlarm: j['repeatAlarm'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'minTemp': minTemp,
        'maxTemp': maxTemp,
        'minHum': minHum,
        'maxHum': maxHum,
        'notifyThreshold': notifyThreshold,
        'notifyOffline': notifyOffline,
        'notifyOnline': notifyOnline,
        'alarmSound': alarmSound,
        'vibration': vibration,
        'repeatAlarm': repeatAlarm,
      };
}

class PrefsService {
  static SharedPreferences? _sp;
  static final Map<String, DevicePrefs> _cache = {};

  /// Bump to refresh any UI listening for preference changes.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  static String _key(String id) => 'prefs:$id';

  static DevicePrefs get(String id) {
    final cached = _cache[id];
    if (cached != null) return cached;
    DevicePrefs p;
    try {
      final raw = _sp?.getString(_key(id));
      p = raw == null
          ? DevicePrefs()
          : DevicePrefs.fromJson(
              jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      p = DevicePrefs();
    }
    // Guard against swapped min/max from older saves.
    if (p.minTemp > p.maxTemp) {
      final t = p.minTemp;
      p.minTemp = p.maxTemp;
      p.maxTemp = t;
    }
    if (p.minHum > p.maxHum) {
      final h = p.minHum;
      p.minHum = p.maxHum;
      p.maxHum = h;
    }
    _cache[id] = p;
    return p;
  }

  static Future<void> save(String id, DevicePrefs p) async {
    _cache[id] = p;
    await _sp?.setString(_key(id), jsonEncode(p.toJson()));
    changes.value++;
  }

  static Future<void> reset(String id) => save(id, DevicePrefs());

  static bool tempOut(String id, double? t) {
    if (t == null) return false;
    final p = get(id);
    return t > p.maxTemp || t < p.minTemp;
  }

  static bool humOut(String id, double? h) {
    if (h == null) return false;
    final p = get(id);
    return h > p.maxHum || h < p.minHum;
  }

  static String fmt(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
}
