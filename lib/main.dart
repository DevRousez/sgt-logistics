import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/usuario/usuario_dashboard_screen.dart';
import 'api/api_service.dart';
import 'config/api_config.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.loadConfig();
  await ApiService.initSession();

  // Inicializar notificaciones
  await NotificationService.init();
  await NotificationService.requestPermissions();
  if (ApiService.token != null && ApiService.token!.isNotEmpty) {
    NotificationService.fetchAndScheduleNotification();
  }

  runApp(const SGTApp());
}

class SGTApp extends StatelessWidget {
  const SGTApp({super.key});

  @override
  Widget build(BuildContext context) {
    Widget initialScreen = const HomeScreen();
    if (ApiService.token != null && ApiService.token!.isNotEmpty) {
      initialScreen = const UsuarioDashboardScreen();
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mobile',
      home: initialScreen,
    );
  }
}