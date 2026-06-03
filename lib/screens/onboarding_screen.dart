import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/onboarding.dart';
import '../services/xmrt_agent.dart';
import 'main_shell.dart';

/// First-launch wizard. 4 steps:
///
///  1. Welcome
///  2. Worker name (default "fleet-node")
///  3. Provider pick (Cloud default, Local opt-in for 6GB+ devices)
///  4. Hardware check (Termux:API + Ollama detection, instructions)
///
/// On finish, we mark onboarding complete and push the MainShell.
class OnboardingScreen extends StatefulWidget {
  final OnboardingService service;
  const OnboardingScreen({super.key, required this.service});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _step = 0;
  final _workerCtrl = TextEditingController(text: 'fleet-node');
  String _provider = 'ollama_cloud';
  final _agent = XmrtAgent();
  bool _checking = false;
  String? _installState; // 'not_installed' | 'installed_not_running' | 'running' | 'unreachable'
  String? _hardwareHint;

  @override
  void initState() {
    super.initState();
    _provider = widget.service.agentProvider;
    _workerCtrl.text = widget.service.workerName;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _workerCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 3) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _finish() async {
    await widget.service.setAgentProvider(_provider);
    await widget.service.setWorkerName(_workerCtrl.text.trim().isEmpty ? 'fleet-node' : _workerCtrl.text.trim());
    await widget.service.markComplete();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => MainShell(service: widget.service)),
    );
  }

  Future<void> _checkHardware() async {
    setState(() {
      _checking = true;
      _hardwareHint = null;
    });
    try {
      final status = await _agent.status();
      setState(() {
        _installState = status.state;
        _checking = false;
        if (status.state == 'running') {
          _hardwareHint = AppLocalizations.of(context)!.onboardingHardwareHintRunning;
        } else if (status.state == 'installed_not_running') {
          _hardwareHint = AppLocalizations.of(context)!.onboardingHardwareHintInstalled;
        } else if (status.state == 'not_installed') {
          _hardwareHint = AppLocalizations.of(context)!.onboardingHardwareHintNotInstalled;
        } else {
          _hardwareHint = AppLocalizations.of(context)!.onboardingHardwareHintUnreachable;
        }
      });
    } catch (e) {
      setState(() {
        _checking = false;
        _installState = 'unreachable';
        _hardwareHint = 'Error checking agent: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      body: SafeArea(
        child: Column(
          children: [
            _stepper(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _welcome(),
                  _workerName(),
                  _provider(),
                  _hardware(),
                ],
              ),
            ),
            _navBar(),
          ],
        ),
      ),
    );
  }

  Widget _stepper() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: List.generate(4, (i) {
          final active = i <= _step;
          return Expanded(
            child: Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: active ? const Color(0xFFFF6600) : const Color(0xFF2a2a3a),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _navBar() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          if (_step > 0)
            TextButton(
              onPressed: _back,
              child: Text(AppLocalizations.of(context)!.back, style: const TextStyle(color: Colors.white70)),
            ),
          const Spacer(),
          if (_step < 3)
            ElevatedButton(
              onPressed: _next,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6600),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: Text(AppLocalizations.of(context)!.next, style: const TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            ElevatedButton(
              onPressed: _finish,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6600),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
              child: Text(AppLocalizations.of(context)!.getStarted, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  // ── Step 1 ───────────────────────────────────────────────────────────────
  Widget _welcome() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x29FF6600),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.bolt, color: Color(0xFFFF6600), size: 56),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.onboardingWelcomeTitle,
            style: const TextStyle(
              color: Color(0xFFFF6600),
              fontSize: 32,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            AppLocalizations.of(context)!.onboardingWelcomeSubtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 32),
          Text(
            AppLocalizations.of(context)!.onboardingWelcomeIntro,
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          _bullet(AppLocalizations.of(context)!.onboardingBulletMining),
          _bullet(AppLocalizations.of(context)!.onboardingBulletFleet),
          _bullet(AppLocalizations.of(context)!.onboardingBulletAgent),
          _bullet(AppLocalizations.of(context)!.onboardingBulletMemory),
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 10),
              child: Icon(Icons.circle, size: 6, color: Color(0xFFFF6600)),
            ),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5))),
          ],
        ),
      );

  // ── Step 2 ───────────────────────────────────────────────────────────────
  Widget _workerName() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppLocalizations.of(context)!.onboardingWorkerTitle, style: const TextStyle(color: Color(0xFFFF6600), fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.onboardingWorkerSubtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _workerCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF0C0C0C),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0x29FF6600)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF6600)),
              ),
              prefixText: 'worker: ',
              prefixStyle: const TextStyle(color: Colors.white38, fontSize: 14, fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.onboardingWorkerHint,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Step 3 ───────────────────────────────────────────────────────────────
  Widget _provider() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppLocalizations.of(context)!.onboardingProviderTitle, style: const TextStyle(color: Color(0xFFFF6600), fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.onboardingProviderSubtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          _providerCard(
            key: const ValueKey('cloud'),
            title: AppLocalizations.of(context)!.onboardingProviderCloud,
            subtitle: AppLocalizations.of(context)!.onboardingProviderCloudSubtitle,
            icon: Icons.cloud_outlined,
            value: 'ollama_cloud',
            groupValue: _provider,
            onChanged: (v) => setState(() => _provider = v ?? 'ollama_cloud'),
          ),
          const SizedBox(height: 12),
          _providerCard(
            key: const ValueKey('local'),
            title: AppLocalizations.of(context)!.onboardingProviderLocal,
            subtitle: AppLocalizations.of(context)!.onboardingProviderLocalSubtitle,
            icon: Icons.phone_android,
            value: 'local_optional',
            groupValue: _provider,
            onChanged: (v) => setState(() => _provider = v ?? 'ollama_cloud'),
          ),
        ],
      ),
    );
  }

  Widget _providerCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
  }) {
    final selected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0x29FF6600) : const Color(0xFF0C0C0C),
          border: Border.all(
            color: selected ? const Color(0xFFFF6600) : const Color(0xFF2a2a3a),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? const Color(0xFFFF6600) : Colors.white54, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: Color(0xFFFF6600)),
          ],
        ),
      ),
    );
  }

  // ── Step 4 ───────────────────────────────────────────────────────────────
  Widget _hardware() {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppLocalizations.of(context)!.onboardingHardwareTitle, style: const TextStyle(color: Color(0xFFFF6600), fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.onboardingHardwareSubtitle,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton.icon(
              icon: _checking
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6600)))
                  : const Icon(Icons.check_circle_outline, color: Color(0xFFFF6600)),
              label: Text(_checking ? AppLocalizations.of(context)!.onboardingHardwareChecking : AppLocalizations.of(context)!.onboardingHardwareCheckNow, style: const TextStyle(color: Color(0xFFFF6600), fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0x1AFFFF6600),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                side: const BorderSide(color: Color(0xFFFF6600)),
              ),
              onPressed: _checking ? null : _checkHardware,
            ),
          ),
          if (_installState != null) ...[
            const SizedBox(height: 24),
            _statusChip(),
            const SizedBox(height: 12),
            Text(
              _hardwareHint ?? '',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip() {
    final (color, icon, label) = switch (_installState) {
      'running' => (const Color(0xFF22c55e), Icons.check_circle, AppLocalizations.of(context)!.onboardingHardwareRunning),
      'installed_not_running' => (const Color(0xFFfbbf24), Icons.pause_circle, AppLocalizations.of(context)!.onboardingHardwareInstalled),
      'not_installed' => (const Color(0xFFf87171), Icons.cancel, AppLocalizations.of(context)!.onboardingHardwareNotInstalled),
      _ => (Colors.grey, Icons.help_outline, AppLocalizations.of(context)!.onboardingHardwareUnknown),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
