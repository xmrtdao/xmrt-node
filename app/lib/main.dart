import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';
import 'screens/mining_screen.dart';
import 'screens/agent_chat_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XMRTNodeApp());
}

class XMRTNodeApp extends StatelessWidget {
  const XMRTNodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XMRT Node',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFFF6600),
          secondary: const Color(0xFFD4AF37),
        ),
        scaffoldBackgroundColor: const Color(0xFF030303),
      ),
      home: const DashboardScreen(),
    );
  }
}
