import 'package:flutter/material.dart';
import '../models/device_state.dart';
import '../theme/app_theme.dart';

/// Detail view for one device — live via the shared ValueNotifier.
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
      body: Stack(
        children: [
          const Backdrop(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 520),
                        child: ValueListenableBuilder<
                            Map<String, DeviceState>>(
                          valueListenable: devicesNotifier,
                          builder: (ctx, devices, _) {
                            final d = devices[deviceId];
                            if (d == null) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 80),
                                child: Text(
                                  'No data for this device',
                                  style: TextStyle(
                                      color: AppColors.muted),
                                ),
                              );
                            }
                            return _buildContent(d);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppColors.indigo),
            style: IconButton.styleFrom(
              backgroundColor:
                  Colors.white.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const LogoTile(size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              deviceId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(DeviceState d) {
    final online = d.online;
    final statusColor = online ? AppColors.green : AppColors.red;

    return Column(
      children: [
        GradientCard(
          online: online,
          padding:
              const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
          child: Column(
            children: [
              _StatusRing(online: online),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.25),
                            end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                ),
                child: Text(
                  online ? 'ONLINE' : 'OFFLINE',
                  key: ValueKey(online),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (d.lastSeen > 0)
                Text(
                  'Last signal ${_formatTime(d.lastSeen)}',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 13.5),
                ),
              if (!online && d.lastSeen > 0) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    'Stopped ${_formatDuration(DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(d.lastSeen)))} ago',
                    style: const TextStyle(
                      color: AppColors.red,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (online)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt,
                          size: 14, color: AppColors.green),
                      SizedBox(width: 6),
                      Text(
                        'Streaming live',
                        style: TextStyle(
                          color: AppColors.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _gauge(
                icon: Icons.thermostat,
                label: 'Temperature',
                value: d.temp,
                unit: '°C',
                fraction: d.temp == null
                    ? 0
                    : (d.temp! / 50).clamp(0.0, 1.0),
                color: AppColors.orange,
                deepColor: AppColors.orangeDeep,
                alert: d.isTempOutOfRange,
                rangeLabel: 'Normal 28–32°C',
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _gauge(
                icon: Icons.water_drop,
                label: 'Humidity',
                value: d.hum,
                unit: '%',
                fraction:
                    d.hum == null ? 0 : (d.hum! / 100).clamp(0.0, 1.0),
                color: AppColors.cyan,
                deepColor: const Color(0xFF0EA5E9),
                alert: d.isHumOutOfRange,
                rangeLabel: 'Normal 60–70%',
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        GradientCard(
          online: online,
          child: Column(
            children: [
              _infoRow(Icons.memory_outlined, 'Device', deviceId),
              const Divider(
                  color: Colors.white10, height: 22),
              _infoRow(Icons.tune_outlined, 'Ranges',
                  '28–32°C  •  60–70%'),
              if (d.backfilled > 0) ...[
                const Divider(
                    color: Colors.white10, height: 22),
                _infoRow(Icons.cloud_done_outlined, 'Synced',
                    '${d.backfilled} buffered'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 17, color: AppColors.faint),
        const SizedBox(width: 10),
        Text(label,
            style: const TextStyle(
                color: AppColors.faint, fontSize: 13)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _gauge({
    required IconData icon,
    required String label,
    required double? value,
    required String unit,
    required double fraction,
    required Color color,
    required Color deepColor,
    required bool alert,
    required String rangeLabel,
  }) {
    final glow = alert ? AppColors.red : color;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: alert
              ? AppColors.red.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.08),
          width: alert ? 1.6 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: alert ? 0.3 : 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              if (alert)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: const Text(
                    'ALERT',
                    style: TextStyle(
                      color: AppColors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                        begin: const Offset(0, 0.3), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            ),
            child: Row(
              key: ValueKey(value?.toStringAsFixed(1) ?? '--'),
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value?.toStringAsFixed(1) ?? '--',
                    style: TextStyle(
                      color: alert ? AppColors.red : Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      fontFeatures: const [
                        FontFeature.tabularFigures()
                      ],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(unit,
                    style: TextStyle(color: color, fontSize: 14)),
              ],
            ),
          ),
          Text(label,
              style: const TextStyle(
                  color: AppColors.faint, fontSize: 12)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, constraints) {
              return Container(
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.easeOutCubic,
                      width: constraints.maxWidth * fraction,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: [color, deepColor]),
                        borderRadius: BorderRadius.circular(50),
                        boxShadow: [
                          BoxShadow(
                            color:
                                color.withValues(alpha: 0.55),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(rangeLabel,
              style: TextStyle(
                color: alert ? AppColors.red : AppColors.faint,
                fontSize: 11,
              )),
        ],
      ),
    );
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

/// Large glowing status ring with a wifi icon in the middle.
class _StatusRing extends StatefulWidget {
  final bool online;
  const _StatusRing({required this.online});

  @override
  State<_StatusRing> createState() => _StatusRingState();
}

class _StatusRingState extends State<_StatusRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.online) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _StatusRing old) {
    super.didUpdateWidget(old);
    if (widget.online && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.online && _ctrl.isAnimating) {
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
    final color = widget.online ? AppColors.green : AppColors.red;
    return ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.04).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Container(
        width: 118,
        height: 118,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(
              color: color.withValues(alpha: 0.55), width: 2.5),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 34,
            ),
          ],
        ),
        child: Icon(
          widget.online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: color,
          size: 52,
        ),
      ),
    );
  }
}
