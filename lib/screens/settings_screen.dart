import 'package:flutter/material.dart';
import '../services/config.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Fleet Node'),
        _tile(Icons.wifi, 'Status', 'Registered'),
        _tile(Icons.hub, 'Pool', NodeConfig.fleetPool),
        _tile(Icons.person_outline, 'Worker', NodeConfig.defaultWorker),
        _tile(Icons.account_balance_wallet, 'Wallet', '${NodeConfig.fleetWallet.substring(0, 16)}...'),
        const SizedBox(height: 24),
        _section('Configuration'),
        _tile(Icons.speed, 'CPU Threads', '50% (4 of 8)'),
        _tile(Icons.cloud, 'AI Model', NodeConfig.ollamaModel),
        _tile(Icons.dashboard, 'Relay', NodeConfig.fleetRelay),
        _tile(Icons.timer, 'Heartbeat', 'Every 60s'),
        const SizedBox(height: 24),
        _section('About'),
        _tile(Icons.info_outline, 'Version', '1.0.0'),
        _tile(Icons.code, 'Framework', 'Flutter 3.x'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: const Text('Reset Node'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
  );

  Widget _tile(IconData icon, String title, String subtitle) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFFF6600), size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace')),
        dense: true,
      ),
    );
  }
}
