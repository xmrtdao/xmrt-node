import 'package:flutter/services.dart';
import 'config.dart';

class MiningService {
  static const _channel = MethodChannel('io.xmrt.node/mining');
  bool _running = false;
  double _hashrate = 0;
  int _sharesGood = 0;
  int _sharesTotal = 0;

  bool get isRunning => _running;
  double get hashrate => _hashrate;
  int get sharesGood => _sharesGood;
  int get sharesTotal => _sharesTotal;

  Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod('mining.start');
      _running = result['success'] ?? false;
      return _running;
    } catch (e) {
      // Running in web preview — simulate
      _running = false;
      return false;
    }
  }

  Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod('mining.stop');
      _running = !(result['success'] ?? false);
      return !_running;
    } catch (e) {
      _running = false;
      return true;
    }
  }

  Future<void> refresh() async {
    try {
      final status = await _channel.invokeMethod('mining.status');
      _running = status['running'] ?? false;
      _hashrate = (status['hashrate'] ?? 0).toDouble();
      _sharesGood = status['shares_good'] ?? 0;
      _sharesTotal = status['shares_total'] ?? 0;
    } catch (_) {}
  }
}
