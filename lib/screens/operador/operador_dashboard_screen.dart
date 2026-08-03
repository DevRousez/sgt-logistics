import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'registrar_diesel_screen.dart';
import 'carga_contenedor_screen.dart';
import 'finalizar_viaje_screen.dart';
import '../home_screen.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';
import '../../utils/file_downloader.dart';

class OperadorDashboardScreen extends StatefulWidget {
  const OperadorDashboardScreen({super.key});

  @override
  State<OperadorDashboardScreen> createState() => _OperadorDashboardScreenState();
}

class _OperadorDashboardScreenState extends State<OperadorDashboardScreen> {
  String? _nombre;
  String? _unidad;
  String? _idEquipo;
  int? _idAsignacion;

  List<Map<String, dynamic>> _documentos = [];
  bool _loadingDocs = false;

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
        _idAsignacion = int.tryParse(data["id_asignacion"]?.toString() ?? "");
      });
    }
  }

  Future<void> _descargarYVerArchivo(BuildContext context, String url, String fileName) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Descargando $fileName..."),
          duration: const Duration(seconds: 2),
        ),
      );

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        await OpenFilex.open(file.path);
      } else {
        throw Exception("Status code: ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No se pudo abrir localmente. Abriendo en navegador..."),
          backgroundColor: Colors.orange,
        ),
      );
      try {
        final Uri uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (err) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error al abrir enlace: $err"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _fetchAndShowDocuments() async {
    setState(() {
      _loadingDocs = true;
    });

    try {
      if (_idAsignacion == null) {
        final data = await ApiService.getUserData();
        if (data != null) {
          _idAsignacion = int.tryParse(data["id_asignacion"]?.toString() ?? "");
        }
      }

      if (_idAsignacion == null) {
        throw Exception("No hay asignación activa");
      }

      final response = await ApiService.post(
        ApiEndpoints.estatusFlujo,
        {"id_asignacion": _idAsignacion},
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final flowData = resData["data"];
          final List<Map<String, dynamic>> tempDocs = [];

          // 1. Verificar si viene una lista explícita configurable "documentos_viaje"
          if (flowData["documentos_viaje"] != null && flowData["documentos_viaje"] is List) {
            for (var item in flowData["documentos_viaje"]) {
              tempDocs.add({
                "nombre": item["nombre"]?.toString() ?? "Documento",
                "url": item["url"]?.toString() ?? "",
              });
            }
          } else {
            // 2. Fallback: buscar propiedades comunes de documentos y autoconstruir el link
            final dynamic docData = flowData["documentos"] ?? flowData;
            if (docData is Map) {
              final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
              final cotizacionId = flowData["cotizacion_id"] ?? flowData["id_cotizacion"] ?? "";

              docData.forEach((key, value) {
                final keyStr = key.toString().toLowerCase();
                if (value != null && value.toString().isNotEmpty && 
                    (keyStr.contains('doda') || 
                     keyStr.contains('boleta') || 
                     keyStr.contains('carta_porte') ||
                     keyStr.contains('eir') ||
                     keyStr.contains('pdf') ||
                     keyStr.contains('xml') ||
                     keyStr.contains('documento'))) {
                  
                  // Generar un nombre limpio legible
                  String label = key.toString().replaceAll('_', ' ').toUpperCase();
                  if (label == "BOLETA LIBERACION") label = "Boleta de Liberación";
                  if (label == "BOLETA VACIO") label = "Boleta de Vacío";
                  if (label == "DODA") label = "Documento DODA";
                  if (label == "CARTA PORTE") label = "Carta Porte PDF";

                  String urlStr = value.toString();
                  if (!urlStr.startsWith('http')) {
                    urlStr = "$cleanBaseUrl/cotizaciones/cotizacion$cotizacionId/$urlStr";
                  }

                  tempDocs.add({
                    "nombre": label,
                    "url": urlStr,
                  });
                }
              });
            }
          }

          setState(() {
            _documentos = tempDocs;
          });
        }
      }
    } catch (e) {
      print("Error fetching documents: $e");
    } finally {
      setState(() {
        _loadingDocs = false;
      });
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.description, color: Colors.blue),
                      SizedBox(width: 10),
                      Text("Documentos"),
                    ],
                  ),
                  if (_documentos.length > 1)
                    IconButton(
                      icon: const Icon(Icons.download_for_offline, color: Colors.blue),
                      tooltip: "Descargar todos",
                      onPressed: () {
                        final List<String> urls = _documentos.map((d) => d["url"]?.toString() ?? "").toList();
                        FileDownloader.downloadAllFiles(
                          context: context,
                          urls: urls,
                          prefix: "documento_viaje",
                        );
                      },
                    ),
                ],
              ),
              content: _loadingDocs
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _documentos.isEmpty
                      ? const Text("No se encontraron documentos asignados a este viaje.")
                      : SizedBox(
                          width: double.maxFinite,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _documentos.length,
                            separatorBuilder: (_, __) => const Divider(),
                            itemBuilder: (context, index) {
                              final doc = _documentos[index];
                              final String url = doc["url"] ?? "";
                              final String extension = url.endsWith('.xml') ? 'xml' : 'pdf';
                              return ListTile(
                                leading: Icon(
                                  extension == 'xml' ? Icons.code : Icons.picture_as_pdf,
                                  color: extension == 'xml' ? Colors.blue : Colors.red,
                                ),
                                title: Text(
                                  doc["nombre"] ?? "Documento",
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: const Text("Toca para descargar en tu galería/descargas"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.download, color: Colors.blue),
                                  onPressed: () {
                                    final String url = doc["url"] ?? "";
                                    final String nombre = doc["nombre"] ?? "documento";
                                    final String extension = url.endsWith('.xml') ? 'xml' : 'pdf';
                                    if (url.isNotEmpty) {
                                      FileDownloader.downloadFile(
                                        context: context,
                                        url: url,
                                        fileName: "${nombre.replaceAll(' ', '_')}.$extension",
                                      );
                                    }
                                  },
                                ),
                                onTap: () {
                                  final String url = doc["url"] ?? "";
                                  final String nombre = doc["nombre"] ?? "documento";
                                  final String extension = url.endsWith('.xml') ? 'xml' : 'pdf';
                                  if (url.isNotEmpty) {
                                    FileDownloader.downloadFile(
                                      context: context,
                                      url: url,
                                      fileName: "${nombre.replaceAll(' ', '_')}.$extension",
                                    );
                                  }
                                },
                              );
                            },
                          ),
                        ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cerrar"),
                ),
              ],
            );
          },
        );
      },
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
              title: const Text('Concluir Viaje'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FinalizarViajeScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.blue),
              title: const Text('Documentos del Viaje'),
              onTap: _fetchAndShowDocuments,
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