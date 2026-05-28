import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class FleetHeartbeat {
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _ping());
    _ping();
  }

  void stop() => _timer?.cancel();

  Future<void> _ping() async {
    try {
      await http.post(
        Uri.parse('${NodeConfig.fleetRelay}/api/fleet/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'agent_id': 'xmrt-node-${NodeConfig.defaultWorker}',
          'status': 'ONLINE',
          'hashrate': 0,
          'wallet': NodeConfig.fleetWallet,
          'worker': NodeConfig.defaultWorker,
          'type': 'fleet-node',
        }),
      );
    } catch (_) {}
  }
}
