import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/device_state.dart';

class SseService {
  final String baseUrl;

  final void Function(List<DeviceState> all) onInit;
  final void Function(DeviceState device) onData;
  final void Function(String deviceId, bool online, int lastSeen) onStatus;
  final void Function(DeviceState device) onDeviceAdded;
  final void Function(String deviceId) onDeviceRemoved;
  final void Function(bool connected) onConnectionChange;

  http.Client? _client;
  StreamSubscription? _subscription;
  bool _stopped = false;

  SseService({
    required this.baseUrl,
    required this.onInit,
    required this.onData,
    required this.onStatus,
    required this.onDeviceAdded,
    required this.onDeviceRemoved,
    required this.onConnectionChange,
  });

  void connect() {
    _stopped = false;
    _startStream();
  }

  Future<void> _startStream() async {
    if (_stopped) return;

    try {
      _client = http.Client();
      final request = http.Request('GET', Uri.parse('$baseUrl/api/stream'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request);

      if (response.statusCode != 200) {
        throw Exception('SSE failed: ${response.statusCode}');
      }

      onConnectionChange(true);

      String buffer = '';

      _subscription = response.stream.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;
          while (buffer.contains('\n\n')) {
            final idx = buffer.indexOf('\n\n');
            final rawEvent = buffer.substring(0, idx);
            buffer = buffer.substring(idx + 2);
            _handleEvent(rawEvent);
          }
        },
        onError: (_) => _reconnect(),
        onDone: () => _reconnect(),
        cancelOnError: true,
      );
    } catch (e) {
      onConnectionChange(false);
      _reconnect();
    }
  }

  void _handleEvent(String rawEvent) {
    String? eventType;
    final dataLines = <String>[];

    for (final line in rawEvent.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }

    if (dataLines.isEmpty) return;
    final dataStr = dataLines.join('\n');

    try {
      final decoded = jsonDecode(dataStr);

      switch (eventType) {
        case 'init':
          final list = (decoded as List)
              .map((j) => DeviceState.fromJson(j as Map<String, dynamic>))
              .toList();
          onInit(list);
          break;

        case 'data':
          onData(DeviceState.fromJson(decoded as Map<String, dynamic>));
          break;

        case 'status':
          final m = decoded as Map<String, dynamic>;
          onStatus(
            m['device_id'] ?? 'unknown',
            m['online'] ?? false,
            m['lastSeen'] ?? m['timestamp'] ?? 0,
          );
          break;

        case 'device_added':
          onDeviceAdded(DeviceState.fromJson(decoded as Map<String, dynamic>));
          break;

        case 'device_removed':
          final m = decoded as Map<String, dynamic>;
          onDeviceRemoved(m['device_id'] ?? '');
          break;
      }
    } catch (_) {}
  }

  void _reconnect() {
    if (_stopped) return;
    onConnectionChange(false);
    _cleanup();
    Future.delayed(const Duration(seconds: 3), () {
      if (!_stopped) _startStream();
    });
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
  }

  void dispose() {
    _stopped = true;
    _cleanup();
  }
}
