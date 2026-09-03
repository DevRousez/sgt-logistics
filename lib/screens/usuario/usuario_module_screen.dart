import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:flutter_map/flutter_map.dart' as fmap;
import 'package:latlong2/latlong.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';
import '/utils/file_downloader.dart';

class UsuarioModuleScreen extends StatefulWidget {
  final String module;
  final String title;

  const UsuarioModuleScreen({
    super.key,
    required this.module,
    required this.title,
  });

  @override
  State<UsuarioModuleScreen> createState() => _UsuarioModuleScreenState();
}

class _UsuarioModuleScreenState extends State<UsuarioModuleScreen> {
  bool isLoading = true;
  bool isMockData = false;
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> filteredItems = [];
  String searchQuery = "";
  String debugErrorMessage = "";
  Map<String, dynamic> reportStats = {};
  final TextEditingController searchController = TextEditingController();
  gmaps.GoogleMapController? _googleMapController;
  final fmap.MapController _mapController = fmap.MapController();
  Map<String, gmaps.BitmapDescriptor> _customMarkerIcons = {};
  Map<String, LatLng> _previousCoordinates = {};
  Set<String> _selectedCardIds = {};
  Map<String, dynamic>? _selectedGpsItem;
  bool _showCamion = true;
  bool _showChasisA = true;
  bool _showChasisB = true;
  bool _showRoute = false;
  List<LatLng> _routePoints = [];
  bool _showContenedores = true;
  bool _showEquipos = true;
  bool _filtersApplied = false;
  String _selectedTipo = "Contenedor";
  String _selectedLineaId = "";
  String _selectedClienteId = "";
  DateTime? _selectedFechaSalida;
  Timer? _refreshTimer;
  List<Map<String, String>> _lineas = [];
  List<Map<String, String>> _clientes = [];
  bool _loadingLines = false;

  // Planeacion variables
  DateTime? _planeacionFechaInicio;
  DateTime? _planeacionFechaFin;
  bool _canFinalize = false;
  bool _canAnular = false;
  bool _isSuperUser = false;

  @override
  void initState() {
    super.initState();
    _planeacionFechaInicio = DateTime.now().subtract(const Duration(days: 15));
    _planeacionFechaFin = DateTime.now().add(const Duration(days: 15));
    _loadPermissions();
    if (widget.module != 'monitoreo') {
      fetchData();
    } else {
      isLoading = false;
      _loadTransportLines();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPermissions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? userRaw = prefs.getString('user_data');
    if (userRaw != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(userRaw);
        if (data["user"] != null) {
          final Map<String, dynamic> user = data["user"];
          final List<dynamic> permsList = user["permissions"] ?? [];
          setState(() {
            _isSuperUser = permsList.contains('superuser');
            _canFinalize = permsList.contains('planeacion-finalizar') || _isSuperUser;
            _canAnular = permsList.contains('planeacion-delete') || _isSuperUser;
          });
        }
      } catch (e) {
        // Fallback
      }
    }
  }

  Future<void> _finalizarViaje(int containerId, {Map<String, dynamic>? item}) async {
    List<String> missingDocs = [];
    if (item != null) {
      if (item["carta_porte"] == null || item["carta_porte"].toString().isEmpty) missingDocs.add("Carta Porte PDF");
      if (item["carta_porte_xml"] == null || item["carta_porte_xml"].toString().isEmpty) missingDocs.add("Carta Porte XML");
      if (item["doda"] == null || item["doda"].toString().isEmpty) missingDocs.add("Documento DODA");
      if (item["boleta_liberacion"] == null || item["boleta_liberacion"].toString().isEmpty) missingDocs.add("Boleta de Liberación");
      if (item["boleta_vacio"] == null || item["boleta_vacio"].toString().isEmpty) missingDocs.add("Boleta de Vacío");
    }

    bool shouldProceed = false;

    if (missingDocs.isNotEmpty) {
      final bool? proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.amber),
              SizedBox(width: 10),
              Text("Documentos Faltantes"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Este viaje aún no cuenta con los siguientes documentos cargados:"),
              const SizedBox(height: 10),
              ...missingDocs.map((doc) => Text("• $doc", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange))),
              const SizedBox(height: 15),

            ],
          ),
         ),
      );
      shouldProceed = proceed == true;
    } else {
      final bool? confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Finalizar Viaje"),
          content: const Text("¿Está seguro que desea finalizar este viaje?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Finalizar"),
            ),
          ],
        ),
      );
      shouldProceed = confirm == true;
    }

    if (!shouldProceed) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await ApiService.post(
        "${ApiConfig.baseUrl}/dashboard/finalizar-viaje",
        {"idContenendor": containerId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data["TMensaje"] == "success") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["Mensaje"] ?? "Viaje finalizado con éxito"), backgroundColor: Colors.green),
        );
        fetchData();
      } else {
        throw Exception(data["Mensaje"] ?? "Error al finalizar el viaje");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _anularPlaneacion(int containerId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Deshacer Planeación"),
        content: const Text("¿Está seguro de que desea deshacer esta planeación? Esta acción es irreversible y devolverá la cotización a estado Aprobada."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancelar")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Confirmar"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      isLoading = true;
    });

    try {
      final response = await ApiService.post(
        "${ApiConfig.baseUrl}/dashboard/anular-planeacion",
        {"idContenendor": containerId},
      );
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data["TMensaje"] == "success") {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["Mensaje"] ?? "Planeación anulada con éxito"), backgroundColor: Colors.green),
        );
        fetchData();
      } else {
        throw Exception(data["Mensaje"] ?? "Error al deshacer planeación");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
      setState(() {
        isLoading = false;
      });
    }
  }

  String _getEndpointUrl() {
    switch (widget.module) {
      case 'cotizaciones':
        return ApiEndpoints.cotizaciones;
      case 'viajes':
        return ApiEndpoints.viajes;
      case 'contenedores':
        return ApiEndpoints.contenedores;
      case 'operaciones':
        return ApiEndpoints.operaciones;
      case 'monitoreo':
        return ApiEndpoints.monitoreo;
      case 'planeacion':
        return ApiEndpoints.planeacion;
      case 'reportes':
        return ApiEndpoints.reportes;
      default:
        return "";
    }
  }

  Future<void> fetchData({bool isSilent = false}) async {
    if (mounted) {
      setState(() {
        if (!isSilent) {
          isLoading = true;
        }
        debugErrorMessage = "";
      });
    }

    String url = _getEndpointUrl();
    if (widget.module == 'monitoreo' && _filtersApplied) {
      final List<String> queryParams = [];
      queryParams.add("tipo=$_selectedTipo");
      if (_selectedLineaId.trim().isNotEmpty) {
        queryParams.add("linea_transporte=${Uri.encodeComponent(_selectedLineaId.trim())}");
      }
      if (_selectedFechaSalida != null) {
        final String formattedDate = "${_selectedFechaSalida!.year}-${_selectedFechaSalida!.month.toString().padLeft(2, '0')}-${_selectedFechaSalida!.day.toString().padLeft(2, '0')}";
        queryParams.add("fecha_salida=$formattedDate");
      }
      url = "$url?${queryParams.join('&')}";
    } else if (widget.module == 'planeacion') {
      final List<String> queryParams = [];
      if (_planeacionFechaInicio != null) {
        queryParams.add("fecha_inicio=${_planeacionFechaInicio!.year}-${_planeacionFechaInicio!.month.toString().padLeft(2, '0')}-${_planeacionFechaInicio!.day.toString().padLeft(2, '0')}");
      }
      if (_planeacionFechaFin != null) {
        queryParams.add("fecha_fin=${_planeacionFechaFin!.year}-${_planeacionFechaFin!.month.toString().padLeft(2, '0')}-${_planeacionFechaFin!.day.toString().padLeft(2, '0')}");
      }
      url = "$url?${queryParams.join('&')}";
    }
    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          items = [];
          filteredItems = [];
          reportStats = {};
          isMockData = true;
          isLoading = false;
          debugErrorMessage = "URL de endpoint no configurada.";
        });
      }
      return;
    }

    try {
      final response = await ApiService.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (widget.module == 'reportes') {
          Map<String, dynamic> stats = {};
          if (data is Map && data["data"] is Map) {
            if (data["data"]["data"] is Map) {
              stats = Map<String, dynamic>.from(data["data"]["data"]);
            } else {
              stats = Map<String, dynamic>.from(data["data"]);
            }
          } else if (data is Map) {
            stats = Map<String, dynamic>.from(data);
          }
          if (mounted) {
            setState(() {
              reportStats = stats;
              isMockData = false;
              isLoading = false;
            });
          }
          return;
        }

        if (widget.module == 'monitoreo') {
          final List<Map<String, dynamic>> parsedGps = [];
          if (data is Map && data["data"] is Map) {
            final mapData = data["data"];
            
            // 1. Procesar contenedores activos (datos)
            if (mapData["datos"] is List) {
              for (var item in mapData["datos"]) {
                if (item is Map) {
                  final Map<String, dynamic> convertedMap = {"tipo_item": "contenedor"};
                  item.forEach((key, value) {
                    convertedMap[key.toString()] = value;
                  });
                  // Asegurar que num_contenedor se guarde en campo común id_equipo para la lista si no tiene
                  if (convertedMap["id_equipo"] == null && convertedMap["contenedor"] != null) {
                    convertedMap["id_equipo"] = convertedMap["contenedor"];
                  }
                  parsedGps.add(convertedMap);
                }
              }
            }
            
            // 2. Procesar equipos de monitoreo general (equipos)
            if (mapData["equipos"] is List) {
              for (var item in mapData["equipos"]) {
                if (item is Map) {
                  final Map<String, dynamic> convertedMap = {"tipo_item": "equipo"};
                  item.forEach((key, value) {
                    convertedMap[key.toString()] = value;
                  });
                  parsedGps.add(convertedMap);
                }
              }
            }

            // 3. Procesar convoys (conboys)
            if (mapData["conboys"] is List) {
              for (var item in mapData["conboys"]) {
                if (item is Map) {
                  final Map<String, dynamic> convertedMap = {"tipo_item": "convoy"};
                  item.forEach((key, value) {
                    convertedMap[key.toString()] = value;
                  });
                  if (convertedMap["lat"] == null && convertedMap["geocerca_lat"] != null) {
                    convertedMap["lat"] = convertedMap["geocerca_lat"];
                  }
                  if (convertedMap["lng"] == null && convertedMap["geocerca_long"] != null) {
                    convertedMap["lng"] = convertedMap["geocerca_long"];
                  }
                  if (convertedMap["id_equipo"] == null && convertedMap["no_conboy"] != null) {
                    convertedMap["id_equipo"] = "Convoy ${convertedMap["no_conboy"]}";
                  }
                  parsedGps.add(convertedMap);
                }
              }
            }
          }

          final String selectedTipoNormalized = _selectedTipo.toLowerCase();
          final List<Map<String, dynamic>> typeFiltered = parsedGps.where((item) {
            if (item["tipo_item"] != selectedTipoNormalized) return false;
            
            if (_selectedClienteId.isNotEmpty) {
              final String? itemClientId = item["id_cliente"]?.toString() ?? item["cliente_id"]?.toString();
              if (itemClientId != _selectedClienteId) return false;
            }
            
            if (_selectedLineaId.isNotEmpty) {
              final String? itemLineaId = item["proveedor_id"]?.toString() ?? item["proveedor_company_id"]?.toString();
              if (itemLineaId != _selectedLineaId) return false;
            }
            
            return true;
          }).toList();

          if (mounted) {
            setState(() {
              items = parsedGps;
              filteredItems = typeFiltered;
              isMockData = false;
              isLoading = false;
              
              if (_selectedCardIds.isEmpty) {
                int count = 0;
                for (var item in typeFiltered) {
                  final String tipoItem = item["tipo_item"]?.toString() ?? "";
                  final String tipo = (item["tipo"]?.toString() ?? "").toLowerCase();
                  if (tipoItem == "contenedor" && tipo == "camion") {
                    final String itemKey = "${item['tipo_item']}_${item['id'] ?? item['contenedor']}";
                    _selectedCardIds.add(itemKey);
                    count++;
                    if (count >= 2) break;
                  } else if (tipoItem != "contenedor") {
                    final String itemKey = "${item['tipo_item']}_${item['id'] ?? item['id_equipo'] ?? item['nombre']}";
                    _selectedCardIds.add(itemKey);
                    count++;
                    if (count >= 2) break;
                  }
                }
              }
            });
          }
          return;
        }

        List<dynamic> rawList = [];
        
        if (data is List) {
          rawList = data;
        } else if (data is Map && data["data"] is Map && data["data"]["data"] is List) {
          rawList = data["data"]["data"];
        } else if (data is Map && data["data"] is List) {
          rawList = data["data"];
        } else {
          if (mounted) {
            setState(() {
              items = [];
              filteredItems = [];
              isMockData = true;
              isLoading = false;
              debugErrorMessage = "Estructura JSON desconocida.";
            });
          }
          return;
        }

        final List<Map<String, dynamic>> parsedItems = [];
        for (var item in rawList) {
          if (item is Map) {
            final Map<String, dynamic> convertedMap = {};
            item.forEach((key, value) {
              convertedMap[key.toString()] = value;
            });
            parsedItems.add(convertedMap);
          }
        }

        if (mounted) {
          setState(() {
            items = parsedItems;
            filteredItems = List<Map<String, dynamic>>.from(parsedItems);
            isMockData = false;
            isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            items = [];
            filteredItems = [];
            reportStats = {};
            isMockData = true;
            isLoading = false;
            debugErrorMessage = "Error HTTP ${response.statusCode}: ${response.body}";
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          items = [];
          filteredItems = [];
          reportStats = {};
          isMockData = true;
          isLoading = false;
          debugErrorMessage = "Error de red/conexión: $e";
        });
      }
    }
  }

  void filterSearchResults(String query) {
    setState(() {
      searchQuery = query;
      if (query.isEmpty) {
        filteredItems = List<Map<String, dynamic>>.from(items);
      } else {
        filteredItems = items.where((item) {
          return item.values.any((value) =>
              value.toString().toLowerCase().contains(query.toLowerCase()));
        }).toList();
      }
    });
  }

  void _executeAction(String actionName, Map<String, dynamic> row) {
    // Perform simulated/actual action
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Acción: $actionName"),
          content: Text("¿Deseas realizar la acción '$actionName' en el elemento ${row['id']}?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancelar"),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Simulate action success and update local state
                setState(() {
                  if (actionName == "Aprobar") {
                    row["estatus"] = "Aprobada";
                  } else if (actionName == "Rechazar") {
                    row["estatus"] = "Rechazada";
                  } else if (actionName == "Liberar") {
                    row["estatus"] = "Disponible";
                    row["ubicacion"] = "Patio Principal";
                  } else if (actionName == "Confirmar Plan") {
                    row["estatus"] = "Confirmado";
                  } else if (actionName == "Asignar Operador") {
                    row["operador"] = "Carlos López";
                    row["estatus"] = "Asignado";
                  } else if (actionName == "Enviar Alerta") {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Alerta de seguridad enviada al operador")),
                    );
                    return;
                  } else if (actionName == "Descargar PDF") {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Descargando reporte PDF...")),
                    );
                    return;
                  }
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Acción ejecutada con éxito para ${row['id']}")),
                );
              },
              child: const Text("Confirmar"),
            )
          ],
        );
      },
    );
  }

  List<Widget> _buildRowActions(Map<String, dynamic> row) {
    switch (widget.module) {
      case 'cotizaciones':
        return [
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            tooltip: 'Aprobar',
            onPressed: () => _executeAction("Aprobar", row),
          ),
          IconButton(
            icon: const Icon(Icons.highlight_off, color: Colors.red),
            tooltip: 'Rechazar',
            onPressed: () => _executeAction("Rechazar", row),
          ),
        ];
      case 'viajes':
        return [
          IconButton(
            icon: const Icon(Icons.person_add, color: Colors.blue),
            tooltip: 'Asignar Operador',
            onPressed: () => _executeAction("Asignar Operador", row),
          ),
          IconButton(
            icon: const Icon(Icons.map, color: Colors.green),
            tooltip: 'Ver Mapa',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Mostrando ruta en el mapa...")),
              );
            },
          ),
        ];
      case 'contenedores':
        return [
          IconButton(
            icon: const Icon(Icons.lock_open, color: Colors.orange),
            tooltip: 'Liberar',
            onPressed: () => _executeAction("Liberar", row),
          ),
        ];
      case 'monitoreo':
        return [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded, color: Colors.red),
            tooltip: 'Enviar Alerta',
            onPressed: () => _executeAction("Enviar Alerta", row),
          ),
        ];
      case 'planeacion':
        return [
          IconButton(
            icon: const Icon(Icons.assignment_turned_in, color: Colors.purple),
            tooltip: 'Confirmar Plan',
            onPressed: () => _executeAction("Confirmar Plan", row),
          ),
        ];
      case 'reportes':
        return [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.teal),
            tooltip: 'Descargar PDF',
            onPressed: () => _executeAction("Descargar PDF", row),
          ),
        ];
      default:
        return [];
    }
  }



  List<String> _getHeaders() {
    switch (widget.module) {
      case 'cotizaciones':
        return ["ID", "Cliente", "Contenedor", "Total", "Estatus"];
      case 'viajes':
        return ["ID", "Origen", "Destino", "Operador", "Costo", "Estatus"];
      case 'contenedores':
        return ["ID", "Número", "Tipo", "Tamaño", "Ubicación", "Estatus"];
      case 'operaciones':
        return ["ID", "Contenedor", "Cliente", "Origen", "Destino", "Estatus"];
      case 'monitoreo':
        return ["ID", "Unidad", "Operador", "Ubicación", "Velocidad", "Estatus"];
      case 'planeacion':
        return ["ID", "Viaje", "Fecha", "Prioridad", "Estatus"];
      case 'reportes':
        return ["ID", "Tipo Reporte", "Generado", "Fecha", "Estatus"];
      default:
        return ["ID"];
    }
  }

  List<String> _getKeys() {
    switch (widget.module) {
      case 'cotizaciones':
        return ["id", "cliente", "contenedor", "total", "estatus"];
      case 'viajes':
        return ["id", "origen", "destino", "operador", "costo", "estatus"];
      case 'contenedores':
        return ["id", "numero", "tipo", "tamano", "ubicacion", "estatus"];
      case 'operaciones':
        return ["id", "contenedor", "cliente", "origen", "destino", "estatus"];
      case 'monitoreo':
        return ["id", "unidad", "operador", "ubicacion", "velocidad", "estatus"];
      case 'planeacion':
        return ["id", "viaje", "fecha", "prioridad", "estatus"];
      case 'reportes':
        return ["id", "tipo", "generado", "fecha", "estatus"];
      default:
        return ["id"];
    }
  }

  Color _getStatusColor(dynamic status) {
    if (status == null) return Colors.grey;
    final s = status.toString().toLowerCase();
    if (s.contains('aprob') || s.contains('complet') || s.contains('list') || s.contains('dispon') || s.contains('activ')) {
      return Colors.green.shade600;
    }
    if (s.contains('pendient') || s.contains('plan') || s.contains('proceso') || s.contains('asign')) {
      return Colors.orange.shade700;
    }
    if (s.contains('rechaz') || s.contains('reten') || s.contains('deten')) {
      return Colors.red.shade600;
    }
    return Colors.blue.shade600;
  }

  String _formatMoneda(double value) {
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String mathFunc(Match match) => '${match[1]},';
    return value.toStringAsFixed(2).replaceAllMapped(reg, mathFunc);
  }

  Widget _buildGroupedOperacionesList(List<Map<String, dynamic>> list) {
    final List<Map<String, dynamic>> planeadas = [];
    final List<Map<String, dynamic>> finalizadas = [];
    final List<Map<String, dynamic>> pendientes = [];
    final List<Map<String, dynamic>> aprobadas = [];
    final List<Map<String, dynamic>> canceladas = [];

    for (var item in list) {
      final status = item["estatus"]?.toString().toLowerCase() ?? "";
      if (status.contains("plan")) {
        planeadas.add(item);
      } else if (status.contains("final") || status.contains("termin")) {
        finalizadas.add(item);
      } else if (status.contains("pend") || status.contains("espera")) {
        pendientes.add(item);
      } else if (status.contains("aprob")) {
        aprobadas.add(item);
      } else {
        canceladas.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (planeadas.isNotEmpty)
          _buildExpansionSection("Planeadas", planeadas, Colors.orange.shade700),
        if (finalizadas.isNotEmpty)
          _buildExpansionSection("Finalizadas", finalizadas, Colors.green.shade600),
        if (pendientes.isNotEmpty)
          _buildExpansionSection("En espera (Pendientes)", pendientes, Colors.amber.shade700),
        if (aprobadas.isNotEmpty)
          _buildExpansionSection("Aprobadas", aprobadas, Colors.blue.shade600),
        if (canceladas.isNotEmpty)
          _buildExpansionSection("Otras / Canceladas", canceladas, Colors.red.shade600),
      ],
    );
  }

  Widget _buildExpansionSection(String title, List<Map<String, dynamic>> items, Color color) {
    // Agrupar items por cliente
    final Map<String, List<Map<String, dynamic>>> groupedByClient = {};
    for (var item in items) {
      final clientName = item["cliente"]?.toString() ?? "Sin Cliente";
      if (!groupedByClient.containsKey(clientName)) {
        groupedByClient[clientName] = [];
      }
      groupedByClient[clientName]!.add(item);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(
          "$title (${items.length})",
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        leading: Icon(Icons.folder, color: color),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: groupedByClient.entries.map((entry) {
          final String clientName = entry.key;
          final List<Map<String, dynamic>> clientItems = entry.value;

          return Card(
            elevation: 0.5,
            margin: const EdgeInsets.symmetric(vertical: 4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Colors.grey.shade50,
            child: ExpansionTile(
              initiallyExpanded: false, // Colapsado por defecto para facilitar la navegación
              leading: const Icon(Icons.person, color: Colors.blueGrey),
              title: Text(
                "$clientName (${clientItems.length})",
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
              ),
              childrenPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: clientItems.map((row) => _buildOperacionCard(row)).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOperacionCard(Map<String, dynamic> row) {
    final Map<String, dynamic> costosDetalle = (row["costos_detalle"] is Map)
        ? Map<String, dynamic>.from(row["costos_detalle"])
        : {};
    final double totalBase = double.tryParse(row["total"]?.toString() ?? "0") ?? 0;
    final double totalCalculado = double.tryParse(row["costo_total_calculado"]?.toString() ?? "0") ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(16),
          leading: CircleAvatar(
            backgroundColor: _getStatusColor(row["estatus"]).withOpacity(0.1),
            child: Icon(Icons.local_shipping, color: _getStatusColor(row["estatus"])),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "COT-${row["id"]}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blueGrey,
                ),
              ),
              if (row["estatus"] != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(row["estatus"]).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(row["estatus"]),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    row["estatus"].toString(),
                    style: TextStyle(
                      color: _getStatusColor(row["estatus"]),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                row["cliente"]?.toString() ?? "Cliente N/A",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Cont: ${row["contenedor"]}",
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 14, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "${row["origen"]} → ${row["destino"]}",
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Operación & Asignación",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Operador", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              row["operador"] ?? "Sin Asignar",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text("Tracto / Unidad", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              row["unidad"] ?? "Ninguno",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              textAlign: TextAlign.end,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Detalles de Carga",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Terminal", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(row["terminal"] ?? "N/A", style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Naviera", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          Text(row["naviera"]?.toString() ?? "N/A", style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Resumen de Costos y Liquidación",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueAccent),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Costo Base Cotización:"),
                            Text(
                              "\$${_formatMoneda(totalBase)} MXN",
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        if (costosDetalle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          const Text(
                            "Conceptos Base (Flete, Maniobras, etc. - No sumados al Total para evitar descuadres):",
                            style: TextStyle(fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                          const SizedBox(height: 4),
                          ...costosDetalle.entries.map((entry) {
                            if (entry.value == null || (double.tryParse(entry.value.toString()) ?? 0) == 0) {
                              return const SizedBox.shrink();
                            }
                            final double val = double.tryParse(entry.value.toString()) ?? 0;
                            final String label = entry.key.toString().replaceAll('_', ' ').toUpperCase();
                            final bool isRetencion = label.contains('RETENCION');
                            final Color textColor = isRetencion ? Colors.red.shade700 : Colors.black54;
                            final FontWeight fontWeight = isRetencion ? FontWeight.bold : FontWeight.normal;

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(fontSize: 11, color: textColor, fontWeight: fontWeight),
                                  ),
                                  Text(
                                    "${isRetencion ? '-' : ''}\$${_formatMoneda(val)} MXN",
                                    style: TextStyle(fontSize: 11, color: textColor, fontWeight: fontWeight),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Divider(),
                        ],
                        
                        // FÓRMULA DE COSTOS DEL VIAJE
                        const Text(
                          "Fórmula Desglosada del Costo Real",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                "Costo Viaje (Base Factura + Base Taref + IVA - Ret.):",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "\$${_formatMoneda(double.tryParse(row["total_costos_viaje"]?.toString() ?? "0") ?? 0)} MXN",
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                "Gastos Extras Consolidados:",
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "\$${_formatMoneda(double.tryParse(row["gastos_total"]?.toString() ?? "0") ?? 0)} MXN",
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
                            ),
                          ],
                        ),
                        
                        // LISTADO DE GASTOS EXTRAS SI EXISTEN
                        if (row["gastos_detalle"] != null && (row["gastos_detalle"] as List).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Gastos Extras Detalle:",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blueGrey),
                                ),
                                const SizedBox(height: 4),
                                ...((row["gastos_detalle"] as List).map((g) {
                                  final Map<String, dynamic> gasto = Map<String, dynamic>.from(g);
                                  final double valG = double.tryParse(gasto['monto']?.toString() ?? "0") ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            "${gasto['folio'] ?? 'S/F'} - ${gasto['concepto']}",
                                            style: const TextStyle(fontSize: 10, color: Colors.black87),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          "\$${_formatMoneda(valG)} MXN",
                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList()),
                              ],
                            ),
                          ),
                        ],

                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Costo Real Acumulado:",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "\$${_formatMoneda(totalCalculado)} MXN",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          "Total = Viaje (\$${_formatMoneda(double.tryParse(row["total_costos_viaje"]?.toString() ?? "0") ?? 0)}) + Gastos (\$${_formatMoneda(double.tryParse(row["gastos_total"]?.toString() ?? "0") ?? 0)})",
                          style: const TextStyle(fontSize: 9, color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showTripDetailsModal(row),
                      icon: const Icon(Icons.info_outline),
                      label: const Text("Detalle Operativo y Documentos"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
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

  void _showTripDetailsModal(Map<String, dynamic> row) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return FutureBuilder(
              future: ApiService.post(ApiEndpoints.infoViaje, {"id": row["contenedor_id"]?.toString() ?? ""}),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 300,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError || snapshot.data == null || snapshot.data!.statusCode != 200) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          "Error al cargar información del viaje: ${snapshot.error ?? 'Respuesta inválida'}",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  );
                }

                final response = jsonDecode(snapshot.data!.body);
                if (response["success"] != true) {
                  return SizedBox(
                    height: 200,
                    child: Center(
                      child: Text(response["mensaje"] ?? "Error desconocido"),
                    ),
                  );
                }

                final data = response["data"] ?? {};
                final documentos = data["documentos"] ?? {};
                final documentsStatus = data["documents"] ?? {};
                final isCima = documentsStatus["cima"] == 1 || documentsStatus["cima"] == "1" || (documentos != null && documentos["cima"] == 1);
                final String beneficiarioTelefono = documentos["beneficiario_telefono"]?.toString() ?? "";

                return DraggableScrollableSheet(
                  initialChildSize: 0.85,
                  maxChildSize: 0.95,
                  minChildSize: 0.5,
                  expand: false,
                  builder: (context, scrollController) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              data["tipo"] ?? "Viaje",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: (data["tipo"] ?? "").toString().contains("Propio") ? Colors.green.shade800 : Colors.blue.shade800
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            )
                          ],
                        ),
                        const Divider(),
                        
                        _sectionTitle("Información Operativa"),
                        _detailRow("Cliente", data["cliente"]?["nombre"] ?? "N/A"),
                        _detailRow("Subcliente", data["subcliente"]?["nombre"] ?? "N/A"),
                        _detailRow("Proveedor", documentos["Empresa"] ?? "N/A"),
                        _detailRow("Transportista", (documentos["transportista_nombre"] != null && documentos["transportista_nombre"].toString().trim().isNotEmpty) ? documentos["transportista_nombre"] : (documentos["Empresa"] ?? "N/A")),
                        _detailRow("Contenedor(es)", documentsStatus["num_contenedor"] ?? "N/A"),
                        _detailRow("Origen", data["cotizacion"]?["origen"] ?? "N/A"),
                        _detailRow("Destino", data["cotizacion"]?["destino"] ?? "N/A"),
                        const SizedBox(height: 16),
                        
                        _sectionTitle("Asignación de Tránsito"),
                        _detailRow("Operador", documentos["operador"] ?? "N/A"),
                        Row(
                          children: [
                            Expanded(child: _detailRow("Teléfono", beneficiarioTelefono.isNotEmpty ? beneficiarioTelefono : "N/A")),
                            if (beneficiarioTelefono.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.phone, color: Colors.green),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Marcando a $beneficiarioTelefono...")),
                                  );
                                },
                              )
                          ],
                        ),
                        _detailRow("Tractocamión placas", documentos["placas_camion"] ?? "N/A"),
                        _detailRow("Unidad ID", documentos["id_equipo_camion"] ?? "N/A"),
                        _detailRow("Marca", documentos["marca_camion"] ?? "N/A"),
                        _detailRow("Chasis ID", documentos["id_equipo_chasis"] ?? "N/A"),
                        const SizedBox(height: 16),

                        _sectionTitle("Checklist de Documentos"),
                        _docCheckRow("Formato CCP", documentsStatus["doc_ccp"], filename: documentos["doc_ccp"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Boleta de liberación", documentsStatus["boleta_liberacion"], filename: documentos["boleta_liberacion"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Doda", documentsStatus["doda"], filename: documentos["doda"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Carta Porte PDF", documentsStatus["carta_porte"], filename: documentos["carta_porte"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Carta Porte XML", documentsStatus["carta_porte_xml"], filename: documentos["carta_porte_xml"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Prealta - Boleta vacío", documentsStatus["boleta_vacio"], filename: documentos["boleta_vacio"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        if (!isCima)
                          _docCheckRow("EIR - Comprobante vacío", documentsStatus["doc_eir"], filename: documentos["doc_eir"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? ""))
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                                const SizedBox(width: 6),
                                Text(
                                  "CIMA Activo: EIR omitido",
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                          ),
                        _docCheckRow("Evidencia Descarga", documentsStatus["evidencia_descarga"], filename: documentos["evidencia_descarga"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Complemento de pago PDF", documentsStatus["comprobante_pago_pdf"], filename: documentos["comprobante_pago_pdf"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Complemento de pago XML", documentsStatus["comprobante_pago_xml"], filename: documentos["comprobante_pago_xml"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => _generateAndShareTripPdf(
                              data: data,
                              documentos: documentos,
                              documentsStatus: documentsStatus,
                            ),
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                            label: const Text(
                              "Resumen Viaje",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                );
              },
            );
          }
        );
      },
    );
  }

  Future<void> _generateAndShareTripPdf({
    required Map<String, dynamic> data,
    required Map<String, dynamic> documentos,
    required Map<String, dynamic> documentsStatus,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text("Generando Resumen PDF..."),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final pdf = pw.Document();

      final String tipo = data["tipo"]?.toString() ?? "Viaje";
      final String cliente = data["cliente"]?["nombre"]?.toString() ?? "N/A";
      final String subcliente = data["subcliente"]?["nombre"]?.toString() ?? "N/A";
      final String proveedor = documentos["Empresa"]?.toString() ?? "N/A";
      final String transportista = (documentos["transportista_nombre"] != null && documentos["transportista_nombre"].toString().trim().isNotEmpty)
          ? documentos["transportista_nombre"].toString()
          : (documentos["Empresa"]?.toString() ?? "N/A");
      final String numContenedor = documentsStatus["num_contenedor"]?.toString() ?? documentos["num_contenedor"]?.toString() ?? "N/A";
      final String origen = data["cotizacion"]?["origen"]?.toString() ?? "N/A";
      final String destino = data["cotizacion"]?["destino"]?.toString() ?? "N/A";
      final String operador = documentos["operador"]?.toString() ?? "N/A";
      final String telefono = documentos["beneficiario_telefono"]?.toString() ?? "N/A";
      final String placas = documentos["placas_camion"]?.toString() ?? "N/A";
      final String unidad = documentos["id_equipo_camion"]?.toString() ?? "N/A";
      final String marca = documentos["marca_camion"]?.toString() ?? "N/A";
      final String chasis = documentos["id_equipo_chasis"]?.toString() ?? "N/A";
      final String fechaInicio = documentos["fecha_inicio"]?.toString() ?? "N/A";
      final String fechaFin = documentos["fecha_fin"]?.toString() ?? "N/A";
      final bool isCima = documentsStatus["cima"] == 1 || documentsStatus["cima"] == "1" || documentos["cima"] == 1;

      final List<Map<String, String>> docsList = [
        {
          "nombre": "Formato CCP",
          "status": (documentsStatus["doc_ccp"] != null && documentsStatus["doc_ccp"] != false && documentsStatus["doc_ccp"] != 0 && documentsStatus["doc_ccp"] != "0" && documentsStatus["doc_ccp"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["doc_ccp"]?.toString() ?? "-"
        },
        {
          "nombre": "Boleta de liberación",
          "status": (documentsStatus["boleta_liberacion"] != null && documentsStatus["boleta_liberacion"] != false && documentsStatus["boleta_liberacion"] != 0 && documentsStatus["boleta_liberacion"] != "0" && documentsStatus["boleta_liberacion"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["boleta_liberacion"]?.toString() ?? "-"
        },
        {
          "nombre": "Doda",
          "status": (documentsStatus["doda"] != null && documentsStatus["doda"] != false && documentsStatus["doda"] != 0 && documentsStatus["doda"] != "0" && documentsStatus["doda"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["doda"]?.toString() ?? "-"
        },
        {
          "nombre": "Carta Porte PDF",
          "status": (documentsStatus["carta_porte"] != null && documentsStatus["carta_porte"] != false && documentsStatus["carta_porte"] != 0 && documentsStatus["carta_porte"] != "0" && documentsStatus["carta_porte"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["carta_porte"]?.toString() ?? "-"
        },
        {
          "nombre": "Carta Porte XML",
          "status": (documentsStatus["carta_porte_xml"] != null && documentsStatus["carta_porte_xml"] != false && documentsStatus["carta_porte_xml"] != 0 && documentsStatus["carta_porte_xml"] != "0" && documentsStatus["carta_porte_xml"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["carta_porte_xml"]?.toString() ?? "-"
        },
        {
          "nombre": "Prealta - Boleta vacío",
          "status": (documentsStatus["boleta_vacio"] != null && documentsStatus["boleta_vacio"] != false && documentsStatus["boleta_vacio"] != 0 && documentsStatus["boleta_vacio"] != "0" && documentsStatus["boleta_vacio"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["boleta_vacio"]?.toString() ?? "-"
        },
        if (!isCima)
          {
            "nombre": "EIR - Comprobante vacío",
            "status": (documentsStatus["doc_eir"] != null && documentsStatus["doc_eir"] != false && documentsStatus["doc_eir"] != 0 && documentsStatus["doc_eir"] != "0" && documentsStatus["doc_eir"] != "") ? "CARGADO" : "PENDIENTE",
            "archivo": documentos["doc_eir"]?.toString() ?? "-"
          }
        else
          {
            "nombre": "EIR - Comprobante vacío",
            "status": "CIMA ACTIVO (OMITIDO)",
            "archivo": "CIMA"
          },
        {
          "nombre": "Evidencia Descarga",
          "status": (documentsStatus["evidencia_descarga"] != null && documentsStatus["evidencia_descarga"] != false && documentsStatus["evidencia_descarga"] != 0 && documentsStatus["evidencia_descarga"] != "0" && documentsStatus["evidencia_descarga"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["evidencia_descarga"]?.toString() ?? "-"
        },
        {
          "nombre": "Complemento de pago PDF",
          "status": (documentsStatus["comprobante_pago_pdf"] != null && documentsStatus["comprobante_pago_pdf"] != false && documentsStatus["comprobante_pago_pdf"] != 0 && documentsStatus["comprobante_pago_pdf"] != "0" && documentsStatus["comprobante_pago_pdf"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["comprobante_pago_pdf"]?.toString() ?? "-"
        },
        {
          "nombre": "Complemento de pago XML",
          "status": (documentsStatus["comprobante_pago_xml"] != null && documentsStatus["comprobante_pago_xml"] != false && documentsStatus["comprobante_pago_xml"] != 0 && documentsStatus["comprobante_pago_xml"] != "0" && documentsStatus["comprobante_pago_xml"] != "") ? "CARGADO" : "PENDIENTE",
          "archivo": documentos["comprobante_pago_xml"]?.toString() ?? "-"
        },
      ];

      final fontBase = pw.Font.helvetica();
      final fontBold = pw.Font.helveticaBold();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            return [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blue900,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "SGT LOGISTICS",
                          style: pw.TextStyle(font: fontBold, color: PdfColors.white, fontSize: 16),
                        ),
                        pw.Text(
                          "Resumen Operativo de Viaje",
                          style: pw.TextStyle(font: fontBase, color: PdfColors.white, fontSize: 11),
                        ),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                      ),
                      child: pw.Text(
                        tipo.toUpperCase(),
                        style: pw.TextStyle(font: fontBold, color: PdfColors.blue900, fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Contenedor Highlight
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  border: pw.Border.all(color: PdfColors.grey400),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("CONTENEDOR(ES):", style: pw.TextStyle(font: fontBold, fontSize: 11, color: PdfColors.blueGrey800)),
                    pw.Text(numContenedor, style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue900)),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),

              // Sección 1: Información Operativa
              pw.Text("1. INFORMACIÓN OPERATIVA", style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue900)),
              pw.Divider(color: PdfColors.blue900, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(children: [
                    pw.Text("Cliente:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(cliente, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Subcliente:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(subcliente, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text("Proveedor:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(proveedor, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Transportista:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(transportista, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text("Origen:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(origen, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Destino:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(destino, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text("Fecha Inicio:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(fechaInicio, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Fecha Fin:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(fechaFin, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 14),

              // Sección 2: Asignación de Tránsito
              pw.Text("2. ASIGNACIÓN DE TRÁNSITO", style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue900)),
              pw.Divider(color: PdfColors.blue900, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(3),
                },
                children: [
                  pw.TableRow(children: [
                    pw.Text("Operador:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(operador, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Teléfono:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(telefono, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text("Unidad / Eco:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(unidad, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Placas:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(placas, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                  pw.TableRow(children: [
                    pw.Text("Marca:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(marca, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                    pw.Text("Chasis ID:", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                    pw.Text(chasis, style: pw.TextStyle(font: fontBase, fontSize: 9)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 14),

              // Sección 3: Checklist de Documentos
              pw.Text("3. CHECKLIST DE DOCUMENTACIÓN", style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.blue900)),
              pw.Divider(color: PdfColors.blue900, thickness: 1),
              pw.SizedBox(height: 4),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("DOCUMENTO", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("ESTADO", style: pw.TextStyle(font: fontBold, fontSize: 9), textAlign: pw.TextAlign.center),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(6),
                        child: pw.Text("ARCHIVO ADJUNTO", style: pw.TextStyle(font: fontBold, fontSize: 9)),
                      ),
                    ],
                  ),
                  ...docsList.map((d) {
                    final bool isOk = d["status"] == "CARGADO";
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(d["nombre"]!, style: pw.TextStyle(font: fontBase, fontSize: 8.5)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            isOk ? "[OK] CARGADO" : "[-] PENDIENTE",
                            style: pw.TextStyle(
                              font: fontBold,
                              fontSize: 8.5,
                              color: isOk ? PdfColors.green800 : PdfColors.red800,
                            ),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            d["archivo"]!,
                            style: pw.TextStyle(
                              font: fontBase,
                              fontSize: 7.5,
                              color: isOk ? PdfColors.black : PdfColors.grey600,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 20),

              // Footer
              pw.Divider(color: PdfColors.grey400),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    "Generado desde SGT Móvil - Sistema de Gestión de Transporte",
                    style: pw.TextStyle(font: fontBase, fontSize: 8, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    "Fecha de emisión: ${DateTime.now().toLocal().toString().split('.')[0]}",
                    style: pw.TextStyle(font: fontBase, fontSize: 8, color: PdfColors.grey600),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final cleanNum = numContenedor.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File('${dir.path}/Detalle_Viaje_$cleanNum.pdf');
      await file.writeAsBytes(bytes);

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: "Resumen de Viaje - Contenedor: $numContenedor\nTipo: $tipo\nOperador: $operador",
          subject: "Detalle de Viaje $numContenedor",
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al generar PDF: $e")),
      );
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey),
      ),
    );
  }

  String _getItemName(Map<String, dynamic> item) {
    final String tipoItem = item["tipo_item"]?.toString() ?? "equipo";
    final String subTipo = (item["tipo"]?.toString() ?? "").toLowerCase();

    if (tipoItem == "contenedor") {
      if (subTipo == "chasis" || subTipo == "chasis b" || subTipo == "plataforma") {
        return item["id_equipo"]?.toString() ?? item["placas"]?.toString() ?? "Chasis";
      }
      return item["contenedor"]?.toString() ?? item["num_contenedor"]?.toString() ?? "Contenedor";
    } else if (tipoItem == "convoy") {
      return item["nombre"]?.toString() ?? "Convoy ${item["no_conboy"]}";
    } else {
      return item["id_equipo"]?.toString() ?? item["placas"]?.toString() ?? "Equipo";
    }
  }

  Future<void> _showWebStyleInfoViajeModal(Map<String, dynamic> item) async {
    final dynamic containerId = item["id_contenedor"] ?? item["contenedor_id"] ?? item["id"];
    if (containerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No se encontró ID de contenedor para cargar la información.")),
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
      final response = await ApiService.post(ApiEndpoints.infoViaje, {"id": containerId});
      Navigator.pop(context);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final dynamic data = body["data"];
        if (data == null) throw Exception("No data");
        final dynamic docum = data["documentos"];
        final dynamic cotizacion = data["cotizacion"];
        final String? waText = data["wa_text"]?.toString();
        
        if (docum == null) {
          throw Exception("No data");
        }

        final String cliente = docum["cliente"]?.toString() ?? "S/N";
        final String origen = cotizacion?["origen"]?.toString() ?? "S/N";
        final String destino = cotizacion?["destino"]?.toString() ?? "S/N";
        final String fechaInicio = docum["fecha_inicio"]?.toString() ?? "S/N";
        final String fechaFin = docum["fecha_fin"]?.toString() ?? "S/N";
        final String contrato = docum["tipo_contrato"]?.toString() ?? "S/N";
        
        final String operador = docum["operador"]?.toString() ?? "S/N";
        final String contacto = cotizacion?["cp_contacto_entrega"]?.toString() ?? "S/N";
        final String telefono = docum["beneficiario_telefono"]?.toString() ?? "S/N";
        
        final String empresa = docum["Empresa"]?.toString() ?? "S/N";
        final String transportista = docum["transportista_nombre"]?.toString() ??  docum["Empresa"]?.toString() ?? "S/N";
        
        final String tractoImei = docum["imei_camion"]?.toString() ?? "S/N";
        final String tractoEquipo = docum["id_equipo_camion"]?.toString() ?? "S/N";
        final String tractoPlacas = docum["placas_camion"]?.toString() ?? "S/N";
        
        final String chasisAImei = docum["imei_chasis"]?.toString() ?? "S/N";
        final String chasisAEquipo = docum["id_equipo_chasis"]?.toString() ?? "S/N";
        final String chasisAPlacas = "S/N";

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            titlePadding: EdgeInsets.zero,
            contentPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.airport_shuttle, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Información de Viaje: ${docum["contenedor"] ?? docum["num_contenedor"] ?? 'S/N'}",
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(left: BorderSide(color: Colors.blue.shade700, width: 5)),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [BoxShadow(color: Colors.grey.shade200, blurRadius: 4)],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("CLIENTE:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12)),
                                child: Text(contrato, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(cliente, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const Divider(),
                          const Text("ORIGEN / DESTINO:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                          const SizedBox(height: 4),
                          Text(origen, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const SizedBox(height: 2),
                          const Icon(Icons.arrow_downward, size: 16, color: Colors.blueGrey),
                          const SizedBox(height: 2),
                          Text(destino, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("INICIO:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    Text(fechaInicio, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text("FIN:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
                                    const SizedBox(height: 4),
                                    Text(fechaFin, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildWebModalSection(
                      title: "Beneficiario",
                      icon: Icons.person,
                      color: Colors.blue,
                      children: [
                        _webModalRow("Operador:", operador),
                        _webModalRow("Contacto:", contacto),
                        _webModalRow("Teléfono:", telefono),
                      ],
                    ),

                    _buildWebModalSection(
                      title: "Transportista",
                      icon: Icons.business,
                      color: Colors.teal,
                      children: [
                        _webModalRow("Empresa:", empresa),
                        _webModalRow("Transportista:", transportista),
                      ],
                    ),

                    _buildWebModalSection(
                      title: "Equipo Asignado",
                      icon: Icons.airport_shuttle,
                      color: Colors.orange,
                      children: [
                        const Text("Tracto:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        _webModalRow("  IMEI:", tractoImei),
                        _webModalRow("  Equipo:", tractoEquipo),
                        _webModalRow("  Placas:", tractoPlacas),
                        const Divider(),
                        const Text("Chasis A:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        _webModalRow("  IMEI:", chasisAImei),
                        _webModalRow("  Equipo:", chasisAEquipo),
                        _webModalRow("  Placas:", chasisAPlacas),
                      ],
                    ),
                    if (waText != null && waText.trim().isNotEmpty)
                      _buildWebModalSection(
                        title: "Información para operador",
                        icon: Icons.chat,
                        color: Colors.green,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: SelectableText(
                              waText,
                              style: const TextStyle(fontSize: 12, height: 1.4, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                child: const Text("Cerrar", style: TextStyle(color: Colors.white)),
              ),
              if (waText != null && waText.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _shareTripText(waText),
                  icon: const Icon(Icons.share, color: Colors.white, size: 16),
                  label: const Text("Compartir WhatsApp", style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                ),
            ],
          ),
        );
      } else {
        throw Exception("Error");
      }
    } catch (e) {
      if (Navigator.canPop(context)) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Error al cargar la información del viaje.")),
      );
    }
  }

  Future<void> _shareTripText(String text) async {
    if (text.isEmpty) return;
    final encodedText = Uri.encodeComponent(text);
    final Uri waUri = Uri.parse("whatsapp://send?text=$encodedText");
    final Uri waWebUri = Uri.parse("https://api.whatsapp.com/send?text=$encodedText");

    try {
      if (await canLaunchUrl(waUri)) {
        await launchUrl(waUri, mode: LaunchMode.externalApplication);
        return;
      } else if (await canLaunchUrl(waWebUri)) {
        await launchUrl(waWebUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}

    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _shareDocumentFile(String url, String fileName, String docTitle) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await http.get(Uri.parse(url));
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (response.statusCode != 200) {
        throw Exception("Error de descarga (${response.statusCode})");
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsBytes(response.bodyBytes);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path)],
          text: 'Documento: $docTitle',
        ),
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al compartir documento: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildWebModalSection({required String title, required IconData icon, required Color color, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
            ],
          ),
          const Divider(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _webModalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey)),
          const SizedBox(width: 6),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _docCheckRow(String label, dynamic value, {String? filename, int? cotizacionId}) {
    final bool isCompleted = value != null && value != false && value != 0 && value != "0" && value != "";
    final bool canLaunch = isCompleted && filename != null && filename.isNotEmpty && cotizacionId != null;
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    final fileUrl = canLaunch ? "$cleanBaseUrl/cotizaciones/cotizacion$cotizacionId/$filename" : "";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: InkWell(
              onTap: canLaunch
                  ? () {
                      FileDownloader.downloadFile(
                        context: context,
                        url: fileUrl,
                        fileName: filename,
                      );
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: canLaunch ? Colors.blue.shade900 : Colors.black87,
                          fontWeight: canLaunch ? FontWeight.w600 : FontWeight.normal,
                          decoration: canLaunch ? TextDecoration.underline : TextDecoration.none,
                        ),
                      ),
                    ),
                    if (canLaunch) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.file_download, size: 16, color: Colors.blue),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (canLaunch) ...[
            IconButton(
              icon: const Icon(Icons.share, color: Colors.green, size: 18),
              tooltip: "Compartir $label",
              onPressed: () => _shareDocumentFile(fileUrl, filename, label),
            ),
          ],
          Icon(
            isCompleted ? Icons.check_circle : Icons.cancel,
            color: isCompleted ? Colors.green : Colors.grey.shade400,
          ),
        ],
      ),
    );
  }

  Future<gmaps.BitmapDescriptor> _createCustomMarkerIcon(
      Color color, String mainTitle, String subTitle, String typeLetter, bool isStopped) async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(pictureRecorder);
    const double width = 360.0;
    const double height = 110.0;

    final ui.Paint bubblePaint = ui.Paint()
      ..color = const Color(0xE62E4053)
      ..style = ui.PaintingStyle.fill;
      
    final ui.Paint bubbleBorderPaint = ui.Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final RRect bubbleRect = RRect.fromLTRBAndCorners(
      85.0, 15.0, 350.0, 95.0,
      topLeft: const Radius.circular(12),
      topRight: const Radius.circular(12),
      bottomLeft: const Radius.circular(12),
      bottomRight: const Radius.circular(12),
    );
    canvas.drawRRect(bubbleRect, bubblePaint);
    canvas.drawRRect(bubbleRect, bubbleBorderPaint);

    final ui.Paint pinPaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;
    final ui.Paint pinBorderPaint = ui.Paint()
      ..color = Colors.white
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final ui.Path path = ui.Path();
    path.moveTo(45.0, height - 15.0);
    path.lineTo(35.0, height - 40.0);
    path.lineTo(55.0, height - 40.0);
    path.close();
    canvas.drawPath(path, pinPaint);
    canvas.drawPath(path, pinBorderPaint);

    canvas.drawCircle(const Offset(45.0, 45.0), 30.0, pinPaint);
    canvas.drawCircle(const Offset(45.0, 45.0), 30.0, pinBorderPaint);

    final TextPainter letterPainter = TextPainter(textDirection: TextDirection.ltr);
    letterPainter.text = TextSpan(
      text: typeLetter,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: Colors.white,
      ),
    );
    letterPainter.layout();
    letterPainter.paint(canvas, Offset(45.0 - letterPainter.width / 2, 45.0 - letterPainter.height / 2));

    final ui.Paint badgePaint = ui.Paint()
      ..color = color
      ..style = ui.PaintingStyle.fill;
    final RRect badgeRect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(20.0, 78.0, 70.0, 92.0),
      const Radius.circular(4),
    );
    canvas.drawRRect(badgeRect, badgePaint);

    final TextPainter statusPainter = TextPainter(textDirection: TextDirection.ltr);
    statusPainter.text = TextSpan(
      text: isStopped ? "DET" : "RUTA",
      style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
    );
    statusPainter.layout();
    statusPainter.paint(canvas, Offset(45.0 - statusPainter.width / 2, 85.0 - statusPainter.height / 2));

    final TextPainter titlePainter = TextPainter(textDirection: TextDirection.ltr);
    titlePainter.text = TextSpan(
      text: mainTitle,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
    );
    titlePainter.layout();
    titlePainter.paint(canvas, const Offset(100.0, 24.0));

    final TextPainter subTitlePainter = TextPainter(textDirection: TextDirection.ltr);
    subTitlePainter.text = TextSpan(
      text: subTitle.toUpperCase(),
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.85)),
    );
    subTitlePainter.layout();
    subTitlePainter.paint(canvas, const Offset(100.0, 46.0));

    final TextPainter statusLinePainter = TextPainter(textDirection: TextDirection.ltr);
    statusLinePainter.text = TextSpan(
      text: isStopped ? "DETENIDO" : "EN MOVIMIENTO",
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
    );
    statusLinePainter.layout();
    statusLinePainter.paint(canvas, const Offset(100.0, 66.0));

    final image = await pictureRecorder.endRecording().toImage(width.toInt(), height.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return gmaps.BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  void _loadCustomMarkerIcon(String key, Color color, String mainTitle, String subTitle, String typeLetter, bool isStopped) async {
    if (_customMarkerIcons.containsKey(key)) return;
    try {
      final icon = await _createCustomMarkerIcon(color, mainTitle, subTitle, typeLetter, isStopped);
      if (mounted) {
        setState(() {
          _customMarkerIcons[key] = icon;
        });
      }
    } catch (e) {
      // Fallback
    }
  }

  Set<gmaps.Marker> _buildGoogleGpsMarkers() {
    final Set<gmaps.Marker> markers = {};
    for (var item in filteredItems) {
      final String tipoItem = item["tipo_item"]?.toString() ?? "equipo";
      if (tipoItem == "contenedor" && !_showContenedores) continue;
      if (tipoItem == "equipo" && !_showEquipos) continue;

      final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
      final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
      if (lat == null || lng == null || lat == 0 || lng == 0) continue;

      final String tipo = (item["tipo"]?.toString() ?? "camion").toLowerCase();
      if (tipo.contains("chasis") || tipo.contains("plataforma")) {
        if (tipo.contains("b") || item["id_equipo"]?.toString().toLowerCase().contains("b") == true) {
          if (!_showChasisB) continue;
        } else {
          if (!_showChasisA) continue;
        }
      } else {
        if (!_showCamion) continue;
      }

      final String itemKey = tipoItem == "contenedor"
          ? "${item['tipo_item']}_${item['id'] ?? item['contenedor']}"
          : "${item['tipo_item']}_${item['id'] ?? item['id_equipo'] ?? item['nombre']}";
          
      if (!_selectedCardIds.contains(itemKey)) continue;

      final String markerKey = "${item['tipo_item']}_${item['id'] ?? item['contenedor']}_$tipo";

      bool isMovingByCoords = false;
      if (_previousCoordinates.containsKey(markerKey)) {
        final prev = _previousCoordinates[markerKey]!;
        if (prev.latitude != lat || prev.longitude != lng) {
          isMovingByCoords = true;
        }
      }
      _previousCoordinates[markerKey] = LatLng(lat, lng);

      bool isStopped = (item["velocidad"]?.toString() == "0" || 
                        item["speed"]?.toString() == "0" || 
                        (item["estatus"]?.toString().toLowerCase().contains("detenido") ?? false));
      if (isMovingByCoords) {
        isStopped = false;
      }

      final Color markerColor = isStopped ? Colors.orange.shade800 : Colors.green.shade600;
      
      String typeLetter = "T";
      String subTitleLabel = "Tracto";
      if (tipo.contains("chasis") || tipo.contains("plataforma")) {
        if (tipo.contains("b") || item["id_equipo"]?.toString().toLowerCase().contains("b") == true) {
          typeLetter = "B";
          subTitleLabel = "Chasis B";
        } else {
          typeLetter = "A";
          subTitleLabel = "Chasis A";
        }
      }
      
      final String idEquipo = item["id_equipo"]?.toString() ?? "";
      final String formattedSubTitle = "$subTitleLabel${idEquipo.isNotEmpty ? ' - $idEquipo' : ''}";
      
      final String containerNum = item["contenedor"]?.toString() ?? item["num_contenedor"]?.toString() ?? _getItemName(item);
      
      final String cacheKey = "${markerKey}_$isStopped";
      _loadCustomMarkerIcon(cacheKey, markerColor, containerNum, formattedSubTitle, typeLetter, isStopped);
      
      final gmaps.BitmapDescriptor icon = _customMarkerIcons[cacheKey] ?? gmaps.BitmapDescriptor.defaultMarkerWithHue(
        isStopped ? gmaps.BitmapDescriptor.hueOrange : gmaps.BitmapDescriptor.hueGreen
      );

      markers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId(markerKey),
          position: gmaps.LatLng(lat, lng),
          icon: icon,
          onTap: () {
            setState(() {
              _selectedGpsItem = item;
            });
            _googleMapController?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(lat, lng), 15));
            _fetchDestinationAndRoute(item, LatLng(lat, lng));
          },
        ),
      );
    }
    return markers;
  }

  List<fmap.Marker> _buildFlutterMapMarkers() {
    final List<fmap.Marker> markers = [];
    for (var item in filteredItems) {
      final String tipoItem = item["tipo_item"]?.toString() ?? "equipo";
      if (tipoItem == "contenedor" && !_showContenedores) continue;
      if (tipoItem == "equipo" && !_showEquipos) continue;

      final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
      final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
      if (lat == null || lng == null || lat == 0 || lng == 0) continue;

      final String tipo = (item["tipo"]?.toString() ?? "camion").toLowerCase();
      if (tipo.contains("chasis") || tipo.contains("plataforma")) {
        if (tipo.contains("b") || item["id_equipo"]?.toString().toLowerCase().contains("b") == true) {
          if (!_showChasisB) continue;
        } else {
          if (!_showChasisA) continue;
        }
      } else {
        if (!_showCamion) continue;
      }

      final isStopped = (item["velocidad"]?.toString() == "0" || 
                         item["speed"]?.toString() == "0" || 
                         (item["estatus"]?.toString().toLowerCase().contains("detenido") ?? false));
                           
      final Color markerColor = isStopped ? Colors.red : Colors.green;

      markers.add(
        fmap.Marker(
          point: LatLng(lat, lng),
          width: 90,
          height: 90,
          child: GestureDetector(
            onTap: () {
              setState(() {
                _selectedGpsItem = item;
              });
              _mapController.move(LatLng(lat, lng), 15);
              _fetchDestinationAndRoute(item, LatLng(lat, lng));
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getItemName(item),
                    style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  decoration: BoxDecoration(
                    color: markerColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                    ],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(
                    Icons.local_shipping,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return markers;
  }

  void _showUnitSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String filterText = "";
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final List<Map<String, dynamic>> searchResults = filteredItems.where((item) {
              final String name = _getItemName(item).toLowerCase();
              final String type = (item["tipo_item"] ?? "").toString().toLowerCase();
              return name.contains(filterText.toLowerCase()) || type.contains(filterText.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text("Seleccionar Unidad / Convoy"),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: "Buscar por nombre, contenedor...",
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          filterText = val;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.builder(
                        itemCount: searchResults.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ListTile(
                              leading: const Icon(Icons.map, color: Colors.blue),
                              title: const Text("Mostrar Todos (Centrar)"),
                              onTap: () {
                                Navigator.pop(context);
                                if (filteredItems.isNotEmpty) {
                                  for (var item in filteredItems) {
                                    final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
                                    final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
                                    if (lat != null && lng != null && lat != 0 && lng != 0) {
                                      final bool useGoogleMaps = kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);
                                      if (useGoogleMaps) {
                                        _googleMapController?.animateCamera(
                                          gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(lat, lng), 10),
                                        );
                                      } else {
                                        _mapController.move(LatLng(lat, lng), 10);
                                      }
                                      break;
                                    }
                                  }
                                }
                              },
                            );
                          }
                          final item = searchResults[index - 1];
                          final String name = _getItemName(item);
                          final String type = item["tipo_item"] == "contenedor"
                              ? "Contenedor"
                              : item["tipo_item"] == "convoy"
                                  ? "Convoy"
                                  : "Equipo";
                          final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
                          final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
                          final bool hasCoords = lat != null && lng != null && lat != 0 && lng != 0;
                          
                          final String itemKey = item["tipo_item"] == "contenedor"
                              ? "${item['tipo_item']}_${item['id'] ?? item['contenedor']}"
                              : "${item['tipo_item']}_${item['id'] ?? item['id_equipo'] ?? item['nombre']}";
                          final bool isPinned = _selectedCardIds.contains(itemKey);

                          return ListTile(
                            leading: Icon(
                              item["tipo_item"] == "contenedor"
                                  ? Icons.inventory_2
                                  : item["tipo_item"] == "convoy"
                                      ? Icons.group_work
                                      : Icons.local_shipping,
                              color: hasCoords ? Colors.green : Colors.grey,
                            ),
                            title: Text(name),
                            subtitle: Text("$type ${hasCoords ? '' : '(Sin señal)'}"),
                            trailing: Checkbox(
                              activeColor: Colors.blue.shade700,
                              value: isPinned,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    _selectedCardIds.add(itemKey);
                                  } else {
                                    _selectedCardIds.remove(itemKey);
                                  }
                                });
                                setState(() {});
                              },
                            ),
                            onTap: !hasCoords ? null : () {
                              Navigator.pop(context);
                              setState(() {
                                _selectedGpsItem = item;
                              });
                              final bool useGoogleMaps = kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);
                              if (useGoogleMaps) {
                                _googleMapController?.animateCamera(
                                  gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(lat, lng), 15),
                                );
                              } else {
                                _mapController.move(LatLng(lat, lng), 15);
                              }
                              _fetchDestinationAndRoute(item, LatLng(lat, lng));
                            },
                          );
                        },
                      ),
                    ),
                  ],
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

  Future<void> _fetchRoute(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson"
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data["routes"] != null && data["routes"].isNotEmpty) {
          final coordinates = data["routes"][0]["geometry"]["coordinates"] as List;
          setState(() {
            _routePoints = coordinates.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
          });
        }
      }
    } catch (e) {
      setState(() {
        _routePoints = [start, end];
      });
    }
  }

  Widget _buildGpsMonitoreoView() {
    final List<Map<String, dynamic>> visibleCards = filteredItems.where((item) {
      final String tipoItem = item["tipo_item"]?.toString() ?? "";
      final String tipo = (item["tipo"]?.toString() ?? "").toLowerCase();
      
      // Exclude sub-equipments (Chasis A / Chasis B) from getting their own cards
      if (tipoItem == "contenedor" && (tipo == "chasis" || tipo == "chasis b" || tipo == "plataforma")) {
        return false;
      }
      
      final String itemKey = tipoItem == "contenedor"
          ? "${item['tipo_item']}_${item['id'] ?? item['contenedor']}"
          : "${item['tipo_item']}_${item['id'] ?? item['id_equipo'] ?? item['nombre']}";
          
      return _selectedCardIds.contains(itemKey);
    }).toList();

    LatLng initialCenter = const LatLng(19.4326, -99.1332);
    for (var item in filteredItems) {
      final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
      final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
      if (lat != null && lng != null && lat != 0 && lng != 0) {
        initialCenter = LatLng(lat, lng);
        break;
      }
    }

    // Verificar si hay por lo menos un equipo en rastreo activo con coordenadas válidas
    final bool hasActiveGps = filteredItems.any((item) {
      final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
      final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
      return lat != null && lng != null && lat != 0 && lng != 0;
    });

    return Stack(
      children: [
        (() {
          final bool useGoogleMaps = kIsWeb || (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS);
          if (useGoogleMaps) {
            return gmaps.GoogleMap(
              initialCameraPosition: gmaps.CameraPosition(
                target: gmaps.LatLng(initialCenter.latitude, initialCenter.longitude),
                zoom: 10,
              ),
              onMapCreated: (controller) {
                _googleMapController = controller;
              },
              markers: _buildGoogleGpsMarkers(),
              polylines: {
                if (_showRoute && _routePoints.isNotEmpty)
                  gmaps.Polyline(
                    polylineId: const gmaps.PolylineId("route"),
                    points: _routePoints.map((p) => gmaps.LatLng(p.latitude, p.longitude)).toList(),
                    width: 4,
                    color: Colors.blue.shade700,
                  ),
              },
            );
          } else {
            return fmap.FlutterMap(
              mapController: _mapController,
              options: fmap.MapOptions(
                initialCenter: initialCenter,
                initialZoom: 10,
              ),
              children: [
                fmap.TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: 'com.sgtlogistics.app',
                ),
                if (_showRoute && _routePoints.isNotEmpty)
                  fmap.PolylineLayer(
                    polylines: [
                      fmap.Polyline(
                        points: _routePoints,
                        strokeWidth: 4,
                        color: Colors.blue.shade700,
                      ),
                    ],
                  ),
                fmap.MarkerLayer(
                  markers: _buildFlutterMapMarkers(),
                ),
              ],
            );
          }
        })(),

        // Botón flotante superior derecho para filtros y vista
        Positioned(
          top: 16,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: "mapFilterBtn",
                backgroundColor: Colors.white,
                foregroundColor: hasActiveGps ? Colors.blueGrey.shade800 : Colors.grey.shade400,
                onPressed: !hasActiveGps
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Opción deshabilitada: No hay equipos activos con señal GPS en el mapa."),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    : () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text("Mostrar en Mapa"),
                            content: StatefulBuilder(
                              builder: (context, setDialogState) {
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CheckboxListTile(
                                      title: const Text("Contenedores Activos (Viajes)"),
                                      value: _showContenedores,
                                      activeColor: Colors.blue.shade700,
                                      onChanged: (val) {
                                        setDialogState(() => _showContenedores = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                    CheckboxListTile(
                                      title: const Text("Equipos en General"),
                                      value: _showEquipos,
                                      activeColor: Colors.blue.shade700,
                                      onChanged: (val) {
                                        setDialogState(() => _showEquipos = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                    const Divider(),
                                    CheckboxListTile(
                                      title: const Text("Tractos (Camiones)"),
                                      value: _showCamion,
                                      onChanged: (val) {
                                        setDialogState(() => _showCamion = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                    CheckboxListTile(
                                      title: const Text("Chasis A"),
                                      value: _showChasisA,
                                      onChanged: (val) {
                                        setDialogState(() => _showChasisA = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                    CheckboxListTile(
                                      title: const Text("Chasis B"),
                                      value: _showChasisB,
                                      onChanged: (val) {
                                        setDialogState(() => _showChasisB = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                    CheckboxListTile(
                                      title: const Text("Trazar Ruta de Viaje"),
                                      value: _showRoute,
                                      onChanged: (val) {
                                        setDialogState(() => _showRoute = val ?? true);
                                        setState(() {});
                                      },
                                    ),
                                  ],
                                );
                              }
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Aceptar"),
                              )
                            ],
                          ),
                        );
                      },
                child: const Icon(Icons.tune),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: "mapSearchUnitBtn",
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade700,
                onPressed: () {
                  _showUnitSelectionDialog();
                },
                child: const Icon(Icons.search),
              ),
            ],
          ),
        ),

        if (_selectedGpsItem != null)
          Positioned(
            top: 16,
            left: 16,
            right: 76,
            child: Card(
              color: Colors.white.withOpacity(0.95),
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            "${_selectedGpsItem!["tipo_item"] == 'contenedor' ? 'Contenedor' : _selectedGpsItem!["tipo_item"] == 'convoy' ? 'Convoy' : 'Equipo'}: ${_getItemName(_selectedGpsItem!)}",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () {
                            setState(() {
                              _selectedGpsItem = null;
                              _routePoints = [];
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (_selectedGpsItem!["id_contenedor"] != null || _selectedGpsItem!["contenedor_id"] != null || (_selectedGpsItem!["id"] != null && _selectedGpsItem!["tipo_item"] == 'contenedor')) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  final dynamic cId = _selectedGpsItem!["id_contenedor"] ?? _selectedGpsItem!["contenedor_id"] ?? _selectedGpsItem!["id"];
                                  final Map<String, dynamic> rowCompat = {
                                    "contenedor_id": cId,
                                    "estatus": _selectedGpsItem!["estatus"] ?? "Aprobada"
                                  };
                                  _showTripDetailsModal(rowCompat);
                                },
                                icon: const Icon(Icons.checklist, size: 14),
                                label: const Text("Checklist & Fin", style: TextStyle(fontSize: 10)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.blueGrey.shade800),
                                  foregroundColor: Colors.blueGrey.shade800,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 36,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _showWebStyleInfoViajeModal(_selectedGpsItem!);
                                },
                                icon: const Icon(Icons.info, size: 14),
                                label: const Text("Ficha de Viaje", style: TextStyle(fontSize: 10)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: SizedBox(
            height: 96,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: visibleCards.length,
              itemBuilder: (context, index) {
                final item = visibleCards[index];
                final double? lat = double.tryParse(item["lat"]?.toString() ?? item["latitud"]?.toString() ?? "");
                final double? lng = double.tryParse(item["lng"]?.toString() ?? item["longitud"]?.toString() ?? "");
                final bool hasCoords = lat != null && lng != null && lat != 0 && lng != 0;

                final isStopped = (item["velocidad"]?.toString() == "0" || 
                                   item["speed"]?.toString() == "0" || 
                                   (item["estatus"]?.toString().toLowerCase().contains("detenido") ?? false));

                // Colores y textos idénticos a los del panel web
                String statusText = "En Movimiento";
                Color statusColor = Colors.green.shade700;
                
                if (!hasCoords) {
                  statusText = "Sin Señal";
                  statusColor = Colors.grey.shade600;
                } else if (isStopped) {
                  statusText = "Detenido";
                  statusColor = Colors.red.shade700;
                }

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedGpsItem = item;
                    });
                    if (hasCoords) {
                      _googleMapController?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(gmaps.LatLng(lat, lng), 15));
                      _mapController.move(LatLng(lat, lng), 15);
                      
                      _fetchDestinationAndRoute(item, LatLng(lat, lng));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Este equipo no cuenta con coordenadas GPS válidas.")),
                      );
                    }
                  },
                  child: Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(right: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Container(
                      width: 155,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _getItemName(item),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            (item["tipo_item"] == "contenedor" ? (item["cliente"] ?? "Contenedor") : (item["marca"] ?? item["tipo"] ?? "Vehículo")),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10, 
                                    color: statusColor, 
                                    fontWeight: FontWeight.bold
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (hasCoords) ...[
                            const SizedBox(height: 2),
                            Text(
                              "${item["speed"] ?? item["velocidad"] ?? '0'} km/h",
                              style: const TextStyle(fontSize: 9, color: Colors.grey),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadTransportLines() async {
    setState(() {
      _loadingLines = true;
    });
    try {
      final url = _getEndpointUrl();
      final response = await ApiService.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map && data["data"] is Map) {
          final mapData = data["data"];
          final Map<String, String> uniqueLines = {};
          final Map<String, String> uniqueClients = {};
          
          if (mapData["datos"] is List) {
            for (var item in mapData["datos"]) {
              final String? providerId = item["proveedor_id"]?.toString();
              final String? providerName = item["proveedor_nombre"]?.toString() ?? item["transportista_nombre"]?.toString();
              if (providerId != null && providerId != "0" && providerName != null && providerName.trim().isNotEmpty) {
                uniqueLines[providerId] = providerName.trim();
              }

              final String? clientId = item["id_cliente"]?.toString();
              final String? clientName = item["cliente"]?.toString() ?? item["cliente_nombre"]?.toString();
              if (clientId != null && clientId != "0" && clientName != null && clientName.trim().isNotEmpty) {
                uniqueClients[clientId] = clientName.trim();
              }
            }
          }
          
          if (mapData["equipos"] is List) {
            for (var item in mapData["equipos"]) {
              final String? providerId = item["proveedor_id"]?.toString() ?? item["proveedor_company_id"]?.toString();
              final String? providerName = item["proveedor_nombre"]?.toString() ?? item["transportista_nombre"]?.toString();
              if (providerId != null && providerId != "0" && providerName != null && providerName.trim().isNotEmpty) {
                uniqueLines[providerId] = providerName.trim();
              }

              final String? clientId = item["id_cliente"]?.toString();
              final String? clientName = item["cliente"]?.toString() ?? item["cliente_nombre"]?.toString();
              if (clientId != null && clientId != "0" && clientName != null && clientName.trim().isNotEmpty) {
                uniqueClients[clientId] = clientName.trim();
              }
            }
          }

          setState(() {
            _lineas = uniqueLines.entries.map((e) => {"id": e.key, "nombre": e.value}).toList();
            _clientes = uniqueClients.entries.map((e) => {"id": e.key, "nombre": e.value}).toList();
          });
        }
      }
    } catch (e) {
      // Ignore
    } finally {
      setState(() {
        _loadingLines = false;
      });
    }
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (widget.module == 'monitoreo' && _filtersApplied && !isLoading) {
        fetchData(isSilent: true);
      }
    });
  }

  Future<void> _fetchDestinationAndRoute(Map<String, dynamic> item, LatLng start) async {
    final dynamic containerId = item["id_contenedor"] ?? item["contenedor_id"] ?? item["id"];
    if (containerId == null) return;
    try {
      final response = await ApiService.post(ApiEndpoints.infoViaje, {"id": containerId});
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body["cotizacion"] != null) {
          final double? destLat = double.tryParse(body["cotizacion"]["latitud"]?.toString() ?? "");
          final double? destLng = double.tryParse(body["cotizacion"]["longitud"]?.toString() ?? "");
          if (destLat != null && destLng != null && destLat != 0 && destLng != 0) {
            _fetchRoute(start, LatLng(destLat, destLng));
            return;
          }
        }
      }
    } catch (e) {
      // ignore
    }
    setState(() {
      _routePoints = [];
    });
  }

  Widget _buildMonitoreoFilterForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.location_searching, size: 64, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                "Configurar Monitoreo GPS",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                "Selecciona los criterios obligatorios y opcionales para iniciar el rastreo de unidades",
                style: TextStyle(color: Colors.grey, fontSize: 11),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // 1. Cliente (Opcional)
              _loadingLines
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 10),
                            Text("Cargando opciones...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      value: _selectedClienteId.isEmpty ? null : _selectedClienteId,
                      decoration: const InputDecoration(
                        labelText: "Cliente (Opcional)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      items: [
                        const DropdownMenuItem(value: "", child: Text("Todos")),
                        ..._clientes.map((cliente) => DropdownMenuItem(
                              value: cliente["id"],
                              child: Text(cliente["nombre"] ?? "Cliente"),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedClienteId = val ?? "";
                        });
                      },
                    ),
              const SizedBox(height: 16),

              // 2. Linea Transporte (Opcional)
              _loadingLines
                  ? const SizedBox.shrink()
                  : DropdownButtonFormField<String>(
                      value: _selectedLineaId.isEmpty ? null : _selectedLineaId,
                      decoration: const InputDecoration(
                        labelText: "Línea de Transporte (Opcional)",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_shipping),
                      ),
                      items: [
                        const DropdownMenuItem(value: "", child: Text("Todas")),
                        ..._lineas.map((linea) => DropdownMenuItem(
                              value: linea["id"],
                              child: Text(linea["nombre"] ?? "Línea"),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() {
                          _selectedLineaId = val ?? "";
                        });
                      },
                    ),
              if (!_loadingLines) const SizedBox(height: 16),

              // 3. Fecha Salida (Opcional)
              InkWell(
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _selectedFechaSalida ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    setState(() {
                      _selectedFechaSalida = date;
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Colors.blueGrey, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedFechaSalida == null
                              ? "Fecha de Salida (Opcional)"
                              : "Fecha: ${_selectedFechaSalida!.day}/${_selectedFechaSalida!.month}/${_selectedFechaSalida!.year}",
                          style: TextStyle(
                            fontSize: 14,
                            color: _selectedFechaSalida == null ? Colors.grey.shade600 : Colors.black,
                          ),
                        ),
                      ),
                      if (_selectedFechaSalida != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedFechaSalida = null;
                            });
                          },
                          child: const Icon(Icons.clear, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 4. Tipo (Obligatorio)
              DropdownButtonFormField<String>(
                value: _selectedTipo,
                decoration: const InputDecoration(
                  labelText: "Tipo de Rastreo (Obligatorio)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: const [
                  DropdownMenuItem(value: "Contenedor", child: Text("Contenedores")),
                  DropdownMenuItem(value: "Equipo", child: Text("Equipos")),
                  DropdownMenuItem(value: "Convoy", child: Text("Convoys")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedTipo = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 28),

              // Botón Aplicar
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _filtersApplied = true;
                  });
                  fetchData();
                  _startRefreshTimer();
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text("INICIAR RASTREO", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headers = _getHeaders();
    final keys = _getKeys();

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            if (widget.module == 'monitoreo') {
              setState(() {
                _filtersApplied = false;
                _selectedGpsItem = null;
                _routePoints = [];
                items = [];
                filteredItems = [];
              });
            }
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title),
              if (widget.module == 'monitoreo' && _filtersApplied) ...[
                const SizedBox(width: 6),
                const Icon(Icons.edit, size: 16, color: Colors.white70),
              ]
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchData,
          ),
        ],
      ),
      body: Column(
        children: [
          if (isMockData)
            Container(
              color: Colors.amber.shade100,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Servidor no disponible. Mostrando datos locales (modo offline).",
                          style: TextStyle(color: Colors.brown, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        if (debugErrorMessage.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            debugErrorMessage,
                            style: TextStyle(color: Colors.brown.shade800, fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (widget.module != 'reportes' && widget.module != 'monitoreo')
            Padding(
              padding: const EdgeInsets.all(12),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: "Buscar...",
                      border: InputBorder.none,
                      icon: Icon(Icons.search),
                    ),
                    onChanged: filterSearchResults,
                  ),
                ),
              ),
            ),
          if (widget.module == 'planeacion')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              width: double.infinity,
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _planeacionFechaInicio ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            _planeacionFechaInicio = picked;
                          });
                          fetchData();
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.date_range, color: Colors.blue.shade800, size: 16),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Desde", style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                              Text(
                                _planeacionFechaInicio == null
                                    ? "Seleccionar"
                                    : "${_planeacionFechaInicio!.year}-${_planeacionFechaInicio!.month.toString().padLeft(2, '0')}-${_planeacionFechaInicio!.day.toString().padLeft(2, '0')}",
                                style: TextStyle(color: Colors.blue.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _planeacionFechaFin ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            _planeacionFechaFin = picked;
                          });
                          fetchData();
                        }
                      },
                      child: Row(
                        children: [
                          Icon(Icons.date_range, color: Colors.blue.shade800, size: 16),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Hasta", style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
                              Text(
                                _planeacionFechaFin == null
                                    ? "Seleccionar"
                                    : "${_planeacionFechaFin!.year}-${_planeacionFechaFin!.month.toString().padLeft(2, '0')}-${_planeacionFechaFin!.day.toString().padLeft(2, '0')}",
                                style: TextStyle(color: Colors.blue.shade900, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : widget.module == 'reportes'
                    ? _buildReportesDashboard()
                    : widget.module == 'monitoreo'
                        ? (!_filtersApplied 
                            ? _buildMonitoreoFilterForm()
                            : _buildGpsMonitoreoView())
                        : filteredItems.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text("No se encontraron registros",
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: fetchData,
                            child: widget.module == 'operaciones'
                                ? _buildGroupedOperacionesList(filteredItems)
                                : widget.module == 'planeacion'
                                    ? _buildPlaneacionList(filteredItems)
                                    : ListView.builder(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: filteredItems.length,
                                        itemBuilder: (context, index) {
                                          final Map<String, dynamic> row = Map<String, dynamic>.from(filteredItems[index]);
                                          return Card(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            elevation: 2,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Text(
                                                    row["id"]?.toString() ?? "",
                                                    style: const TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                      color: Colors.blueGrey,
                                                    ),
                                                  ),
                                                  if (row["estatus"] != null)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: _getStatusColor(row["estatus"]).withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(20),
                                                        border: Border.all(
                                                          color: _getStatusColor(row["estatus"]),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        row["estatus"].toString(),
                                                        style: TextStyle(
                                                          color: _getStatusColor(row["estatus"]),
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const Divider(height: 20),
                                              ...List.generate(headers.length, (colIdx) {
                                                final headerName = headers[colIdx];
                                                final keyName = keys[colIdx];
                                                if (keyName == "id" || keyName == "estatus") return const SizedBox.shrink();
                                                return Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  child: Row(
                                                    children: [
                                                      Text(
                                                        "$headerName: ",
                                                        style: const TextStyle(
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Text(
                                                          row[keyName]?.toString() ?? "N/A",
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }),
                                              const SizedBox(height: 10),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                children: _buildRowActions(row),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportesDashboard() {
    final stats = reportStats;
    if (stats.isEmpty) {
      return const Center(child: Text("No hay estadísticas disponibles."));
    }

    final totalCotizaciones = stats['total_cotizaciones']?.toString() ?? '0';
    final totalViajesActivos = stats['total_viajes_activos']?.toString() ?? '0';
    final totalContenedores = stats['total_contenedores']?.toString() ?? '0';
    final cotizacionesAprobadas = stats['cotizaciones_aprobadas']?.toString() ?? '0';
    final cotizacionesPendientes = stats['cotizaciones_pendientes']?.toString() ?? '0';

    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _buildStatCard("Total Cotizaciones", totalCotizaciones, Icons.receipt_long, Colors.blue),
        _buildStatCard("Viajes Activos", totalViajesActivos, Icons.local_shipping, Colors.green),
        _buildStatCard("Contenedores Doc.", totalContenedores, Icons.inventory_2, Colors.orange),
        _buildStatCard("Cot. Aprobadas", cotizacionesAprobadas, Icons.check_circle, Colors.teal),
        _buildStatCard("Cot. Pendientes", cotizacionesPendientes, Icons.hourglass_empty, Colors.amber),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaneacionList(List<dynamic> list) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = Map<String, dynamic>.from(list[index]);
        final String numContenedor = item["contenedor"]?.toString() ?? "S/N";
        final String fechaInicio = item["fecha_inicio"]?.toString() ?? "N/A";
        final String fechaFin = item["fecha_fin"]?.toString() ?? "N/A";
        final String operador = item["operador"]?.toString() ?? "N/A";
        final String proveedor = item["proveedor"]?.toString() ?? "N/A";
        final String transportista = item["transportista"]?.toString() ?? proveedor;
        final String origen = item["origen"]?.toString() ?? "N/A";
        final String destino = item["destino"]?.toString() ?? "N/A";
        final bool isCima = item["cima"] == 1 || item["cima"] == "1" || item["cima"] == true;
        final int? cotId = int.tryParse(item["cotizacion_id"]?.toString() ?? "");
        
        final List<dynamic> docValues = [
          item["doc_ccp"],
          item["boleta_liberacion"],
          item["doda"],
          item["carta_porte"],
          item["carta_porte_xml"],
          item["boleta_vacio"],
          if (!isCima) item["doc_eir"],
          item["evidencia_descarga"],
          item["comprobante_pago_pdf"],
          item["comprobante_pago_xml"],
        ];
        final int docsCount = docValues.where((v) => v != null && v != false && v != 0 && v != "0" && v.toString().trim().isNotEmpty).length;
        final int totalDocs = isCima ? 9 : 10;

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "Contenedor: $numContenedor",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.blueGrey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple, width: 1),
                      ),
                      child: const Text(
                        "Planeada",
                        style: TextStyle(
                          color: Colors.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                _buildPlaneacionInfoRow(Icons.route, "Ruta", "$origen ➔ $destino"),
                const SizedBox(height: 6),
                _buildPlaneacionInfoRow(Icons.calendar_month, "Fechas", "Inicio: $fechaInicio\nFin: $fechaFin"),
                const SizedBox(height: 6),
                _buildPlaneacionInfoRow(Icons.person, "Operador", operador),
                const SizedBox(height: 6),
                _buildPlaneacionInfoRow(Icons.business, "Proveedor", proveedor),
                const SizedBox(height: 6),
                _buildPlaneacionInfoRow(Icons.local_shipping, "Transportista", transportista),

                const Divider(height: 20),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4, bottom: 8),
                    title: Row(
                      children: [
                        const Icon(Icons.folder_open, size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        const Text(
                          "Documentación del Viaje",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: docsCount > 0 ? Colors.green.shade50 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: docsCount > 0 ? Colors.green.shade400 : Colors.grey.shade400),
                          ),
                          child: Text(
                            "$docsCount/$totalDocs",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: docsCount > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    children: [
                      _docCheckRow("Formato CCP", item["doc_ccp"], filename: item["doc_ccp"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Boleta de liberación", item["boleta_liberacion"], filename: item["boleta_liberacion"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Doda", item["doda"], filename: item["doda"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Carta Porte PDF", item["carta_porte"], filename: item["carta_porte"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Carta Porte XML", item["carta_porte_xml"], filename: item["carta_porte_xml"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Prealta - Boleta vacío", item["boleta_vacio"], filename: item["boleta_vacio"]?.toString(), cotizacionId: cotId),
                      if (!isCima)
                        _docCheckRow("EIR - Comprobante vacío", item["doc_eir"], filename: item["doc_eir"]?.toString(), cotizacionId: cotId)
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                              const SizedBox(width: 6),
                              Text(
                                "CIMA Activo: EIR omitido",
                                style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      _docCheckRow("Evidencia Descarga", item["evidencia_descarga"], filename: item["evidencia_descarga"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Complemento de pago PDF", item["comprobante_pago_pdf"], filename: item["comprobante_pago_pdf"]?.toString(), cotizacionId: cotId),
                      _docCheckRow("Complemento de pago XML", item["comprobante_pago_xml"], filename: item["comprobante_pago_xml"]?.toString(), cotizacionId: cotId),
                    ],
                  ),
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_canFinalize) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          final int? cId = int.tryParse(item["contenedor_id"]?.toString() ?? "");
                          if (cId != null) {
                             _finalizarViaje(cId, item: item);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("ID de contenedor no disponible")),
                            );
                          }
                        },
                        icon: const Icon(Icons.check, size: 14),
                        label: const Text("Finalizar"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (_canAnular) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          final int? cId = int.tryParse(item["contenedor_id"]?.toString() ?? "");
                          if (cId != null) {
                            _anularPlaneacion(cId);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("ID de contenedor no disponible")),
                            );
                          }
                        },
                        icon: const Icon(Icons.undo, size: 14),
                        label: const Text("Deshacer"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    ElevatedButton.icon(
                      onPressed: () => _showWebStyleInfoViajeModal(item),
                      icon: const Icon(Icons.info_outline, size: 14),
                      label: const Text("Ver más info"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
    );
  }

  Widget _buildPlaneacionInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          "$label: ",
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
