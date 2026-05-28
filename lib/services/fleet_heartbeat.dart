import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class FleetHeartbeat {
  Timer? _timer;
  int _beat = 0;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    _ping();
  }

  void stop() => _timer?.cancel();

  Future<void> _ping() async {
    _beat++;
    try {
      await http.post(
        Uri.parse('https://relay.mobilemonero.com/api/fleet/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'agent_id': 'xmrt-node-web-preview',
          'status': 'ONLINE',
          'hashrate': 0,
          'wallet': '46UxNFuGM2E3UwmZWWJicaRPoRwqwW4byQkaTHkX8yPcVihp91qAVtSFipWUGJJUyTXgzSqxzDQtNLf2bsp2DX2qCCgC5mg',
          'worker': 'web-preview',
        }),
      );
    } catch (_) {}
  }

  int get beatCount => _beat;
}
