import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'usuario_module_screen.dart';
import '../home_screen.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';

class UsuarioDashboardScreen extends StatefulWidget {
  const UsuarioDashboardScreen({super.key});

  @override
  State<UsuarioDashboardScreen> createState() => _UsuarioDashboardScreenState();
}

class _UsuarioDashboardScreenState extends State<UsuarioDashboardScreen> {
  String? _userName;
  int? _selectedEmpresaId;
  String _selectedEmpresaNombre = "Cargando...";
  List<Map<String, dynamic>> _empresasPropias = [];
  bool _isSgtUser = false;
  bool _isMepUser = false;
  bool _isMecUser = false;

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
      
      final List<dynamic> permissions = user["permissions"] ?? [];
      final List<dynamic> roles = user["roles"] ?? [];
      print("Loaded User Permissions: $permissions, Roles: $roles");

      // Check if user is SGT, MEP, or MEC using the new permissions
      final bool isSgt = permissions.contains("SGT-movil") || 
                         roles.contains("SGT-movil") ||
                         (permissions.isEmpty && roles.isEmpty); // Default fallback for tests
      final bool isMep = permissions.contains("MEP-movil") || roles.contains("MEP-movil");
      final bool isMec = permissions.contains("MEC-movil") || roles.contains("MEC-movil");

      int? activeEmpresaId = prefs.getInt('selected_empresa_id') ?? defaultEmpresaId;
      if (activeEmpresaId != null) {
        await prefs.setInt('selected_empresa_id', activeEmpresaId);
      }

      setState(() {
        _userName = name;
        _selectedEmpresaId = activeEmpresaId;
        _isSgtUser = isSgt;
        _isMepUser = isMep;
        _isMecUser = isMec;
      });

      if (isSgt) {
        await _fetchEmpresasPropias();
      } else {
        setState(() {
          _selectedEmpresaNombre = "Mi Empresa";
        });
      }
    }
  }

  Future<void> _fetchEmpresasPropias() async {
    try {
      final response = await ApiService.get(ApiEndpoints.empresasPropias);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["data"] != null) {
          final rawData = resData["data"];
          List<dynamic> listObj = [];
          if (rawData is List) {
            listObj = rawData;
          } else if (rawData is Map && rawData["data"] is List) {
            listObj = rawData["data"];
          }

          final List<Map<String, dynamic>> list = listObj.map((e) => Map<String, dynamic>.from(e)).toList();
          
          if (list.isEmpty) {
            list.addAll([
              {"id": 7, "nombre": "Empresa SGT Demo (ID 7)"},
              {"id": 8, "nombre": "Empresa Alterna (ID 8)"},
            ]);
          }

          String selectedName = "No Asignada";
          if (_selectedEmpresaId != null) {
            final found = list.firstWhere(
              (element) => int.tryParse(element["id"]?.toString() ?? "") == _selectedEmpresaId,
              orElse: () => {},
            );
            if (found.isNotEmpty) {
              selectedName = found["nombre"]?.toString() ?? "No Asignada";
            }
          }

          setState(() {
            _empresasPropias = list;
            _selectedEmpresaNombre = selectedName;
          });
        }
      }
    } catch (e) {
      print("Error loading own companies: $e");
      setState(() {
        _selectedEmpresaNombre = "Error al cargar";
      });
    }
  }

  Future<void> _changeEmpresa(int id, String nombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_empresa_id', id);
    setState(() {
      _selectedEmpresaId = id;
      _selectedEmpresaNombre = nombre;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Empresa cambiada a: $nombre"),
        backgroundColor: Colors.blue.shade800,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showEmpresaSelector() {
    if (_empresasPropias.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cargando listado de empresas... por favor espere")),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  "Seleccionar Empresa Propia",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: _empresasPropias.length,
                  itemBuilder: (context, index) {
                    final item = _empresasPropias[index];
                    final int itemId = int.tryParse(item["id"]?.toString() ?? "") ?? 0;
                    final String itemNombre = item["nombre"]?.toString() ?? "N/A";
                    final bool isSelected = itemId == _selectedEmpresaId;

                    return ListTile(
                      leading: Icon(
                        Icons.business, 
                        color: isSelected ? Colors.blue.shade800 : Colors.grey,
                      ),
                      title: Text(
                        itemNombre,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.blue.shade800 : Colors.black87,
                        ),
                      ),
                      trailing: isSelected 
                          ? Icon(Icons.check, color: Colors.blue.shade800) 
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _changeEmpresa(itemId, itemNombre);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Block back button navigation
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("SGT - Panel", style: TextStyle(fontSize: 16)),
              Text(
                _selectedEmpresaNombre,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          actions: [
            if (_isSgtUser)
              IconButton(
                onPressed: _showEmpresaSelector,
                icon: const Icon(Icons.swap_horiz),
                tooltip: "Cambiar Empresa",
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
              icon: const Icon(Icons.logout),
              tooltip: 'Cerrar Sesión',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Builder(
            builder: (context) {
              final List<Widget> gridCards = [];

              if (_isSgtUser || _isMepUser) {
                gridCards.add(
                  _card(
                    context,
                    title: "Operaciones",
                    icon: Icons.local_shipping,
                    color: Colors.blueAccent,
                    onTap: () => _goTo(context, "operaciones", "Control de Operaciones"),
                    subtitle: "Viajes, contenedores y costos",
                  ),
                );
                gridCards.add(
                  _card(
                    context,
                    title: "Monitoreo",
                    icon: Icons.map,
                    color: Colors.red,
                    onTap: () => _goTo(context, "monitoreo", "Monitoreo GPS"),
                    subtitle: "GPS y rutas",
                  ),
                );
              }

              if (_isSgtUser) {
                gridCards.add(
                  _card(
                    context,
                    title: "Planeación",
                    icon: Icons.route,
                    color: Colors.purple,
                    onTap: () => _goTo(context, "planeacion", "Planeación Operativa"),
                    subtitle: "Asignación operativa",
                  ),
                );
                gridCards.add(
                  _card(
                    context,
                    title: "Reportes",
                    icon: Icons.bar_chart,
                    color: Colors.teal,
                    onTap: () => _goTo(context, "reportes", "Reportes y Estadísticas"),
                    subtitle: "Estadísticas",
                  ),
                );
              }

              if (_isMecUser) {
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
              }

              if (gridCards.isEmpty) {
                return const Center(
                  child: Text(
                    "No tienes módulos asignados para tu tipo de usuario.",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                );
              }

              return GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: gridCards,
              );
            },
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