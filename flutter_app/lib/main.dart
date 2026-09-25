import 'package:flutter/material.dart';
import 'screens/devices_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EspMonitorApp());
}

class EspMonitorApp extends StatelessWidget {
  const EspMonitorApp({super.key});

  // ⚠️ غيّر الرابط
  static const String serverUrl = 'https://esp-monitor-production.up.railway.app';

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA5B4FC),
          brightness: Brightness.dark,
        ),
      ),
      home: const DevicesScreen(serverUrl: serverUrl),
    );
  }
}
