import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';
import '/utils/file_downloader.dart';
import '../home_screen.dart';

class EmpresasDocumentosDashboardScreen extends StatefulWidget {
  const EmpresasDocumentosDashboardScreen({super.key});

  @override
  State<EmpresasDocumentosDashboardScreen> createState() =>
      _EmpresasDocumentosDashboardScreenState();
}

class _EmpresasDocumentosDashboardScreenState
    extends State<EmpresasDocumentosDashboardScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _contenedores = [];
  List<Map<String, dynamic>> _filteredContenedores = [];
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  Timer? _countdownTimer;
  String? _userName;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _fetchContenedores();
    // Actualizar conteo cada minuto
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserInfo() async {
    final data = await ApiService.getUserData();
    if (data != null && data["user"] != null) {
      final user = data["user"];
      setState(() {
        _userName = user["name"];
        _userEmail = user["email"];
      });
    }
  }

  Future<void> _fetchContenedores() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.get(ApiEndpoints.documentosEmpresasContenedores);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final List<dynamic> list = resData["data"];
          setState(() {
            _contenedores = list.map((item) => Map<String, dynamic>.from(item)).toList();
            _applyFilter();
          });
        } else {
          setState(() {
            _errorMessage = resData["message"] ?? "No se encontraron datos.";
          });
        }
      } else {
        setState(() {
          _errorMessage = "Error del servidor: Código ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Error de conexión: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredContenedores = List.from(_contenedores);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredContenedores = _contenedores.where((item) {
        final numContenedor = (item["num_contenedor"] ?? "").toString().toLowerCase();
        final empresa = (item["empresa_nombre"] ?? "").toString().toLowerCase();
        final cliente = (item["cliente_nombre"] ?? "").toString().toLowerCase();
        final origen = (item["origen"] ?? "").toString().toLowerCase();
        final destino = (item["destino"] ?? "").toString().toLowerCase();
        return numContenedor.contains(query) ||
            empresa.contains(query) ||
            cliente.contains(query) ||
            origen.contains(query) ||
            destino.contains(query);
      }).toList();
    }
  }

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.redAccent),
            SizedBox(width: 10),
            Text("Cerrar Sesión"),
          ],
        ),
        content: const Text(
          "¿Estás seguro de que deseas salir de la aplicación?",
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancelar", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiService.setToken('');
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text("Cerrar Sesión", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _formatRemainingTime(String? fechaFinStr) {
    if (fechaFinStr == null || fechaFinStr.isEmpty) return "24h";
    try {
      final fin = DateTime.parse(fechaFinStr);
      final now = DateTime.now();
      final diff = fin.difference(now);
      if (diff.isNegative) {
        return "Expirado";
      }
      final hours = diff.inHours;
      final minutes = diff.inMinutes % 60;
      if (hours > 0) {
        return "Quedan ${hours}h ${minutes}m";
      } else {
        return "Quedan ${minutes}m";
      }
    } catch (_) {
      return "24h";
    }
  }

  void _showLoadingDialog(String title, ValueNotifier<String> statusNotifier) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ValueListenableBuilder<String>(
            valueListenable: statusNotifier,
            builder: (context, statusText, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E3A8A)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    statusText,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _shareFileDirectly(String url, String fileName) async {
    final statusNotifier = ValueNotifier<String>("Descargando archivo...");
    _showLoadingDialog("Preparando Archivo", statusNotifier);

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception("Error de descarga: ${response.statusCode}");
      }

      statusNotifier.value = "Abriendo opciones para compartir...";
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          text: 'Documento: $fileName',
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No se pudo compartir el archivo: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _shareWhatsAppOrAll({
    required List<Map<String, dynamic>> availableDocs,
    required String waText,
    required String prefix,
  }) async {
    if (availableDocs.isEmpty) {
      if (waText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No hay información de viaje para compartir."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final encoded = Uri.encodeComponent(waText);
      final waUri = Uri.parse("whatsapp://send?text=$encoded");
      final waWebUri = Uri.parse("https://api.whatsapp.com/send?text=$encoded");

      try {
        if (await canLaunchUrl(waUri)) {
          await launchUrl(waUri, mode: LaunchMode.externalApplication);
          return;
        } else if (await canLaunchUrl(waWebUri)) {
          await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
          return;
        }
      } catch (_) {}

      // Fallback si la app de WhatsApp no responde al intent directo
      await SharePlus.instance.share(ShareParams(text: waText));
      return;
    }

    final statusNotifier = ValueNotifier<String>("Iniciando descarga de ${availableDocs.length} documentos...");
    _showLoadingDialog("Compartiendo por WhatsApp", statusNotifier);

    try {
      final tempDir = await getTemporaryDirectory();
      final List<XFile> xFiles = [];

      for (int i = 0; i < availableDocs.length; i++) {
        final doc = availableDocs[i];
        final url = doc["url"]?.toString() ?? "";
        final originalName = doc["filename"]?.toString() ?? "${doc["clave"] ?? 'doc'}.pdf";
        final displayName = doc["nombre"]?.toString() ?? originalName;

        statusNotifier.value = "Descargando (${i + 1}/${availableDocs.length}): $displayName...";

        if (url.isNotEmpty) {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200) {
            final tempFile = File('${tempDir.path}/$originalName');
            await tempFile.writeAsBytes(res.bodyBytes);
            xFiles.add(XFile(tempFile.path));
          }
        }
      }

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }

      if (xFiles.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            files: xFiles,
            text: waText.isNotEmpty ? waText : "Documentos de viaje: $prefix",
          ),
        );
      } else if (waText.isNotEmpty) {
        await SharePlus.instance.share(ShareParams(text: waText));
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al preparar documentos: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _downloadAllWithProgress({
    required List<Map<String, dynamic>> availableDocs,
    required String prefix,
  }) async {
    if (availableDocs.isEmpty) return;

    final statusNotifier = ValueNotifier<String>("Iniciando descarga de ${availableDocs.length} archivos...");
    _showLoadingDialog("Descargando Documentos", statusNotifier);

    int count = 0;
    try {
      final Directory downloadDir;
      if (Platform.isAndroid) {
        final dir = Directory('/storage/emulated/0/Download/SGT');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        downloadDir = dir;
      } else {
        downloadDir = await getApplicationDocumentsDirectory();
      }

      for (int i = 0; i < availableDocs.length; i++) {
        final doc = availableDocs[i];
        final url = doc["url"]?.toString() ?? "";
        final fileName = doc["filename"]?.toString() ?? "${prefix}_doc_${i + 1}.pdf";
        final docName = doc["nombre"]?.toString() ?? fileName;

        statusNotifier.value = "Guardando (${i + 1}/${availableDocs.length}): $docName...";

        if (url.isNotEmpty) {
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200) {
            final file = File('${downloadDir.path}/$fileName');
            await file.writeAsBytes(res.bodyBytes);
            count++;
          }
        }
      }

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("¡$count de ${availableDocs.length} documentos guardados en Descargas/SGT!"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Cerrar diálogo de carga
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error durante la descarga: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showDocumentosModal(Map<String, dynamic> item) async {
    final containerId = item["id_contenedor"];
    if (containerId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiService.post(ApiEndpoints.infoViaje, {"id": containerId.toString()});
      if (mounted) Navigator.pop(context); // cerrar spinner

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final data = resData["data"];
          final dynamic cotizacion = data["cotizacion"] ?? {};
          final dynamic documentos = data["documentos"] ?? {};
          final String waText = data["wa_text"]?.toString() ?? "";
          final int cotizacionId = int.tryParse(cotizacion["id"]?.toString() ?? "") ?? 0;

          final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');

          // Lista de documentos según la configuración global (global_configs) del backend
          final List<Map<String, dynamic>> docsList = [];

          if (data["documentos_configurados"] != null && data["documentos_configurados"] is List && (data["documentos_configurados"] as List).isNotEmpty) {
            final List<dynamic> configList = data["documentos_configurados"];
            for (var d in configList) {
              IconData icon = Icons.description;
              final clave = (d["clave"] ?? "").toString().toLowerCase();
              if (clave.contains("xml") || clave.contains("code")) {
                icon = Icons.code;
              } else if (clave.contains("pdf") || clave.contains("carta_porte")) {
                icon = Icons.picture_as_pdf;
              } else if (clave.contains("vacio") || clave.contains("patio")) {
                icon = Icons.receipt_long;
              } else if (clave.contains("doda") || clave.contains("liberacion")) {
                icon = Icons.document_scanner;
              } else if (clave.contains("eir") || clave.contains("ccp")) {
                icon = Icons.assignment;
              } else if (clave.contains("pago") || clave.contains("comprobante")) {
                icon = Icons.receipt;
              } else if (clave.contains("descarga") || clave.contains("entrega")) {
                icon = Icons.check_circle_outline;
              }

              final filename = d["filename"]?.toString();
              final bool hasFile = d["disponible"] == true && filename != null && filename.isNotEmpty;
              final String fileUrl = (d["url"] != null && d["url"].toString().isNotEmpty)
                  ? d["url"].toString()
                  : (hasFile && cotizacionId > 0 ? "$cleanBaseUrl/cotizaciones/cotizacion$cotizacionId/$filename" : "");

              docsList.add({
                "nombre": d["nombre"] ?? "Documento",
                "clave": d["clave"],
                "icon": icon,
                "filename": filename,
                "hasFile": hasFile,
                "url": fileUrl,
              });
            }
          } else {
            // Fallback por defecto si no viniera configurado
            final fallbackDocs = [
              {"nombre": "Formato CCP", "clave": "doc_ccp", "icon": Icons.assignment, "filename": documentos["doc_ccp"]?.toString()},
              {"nombre": "Boleta de Liberación", "clave": "boleta_liberacion", "icon": Icons.description, "filename": documentos["boleta_liberacion"]?.toString()},
              {"nombre": "DODA", "clave": "doda", "icon": Icons.document_scanner, "filename": documentos["doda"]?.toString()},
              {"nombre": "Carta Porte (PDF)", "clave": "carta_porte", "icon": Icons.picture_as_pdf, "filename": documentos["carta_porte"]?.toString()},
              {"nombre": "Carta Porte (XML)", "clave": "carta_porte_xml", "icon": Icons.code, "filename": documentos["carta_porte_xml"]?.toString()},
              {"nombre": "Prealta - Boleta de Vacío", "clave": "boleta_vacio", "icon": Icons.receipt_long, "filename": documentos["boleta_vacio"]?.toString()},
              {"nombre": "EIR - Comprobante de Vacío", "clave": "doc_eir", "icon": Icons.assignment, "filename": documentos["doc_eir"]?.toString()},
              {"nombre": "Evidencia de Descarga", "clave": "evidencia_descarga", "icon": Icons.check_circle_outline, "filename": documentos["evidencia_descarga"]?.toString()},
              {"nombre": "Complemento de Pago (PDF)", "clave": "comprobante_pago_pdf", "icon": Icons.receipt, "filename": documentos["comprobante_pago_pdf"]?.toString()},
              {"nombre": "Complemento de Pago (XML)", "clave": "comprobante_pago_xml", "icon": Icons.code, "filename": documentos["comprobante_pago_xml"]?.toString()},
            ];

            for (var d in fallbackDocs) {
              final filename = d["filename"]?.toString();
              final bool hasFile = filename != null && filename.isNotEmpty && cotizacionId > 0;
              final String fileUrl = hasFile ? "$cleanBaseUrl/cotizaciones/cotizacion$cotizacionId/$filename" : "";
              docsList.add({
                "nombre": d["nombre"],
                "clave": d["clave"],
                "icon": d["icon"],
                "filename": filename,
                "hasFile": hasFile,
                "url": fileUrl,
              });
            }
          }

          final List<Map<String, dynamic>> availableDocs = [];
          for (var doc in docsList) {
            if (doc["hasFile"] == true && (doc["url"] as String).isNotEmpty) {
              availableDocs.add(doc);
            }
          }

          if (!mounted) return;

          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  // Header Modal
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E3A8A),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.inventory_2, color: Colors.white, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Contenedor: ${item["num_contenedor"] ?? 'S/N'}",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "🏢 ${item["empresa_nombre"] ?? 'Empresa Propia'}",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),

                  // Info Resumen Viaje
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    color: Colors.blue.shade50,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Ruta: ${item["origen"] ?? 'N/A'} ➔ ${item["destino"] ?? 'N/A'}",
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Cliente: ${item["cliente_nombre"] ?? 'N/A'}",
                                style: const TextStyle(fontSize: 12, color: Colors.black54),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _formatRemainingTime(item["fecha_fin_visibilidad"]),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Document List
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: docsList.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final doc = docsList[index];
                        final filename = doc["filename"]?.toString();
                        final bool hasFile = doc["hasFile"] == true;
                        final String fileUrl = (doc["url"] ?? "").toString();

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: hasFile ? Colors.blue.shade100 : Colors.grey.shade200,
                                child: Icon(
                                  doc["icon"] as IconData,
                                  size: 18,
                                  color: hasFile ? Colors.blue.shade800 : Colors.grey.shade500,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc["nombre"],
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: hasFile ? Colors.black87 : Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      hasFile ? (filename ?? "Archivo") : "No adjuntado",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: hasFile ? Colors.black54 : Colors.grey.shade400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (hasFile) ...[
                                // Botón Guardar/Abrir
                                IconButton(
                                  tooltip: "Guardar / Abrir",
                                  icon: const Icon(Icons.download, color: Colors.blue),
                                  onPressed: () {
                                    FileDownloader.downloadFile(
                                      context: context,
                                      url: fileUrl,
                                      fileName: filename ?? "documento.pdf",
                                    );
                                  },
                                ),
                                // Botón Compartir
                                IconButton(
                                  tooltip: "Compartir Archivo",
                                  icon: const Icon(Icons.share, color: Colors.green),
                                  onPressed: () {
                                    _shareFileDirectly(fileUrl, filename ?? "documento.pdf");
                                  },
                                ),
                              ] else ...[
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Icon(Icons.cancel, color: Colors.grey, size: 20),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                  // Bottom Action Buttons
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      border: Border(top: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: Row(
                      children: [
                        if (availableDocs.isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              icon: const Icon(Icons.download_for_offline, color: Colors.white, size: 18),
                              label: const Text(
                                "Descargar Todos",
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () {
                                final prefix = item["num_contenedor"]?.toString().replaceAll(' ', '_') ?? "viaje";
                                _downloadAllWithProgress(
                                  availableDocs: availableDocs,
                                  prefix: prefix,
                                );
                              },
                            ),
                          ),
                        if (availableDocs.isNotEmpty)
                          const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.send, color: Colors.white, size: 18),
                            label: Text(
                              availableDocs.isNotEmpty ? "WhatsApp" : "Enviar Info",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () {
                              final prefix = item["num_contenedor"]?.toString().replaceAll(' ', '_') ?? "viaje";
                              _shareWhatsAppOrAll(
                                availableDocs: availableDocs,
                                waText: waText,
                                prefix: prefix,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al cargar documentos: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 2,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Documentos Empresas",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              _userName ?? _userEmail ?? "Ventana 24 Horas",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Actualizar",
            onPressed: _fetchContenedores,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Cerrar Sesión",
            onPressed: _confirmLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchContenedores,
        child: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.white,
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: "Buscar contenedor, empresa, cliente, destino...",
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1E3A8A)),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = "";
                              _applyFilter();
                            });
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                    _applyFilter();
                  });
                },
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off, size: 50, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(
                                  _errorMessage!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.black54, fontSize: 15),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _fetchContenedores,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Reintentar"),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredContenedores.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.shade400),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? "No se encontraron contenedores con '$_searchQuery'"
                                          : "No hay contenedores activos dentro de las últimas 24 horas para empresas propias.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _filteredContenedores.length,
                              itemBuilder: (context, index) {
                                final item = _filteredContenedores[index];
                                final numContenedor = item["num_contenedor"] ?? "S/N";
                                final empresa = item["empresa_nombre"] ?? "Empresa Propia";
                                final origen = item["origen"] ?? "N/A";
                                final destino = item["destino"] ?? "N/A";
                                final cliente = item["cliente_nombre"] ?? "N/A";
                                final operador = item["operador_nombre"] ?? "Sin Asignar";
                                final tiempoRestante = _formatRemainingTime(item["fecha_fin_visibilidad"]);

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _showDocumentosModal(item),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Top: Contenedor y Badge Empresa
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.inventory_2,
                                                color: Color(0xFF1E3A8A),
                                                size: 24,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      numContenedor,
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                        color: Color(0xFF1E293B),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    // Badge de Empresa Propias
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                      decoration: BoxDecoration(
                                                        color: Colors.indigo.shade50,
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.indigo.shade200),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.business,
                                                            size: 13,
                                                            color: Colors.indigo.shade700,
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Flexible(
                                                            child: Text(
                                                              "EMPRESA: $empresa",
                                                              style: TextStyle(
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.indigo.shade800,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // Chip Tiempo Restante 24h
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber.shade50,
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: Colors.amber.shade300),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.timer_outlined, size: 13, color: Colors.amber.shade900),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      tiempoRestante,
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.amber.shade900,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          const Padding(
                                            padding: EdgeInsets.symmetric(vertical: 10),
                                            child: Divider(height: 1),
                                          ),

                                          // Origen -> Destino
                                          Row(
                                            children: [
                                              const Icon(Icons.route, size: 16, color: Colors.blueGrey),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  "$origen ➔ $destino",
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF334155),
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),

                                          const SizedBox(height: 6),

                                          // Cliente y Operador
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        "Cliente: $cliente",
                                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.local_shipping_outlined, size: 14, color: Colors.grey),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        "Op: $operador",
                                                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),

                                          if (item["asignacion_fecha_inicio"] != null) ...[
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.indigo),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "Vigencia Viaje: ${item["asignacion_fecha_inicio"] ?? ''} al ${item["asignacion_fecha_fin"] ?? 'En curso'}",
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.indigo.shade700),
                                                ),
                                              ],
                                            ),
                                          ],

                                          const SizedBox(height: 12),

                                          // Action Bar inside card
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFF1E3A8A),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                ),
                                                icon: const Icon(Icons.folder_open, size: 16),
                                                label: const Text(
                                                  "Ver Documentos",
                                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                                onPressed: () => _showDocumentosModal(item),
                                              ),
                                            ],
                                          ),
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
    );
  }
}
