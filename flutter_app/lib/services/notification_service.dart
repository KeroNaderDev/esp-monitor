import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'esp_channel',
      'ESP8266 Status',
      channelDescription: 'Device online/offline updates',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  /// Loud alarm notification for limit violations.
  static Future<void> thresholdAlarm({
    required String title,
    required String body,
    required bool useSound,
    required bool vibrate,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'esp_alarm',
      'ESP Alarm',
      channelDescription: 'Loud alarm when a reading breaks its limits',
      importance: Importance.max,
      priority: Priority.high,
      playSound: useSound,
      sound: useSound
          ? const RawResourceAndroidNotificationSound('alarm')
          : null,
      enableVibration: vibrate,
      vibrationPattern: vibrate
          ? Int64List.fromList(const [0, 600, 300, 600, 300, 900])
          : null,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentSound: useSound),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
    );
  }

  static Future<void> alert({required bool online}) async {
    if (online) {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    } else {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
    }
  }
}
