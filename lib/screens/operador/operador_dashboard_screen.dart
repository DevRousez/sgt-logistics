import 'package:flutter/material.dart';
import 'registrar_diesel_screen.dart';
import 'carga_contenedor_screen.dart';
import 'finalizar_viaje_screen.dart';
import '../home_screen.dart';
import '/api/api_service.dart';

class OperadorDashboardScreen extends StatefulWidget {
  const OperadorDashboardScreen({super.key});

  @override
  State<OperadorDashboardScreen> createState() => _OperadorDashboardScreenState();
}

class _OperadorDashboardScreenState extends State<OperadorDashboardScreen> {
  String? _nombre;
  String? _unidad;
  String? _idEquipo;

  @override
  void initState() {
    super.initState();
    _loadOperatorData();
  }

  Future<void> _loadOperatorData() async {
    final data = await ApiService.getUserData();
    if (data != null) {
      setState(() {
        _nombre = data["nombre"]?.toString();
        _unidad = data["unidad"]?.toString() ?? "N/A";
        _idEquipo = data["id_equipo"]?.toString() ?? "N/A";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Block back button navigation
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel Operador'),
          actions: [
            IconButton(
              onPressed: () async {
                await ApiService.setToken('');
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar Sesión',
            ),
          ],
        ),
        body: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.local_gas_station),
              title: const Text('Registrar Diesel'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegistrarDieselScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('Iniciar Viaje / Carga Contenedor'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CargaContenedorScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.red),
              title: const Text('Finalizar Viaje'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FinalizarViajeScreen(),
                  ),
                );
              },
            ),

            const ListTile(
              leading: Icon(Icons.history),
              title: Text('Historial'),
            ),
          ],
        ),
        bottomNavigationBar: _nombre == null
            ? null
            : Container(
                color: Colors.blue.shade900,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "$_nombre (Equ: $_unidad)",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}