import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/operador_login_screen.dart';
import 'auth/usuario_login_screen.dart';
import '../config/api_config.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showSettingsDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final currentHost = prefs.getString('custom_api_host') ?? "192.168.48.1:8080";
    final textController = TextEditingController(text: currentHost);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.blue),
            SizedBox(width: 10),
            Text("Configuración de Servidor"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ingresa la IP y puerto actual de tu servidor (ej. 192.168.1.75:8080):",
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: "Host / Dirección IP",
                hintText: "192.168.1.75:8080",
              ),
            ),
            const SizedBox(height: 15),
            Text(
              "URL Actual: ${ApiConfig.baseUrl}",
              style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newHost = textController.text.trim();
              if (newHost.isNotEmpty) {
                await ApiConfig.saveConfig(newHost);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Servidor actualizado a: ${ApiConfig.baseUrl}"),
                      backgroundColor: Colors.green,
                    ),
                  );
                  Navigator.pop(context);
                }
              }
            },
            child: const Text("Guardar"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: ApiConfig.isProduction
          ? null
          : FloatingActionButton(
              mini: true,
              backgroundColor: Colors.white.withOpacity(0.2),
              foregroundColor: Colors.white,
              onPressed: () => _showSettingsDialog(context),
              child: const Icon(Icons.settings),
            ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF6BA4C9), // Azul cielo suave
              Color(0xFF0F2027), // Azul marino profundo
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Center(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  image: const DecorationImage(
                    image: AssetImage('assets/img/sgtprincipal.png'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: Colors.black.withOpacity(0.55),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(height: 16),
                            const Text(
                              'Sistema de Gestión de Transporte',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            const Spacer(flex: 5),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.local_shipping),
                                label: const Text(
                                  'SOY OPERADOR',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const OperadorLoginScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              height: 55,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.person),
                                label: const Text(
                                  'USUARIO SGT',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                style: ElevatedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                      const UsuarioLoginScreen(),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const Spacer(),
                            const Text(
                              'Versión 1.0',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Align(
                        alignment: Alignment(0.0, 0.04),
                        child: Text(
                          'MOBILE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            shadows: [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}