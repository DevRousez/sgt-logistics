import 'package:flutter/material.dart';
import '/api/api_service.dart';
import 'sgt_dashboard_screen.dart';
import 'mep_dashboard_screen.dart';
import 'mec_dashboard_screen.dart';
import 'empresas_documentos_dashboard_screen.dart';
import '../operador/operador_dashboard_screen.dart';
import '../home_screen.dart';

class UsuarioDashboardScreen extends StatefulWidget {
  const UsuarioDashboardScreen({super.key});

  @override
  State<UsuarioDashboardScreen> createState() => _UsuarioDashboardScreenState();
}

class _UsuarioDashboardScreenState extends State<UsuarioDashboardScreen> {
  bool _isLoading = true;
  String? _userType;

  @override
  void initState() {
    super.initState();
    _determineUserDashboard();
  }

  Future<void> _determineUserDashboard() async {
    final data = await ApiService.getUserData();
    if (data != null) {
      final user = data["user"] ?? data;
      final List<dynamic> permissions = user["permissions"] ?? [];
      final List<dynamic> roles = user["roles"] ?? [];
      final int idCliente = int.tryParse(user["id_cliente"]?.toString() ?? "0") ?? 0;

      if (permissions.contains("documentos-empresas-24h") || roles.contains("documentos-empresas-24h")) {
        _userType = "DOCUMENTOS_EMPRESAS";
      } else if (permissions.contains("acceso-operador-movil") ||
                 roles.contains("acceso-operador-movil") ||
                 permissions.contains("acceso-operaodor-movil") ||
                 roles.contains("acceso-operaodor-movil")) {
        _userType = "OPERADOR";
      } else if (permissions.contains("SGT-movil") || roles.contains("SGT-movil")) {
        _userType = "SGT";
      } else if (permissions.contains("MEP-movil") || roles.contains("MEP-movil")) {
        _userType = "MEP";
      } else if ((permissions.contains("MEC-movil") ||
                 roles.contains("MEC-movil") )&&
                 idCliente != 0) {
        _userType = "MEC";
      } else {
        _userType = null;
      }
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_userType == "DOCUMENTOS_EMPRESAS") {
      return const EmpresasDocumentosDashboardScreen();
    } else if (_userType == "OPERADOR") {
      return const OperadorDashboardScreen();
    } else if (_userType == "SGT") {
      return const SgtDashboardScreen();
    } else if (_userType == "MEP") {
      return const MepDashboardScreen();
    } else if (_userType == "MEC") {
      return const MecDashboardScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Acceso no Autorizado"),
        backgroundColor: const Color(0xFF0F2027),
        actions: [
              IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ApiService.setToken("");
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
          )
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.no_accounts, size: 70, color: Colors.orangeAccent),
              const SizedBox(height: 16),
              const Text(
                "Sin Permisos Asignados",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Tu usuario no posee permisos móviles asignados (SGT-movil, Operador, Empresas 24h, MEP-movil o MEC-movil) para acceder a la aplicación. Por favor contacta al administrador.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text("Cerrar Sesión e Ir al Inicio"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  await ApiService.setToken("");
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                      (route) => false,
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}