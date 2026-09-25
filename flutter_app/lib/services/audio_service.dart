import 'package:audioplayers/audioplayers.dart';

/// Plays the loud alarm tone (bundled asset) for threshold alerts.
class AudioService {
  static final AudioPlayer _player = AudioPlayer();

  static Future<void> playAlarm() async {
    try {
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.play(AssetSource('sounds/alarm.wav'));
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }
}
