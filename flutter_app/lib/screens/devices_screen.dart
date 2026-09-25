import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_state.dart';
import '../services/sse_service.dart';
import '../services/notification_service.dart';
import '../services/prefs_service.dart';
import '../services/audio_service.dart';
import '../theme/app_theme.dart';
import 'device_detail_screen.dart';
import 'device_settings_screen.dart';

class DevicesScreen extends StatefulWidget {
  final String serverUrl;
  const DevicesScreen({super.key, required this.serverUrl});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late SseService _sse;

  // Single source of truth, shared with the detail screen.
  final ValueNotifier<Map<String, DeviceState>> _devicesNotifier =
      ValueNotifier({});
  final Map<String, bool> _previousOnline = {};
  final Map<String, bool> _wasOutOfRange = {};
  final Map<String, int> _lastAlertMs = {};
  static const int _repeatIntervalMs = 10 * 60 * 1000;

  bool _serverConnected = false;
  Timer? _ticker;

  void _updateDevices(void Function(Map<String, DeviceState> m) fn) {
    final m = Map<String, DeviceState>.from(_devicesNotifier.value);
    fn(m);
    _devicesNotifier.value = m;
  }

  @override
  void initState() {
    super.initState();
    NotificationService.init();

    _sse = SseService(
      baseUrl: widget.serverUrl,
      onInit: (list) {
        _updateDevices((m) {
          for (final d in list) {
            m[d.deviceId] = d;
            _previousOnline[d.deviceId] = d.online;
            _checkThresholds(d);
          }
        });
      },
      onData: (d) {
        _updateDevices((m) => m[d.deviceId] = d);
        _checkThresholds(d);
      },
      onStatus: (id, online, lastSeen) {
        final prev = _previousOnline[id];
        if (prev != null && prev != online) {
          _handleStatusChange(id, online);
        }
        _updateDevices((m) {
          final existing = m[id];
          if (existing != null) {
            m[id] = existing.copyWith(online: online, lastSeen: lastSeen);
          } else {
            m[id] = DeviceState(
              deviceId: id,
              temp: null,
              hum: null,
              lastSeen: lastSeen,
              online: online,
            );
          }
        });
        _previousOnline[id] = online;
      },
      onDeviceAdded: (d) {
        _updateDevices((m) => m[d.deviceId] = d);
        _previousOnline[d.deviceId] = d.online;
      },
      onDeviceRemoved: (id) {
        _updateDevices((m) => m.remove(id));
        _previousOnline.remove(id);
      },
      onConnectionChange: (c) {
        setState(() => _serverConnected = c);
      },
    );

    _sse.connect();

    // Refresh "stopped X ago" labels every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _handleStatusChange(String id, bool online) {
    final prefs = PrefsService.get(id);
    if (online && !prefs.notifyOnline) return;
    if (!online && !prefs.notifyOffline) return;
    NotificationService.alert(online: online);
    NotificationService.show(
      title: online ? '$id is back online' : '$id went offline',
      body: online
          ? 'The device is sending data again'
          : 'The device stopped sending data!',
    );
  }

  /// Fires the loud alarm when a reading breaks the user's limits.
  /// Edge-triggered (entry only) + optional 10-minute repeat.
  void _checkThresholds(DeviceState d) {
    if (d.temp == null && d.hum == null) return;
    final prefs = PrefsService.get(d.deviceId);
    if (!prefs.notifyThreshold) {
      _wasOutOfRange[d.deviceId] = false;
      return;
    }
    final out = PrefsService.tempOut(d.deviceId, d.temp) ||
        PrefsService.humOut(d.deviceId, d.hum);
    final was = _wasOutOfRange[d.deviceId] ?? false;
    _wasOutOfRange[d.deviceId] = out;
    if (!out) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastAlertMs[d.deviceId] ?? 0;
    final entered = !was;
    final repeatDue =
        prefs.repeatAlarm && now - last > _repeatIntervalMs;
    if (entered || repeatDue) {
      _lastAlertMs[d.deviceId] = now;
      _fireThresholdAlarm(d, prefs);
    }
  }

  void _fireThresholdAlarm(DeviceState d, DevicePrefs prefs) {
    final parts = <String>[];
    if (PrefsService.tempOut(d.deviceId, d.temp)) {
      parts.add(
          'Temperature ${d.temp!.toStringAsFixed(1)}°C outside ${PrefsService.fmt(prefs.minTemp)}–${PrefsService.fmt(prefs.maxTemp)}°C');
    }
    if (PrefsService.humOut(d.deviceId, d.hum)) {
      parts.add(
          'Humidity ${d.hum!.toStringAsFixed(1)}% outside ${PrefsService.fmt(prefs.minHum)}–${PrefsService.fmt(prefs.maxHum)}%');
    }
    NotificationService.thresholdAlarm(
      title: 'Limit exceeded: ${d.deviceId}',
      body: parts.join(' • '),
      useSound: prefs.alarmSound,
      vibrate: prefs.vibration,
    );
    if (prefs.alarmSound) AudioService.playAlarm();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sse.dispose();
    _devicesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Backdrop(),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildList()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Row(
        children: [
          const LogoTile(),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ESP Monitor',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Live sensor network',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<Map<String, DeviceState>>(
            valueListenable: _devicesNotifier,
            builder: (ctx, devices, _) {
              final list = devices.values.toList();
              final online = list.where((d) => d.online).length;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulseDot(
                      color: _serverConnected
                          ? AppColors.green
                          : AppColors.red,
                      animate: _serverConnected,
                      size: 8,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$online/${list.length}',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      color: AppColors.indigo,
      backgroundColor: AppColors.card,
      onRefresh: () async {
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: ValueListenableBuilder<Map<String, DeviceState>>(
        valueListenable: _devicesNotifier,
        builder: (ctx, devices, _) {
          return ValueListenableBuilder<int>(
            valueListenable: PrefsService.changes,
            builder: (ctx, _, __) {
              final list = devices.values.toList()
                ..sort((a, b) => a.deviceId.compareTo(b.deviceId));
              if (list.isEmpty) return _buildEmptyState();
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                itemCount: list.length,
                itemBuilder: (c, i) => Entrance(
                  key: ValueKey('card-${list[i].deviceId}'),
                  index: i,
                  child: _buildDeviceCard(list[i]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: [
        const SizedBox(height: 110),
        Center(
          child: Column(
            children: [
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.indigo.withValues(alpha: 0.12),
                  border: Border.all(
                      color: AppColors.indigo.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.sensors_outlined,
                  color: AppColors.indigo,
                  size: 44,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'No devices yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Waiting for the first reading from an ESP…',
                style: TextStyle(color: AppColors.faint, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(DeviceState d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DeviceDetailScreen(
                deviceId: d.deviceId,
                devicesNotifier: _devicesNotifier,
              ),
            ),
          );
        },
        child: GradientCard(
          online: d.online,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PulseDot(
                    color: d.online ? AppColors.green : AppColors.red,
                    animate: d.online,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      d.deviceId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  StatusPill(online: d.online),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _metricTile(
                      icon: Icons.thermostat,
                      value: d.temp?.toStringAsFixed(1) ?? '--',
                      unit: '°C',
                      label: 'Temperature',
                      color: AppColors.orange,
                      alert: PrefsService.tempOut(d.deviceId, d.temp),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _metricTile(
                      icon: Icons.water_drop,
                      value: d.hum?.toStringAsFixed(1) ?? '--',
                      unit: '%',
                      label: 'Humidity',
                      color: AppColors.cyan,
                      alert: PrefsService.humOut(d.deviceId, d.hum),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    d.online ? Icons.bolt : Icons.timer_off_outlined,
                    size: 14,
                    color: d.online ? AppColors.faint : AppColors.red,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _statusLine(d),
                      style: TextStyle(
                        color: d.online ? AppColors.muted : AppColors.red,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openSettings(d.deviceId),
                    icon: const Icon(Icons.tune_rounded,
                        size: 19, color: AppColors.faint),
                    tooltip: 'Limits & alerts',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.faint),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String value,
    required String unit,
    required String label,
    required Color color,
    required bool alert,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      decoration: BoxDecoration(
        color: alert
            ? AppColors.red.withValues(alpha: 0.12)
            : color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: alert
            ? Border.all(color: AppColors.red.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: color,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [
                            FontFeature.tabularFigures()
                          ],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Text(unit,
                        style: TextStyle(color: color, fontSize: 12)),
                  ],
                ),
                Text(
                  alert ? '$label • out of range' : label,
                  style: TextStyle(
                    color: alert ? AppColors.red : AppColors.faint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings(String deviceId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceSettingsScreen(deviceId: deviceId),
      ),
    );
  }

  String _statusLine(DeviceState d) {
    if (d.lastSeen == 0) return 'Waiting for data…';
    if (d.online) return 'Last signal ${_formatTime(d.lastSeen)}';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(d.lastSeen));
    return 'Stopped ${_formatDuration(diff)} ago';
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }
}
