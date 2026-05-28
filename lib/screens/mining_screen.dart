import 'package:flutter/material.dart';
import '../services/config.dart';

class MiningScreen extends StatelessWidget {
  const MiningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.memory, size: 48, color: Color(0xFFFF6600)),
                const SizedBox(height: 16),
                const Text('XMRig Engine', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text('v6.26.0 · ARM64 · Fleet Pool', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Mining', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6600), foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.stop),
                    label: const Text('Stop'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _infoField('Pool', NodeConfig.fleetPool),
        _infoField('Worker', NodeConfig.defaultWorker),
        _infoField('Wallet', '${NodeConfig.fleetWallet.substring(0, 20)}...'),
        _infoField('Threads', '4 (50% of 8 cores)'),
        _infoField('API Port', '19090'),
      ],
    );
  }

  Widget _infoField(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 14, fontFamily: 'monospace')),
        dense: true,
      ),
    );
  }
}
