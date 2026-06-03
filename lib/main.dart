import 'package:flutter/material.dart';
import 'screens/onboarding_screen.dart';
import 'screens/main_shell.dart';
import 'services/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onboarding = await OnboardingService.init();
  runApp(XMRTNodeApp(onboarding: onboarding));
}

class XMRTNodeApp extends StatelessWidget {
  final OnboardingService onboarding;
  const XMRTNodeApp({super.key, required this.onboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XMRT Node',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF6600),
          secondary: const Color(0xFFD4AF37),
          surface: const Color(0xFF0C0C0C),
        ),
        scaffoldBackgroundColor: const Color(0xFF030303),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0C0C0C),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF0C0C0C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0x29FF6600)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0C0C0C),
          indicatorColor: const Color(0x29FF6600),
        ),
      ),
      home: onboarding.isComplete
          ? MainShell(service: onboarding)
          : OnboardingScreen(service: onboarding),
    );
  }
}
