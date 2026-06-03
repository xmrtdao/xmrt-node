import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/config.dart';
import '../services/onboarding.dart';

class SettingsScreen extends StatelessWidget {
  final OnboardingService service;
  const SettingsScreen({super.key, required this.service});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _section(AppLocalizations.of(context)!.fleetSection),
        _tile(Icons.wifi, AppLocalizations.of(context)!.fleetStatus, AppLocalizations.of(context)!.fleetRegistered),
        _tile(Icons.hub, AppLocalizations.of(context)!.fleetPool, NodeConfig.fleetPool),
        _tile(Icons.person_outline, AppLocalizations.of(context)!.fleetWorker, service.workerName),
        _tile(Icons.account_balance_wallet, AppLocalizations.of(context)!.fleetWallet, '${NodeConfig.fleetWallet.substring(0, 16)}...'),
        const SizedBox(height: 24),
        _section(AppLocalizations.of(context)!.configSection),
        _tile(Icons.speed, AppLocalizations.of(context)!.configCpu, '50% (4 of 8)'),
        _tile(Icons.cloud, AppLocalizations.of(context)!.configAiModel, NodeConfig.ollamaModel),
        _tile(Icons.dashboard, AppLocalizations.of(context)!.configRelay, NodeConfig.fleetRelay),
        _tile(Icons.timer, AppLocalizations.of(context)!.configHeartbeat, AppLocalizations.of(context)!.configHeartbeatValue),
        const SizedBox(height: 24),
        _section(AppLocalizations.of(context)!.aboutSection),
        _tile(Icons.info_outline, AppLocalizations.of(context)!.aboutVersion, '1.0.0'),
        _tile(Icons.code, AppLocalizations.of(context)!.aboutFramework, 'Flutter 3.x'),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await service.reset();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(AppLocalizations.of(context)!.resetOnboardingHint),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
            icon: const Icon(Icons.replay),
            label: Text(AppLocalizations.of(context)!.resetOnboarding),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFF6600),
              side: const BorderSide(color: Color(0xFFFF6600)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.refresh),
            label: Text(AppLocalizations.of(context)!.resetNode),
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
