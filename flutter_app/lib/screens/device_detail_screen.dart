import 'package:flutter/material.dart';
import '../models/device_state.dart';

/// شاشة تفاصيل جهاز واحد — تتحدث لحظيًا عبر نفس الـ ValueNotifier
/// المشترك مع شاشة القائمة (بدون polling).
class DeviceDetailScreen extends StatelessWidget {
  final String deviceId;
  final ValueNotifier<Map<String, DeviceState>> devicesNotifier;

  const DeviceDetailScreen({
    super.key,
    required this.deviceId,
    required this.devicesNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFA5B4FC)),
        title: Text(
          deviceId,
          style: const TextStyle(color: Color(0xFFA5B4FC), fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: ValueListenableBuilder<Map<String, DeviceState>>(
                valueListenable: devicesNotifier,
                builder: (ctx, devices, _) {
                  final d = devices[deviceId];
                  if (d == null) {
                    return const Text(
                      'لا توجد بيانات',
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    );
                  }
                  return _buildContent(d);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(DeviceState d) {
    final online = d.online;
    final color = online ? const Color(0xFF4ADE80) : const Color(0xFFF87171);
    final bg = online ? const Color(0x2622C55E) : const Color(0x26EF4444);
    final border = online ? const Color(0x4D22C55E) : const Color(0x4DEF4444);

    final offlineFor = !online && d.lastSeen > 0
        ? DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(d.lastSeen))
        : Duration.zero;

    return Column(
      children: [
        _card(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  color: bg,
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: color, size: 14),
                    const SizedBox(width: 12),
                    Text(
                      online ? 'متصل' : 'معطل',
                      style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (d.lastSeen > 0) ...[
                const SizedBox(height: 16),
                Text(
                  'آخر إشارة: ${_formatTime(d.lastSeen)}',
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 14),
                ),
              ],
              if (!online && d.lastSeen > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'متوقف من ${_formatDuration(offlineFor)}',
                  style: const TextStyle(
                    color: Color(0xFFF87171),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _card(
          child: Row(
            children: [
              Expanded(
                child: _readingBox(
                  icon: '🌡️',
                  value: d.temp?.toStringAsFixed(1) ?? '--',
                  label: 'درجة الحرارة (°C)',
                  valueColor: const Color(0xFFFB923C),
                  bg: const Color(0x1AFB923C),
                  alert: d.isTempOutOfRange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _readingBox(
                  icon: '💧',
                  value: d.hum?.toStringAsFixed(1) ?? '--',
                  label: 'الرطوبة (%)',
                  valueColor: const Color(0xFF38BDF8),
                  bg: const Color(0x1A38BDF8),
                  alert: d.isHumOutOfRange,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _readingBox({
    required String icon,
    required String value,
    required String label,
    required Color valueColor,
    required Color bg,
    required bool alert,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: alert
            ? Border.all(color: const Color(0xFFEF4444), width: 2)
            : null,
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0x0FFFFFFF),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
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
