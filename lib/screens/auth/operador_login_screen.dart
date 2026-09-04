import 'package:flutter/material.dart';
import 'dart:convert';

import '../operador/operador_dashboard_screen.dart';
import '/endpoints/api_endpoints.dart';
import '/api/api_service.dart';
import '../../services/notification_service.dart';
import '../../services/operador_sync_service.dart';

class OperadorLoginScreen extends StatefulWidget {
  const OperadorLoginScreen({super.key});

  @override
  State<OperadorLoginScreen> createState() => _OperadorLoginScreenState();
}

class _OperadorLoginScreenState extends State<OperadorLoginScreen> {
  final TextEditingController usuarioController = TextEditingController();
  final TextEditingController contrasenaController = TextEditingController();
  bool _obscureContrasena = true;
  bool _isLoading = false;

  @override
  void dispose() {
    usuarioController.dispose();
    contrasenaController.dispose();
    super.dispose();
  }

  Future<void> validarOperador() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final response = await ApiService.post(
        ApiEndpoints.login,
        {
          "usuario": usuarioController.text.trim(),
          "contrasena": contrasenaController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data["token"] ?? 
                      data["access_token"] ?? 
                      (data["data"] != null ? data["data"]["token"] : null);
        if (token != null) {
          await ApiService.setToken(token.toString(), type: 'operador');
        }
        if (data["data"] != null) {
          await ApiService.saveUserData(data["data"]);
        }
        // Sincronizar de inmediato si el operador tiene un viaje activo en curso
        await OperadorSyncService.sincronizarSiEsNecesario();
        // Programar notificación dinámica al iniciar sesión
        NotificationService.fetchAndScheduleNotification();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const OperadorDashboardScreen(),
          ),
        );
      } else {
        final data = jsonDecode(response.body);

        String message = data["message"] ?? data["mensaje"] ??
            "No se encontró información con los datos proporcionados";

        if (data["errors"] != null && data["errors"] is Map) {
          final List<String> errList = [];
          (data["errors"] as Map).forEach((key, val) {
            if (val is List && val.isNotEmpty) {
              errList.add(val.first.toString());
            }
          });
          if (errList.isNotEmpty) {
            message = errList.join("\n");
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print("Error request: $e");
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operador'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [

            TextField(
              controller: usuarioController,
              decoration: const InputDecoration(labelText: 'Correo Electrónico'),
            ),

            TextField(
              controller: contrasenaController,
              obscureText: _obscureContrasena,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureContrasena ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureContrasena = !_obscureContrasena;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 25),

            ElevatedButton(
              onPressed: _isLoading ? null : validarOperador,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Ingresar'),
            ),
          ],
        ),
      ),
    );
  }
}