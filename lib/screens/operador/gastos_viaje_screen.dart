import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';

class GastosViajeScreen extends StatefulWidget {
  const GastosViajeScreen({super.key});

  @override
  State<GastosViajeScreen> createState() => _GastosViajeScreenState();
}

class GastoRowData {
  TextEditingController conceptoController = TextEditingController();
  TextEditingController montoController = TextEditingController();
  XFile? photo;
}

class _GastosViajeScreenState extends State<GastosViajeScreen> {
  bool _loadingViajes = true;
  bool _loadingGastosRegistrados = false;
  bool _saving = false;
  
  List<dynamic> _viajes = [];
  int? _selectedAsignacionId;
  
  List<dynamic> _gastosRegistrados = [];
  bool _hasGastos = false;
  final List<GastoRowData> _gastos = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _fetchViajesPendientes();
  }

  Future<void> _fetchViajesPendientes() async {
    setState(() {
      _loadingViajes = true;
    });

    try {
      final response = await ApiService.get(ApiEndpoints.viajesPendientesLiquidar);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          setState(() {
            _viajes = resData["data"];
            if (_viajes.isNotEmpty) {
              _selectedAsignacionId = int.tryParse(_viajes[0]["id_asignacion"]?.toString() ?? "");
              if (_selectedAsignacionId != null) {
                _fetchGastosRegistrados(_selectedAsignacionId!);
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error al obtener viajes pendientes: $e");
    } finally {
      setState(() {
        _loadingViajes = false;
      });
    }
  }

  Future<void> _fetchGastosRegistrados(int asignacionId) async {
    setState(() {
      _loadingGastosRegistrados = true;
    });

    try {
      final response = await ApiService.get("${ApiEndpoints.obtenerGastosViaje}/$asignacionId");
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          setState(() {
            _gastosRegistrados = resData["data"];
          });
        }
      }
    } catch (e) {
      debugPrint("Error al obtener gastos registrados: $e");
    } finally {
      setState(() {
        _loadingGastosRegistrados = false;
      });
    }
  }

  Future<void> _eliminarGastoRegistrado(int idGasto) async {
    try {
      final response = await ApiService.post(
        ApiEndpoints.eliminarGastoViaje,
        {"id_gasto": idGasto},
      );
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Gasto eliminado correctamente."), backgroundColor: Colors.green),
            );
          }
          if (_selectedAsignacionId != null) {
            _fetchGastosRegistrados(_selectedAsignacionId!);
          }
        } else {
          throw Exception(resData["message"]);
        }
      } else {
        throw Exception("Código de estado: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al eliminar gasto: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmarEliminarGasto(int idGasto) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Eliminar Gasto"),
        content: const Text("¿Estás seguro de que deseas eliminar este gasto de viaje? Esto afectará los saldos en el sistema contable."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _eliminarGastoRegistrado(idGasto);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("Eliminar"),
          ),
        ],
      ),
    );
  }

  void _agregarGastoRow() {
    setState(() {
      _gastos.add(GastoRowData());
    });
  }

  void _removerGastoRow(int index) {
    setState(() {
      _gastos[index].conceptoController.dispose();
      _gastos[index].montoController.dispose();
      _gastos.removeAt(index);
    });
  }

  Future<void> _capturarFoto(int index) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _gastos[index].photo = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar ticket de galería: $e")),
      );
    }
  }

  Future<void> _guardarGastos() async {
    if (_selectedAsignacionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor selecciona un viaje / contenedor."), backgroundColor: Colors.red),
      );
      return;
    }

    if (_hasGastos && _gastos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Por favor agrega al menos un concepto de gasto."), backgroundColor: Colors.red),
      );
      return;
    }

    if (_hasGastos) {
      for (var gasto in _gastos) {
        if (gasto.conceptoController.text.trim().isEmpty || gasto.montoController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Por favor completa concepto y monto en todas las filas."), backgroundColor: Colors.red),
          );
          return;
        }
      }
    }

    setState(() {
      _saving = true;
    });

    try {
      List<Map<String, dynamic>> gastosPayload = [];
      for (var row in _gastos) {
        String? base64Photo;
        if (row.photo != null) {
          final bytes = await row.photo!.readAsBytes();
          base64Photo = "data:image/jpeg;base64,${base64Encode(bytes)}";
        }

        gastosPayload.add({
          "concepto": row.conceptoController.text.trim(),
          "monto": double.tryParse(row.montoController.text.trim()) ?? 0.0,
          "evidencia_base64": base64Photo,
        });
      }

      final Map<String, dynamic> payload = {
        "id_asignacion": _selectedAsignacionId,
        "has_gastos": _hasGastos ? "si" : "no",
        "gastos": gastosPayload,
      };

      final response = await ApiService.post(ApiEndpoints.registrarGastosViaje, payload);
      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Gastos de viaje registrados con éxito."), backgroundColor: Colors.green),
          );
          
          setState(() {
            _hasGastos = false;
            for (var row in _gastos) {
              row.conceptoController.dispose();
              row.montoController.dispose();
            }
            _gastos.clear();
          });
          
          if (_selectedAsignacionId != null) {
            _fetchGastosRegistrados(_selectedAsignacionId!);
          }
        }
      } else {
        if (mounted) {
          _mostrarErrorEnvio(errorDetails: "HTTP ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      if (mounted) {
        _mostrarErrorEnvio(errorDetails: e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _mostrarErrorEnvio({String? errorDetails}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Expanded(child: Text("Falla de Conexión")),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "No se pudo registrar los gastos en el servidor debido a señal débil o falta de internet en carretera.",
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Los ${_gastos.length} conceptos y montos capturados se conservan intactos en la pantalla.",
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              if (kDebugMode && errorDetails != null) ...[
                const SizedBox(height: 10),
                const Text(
                  "Detalle Técnico del Error:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      errorDetails,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // SOLO cierra diálogo
            },
            child: const Text("Conservar gastos"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _guardarGastos(); // Reintentar
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text("Reintentar Envío"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(
          child: Image.network(
            url,
            errorBuilder: (c, o, s) => Container(
              height: 200,
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image, size: 40),
            ),
          ),
        ),
      ),
    );
  }

  String _formatCurrency(dynamic amount) {
    final double numVal = (amount is num) 
        ? amount.toDouble() 
        : (double.tryParse(amount?.toString().replaceAll(',', '') ?? '0') ?? 0.0);
    List<String> parts = numVal.toStringAsFixed(2).split('.');
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String formattedInt = parts[0].replaceAllMapped(reg, (Match match) => '${match[1]},');
    return '\$$formattedInt.${parts[1]}';
  }

  Future<void> _generarReporteViaticos() async {
    if (_viajes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay viajes pendientes para generar el reporte.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final response = await ApiService.get(ApiEndpoints.reporteViaticosPdf);

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        final output = await getTemporaryDirectory();
        final file = File("${output.path}/reporte_viaticos_${DateTime.now().millisecondsSinceEpoch}.pdf");
        await file.writeAsBytes(response.bodyBytes);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'Reporte de Viáticos - SGT Logistics',
          ),
        );
      } else {
        String msg = "Error al obtener reporte PDF";
        try {
          final data = jsonDecode(response.body);
          if (data["message"] != null) msg = data["message"];
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("Error generating PDF: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al generar reporte: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  void dispose() {
    for (var row in _gastos) {
      row.conceptoController.dispose();
      row.montoController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos de Viaje'),
        actions: [
          if (_viajes.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Generar reporte de viáticos',
              onPressed: _generarReporteViaticos,
            ),
        ],
      ),
      body: _loadingViajes
          ? const Center(child: CircularProgressIndicator())
          : _viajes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      "No tienes viajes pendientes de liquidar.",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Seleccionar Contenedor / Viaje",
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: _selectedAsignacionId,
                            isExpanded: true,
                            onChanged: (val) {
                              setState(() {
                                _selectedAsignacionId = val;
                                _gastosRegistrados = [];
                              });
                              if (val != null) {
                                _fetchGastosRegistrados(val);
                              }
                            },
                            items: _viajes.map((viaje) {
                              final String numContenedor = viaje["num_contenedor"]?.toString() ?? "Sin Contenedor";
                              final String ref = viaje["referencia_full"]?.toString() ?? "";
                              final String camion = viaje["economico_camion"]?.toString() ?? "N/A";
                              final String placas = viaje["placas_camion"]?.toString() ?? "N/A";
                              return DropdownMenuItem<int>(
                                value: int.tryParse(viaje["id_asignacion"]?.toString() ?? ""),
                                child: Text("$numContenedor - Camión: $camion ($placas)"),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),
                      
                      // 1. Mostrar gastos ya registrados
                      if (_loadingGastosRegistrados)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_gastosRegistrados.isNotEmpty) ...[
                        const Text(
                          "Gastos Registrados Anteriormente",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _gastosRegistrados.length,
                          itemBuilder: (context, index) {
                            final item = _gastosRegistrados[index];
                            final String concepto = item["concepto"] ?? "Sin Concepto";
                            final String monto = item["monto"]?.toString() ?? "0";
                            final String? comprobante = item["comprobante"]?.toString();

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.receipt, color: Colors.grey),
                                title: Text(concepto),
                                subtitle: Text("Monto: ${_formatCurrency(monto)}"),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (comprobante != null && comprobante.isNotEmpty)
                                      IconButton(
                                        icon: const Icon(Icons.image, color: Colors.blue),
                                        onPressed: () {
                                          _showImageDialog("$cleanBaseUrl/$comprobante");
                                        },
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        final int? idGasto = int.tryParse(item["id"]?.toString() ?? "");
                                        if (idGasto != null) {
                                          _confirmarEliminarGasto(idGasto);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                      ],


                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: SwitchListTile(
                          value: _hasGastos,
                          title: const Text(
                            "¿Tiene nuevos gastos que registrar?",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text("Habilita esta opción para agregar conceptos y tickets"),
                          activeColor: Colors.orange.shade800,
                          onChanged: (val) {
                            setState(() {
                              _hasGastos = val;
                              if (_hasGastos && _gastos.isEmpty) {
                                _agregarGastoRow();
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_hasGastos) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Nuevos Conceptos",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            TextButton.icon(
                              onPressed: _agregarGastoRow,
                              icon: const Icon(Icons.add, color: Colors.blue),
                              label: const Text("Agregar Fila", style: TextStyle(color: Colors.blue)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _gastos.length,
                          itemBuilder: (context, index) {
                            final row = _gastos[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Gasto #${index + 1}",
                                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                                        ),
                                        if (_gastos.length > 1)
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                                            onPressed: () => _removerGastoRow(index),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: row.conceptoController,
                                      decoration: const InputDecoration(
                                        labelText: "Concepto (Ej. Casetas, Maniobras, Taxi)",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: row.montoController,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      decoration: const InputDecoration(
                                        labelText: "Monto (\$)",
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () => _capturarFoto(index),
                                            icon: const Icon(Icons.photo_library, size: 18),
                                            label: Text(row.photo == null ? "Seleccionar Ticket" : "Cambiar Ticket"),
                                            style: OutlinedButton.styleFrom(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                          ),
                                        ),
                                        if (row.photo != null) ...[
                                          const SizedBox(width: 12),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: Image.file(
                                              File(row.photo!.path),
                                              width: 50,
                                              height: 50,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.close, color: Colors.red),
                                            onPressed: () {
                                              setState(() {
                                                row.photo = null;
                                              });
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 35),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _guardarGastos,
                          icon: _saving
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.save),
                          label: Text(_saving ? "Guardando..." : "Guardar Gastos de Viaje"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade800,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
