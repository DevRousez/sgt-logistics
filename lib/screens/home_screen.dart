import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'usuario/usuario_dashboard_screen.dart';
import '../config/api_config.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '../services/notification_service.dart';
import '../services/update_checker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _usuarioController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usuarioController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final usuario = _usuarioController.text.trim();
    final password = _passwordController.text;

    if (usuario.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Por favor ingresa tu usuario/correo y contraseña"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.post(
        ApiEndpoints.login,
        {
          "email": usuario,
          "password": password,
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["success"] == true) {
        final userData = data["data"]?["user"] ?? data["data"] ?? {};
        final List<dynamic> permissions = userData["permissions"] ?? [];
        final List<dynamic> roles = userData["roles"] ?? [];

        final bool hasAccess = permissions.contains("documentos-empresas-24h") ||
                               roles.contains("documentos-empresas-24h") ||
                               permissions.contains("acceso-operador-movil") ||
                               roles.contains("acceso-operador-movil") ||
                               permissions.contains("acceso-operaodor-movil") ||
                               roles.contains("acceso-operaodor-movil") ||
                               permissions.contains("SGT-movil") ||
                               roles.contains("SGT-movil") ||
                               permissions.contains("MEP-movil") ||
                               roles.contains("MEP-movil") ||
                               permissions.contains("MEC-movil") ||
                               roles.contains("MEC-movil") ||
                               roles.contains("superuser") ||
                               roles.contains("Admin") ||
                               roles.contains("Administrador");

        if (!hasAccess) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Tu usuario no cuenta con permisos asignados para acceder a la aplicación."),
                backgroundColor: Colors.redAccent,
                duration: Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        final token = data["token"] ?? 
                      data["access_token"] ?? 
                      (data["data"] != null ? data["data"]["token"] : null);
        if (token != null) {
          await ApiService.setToken(token.toString(), type: 'usuario');
        }
        if (data["data"] != null) {
          await ApiService.saveUserData(Map<String, dynamic>.from(data["data"]));
        }

        // Programar notificaciones al iniciar sesión
        NotificationService.fetchAndScheduleNotification();

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const UsuarioDashboardScreen(),
            ),
          );
        }
      } else {
        String msg = data["mensaje"] ?? data["message"] ?? "Credenciales incorrectas";
        if (data["errors"] != null) {
          msg = "$msg: ${data["errors"]}";
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error de conexión: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

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
      resizeToAvoidBottomInset: true,
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
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
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(height: 10),
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

                                    // Inputs de inicio de sesión a la altura de los botones anteriores
                                    TextField(
                                      controller: _usuarioController,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(0.4),
                                        labelText: 'Usuario o Correo',
                                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                                        prefixIcon: const Icon(Icons.person, color: Colors.white70, size: 20),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: _passwordController,
                                      obscureText: _obscurePassword,
                                      style: const TextStyle(color: Colors.white, fontSize: 14),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                        filled: true,
                                        fillColor: Colors.black.withOpacity(0.4),
                                        labelText: 'Contraseña',
                                        labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
                                        prefixIcon: const Icon(Icons.lock, color: Colors.white70, size: 20),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                            color: Colors.white70,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _obscurePassword = !_obscurePassword;
                                            });
                                          },
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                          borderSide: const BorderSide(color: Colors.blueAccent, width: 2),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 50,
                                      child: ElevatedButton(
                                        onPressed: _isLoading ? null : _login,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1E3A8A),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          elevation: 4,
                                        ),
                                        child: _isLoading
                                            ? const SizedBox(
                                                height: 20,
                                                width: 20,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : const Text(
                                                'INGRESAR',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                      ),
                                    ),

                                     const Spacer(),
                                     Text(
                                       'Versión ${UpdateChecker.currentVersion}',
                                       style: const TextStyle(
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}