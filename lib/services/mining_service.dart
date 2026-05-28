class MiningService {
  bool _running = false;
  int _hashrate = 0;
  int _shares = 0;

  bool get isRunning => _running;
  int get hashrate => _hashrate;
  int get shares => _shares;

  Future<void> start({String? wallet, String? worker}) async {
    _running = true;
    _hashrate = 0;
  }

  Future<void> stop() async {
    _running = false;
  }

  Map<String, dynamic> status() => {
    'running': _running,
    'hashrate': _hashrate,
    'shares': _shares,
  };
}
