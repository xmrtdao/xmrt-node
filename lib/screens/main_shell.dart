import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../screens/agent_chat_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/mining_screen.dart';
import '../screens/settings_screen.dart';
import '../services/fleet_heartbeat.dart';
import '../services/mining_service.dart';
import '../services/onboarding.dart';

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
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: AppLocalizations.of(context)!.navDashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.memory_outlined),
            selectedIcon: const Icon(Icons.memory),
            label: AppLocalizations.of(context)!.navMining,
          ),
          NavigationDestination(
            icon: const Icon(Icons.smart_toy_outlined),
            selectedIcon: const Icon(Icons.smart_toy),
            label: AppLocalizations.of(context)!.navAgent,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: AppLocalizations.of(context)!.navSettings,
          ),
        ],
      ),
    );
  }
}
