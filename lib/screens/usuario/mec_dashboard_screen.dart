import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'usuario_module_screen.dart';
import '../home_screen.dart';
import '/api/api_service.dart';

class MecDashboardScreen extends StatefulWidget {
  const MecDashboardScreen({super.key});

  @override
  State<MecDashboardScreen> createState() => _MecDashboardScreenState();
}

class _MecDashboardScreenState extends State<MecDashboardScreen> {
  String? _userName;
  String _displayName = "MEC - Taller Mecánico";

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final data = await ApiService.getUserData();
    
    if (data != null && data["user"] != null) {
      final user = data["user"];
      final String? name = user["name"];
      final int? defaultEmpresaId = int.tryParse(user["id_empresa"]?.toString() ?? "");
      final String? clienteNombre = user["cliente_nombre"]?.toString();

      // Forzar a usar la empresa por defecto asignada al usuario
      if (defaultEmpresaId != null) {
        await prefs.setInt('selected_empresa_id', defaultEmpresaId);
      }

      setState(() {
        _userName = name;
        if (clienteNombre != null && clienteNombre.isNotEmpty) {
          _displayName = "Cliente: $clienteNombre";
        } else {
          _displayName = "MEC - Taller Mecánico";
        }
      });
    }
  }

  void _goTo(BuildContext context, String module, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UsuarioModuleScreen(module: module, title: title),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> gridCards = [];

    // Operaciones
    gridCards.add(
      _card(
        context,
        title: "Operaciones",
        icon: Icons.local_shipping,
        color: Colors.blueAccent,
        onTap: () => _goTo(context, "operaciones", "Control de Operaciones"),
        subtitle: "Viajes, contenedores y costos del cliente",
      ),
    );

    // Monitoreo
    gridCards.add(
      _card(
        context,
        title: "Monitoreo",
        icon: Icons.map,
        color: Colors.red,
        onTap: () => _goTo(context, "monitoreo", "Monitoreo GPS"),
        subtitle: "GPS y rutas del cliente",
      ),
    );

    // Taller / Mecánico
    gridCards.add(
      _card(
        context,
        title: "Taller / Mecánico",
        icon: Icons.build,
        color: Colors.orange,
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Módulo de Taller Mecánico en desarrollo")),
          );
        },
        subtitle: "Mantenimiento y reparaciones",
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("MEC - Panel", style: TextStyle(fontSize: 16)),
              Text(
                _displayName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: gridCards,
          ),
        ),
        bottomNavigationBar: _userName == null
            ? null
            : Container(
                color: Colors.blue.shade900,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _userName!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('selected_empresa_id');
                        await ApiService.setToken('');
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const HomeScreen()),
                            (route) => false,
                          );
                        }
                      },
                      icon: const Icon(Icons.logout, color: Colors.white),
                      tooltip: 'Cerrar Sesión',
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6,
              offset: const Offset(0, 3),
            )
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
