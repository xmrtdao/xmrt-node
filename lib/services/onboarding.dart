import 'package:shared_preferences/shared_preferences.dart';

/// Tracks first-run state and onboarding completion.
///
/// Persists a single boolean in SharedPreferences. Once the user
/// finishes the onboarding wizard, we mark it done and never show
/// the wizard again (unless they reset from Settings).
class OnboardingService {
  static const _kDoneKey = 'onboarding.completed';
  static const _kAgentProviderKey = 'agent.provider';
  static const _kWorkerNameKey = 'mining.worker_name';

  final SharedPreferences _prefs;

  OnboardingService._(this._prefs);

  /// Initialize from SharedPreferences. Call once at app start.
  static Future<OnboardingService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingService._(prefs);
  }

  bool get isComplete => _prefs.getBool(_kDoneKey) ?? false;

  Future<void> markComplete() => _prefs.setBool(_kDoneKey, true);
  Future<void> reset() => _prefs.setBool(_kDoneKey, false);

  /// Which LLM provider the user picked. Defaults to "ollama_cloud".
  String get agentProvider => _prefs.getString(_kAgentProviderKey) ?? 'ollama_cloud';
  Future<void> setAgentProvider(String p) => _prefs.setString(_kAgentProviderKey, p);

  String get workerName => _prefs.getString(_kWorkerNameKey) ?? 'fleet-node';
  Future<void> setWorkerName(String n) => _prefs.setString(_kWorkerNameKey, n);
}
