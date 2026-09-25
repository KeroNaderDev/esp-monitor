import 'package:flutter/material.dart';
import 'screens/devices_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EspMonitorApp());
}

class EspMonitorApp extends StatelessWidget {
  const EspMonitorApp({super.key});

  // Server base URL (no trailing /api).
  static const String serverUrl =
      'https://esp-monitor-production.up.railway.app';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP Monitor',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const DevicesScreen(serverUrl: serverUrl),
    );
  }
}
