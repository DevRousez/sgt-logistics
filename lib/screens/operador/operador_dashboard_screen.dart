import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'registrar_diesel_screen.dart';
import 'dart:async';
import 'carga_contenedor_screen.dart';
import 'finalizar_viaje_screen.dart';
import 'historial_viajes_screen.dart';
import 'gastos_viaje_screen.dart';
import '../home_screen.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';
import '../../utils/file_downloader.dart';
import '../../services/notification_service.dart';
import '../../services/operador_sync_service.dart';

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
  Timer? _pollingTimer;
  bool _isDialogOpen = false;

  List<Map<String, dynamic>> _documentos = [];
  bool _loadingDocs = false;

  @override
  void initState() {
    super.initState();
    _loadOperatorData().then((_) {
      _checkPendingAssignment();
      NotificationService.fetchAndScheduleNotification();
    });
    // Configurar el sondeo automático cada 30 segundos
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isDialogOpen) {
        _checkPendingAssignment();
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _manualRefresh() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Actualizando información..."),
        duration: Duration(seconds: 1),
      ),
    );
    await _loadOperatorData();
    await _checkPendingAssignment();
    await NotificationService.fetchAndScheduleNotification();
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

  Future<void> _checkPendingAssignment() async {
    try {
      final response = await ApiService.get(ApiEndpoints.checkAsignacion);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        
        // Sincronización automática de viaje cancelado o deshecho en web (Silenciosa)
        final dynamic activeIdRaw = resData["viaje_activo_id"];
        final int? activeIdBackend = activeIdRaw != null ? int.tryParse(activeIdRaw.toString()) : null;
        if (_idAsignacion != null && activeIdBackend == null) {
          final userData = await ApiService.getUserData() ?? {};
          userData["id_asignacion"] = null;
          userData["num_contenedor"] = "N/A";
          userData["unidad"] = "N/A";
          userData["id_equipo"] = "N/A";
          await ApiService.saveUserData(userData);
          if (mounted) {
            setState(() {
              _idAsignacion = null;
              _unidad = "N/A";
              _idEquipo = "N/A";
            });
          }
        } else if (activeIdBackend != null && activeIdBackend > 0 &&
            (_idAsignacion == null || _idAsignacion != activeIdBackend || _unidad == "N/A")) {
          // Sincronización automática de viaje en curso (tras reinstalación, nuevo login o desincronización)
          final updatedData = await OperadorSyncService.sincronizarViajeActivo(
            activeIdBackend,
            checkData: resData,
          );
          if (updatedData != null && mounted) {
            setState(() {
              _idAsignacion = activeIdBackend;
              _unidad = updatedData["unidad"]?.toString() ?? _unidad ?? "N/A";
              _idEquipo = updatedData["id_equipo"]?.toString() ?? _idEquipo ?? "N/A";
            });
          }
        }

        if (resData["success"] == true && resData["data"] != null) {
          final assignment = resData["data"];
          final int? idAsig = int.tryParse(assignment["id_asignacion"]?.toString() ?? "");
          final String empresaNombre = assignment["nombre_empresa"]?.toString() ?? "Nueva Empresa";
          final String viajeOrigenDestino = assignment["origen_destino"]?.toString() ?? "";
          final String numContenedor = assignment["num_contenedor"]?.toString() ?? "N/A";
          final String camionUnidad = assignment["camion"]?.toString() ?? "N/A";

          if (idAsig != null && mounted && !_isDialogOpen) {
            _showAssignmentDialog(idAsig, empresaNombre, viajeOrigenDestino, numContenedor, camionUnidad);
          }
        }
      }
    } catch (e) {
      print("Error checking pending assignment: $e");
    }
  }

  void _showAssignmentDialog(int idAsignacion, String empresaNombre, String detallesViaje, String numContenedor, String camionUnidad) {
    setState(() {
      _isDialogOpen = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.assignment, color: Colors.blue),
              SizedBox(width: 10),
              Text("Nueva Asignación"),
            ],
          ),
          content: Text(
            "Has sido asignado a la empresa: $empresaNombre.\n\n"
            "Contenedor: $numContenedor\n"
            "Unidad/Camión: $camionUnidad\n"
            "Ruta: $detallesViaje\n\n"
            "¿Aceptas esta asignación para comenzar a capturar datos?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _isDialogOpen = false;
                });
              },
              child: const Text("Rechazar"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                setState(() {
                  _isDialogOpen = false;
                });
                await _aceptarAsignacion(idAsignacion);
              },
              child: const Text("Aceptar"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _aceptarAsignacion(int idAsignacion) async {
    try {
      final response = await ApiService.post(
        ApiEndpoints.aceptarAsignacion,
        {"id_asignacion": idAsignacion},
      );
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true) {
          if (resData["data"] != null) {
            final currentData = await ApiService.getUserData() ?? {};
            currentData.addAll(Map<String, dynamic>.from(resData["data"]));
            await ApiService.saveUserData(currentData);
            await _loadOperatorData();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Asignación aceptada con éxito"),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception(resData["message"] ?? "Error al aceptar");
        }
      } else {
        throw Exception("Status code: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al aceptar asignación: $e"),
            backgroundColor: Colors.red,
          ),
        );
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
        final synced = await OperadorSyncService.sincronizarSiEsNecesario();
        if (synced != null) {
          _idAsignacion = int.tryParse(synced["id_asignacion"]?.toString() ?? "");
          if (mounted) {
            setState(() {
              _unidad = synced["unidad"]?.toString() ?? _unidad;
              _idEquipo = synced["id_equipo"]?.toString() ?? _idEquipo;
            });
          }
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
                if (keyStr == 'documentos' || keyStr == 'documentos_viaje') return;
                if (value is! String) return;
                final valStr = value.trim();
                if (valStr.isEmpty || valStr.startsWith('{') || valStr.startsWith('[')) return;

                if (keyStr.contains('doda') || 
                    keyStr.contains('boleta') || 
                    keyStr.contains('carta_porte') ||
                    keyStr.contains('eir') ||
                    keyStr.contains('pdf') ||
                    keyStr.contains('xml') ||
                    keyStr.contains('documento')) {
                  
                  // Generar un nombre limpio legible
                  String label = key.toString().replaceAll('_', ' ').toUpperCase();
                  if (label == "BOLETA LIBERACION") label = "Boleta de Liberación";
                  if (label == "BOLETA VACIO") label = "Boleta de Vacío";
                  if (label == "DODA") label = "Documento DODA";
                  if (label == "CARTA PORTE") label = "Carta Porte PDF";

                  String urlStr = valStr;
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
                      onPressed: () async {
                        final List<String> urls = [];
                        final List<String> fileNames = [];
                        for (int i = 0; i < _documentos.length; i++) {
                          final doc = _documentos[i];
                          final String url = doc["url"]?.toString() ?? "";
                          if (url.isNotEmpty) {
                            urls.add(url);
                            final String nombre = doc["nombre"]?.toString() ?? "documento_${i + 1}";
                            final String extension = FileDownloader.detectExtension(url, defaultExt: 'pdf');
                            fileNames.add("${nombre.replaceAll(' ', '_')}.$extension");
                          }
                        }
                        if (urls.isNotEmpty) {
                          await FileDownloader.downloadAllFiles(
                            context: context,
                            urls: urls,
                            fileNames: fileNames,
                            prefix: "documento_viaje",
                          );
                        }
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
                              final String extension = FileDownloader.detectExtension(url, defaultExt: 'pdf');
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
                                    final String extension = FileDownloader.detectExtension(url, defaultExt: 'pdf');
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
                                  final String extension = FileDownloader.detectExtension(url, defaultExt: 'pdf');
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

  void _showNotificationDiagnosticsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.notifications_active, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Diagnóstico Notificaciones",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("📍 Zona Horaria: ${NotificationService.timezoneName ?? 'Detectando...'}",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text("⏰ Hora Celular: ${DateTime.now()}",
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 6),
                    const Text("📅 Info Programación Servidor:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(NotificationService.lastScheduledInfo ?? "Aún no programada",
                        style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                    const Divider(height: 24),
                    const Text("Pruebas de Notificación:",
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 38),
                      ),
                      icon: const Icon(Icons.flash_on, size: 18),
                      label: const Text("Notificación Inmediata (Ya)"),
                      onPressed: () async {
                        await NotificationService.showInstantTestNotification();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Notificación enviada al instante.")),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 38),
                      ),
                      icon: const Icon(Icons.timer, size: 18),
                      label: const Text("Programar en 10 segundos"),
                      onPressed: () async {
                        final scheduledDate = await NotificationService.scheduleTestNotificationInSeconds(10);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text("Programada para las ${scheduledDate.hour}:${scheduledDate.minute.toString().padLeft(2, '0')}:${scheduledDate.second.toString().padLeft(2, '0')}. ¡Bloquea la pantalla o sal de la app!"),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 38),
                      ),
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text("Recargar del Servidor"),
                      onPressed: () async {
                        await NotificationService.fetchAndScheduleNotification();
                        setDialogState(() {});
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
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
            if (!ApiConfig.isProduction)
              IconButton(
                onPressed: _showNotificationDiagnosticsDialog,
                icon: const Icon(Icons.notifications_active_outlined),
                tooltip: 'Diagnóstico de Notificaciones',
              ),
            IconButton(
              onPressed: _manualRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
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
            if (NotificationService.isTodayNotificationDay())
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 24),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Recordatorio de Gastos (Hoy ${NotificationService.getWeekdayName(NotificationService.configuredWeekday)})",
                            style: TextStyle(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Se requiere que capture los gastos de los viajes de la semana, ya que está próximo a su liquidación.",
                      style: TextStyle(color: Colors.brown.shade900, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.receipt_long, size: 18),
                        label: const Text("Ir a Gastos de Viaje", style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GastosViajeScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
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
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CargaContenedorScreen(),
                  ),
                );
                _loadOperatorData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline, color: Colors.red),
              title: const Text('Concluir Viaje'),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FinalizarViajeScreen(),
                  ),
                );
                _loadOperatorData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.description, color: Colors.blue),
              title: const Text('Documentos del Viaje'),
              onTap: _fetchAndShowDocuments,
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: const Text('Gastos de Viaje'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GastosViajeScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Historial'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HistorialViajesScreen(),
                  ),
                );
              },
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