import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_state.dart';
import '../services/sse_service.dart';
import '../services/notification_service.dart';
import 'device_detail_screen.dart';

class DevicesScreen extends StatefulWidget {
  final String serverUrl;
  const DevicesScreen({super.key, required this.serverUrl});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late SseService _sse;

  // مصدر الحقيقة الوحيد — مشترك مع شاشة التفاصيل
  final ValueNotifier<Map<String, DeviceState>> _devicesNotifier =
      ValueNotifier({});
  final Map<String, bool> _previousOnline = {};

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
          }
        });
      },
      onData: (d) {
        _updateDevices((m) => m[d.deviceId] = d);
      },
      onStatus: (id, online, lastSeen) {
        final prev = _previousOnline[id];
        if (prev != null && prev != online) {
          _handleStatusChange(id, online);
        }
        _updateDevices((m) {
          final existing = m[id];
          if (existing != null) {
            m[id] =
                existing.copyWith(online: online, lastSeen: lastSeen);
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

    // لتحديث "متوقف من X" كل ثانية
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _handleStatusChange(String id, bool online) {
    NotificationService.alert(online: online);
    if (online) {
      NotificationService.show(
        title: '$id متصل',
        body: 'الجهاز رجع يبعت بيانات',
      );
    } else {
      NotificationService.show(
        title: '$id معطل',
        body: 'الجهاز توقف عن الإرسال!',
      );
    }
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
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'ESP Monitor',
          style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 20),
        ),
        actions: [
          ValueListenableBuilder<Map<String, DeviceState>>(
            valueListenable: _devicesNotifier,
            builder: (ctx, devices, _) {
              final list = devices.values.toList();
              final onlineCount = list.where((d) => d.online).length;
              return Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: _serverConnected
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFEF4444),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$onlineCount/${list.length}',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFFA5B4FC),
        backgroundColor: const Color(0xFF2A2A3E),
        onRefresh: () async {
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: ValueListenableBuilder<Map<String, DeviceState>>(
          valueListenable: _devicesNotifier,
          builder: (ctx, devices, _) {
            final list = devices.values.toList()
              ..sort((a, b) => a.deviceId.compareTo(b.deviceId));
            if (list.isEmpty) return _buildEmptyState();
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (c, i) => _buildDeviceCard(list[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Text('📭', style: TextStyle(fontSize: 60)),
              SizedBox(height: 16),
              Text(
                'لا توجد أجهزة متصلة',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'في انتظار أول قراءة من ESP...',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(DeviceState d) {
    final color = d.online ? const Color(0xFF4ADE80) : const Color(0xFFF87171);
    final bg = d.online ? const Color(0x2622C55E) : const Color(0x26EF4444);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
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
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0x0FFFFFFF),
              border: Border.all(color: const Color(0x1AFFFFFF)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          _PulsingDot(color: color, animate: d.online),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              d.deviceId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        d.online ? 'متصل' : 'معطل',
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _miniReading(
                        '🌡️',
                        d.temp?.toStringAsFixed(1) ?? '--',
                        '°C',
                        const Color(0xFFFB923C),
                        d.isTempOutOfRange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _miniReading(
                        '💧',
                        d.hum?.toStringAsFixed(1) ?? '--',
                        '%',
                        const Color(0xFF38BDF8),
                        d.isHumOutOfRange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.access_time,
                        size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _statusLine(d),
                        style: TextStyle(
                          color: d.online
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFFF87171),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_left,
                        size: 18, color: Color(0xFF64748B)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniReading(
    String icon,
    String value,
    String unit,
    Color color,
    bool alert,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color:
            alert ? const Color(0x26EF4444) : const Color(0x0FFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: alert
            ? Border.all(color: const Color(0xFFEF4444), width: 1)
            : null,
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 2),
          Text(unit, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }

  String _statusLine(DeviceState d) {
    if (d.lastSeen == 0) return 'في انتظار البيانات...';
    if (d.online) return 'آخر إشارة: ${_formatTime(d.lastSeen)}';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(d.lastSeen));
    return 'متوقف من ${_formatDuration(diff)}';
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes > 0) return '${d.inMinutes} د ${d.inSeconds % 60} ث';
    return '${d.inSeconds} ث';
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool animate;
  const _PulsingDot({required this.color, required this.animate});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.animate) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animate) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_ctrl),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 1.2).animate(_ctrl),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
