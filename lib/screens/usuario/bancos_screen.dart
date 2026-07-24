import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/api_config.dart';
import '/api/api_service.dart';
import '../../utils/file_helper.dart';

class BancosScreen extends StatefulWidget {
  const BancosScreen({super.key});

  @override
  State<BancosScreen> createState() => _BancosScreenState();
}

class _BancosScreenState extends State<BancosScreen> {
  bool _isLoading = true;
  DateTime _fechaCorte = DateTime.now();
  List<dynamic> _cuentas = [];
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _fetchBancos();
  }

  Future<void> _fetchBancos() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final String formattedDate = DateFormat('yyyy-MM-dd').format(_fechaCorte);
      final response = await ApiService.get(
        "${ApiConfig.baseUrl}/dashboard/bancos?fecha_corte=$formattedDate",
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["success"] == true) {
          setState(() {
            _cuentas = data["data"] ?? [];
            _isLoading = false;
          });
        } else {
          throw Exception(data["mensaje"] ?? "Error al obtener las cuentas.");
        }
      } else {
        throw Exception("Error del servidor: ${response.statusCode}");
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll("Exception:", "");
        _isLoading = false;
      });
    }
  }

  Future<void> _selectFechaCorte(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _fechaCorte,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Color(0xFF1F2937),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _fechaCorte) {
      setState(() {
        _fechaCorte = picked;
      });
      _fetchBancos();
    }
  }

  Future<void> _descargarReporte(int idCuenta) async {
    final String formattedDate = DateFormat('yyyy-MM-dd').format(_fechaCorte);
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get(
        "${ApiConfig.baseUrl}/dashboard/bancos/$idCuenta/reporte?fecha_de=$formattedDate&fecha_hasta=$formattedDate",
      );

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        await saveAndOpenFile(bytes, "Reporte_Banco_${idCuenta}_$formattedDate.pdf");
      } else {
        throw Exception("Error del servidor: código ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al descargar reporte: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _enviarCorreo(int idCuenta) async {
    final TextEditingController emailController = TextEditingController();
    final String formattedDate = DateFormat('yyyy-MM-dd').format(_fechaCorte);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text("Enviar Estado de Cuenta", style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Ingrese el correo electrónico destinatario:", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "ejemplo@sgt.com",
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF111827),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar", style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text("Enviar"),
          ),
        ],
      ),
    );

    if (confirmed == true && emailController.text.isNotEmpty) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await ApiService.post(
          "${ApiConfig.baseUrl}/dashboard/reportes/generar",
          {
            "tipo_reporte": "banco_reporte",
            "fecha_de": formattedDate,
            "fecha_hasta": formattedDate,
            "id_banco": idCuenta,
            "enviar_correo": true,
            "correo_destinatario": emailController.text.trim(),
          },
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data["success"] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data["mensaje"] ?? "Reporte enviado con éxito."), backgroundColor: Colors.green),
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
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

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
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      "Cuentas Bancarias",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Fecha de Corte:",
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_fechaCorte),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _selectFechaCorte(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.calendar_month, size: 18),
                        label: const Text("Cambiar"),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                _errorMessage,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : _cuentas.isEmpty
                            ? const Center(
                                child: Text(
                                  "No se encontraron cuentas activas.",
                                  style: TextStyle(color: Colors.white54, fontSize: 16),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _cuentas.length,
                                itemBuilder: (context, index) {
                                  final item = _cuentas[index];
                                  final double saldoActual = double.tryParse(item["saldo_actual"]?.toString() ?? "0") ?? 0.0;
                                  final double saldoAnterior = double.tryParse(item["saldo_anterior"]?.toString() ?? "0") ?? 0.0;
                                  final String bancoNombre = item["banco"]?.toString() ?? "Banco";
                                  final String beneficiario = item["nombre_beneficiario"]?.toString() ?? "N/A";
                                  final String idStr = item["id"]?.toString() ?? "";
                                  final int? id = int.tryParse(idStr);

                                  return Card(
                                    color: const Color(0xFF1E293B).withOpacity(0.6),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      side: BorderSide(color: Colors.white.withOpacity(0.05)),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  bancoNombre,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  item["tipo"]?.toString().toUpperCase() ?? "CUENTA",
                                                  style: const TextStyle(
                                                    color: Colors.tealAccent,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            "Titular: $beneficiario",
                                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                                          ),
                                          const Divider(color: Colors.white10, height: 24),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text("SALDO ANTERIOR", style: TextStyle(color: Colors.white38, fontSize: 10)),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    currencyFormat.format(saldoAnterior),
                                                    style: const TextStyle(color: Colors.white60, fontSize: 14, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text("SALDO AL CORTE", style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    currencyFormat.format(saldoActual),
                                                    style: const TextStyle(color: Colors.tealAccent, fontSize: 18, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          if (id != null)
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () => _descargarReporte(id),
                                                    style: OutlinedButton.styleFrom(
                                                      foregroundColor: Colors.tealAccent,
                                                      side: const BorderSide(color: Colors.teal),
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                    ),
                                                    icon: const Icon(Icons.file_download, size: 16),
                                                    label: const Text("Descargar PDF"),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                IconButton(
                                                  onPressed: () => _enviarCorreo(id),
                                                  icon: const Icon(Icons.mail_outline, color: Colors.tealAccent),
                                                  style: IconButton.styleFrom(
                                                    backgroundColor: Colors.teal.withOpacity(0.1),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                      side: BorderSide(color: Colors.teal.withOpacity(0.3)),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
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
