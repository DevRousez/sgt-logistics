import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '/api/api_service.dart';
import '../../utils/file_helper.dart';

class ReportesListScreen extends StatefulWidget {
  const ReportesListScreen({super.key});

  @override
  State<ReportesListScreen> createState() => _ReportesListScreenState();
}

class _ReportesListScreenState extends State<ReportesListScreen> {
  bool _isLoading = false;
  List<dynamic> _clientes = [];
  List<dynamic> _proveedores = [];
  List<dynamic> _camiones = [];
  String _errorMessage = "";

  final List<Map<String, dynamic>> _reportOptions = [
    {
      "id": "cxc",
      "titulo": "Cuentas por Cobrar",
      "descripcion": "Análisis de cuentas pendientes de cobro.",
      "icon": Icons.account_balance_wallet,
      "color": Colors.teal,
    },
    {
      "id": "cxp",
      "titulo": "Cuentas por Pagar",
      "descripcion": "Análisis de cuentas pendientes de pago.",
      "icon": Icons.payments,
      "color": Colors.red,
    },
    {
      "id": "viajes",
      "titulo": "Viajes Realizados",
      "descripcion": "Reporte detallado de viajes históricos.",
      "icon": Icons.local_shipping,
      "color": Colors.blue,
    },
    {
      "id": "utilidad",
      "titulo": "Reporte de Resultados",
      "descripcion": "Resumen de utilidad y rentabilidad de viajes.",
      "icon": Icons.insights,
      "color": Colors.purple,
    },
    {
      "id": "documentos",
      "titulo": "Reporte de Documentos",
      "descripcion": "Estatus y bitácora de documentos adjuntos.",
      "icon": Icons.description,
      "color": Colors.amber,
    },
    {
      "id": "validacion_documentos",
      "titulo": "Validación de Documentos",
      "descripcion": "Listado de validación y control de archivos.",
      "icon": Icons.fact_check,
      "color": Colors.indigo,
    },
    {
      "id": "liquidados_cxc",
      "titulo": "Liquidados CxC",
      "descripcion": "Movimientos ya saldados de clientes.",
      "icon": Icons.check_circle_outline,
      "color": Colors.green,
    },
    {
      "id": "liquidados_cxp",
      "titulo": "Liquidados CxP",
      "descripcion": "Movimientos ya saldados de proveedores.",
      "icon": Icons.task_alt,
      "color": Colors.orange,
    },
    {
      "id": "rendimiento",
      "titulo": "Rendimiento y Combustible",
      "descripcion": "Análisis de consumo y eficiencia de unidades.",
      "icon": Icons.local_gas_station,
      "color": Colors.pink,
    },
    {
      "id": "gastos_pagar",
      "titulo": "Gastos por Pagar",
      "descripcion": "Registro y control de gastos administrativos.",
      "icon": Icons.money_off,
      "color": Colors.cyan,
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchCatalogs();
  }

  Future<void> _fetchCatalogs() async {
    try {
      final response = await ApiService.get(
        "${ApiConfig.baseUrl}/dashboard/catalogos-programar-viaje",
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true && data["data"] != null) {
          setState(() {
            _clientes = data["data"]["clientes"] ?? [];
            _proveedores = data["data"]["proveedores"] ?? [];
            _camiones = data["data"]["camiones"] ?? [];
          });
        }
      }
    } catch (e) {
      // Non-blocking catch
    }
  }

  void _openFilterDialog(Map<String, dynamic> report) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReportFilterSheet(
        report: report,
        clientes: _clientes,
        proveedores: _proveedores,
        camiones: _camiones,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      "Reportes Operativos",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  "Selecciona el reporte que deseas generar o enviar:",
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ),

              const SizedBox(height: 16),

              // Reports Grid
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _reportOptions.length,
                  itemBuilder: (context, index) {
                    final report = _reportOptions[index];
                    final Color color = report["color"];

                    return Card(
                      color: const Color(0xFF1E293B).withOpacity(0.6),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      child: InkWell(
                        onTap: () => _openFilterDialog(report),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: color.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(report["icon"], color: color, size: 24),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      report["titulo"],
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      report["descripcion"],
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.white30),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportFilterSheet extends StatefulWidget {
  final Map<String, dynamic> report;
  final List<dynamic> clientes;
  final List<dynamic> proveedores;
  final List<dynamic> camiones;

  const _ReportFilterSheet({
    required this.report,
    required this.clientes,
    required this.proveedores,
    required this.camiones,
  });

  @override
  State<_ReportFilterSheet> createState() => _ReportFilterSheetState();
}

class _ReportFilterSheetState extends State<_ReportFilterSheet> {
  DateTime _fechaInicio = DateTime.now().subtract(const Duration(days: 30));
  DateTime _fechaFin = DateTime.now();
  String _formato = "pdf"; // 'pdf' or 'excel'
  String? _selectedClientId;
  String? _selectedProviderId;
  String? _selectedUnitId;
  bool _enviarCorreo = false;
  final TextEditingController _emailController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _fechaInicio, end: _fechaFin),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Color(0xFF1F2937),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF1F2937),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: Colors.tealAccent,
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fechaInicio = picked.start;
        _fechaFin = picked.end;
      });
    }
  }

  Future<void> _descargarReporte() async {
    if (widget.report["id"] == "rendimiento" && _selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor, seleccione una unidad."), backgroundColor: Colors.orange),
      );
      return;
    }
    setState(() {
      _isSubmitting = true;
    });

    final String startStr = DateFormat('yyyy-MM-dd').format(_fechaInicio);
    final String endStr = DateFormat('yyyy-MM-dd').format(_fechaFin);

    final Map<String, dynamic> body = {
      "tipo_reporte": widget.report["id"],
      "formato": _formato,
      "fecha_de": startStr,
      "fecha_hasta": endStr,
      "fecha_inicio": startStr,
      "fecha_fin": endStr,
    };

    if (_selectedClientId != null) {
      body["id_client"] = _selectedClientId;
      body["cliente_id"] = _selectedClientId;
    }
    if (_selectedProviderId != null) {
      body["id_proveedor"] = _selectedProviderId;
      body["proveedor_id"] = _selectedProviderId;
    }
    if (_selectedUnitId != null) {
      body["unidad_id"] = _selectedUnitId;
    }

    try {
      final response = await ApiService.post(
        "${ApiConfig.baseUrl}/dashboard/reportes/generar",
        body,
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final String ext = _formato == "excel" ? "xlsx" : "pdf";
        await saveAndOpenFile(bytes, "Reporte_${widget.report["id"]}_$startStr.$ext");
      } else {
        throw Exception("Error del servidor: código ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al descargar reporte: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  Future<void> _enviarPorCorreo() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingrese un correo válido."), backgroundColor: Colors.red),
      );
      return;
    }

    if (widget.report["id"] == "rendimiento" && _selectedUnitId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor, seleccione una unidad."), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final String startStr = DateFormat('yyyy-MM-dd').format(_fechaInicio);
    final String endStr = DateFormat('yyyy-MM-dd').format(_fechaFin);

    final Map<String, dynamic> body = {
      "tipo_reporte": widget.report["id"],
      "formato": _formato,
      "fecha_de": startStr,
      "fecha_hasta": endStr,
      "fecha_inicio": startStr,
      "fecha_fin": endStr,
      "enviar_correo": true,
      "correo_destinatario": _emailController.text.trim(),
    };

    if (_selectedClientId != null) {
      body["id_client"] = _selectedClientId;
      body["cliente_id"] = _selectedClientId;
    }
    if (_selectedProviderId != null) {
      body["id_proveedor"] = _selectedProviderId;
      body["proveedor_id"] = _selectedProviderId;
    }
    if (_selectedUnitId != null) {
      body["unidad_id"] = _selectedUnitId;
    }

    try {
      final response = await ApiService.post(
        "${ApiConfig.baseUrl}/dashboard/reportes/generar",
        body,
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data["success"] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["mensaje"] ?? "Reporte enviado por correo con éxito."), backgroundColor: Colors.green),
        );
      } else {
        throw Exception(data["mensaje"] ?? "Error al enviar el reporte.");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String reportId = widget.report["id"];
    final bool showClientFilter = reportId == "cxc" || reportId == "liquidados_cxc";
    final bool showProviderFilter = reportId == "cxp" || reportId == "liquidados_cxp" || reportId == "gastos_pagar";

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Icon(widget.report["icon"], color: widget.report["color"]),
              const SizedBox(width: 10),
              Text(
                widget.report["titulo"],
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Date Picker trigger
          const Text("Rango de Fechas:", style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => _selectDateRange(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${DateFormat('dd/MM/yyyy').format(_fechaInicio)}   ➔   ${DateFormat('dd/MM/yyyy').format(_fechaFin)}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.date_range, color: Colors.tealAccent),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Client Dropdown
          if (showClientFilter && widget.clientes.isNotEmpty) ...[
            const Text("Filtrar por Cliente (Opcional):", style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF0F172A),
              value: _selectedClientId,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text("Todos los clientes", style: TextStyle(color: Colors.white54))),
                ...widget.clientes.map((c) => DropdownMenuItem(
                      value: c["id"]?.toString(),
                      child: Text(c["nombre"]?.toString() ?? "Cliente", overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedClientId = val),
            ),
            const SizedBox(height: 16),
          ],

          // Provider Dropdown
          if (showProviderFilter && widget.proveedores.isNotEmpty) ...[
            const Text("Filtrar por Proveedor (Opcional):", style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF0F172A),
              value: _selectedProviderId,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text("Todos los proveedores", style: TextStyle(color: Colors.white54))),
                ...widget.proveedores.map((p) => DropdownMenuItem(
                      value: p["id"]?.toString(),
                      child: Text(p["nombre"]?.toString() ?? "Proveedor", overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (val) => setState(() => _selectedProviderId = val),
            ),
            const SizedBox(height: 16),
          ],

          // Unit / Camión Dropdown (Rendimiento only)
          if (reportId == "rendimiento" && widget.camiones.isNotEmpty) ...[
            const Text("Seleccionar Unidad (Obligatorio):", style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF0F172A),
              value: _selectedUnitId,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              items: widget.camiones.map((u) => DropdownMenuItem(
                    value: u["id"]?.toString(),
                    child: Text("${u["economico"] ?? 'Unidad'} - ${u["placas"] ?? ''}", overflow: TextOverflow.ellipsis),
                  )).toList(),
              onChanged: (val) => setState(() => _selectedUnitId = val),
            ),
            const SizedBox(height: 16),
          ],

          // Format selector
          const Text("Formato del reporte:", style: TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: RadioListTile<String>(
                  title: const Text("PDF Document", style: TextStyle(color: Colors.white)),
                  value: "pdf",
                  groupValue: _formato,
                  activeColor: Colors.tealAccent,
                  onChanged: (val) => setState(() => _formato = val!),
                ),
              ),
              Expanded(
                child: RadioListTile<String>(
                  title: const Text("Excel Sheet", style: TextStyle(color: Colors.white)),
                  value: "excel",
                  groupValue: _formato,
                  activeColor: Colors.tealAccent,
                  onChanged: (val) => setState(() => _formato = val!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Email switch
          SwitchListTile(
            title: const Text("Enviar por Correo Electrónico", style: TextStyle(color: Colors.white, fontSize: 14)),
            subtitle: const Text("Se enviará el archivo como adjunto", style: TextStyle(color: Colors.white54, fontSize: 12)),
            value: _enviarCorreo,
            activeColor: Colors.tealAccent,
            onChanged: (val) => setState(() => _enviarCorreo = val),
          ),

          if (_enviarCorreo) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "correo@ejemplo.com",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],

          const SizedBox(height: 24),

          // Action CTAs
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : (_enviarCorreo ? _enviarPorCorreo : _descargarReporte),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Icon(_enviarCorreo ? Icons.mail : Icons.download),
                  label: Text(_isSubmitting
                      ? "Procesando..."
                      : (_enviarCorreo ? "Enviar por Correo" : "Descargar Reporte")),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
