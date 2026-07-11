import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '/config/api_config.dart';

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
  final MapController _mapController = MapController();
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

  @override
  void initState() {
    super.initState();
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

  Future<void> fetchData() async {
    if (mounted) {
      setState(() {
        isLoading = true;
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
                
                final requiredDocs = [
                  "boleta_liberacion",
                  "boleta_vacio",
                  "carta_porte",
                  "carta_porte_xml",
                  "doc_ccp",
                  if (!isCima) "doc_eir",
                  "doda"
                ];

                bool allDocsCompleted = true;
                for (var doc in requiredDocs) {
                  final val = documentsStatus[doc];
                  if (val == null || val == false || val == 0 || val == "0" || val == "") {
                    allDocsCompleted = false;
                  }
                }

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
                        _docCheckRow("Boleta de Liberación", documentsStatus["boleta_liberacion"], filename: documentos["boleta_liberacion"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Boleta de Vacío", documentsStatus["boleta_vacio"], filename: documentos["boleta_vacio"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Carta Porte PDF", documentsStatus["carta_porte"], filename: documentos["carta_porte"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Carta Porte XML", documentsStatus["carta_porte_xml"], filename: documentos["carta_porte_xml"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Carta Porte CCP", documentsStatus["doc_ccp"], filename: documentos["doc_ccp"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        if (!isCima) _docCheckRow("Documento EIR", documentsStatus["doc_eir"], filename: documentos["doc_eir"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        _docCheckRow("Documento DODA", documentsStatus["doda"], filename: documentos["doda"]?.toString(), cotizacionId: int.tryParse(data["cotizacion"]?["id"]?.toString() ?? "")),
                        if (isCima)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.info, color: Colors.blue, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      "CIMA activo: EIR omitido del checklist obligatorio.",
                                      style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),

                        if (row["estatus"] != "Finalizado" && row["estatus"] != "Finalizada")
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: !allDocsCompleted ? null : () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text("¿Finalizar viaje?"),
                                    content: const Text("Confirmas que deseas finalizar esta operación logística."),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancelar")),
                                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Confirmar")),
                                    ],
                                  )
                                );

                                if (confirm == true) {
                                  final postResp = await ApiService.post(ApiEndpoints.finalizarViaje, {
                                    "idContenedor": row["contenedor_id"]?.toString() ?? ""
                                  });
                                  if (postResp.statusCode == 200) {
                                    final pData = jsonDecode(postResp.body);
                                    if (pData["success"] == true) {
                                      Navigator.pop(context); 
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(pData["mensaje"] ?? "Viaje finalizado")),
                                      );
                                      fetchData(); 
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(pData["mensaje"] ?? "Error")),
                                      );
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                disabledBackgroundColor: Colors.grey.shade300,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: Text(
                                allDocsCompleted ? "FINALIZAR VIAJE" : "COMPLETAR CHECKLIST PARA FINALIZAR",
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  "VIAJE FINALIZADO CORRECTAMENTE",
                                  style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
                                )
                              ],
                            ),
                          )
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
    if (tipoItem == "contenedor") {
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
        
        if (docum == null) {
          throw Exception("No data");
        }

        final String cliente = docum["cliente"]?.toString() ?? "S/N";
        final String origen = cotizacion?["origen"]?.toString() ?? "S/N";
        final String destino = cotizacion?["destino"]?.toString() ?? "S/N";
        final String fechaInicio = docum["fecha_inicio"]?.toString() ?? "S/N";
        final String fechaFin = docum["fecha_fin"]?.toString() ?? "S/N";
        final String contrato = docum["tipo_contrato"]?.toString() ?? "S/N";
        final bool esFull = cotizacion?["referencia_full"] != null;
        
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
                          const SizedBox(height: 4),
                          Text(cliente, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(esFull ? "FULL 🧱" : "Sencillo 🚛", style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        ],
                      ),
                    ),

                    _buildWebModalSection(
                      title: "Datos del viaje",
                      icon: Icons.route,
                      color: Colors.blue.shade700,
                      children: [
                        _webModalRow("Origen:", origen),
                        _webModalRow("Destino:", destino),
                        _webModalRow("Fecha Inicio:", fechaInicio),
                        _webModalRow("Fecha Fin:", fechaFin),
                      ],
                    ),

                    _buildWebModalSection(
                      title: "Contacto / Operador",
                      icon: Icons.person,
                      color: Colors.green.shade700,
                      children: [
                        _webModalRow("Contacto:", contacto),
                        _webModalRow("Operador:", operador),
                        _webModalRow("Teléfono:", telefono),
                      ],
                    ),

                    _buildWebModalSection(
                      title: "Transporte",
                      icon: Icons.local_shipping,
                      color: Colors.purple.shade700,
                      children: [
                        _webModalRow("Proveedor:", empresa),
                        _webModalRow("Transportista:", transportista),
                      ],
                    ),

                    _buildWebModalSection(
                      title: "Equipos / GPS",
                      icon: Icons.settings_remote,
                      color: Colors.orange.shade700,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: canLaunch
            ? () async {
                final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
                final fileUrl = "$cleanBaseUrl/cotizaciones/cotizacion$cotizacionId/$filename";
                final Uri uri = Uri.parse(fileUrl);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Abriendo documento..."),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }

                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("No se pudo abrir el documento: $e")),
                    );
                  }
                }
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(label),
                  if (canLaunch) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new, size: 14, color: Colors.blueAccent),
                  ],
                ],
              ),
              Icon(
                isCompleted ? Icons.check_circle : Icons.cancel,
                color: isCompleted ? Colors.green : Colors.grey.shade400,
              )
            ],
          ),
        ),
      ),
    );
  }

  List<Marker> _buildGpsMarkers() {
    final List<Marker> markers = [];
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
        Marker(
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
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: 10,
          ),
          children: [
            TileLayer(
              urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
              userAgentPackageName: 'com.sgtlogistics.app',
            ),
            if (_showRoute && _routePoints.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 4,
                    color: Colors.blue.shade700,
                  ),
                ],
              ),
            MarkerLayer(
              markers: _buildGpsMarkers(),
            ),
          ],
        ),

        // Botón flotante superior derecho para filtros y vista
        Positioned(
          top: 16,
          right: 16,
          child: FloatingActionButton.small(
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
                    const Divider(height: 8),
                    _detailRow("Marca/Modelo", _selectedGpsItem!["marca"] ?? "N/A"),
                    _detailRow("Placas", _selectedGpsItem!["placas"] ?? "N/A"),
                    _detailRow("Velocidad", "${_selectedGpsItem!["speed"] ?? _selectedGpsItem!["velocidad"] ?? '0'} km/h"),
                    _detailRow("Estado", _selectedGpsItem!["estatus"] ?? "EN MOVIMIENTO"),
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
              itemCount: filteredItems.length,
              itemBuilder: (context, index) {
                final item = filteredItems[index];
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
        fetchData();
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
            const SizedBox(height: 4),
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
}
