import 'package:flutter/material.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section('Node Configuration'),
        _tile(Icons.account_balance_wallet, 'Wallet Address', '46UxNFuGM2E3...CgC5mg'),
        _tile(Icons.person_outline, 'Worker Name', 'web-preview'),
        _tile(Icons.hub, 'Pool URL', 'pool.supportxmr.com:3333'),
        _tile(Icons.speed, 'CPU Threads', '50% (4 of 8)'),
        const SizedBox(height: 24),
        _section('Fleet'),
        _tile(Icons.wifi, 'Heartbeat Interval', 'Every 60s'),
        _tile(Icons.cloud, 'AI Model', 'kimi-k2.6:cloud'),
        _tile(Icons.dashboard, 'Relay URL', 'https://relay.mobilemonero.com'),
        const SizedBox(height: 24),
        _section('About'),
        _tile(Icons.info_outline, 'Version', '1.0.0-web'),
        _tile(Icons.code, 'Flutter', '3.x'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: const Text('Reset to Defaults'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange, side: const BorderSide(color: Colors.orange)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.delete_outline),
            label: const Text('Factory Reset Node'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
          ),
        ),
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }

  Widget _tile(IconData icon, String title, String subtitle) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFFFF6600), size: 20),
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        dense: true,
      ),
    );
  }
}
