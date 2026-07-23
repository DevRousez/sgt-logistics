import 'package:flutter/material.dart';
import '/api/api_service.dart';
import 'sgt_dashboard_screen.dart';
import 'mep_dashboard_screen.dart';
import 'mec_dashboard_screen.dart';

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
    if (data != null && data["user"] != null) {
      final user = data["user"];
      final List<dynamic> permissions = user["permissions"] ?? [];
      final List<dynamic> roles = user["roles"] ?? [];

      if (permissions.contains("SGT-movil") || roles.contains("SGT-movil") || (permissions.isEmpty && roles.isEmpty)) {
        _userType = "SGT";
      } else if (permissions.contains("MEP-movil") || roles.contains("MEP-movil")) {
        _userType = "MEP";
      } else if (permissions.contains("MEC-movil") || roles.contains("MEC-movil")) {
        _userType = "MEC";
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

    if (_userType == "SGT") {
      return const SgtDashboardScreen();
    } else if (_userType == "MEP") {
      return const MepDashboardScreen();
    } else if (_userType == "MEC") {
      return const MecDashboardScreen();
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Panel de Control")),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            "Tu usuario no posee los permisos SGT-movil, MEP-movil ni MEC-movil asignados para acceder a la aplicación.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}