import 'package:flutter/material.dart';
import 'dart:convert';
import '/api/api_service.dart';
import '/config/api_config.dart';

class ProgramarViajeScreen extends StatefulWidget {
  const ProgramarViajeScreen({super.key});

  @override
  State<ProgramarViajeScreen> createState() => _ProgramarViajeScreenState();
}

class _ProgramarViajeScreenState extends State<ProgramarViajeScreen> {
  bool _isLoadingCatalogs = true;
  bool _isSaving = false;

  List<dynamic> _contenedores = [];
  List<dynamic> _operadores = [];
  List<dynamic> _camiones = [];
  List<dynamic> _chasis = [];

  String? _selectedContenedor;
  String? _selectedOperador;
  String? _selectedCamion;
  String? _selectedChasis;
  String? _selectedChasis2;

  bool _esFull = false;

  DateTime? _fechaInicio;
  DateTime? _fechaFin;

  final TextEditingController _dieselController = TextEditingController();
  final TextEditingController _ureaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCatalogs();
  }

  Future<void> _loadCatalogs() async {
    try {
      final response = await ApiService.get("${ApiConfig.baseUrl}/dashboard/catalogos-programar-viaje");
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body["success"] == true && body["data"] != null) {
          final data = body["data"];
          setState(() {
            _contenedores = data["contenedores"] ?? [];
            _operadores = data["operadores"] ?? [];
            _camiones = data["camiones"] ?? [];
            _chasis = data["chasis"] ?? [];
            _isLoadingCatalogs = false;
          });
          return;
        }
      }
      throw Exception("Error al cargar los catálogos del servidor");
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
      setState(() {
        _isLoadingCatalogs = false;
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isInicio) async {
    final DateTime initialDate = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(initialDate.year - 1),
      lastDate: DateTime(initialDate.year + 2),
    );

    if (picked != null) {
      setState(() {
        if (isInicio) {
          _fechaInicio = picked;
        } else {
          _fechaFin = picked;
        }
      });
    }
  }

  String _formatDate(DateTime date) {
    // Format: dd/MM/yyyy
    final String day = date.day.toString().padLeft(2, '0');
    final String month = date.month.toString().padLeft(2, '0');
    final String year = date.year.toString();
    return "$day/$month/$year";
  }

  Future<void> _savePlaneacion() async {
    if (_selectedContenedor == null ||
        _selectedOperador == null ||
        _selectedCamion == null ||
        _selectedChasis == null ||
        (_esFull && _selectedChasis2 == null) ||
        _fechaInicio == null ||
        _fechaFin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor complete todos los campos obligatorios")),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final payload = {
        "num_contenedor": jsonEncode([_selectedContenedor]),
        "txtFechaInicio": _formatDate(_fechaInicio!),
        "txtFechaFinal": _formatDate(_fechaFin!),
        "cmbCamion": int.tryParse(_selectedCamion!) ?? 0,
        "cmbChasis": int.tryParse(_selectedChasis!) ?? 0,
        "cmbChasis2": _esFull ? (int.tryParse(_selectedChasis2!) ?? 0) : null,
        "cmbTipoUnidad": _esFull ? "Full" : "Sencillo",
        "cmbOperador": int.tryParse(_selectedOperador!) ?? 0,
        "litros_diesel": double.tryParse(_dieselController.text.trim()) ?? 0.0,
        "litros_urea": double.tryParse(_ureaController.text.trim()) ?? 0.0,
        "tipoViaje": "propio"
      };

      final response = await ApiService.post(
        "${ApiConfig.baseUrl}/dashboard/programar-viaje",
        payload,
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["TMensaje"] == "success") {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data["Mensaje"] ?? "Viaje programado correctamente"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        String errMsg = data["Mensaje"] ?? "Hubo un error al guardar la planeación.";
        throw Exception(errMsg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Programar Viaje( Elemental )"),
      ),
      body: _isLoadingCatalogs
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Nueva Asignación de Viaje",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Dropdown Contenedor
                  _buildDropdown(
                    label: "Contenedor *",
                    hint: "Seleccione Contenedor Aprobado",
                    value: _selectedContenedor,
                    items: _contenedores,
                    onChanged: (val) {
                      final found = _contenedores.firstWhere(
                        (element) => element["id"]?.toString() == val,
                        orElse: () => {},
                      );
                      final bool isFullVal = found != null &&
                          found["referencia_full"] != null &&
                          found["referencia_full"].toString().trim().isNotEmpty;
                      
                      setState(() {
                        _selectedContenedor = val;
                        _esFull = isFullVal;
                        if (!_esFull) {
                          _selectedChasis2 = null;
                        }
                      });
                    },
                  ),
                  if (_esFull) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.layers, size: 16, color: Colors.indigo.shade800),
                          const SizedBox(width: 8),
                          const Text(
                            "Viaje detectado como FULL (Requiere doble chasis)",
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Dropdown Operador
                  _buildDropdown(
                    label: "Operador (Chofer) *",
                    hint: "Seleccione Chofer",
                    value: _selectedOperador,
                    items: _operadores,
                    onChanged: (val) {
                      setState(() {
                        _selectedOperador = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Dropdown Camión
                  _buildDropdown(
                    label: "Camión (Unidad) *",
                    hint: "Seleccione Unidad Económica",
                    value: _selectedCamion,
                    items: _camiones,
                    onChanged: (val) {
                      setState(() {
                        _selectedCamion = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),

                  // Dropdown Chasis A (o Chasis único si es sencillo)
                  _buildDropdown(
                    label: _esFull ? "Chasis A *" : "Chasis *",
                    hint: "Seleccione Chasis A",
                    value: _selectedChasis,
                    items: _chasis,
                    onChanged: (val) {
                      setState(() {
                        _selectedChasis = val;
                      });
                    },
                  ),
                  
                  // Dropdown Chasis B (solo si es FULL)
                  if (_esFull) ...[
                    const SizedBox(height: 16),
                    _buildDropdown(
                      label: "Chasis B *",
                      hint: "Seleccione Chasis B",
                      value: _selectedChasis2,
                      items: _chasis,
                      onChanged: (val) {
                        setState(() {
                          _selectedChasis2 = val;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Fechas
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context, true),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Fecha Inicio *",
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              _fechaInicio == null ? "Seleccionar" : _formatDate(_fechaInicio!),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: InkWell(
                          onTap: () => _selectDate(context, false),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: "Fecha Fin *",
                              border: OutlineInputBorder(),
                            ),
                            child: Text(
                              _fechaFin == null ? "Seleccionar" : _formatDate(_fechaFin!),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Litros Diesel y Urea (Opcional)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _dieselController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Lts Diésel Estimados",
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _ureaController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: "Lts Urea Estimados",
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Botón Guardar
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _savePlaneacion,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              "Programar Viaje",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String hint,
    required String? value,
    required List<dynamic> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 14)),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: items.map((e) {
            final String id = e["id"]?.toString() ?? "";
            final String nombre = e["nombre"]?.toString() ?? "";
            return DropdownMenuItem<String>(
              value: id,
              child: Text(nombre, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
