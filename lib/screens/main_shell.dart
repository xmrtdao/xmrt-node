import 'package:flutter/material.dart';
import '../services/fleet_heartbeat.dart';
import '../services/mining_service.dart';
import '../services/onboarding.dart';
import 'agent_chat_screen.dart';
import 'dashboard_screen.dart';
import 'mining_screen.dart';
import 'settings_screen.dart';

/// Bottom-tab shell. 4 destinations: Dashboard, Mining, Agent, Settings.
class MainShell extends StatefulWidget {
  final OnboardingService service;
  const MainShell({super.key, required this.service});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  final _mining = MiningService();
  final _heartbeat = FleetHeartbeat();
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _heartbeat.start();
    _pages = [
      const DashboardScreen(),
      const MiningScreen(),
      AgentChatScreen(service: widget.service),
      SettingsScreen(service: widget.service),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6600),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('X', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black, fontSize: 16)),
            ),
            const SizedBox(width: 10),
            const Text('XMRT', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const Text('Node', style: TextStyle(color: Color(0xFFFF6600), fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0x29FF6600),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 8, color: Color(0xFF22c55e)),
                SizedBox(width: 6),
                Text('Fleet Node', style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.memory_outlined), selectedIcon: Icon(Icons.memory), label: 'Mining'),
          NavigationDestination(icon: Icon(Icons.smart_toy_outlined), selectedIcon: Icon(Icons.smart_toy), label: 'Agent'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
