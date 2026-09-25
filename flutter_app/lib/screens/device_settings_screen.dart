import 'package:flutter/material.dart';
import '../services/prefs_service.dart';
import '../services/audio_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Per-device limits + notification customization.
class DeviceSettingsScreen extends StatefulWidget {
  final String deviceId;
  const DeviceSettingsScreen({super.key, required this.deviceId});

  @override
  State<DeviceSettingsScreen> createState() =>
      _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  late DevicePrefs _p;

  @override
  void initState() {
    super.initState();
    // Work on a copy so slider drags don't mutate the live cache.
    _p = DevicePrefs.fromJson(
        PrefsService.get(widget.deviceId).toJson());
  }

  Future<void> _save() => PrefsService.save(widget.deviceId, _p);

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
                    padding:
                        const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 520),
                        child: Column(
                          children: [
                            _limitsCard(
                              title: 'Temperature limits',
                              icon: Icons.thermostat,
                              color: AppColors.orange,
                              values: RangeValues(
                                  _p.minTemp, _p.maxTemp),
                              min: 0,
                              max: 50,
                              unit: '°C',
                              onChanged: (v) {
                                setState(() {
                                  _p.minTemp = v.start;
                                  _p.maxTemp = v.end;
                                });
                                _save();
                              },
                            ),
                            const SizedBox(height: 14),
                            _limitsCard(
                              title: 'Humidity limits',
                              icon: Icons.water_drop,
                              color: AppColors.cyan,
                              values: RangeValues(
                                  _p.minHum, _p.maxHum),
                              min: 0,
                              max: 100,
                              unit: '%',
                              onChanged: (v) {
                                setState(() {
                                  _p.minHum = v.start;
                                  _p.maxHum = v.end;
                                });
                                _save();
                              },
                            ),
                            const SizedBox(height: 14),
                            _sectionCard(
                              title: 'Notifications',
                              icon: Icons.notifications_outlined,
                              children: [
                                _switch(
                                  'Limit alarm',
                                  'Alert when a reading breaks the limits',
                                  _p.notifyThreshold,
                                  (v) {
                                    setState(() =>
                                        _p.notifyThreshold = v);
                                    _save();
                                  },
                                ),
                                _switch(
                                  'Offline alert',
                                  'Alert when this device stops sending',
                                  _p.notifyOffline,
                                  (v) {
                                    setState(() =>
                                        _p.notifyOffline = v);
                                    _save();
                                  },
                                ),
                                _switch(
                                  'Back-online alert',
                                  'Alert when this device reconnects',
                                  _p.notifyOnline,
                                  (v) {
                                    setState(() =>
                                        _p.notifyOnline = v);
                                    _save();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _sectionCard(
                              title: 'Alarm style',
                              icon: Icons.volume_up_outlined,
                              children: [
                                _switch(
                                  'Alarm sound',
                                  'Loud siren for limit violations',
                                  _p.alarmSound,
                                  (v) {
                                    setState(
                                        () => _p.alarmSound = v);
                                    _save();
                                  },
                                ),
                                _switch(
                                  'Vibration',
                                  'Vibrate with the alarm',
                                  _p.vibration,
                                  (v) {
                                    setState(
                                        () => _p.vibration = v);
                                    _save();
                                  },
                                ),
                                _switch(
                                  'Repeat while out of range',
                                  'Re-alarm every 10 minutes',
                                  _p.repeatAlarm,
                                  (v) {
                                    setState(() =>
                                        _p.repeatAlarm = v);
                                    _save();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: _actionButton(
                                    label: 'Test alarm',
                                    icon: Icons.play_arrow_rounded,
                                    primary: true,
                                    onTap: _testAlarm,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _actionButton(
                                    label: 'Reset',
                                    icon:
                                        Icons.restart_alt_outlined,
                                    primary: false,
                                    onTap: () async {
                                      await PrefsService.reset(
                                          widget.deviceId);
                                      setState(() {
                                        _p = DevicePrefs();
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  Future<void> _testAlarm() async {
    await AudioService.playAlarm();
    await NotificationService.thresholdAlarm(
      title: 'Limit exceeded: ${widget.deviceId}',
      body:
          'Test alarm — temperature 35.0°C is outside 28–32°C',
      useSound: _p.alarmSound,
      vibrate: _p.vibration,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Device settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  widget.deviceId,
                  style: const TextStyle(
                      color: AppColors.faint, fontSize: 12.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitsCard({
    required String title,
    required IconData icon,
    required Color color,
    required RangeValues values,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<RangeValues> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '${PrefsService.fmt(values.start)} – ${PrefsService.fmt(values.end)} $unit',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [
                      FontFeature.tabularFigures()
                    ],
                  ),
                ),
              ),
            ],
          ),
          RangeSlider(
            values: values,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            activeColor: color,
            inactiveColor: Colors.white.withValues(alpha: 0.12),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.indigo, size: 20),
              const SizedBox(width: 10),
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _switch(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style:
              const TextStyle(color: AppColors.faint, fontSize: 12)),
      activeThumbColor: AppColors.indigo,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 4),
      dense: true,
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [
                      Color(0xFF6366F1),
                      Color(0xFF22D3EE)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: primary ? null : AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: primary
                ? null
                : Border.all(
                    color:
                        Colors.white.withValues(alpha: 0.1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: Colors.white,
                  size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
