import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _heroCard(context),
        const SizedBox(height: 16),
        _statGrid(),
        const SizedBox(height: 24),
        _sectionTitle('Recent Activity'),
        const SizedBox(height: 8),
        _activityRow('Hash submitted', '2 sec ago', Icons.check_circle, const Color(0xFF22c55e)),
        _activityRow('Pool connected', '15 sec ago', Icons.hub, const Color(0xFFFF6600)),
        _activityRow('Heartbeat sent', '45 sec ago', Icons.wifi, Colors.blue),
      ],
    );
  }

  Widget _heroCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0x29FF6600),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.memory, size: 40, color: Color(0xFFFF6600)),
            ),
            const SizedBox(height: 16),
            const Text('0 H/s', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800)),
            const Text('Current Hashrate', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _miniStat('Pool', 'supportxmr.com'),
                const SizedBox(width: 32),
                _miniStat('Worker', 'web-preview'),
                const SizedBox(width: 32),
                _miniStat('Shares', '0'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _statGrid() {
    return Row(
      children: [
        Expanded(child: _statCard('Node Status', 'Idle', Icons.circle, const Color(0xFF6b6b80))),
        const SizedBox(width: 12),
        Expanded(child: _statCard('Fleet', 'Registered', Icons.wifi, const Color(0xFF22c55e))),
        const SizedBox(width: 12),
        Expanded(child: _statCard('Agent', 'Online', Icons.smart_toy, const Color(0xFFFF6600))),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600));
  }

  Widget _activityRow(String text, String time, IconData icon, Color color) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 20),
        title: Text(text, style: const TextStyle(fontSize: 14)),
        trailing: Text(time, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        dense: true,
      ),
    );
  }
}
