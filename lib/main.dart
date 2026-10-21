import 'package:flutter/material.dart';

import 'src/startup_gate.dart';

import 'src/services/session_manager.dart';
import 'src/services/app_config.dart';
import 'src/services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await SessionManager.instance.init();
  await PushNotificationService.instance.initialize();
  runApp(const ZentryApp());
}

class ZentryApp extends StatelessWidget {
  const ZentryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zentry Predict',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD700),
          brightness: Brightness.dark,
          primary: const Color(0xFFFFD700),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F081C),
        useMaterial3: true,
      ),
      home: const StartupGate(),
    );
  }
}
