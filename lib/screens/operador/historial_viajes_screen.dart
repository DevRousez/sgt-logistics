import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';

class HistorialViajesScreen extends StatefulWidget {
  const HistorialViajesScreen({super.key});

  @override
  State<HistorialViajesScreen> createState() => _HistorialViajesScreenState();
}

class _HistorialViajesScreenState extends State<HistorialViajesScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, List<dynamic>> _groupedHistory = {};
  int _totalViajes = 0;

  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  @override
  void initState() {
    super.initState();
    _fetchHistorial();
  }

  Future<void> _fetchHistorial() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final startStr = DateFormat('yyyy-MM-dd').format(_startDate);
      final endStr = DateFormat('yyyy-MM-dd').format(_endDate);

      final response = await ApiService.get(
        "${ApiEndpoints.historialOperador}?fecha_inicio=$startStr&fecha_fin=$endStr",
      );

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final List<dynamic> list = resData["data"];
          final Map<String, List<dynamic>> tempGrouped = {};
          
          for (var item in list) {
            final String numContenedor = item["num_contenedor"]?.toString() ?? "Sin Contenedor";
            tempGrouped.putIfAbsent(numContenedor, () => []).add(item);
          }

          setState(() {
            _groupedHistory = tempGrouped;
            _totalViajes = list.length;
          });
        } else {
          setState(() {
            _errorMessage = resData["message"] ?? "Error al obtener el historial.";
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

  String _buildImageUrl(String path, int idAsignacion, String type) {
    if (path.isEmpty) return "";
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    if (path.contains('uploads/')) {
      return "$cleanBaseUrl/$path";
    }
    if (type == 'diesel') {
      return "$cleanBaseUrl/uploads/diesel/$idAsignacion/$path";
    } else if (type == 'carga') {
      return "$cleanBaseUrl/uploads/carga_contenedor/$idAsignacion/$path";
    } else {
      return "$cleanBaseUrl/uploads/entrega_contenedor/$idAsignacion/$path";
    }
  }

  Future<void> _openMap(double lat, double lng) async {
    final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    try {
      if (await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication)) {
      } else {
        throw 'Could not open map';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No se pudo abrir el mapa: $e")),
        );
      }
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return "N/A";
    try {
      final DateTime dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy hh:mm a').format(dt);
    } catch (e) {
      return dateStr;
    }
  }

  List<String> _parsePhotos(dynamic photosRaw) {
    if (photosRaw == null) return [];
    if (photosRaw is List) {
      return List<String>.from(photosRaw.map((e) => e.toString()));
    }
    if (photosRaw is String && photosRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(photosRaw);
        if (decoded is List) {
          return List<String>.from(decoded.map((e) => e.toString()));
        }
      } catch (e) {
        return [photosRaw];
      }
    }
    return [];
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.network(
                url,
                errorBuilder: (c, o, s) => Container(
                  height: 300,
                  color: Colors.grey.shade100,
                  child: const Center(child: Icon(Icons.broken_image, size: 50)),
                ),
              ),
            ),
            IconButton(
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildEvidencesGrid(List<String> photos, int idAsignacion, String type) {
    if (photos.isEmpty) return const Text("Sin evidencias fotográficas", style: TextStyle(color: Colors.grey));
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final String imgUrl = _buildImageUrl(photos[index], idAsignacion, type);
        return GestureDetector(
          onTap: () => _showImageDialog(imgUrl),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              imgUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, o, s) => Container(
                color: Colors.grey.shade200,
                child: const Icon(Icons.broken_image, size: 20),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Viajes'),
      ),
      body: Column(
        children: [
          // Filtros de fecha y contador de viajes
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text("Desde: ${DateFormat('dd/MM/yyyy').format(_startDate)}"),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _startDate = picked);
                            _fetchHistorial();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_month, size: 16),
                        label: Text("Hasta: ${DateFormat('dd/MM/yyyy').format(_endDate)}"),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => _endDate = picked);
                            _fetchHistorial();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.blue.shade50,
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.blue.shade100),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Total de viajes en periodo:",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          "$_totalViajes",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.blue.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 16), textAlign: TextAlign.center),
                              const SizedBox(height: 20),
                              ElevatedButton(onPressed: _fetchHistorial, child: const Text("Reintentar")),
                            ],
                          ),
                        ),
                      )
                    : _groupedHistory.isEmpty
                        ? const Center(
                            child: Text("No se encontraron registros en tu historial.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                          )
                        : ListView.builder(
                            itemCount: _groupedHistory.length,
                            itemBuilder: (context, index) {
                              final String numContenedor = _groupedHistory.keys.elementAt(index);
                              final List<dynamic> trips = _groupedHistory[numContenedor]!;

                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ExpansionTile(
                                  leading: Icon(Icons.inventory, color: Colors.blue.shade900),
                                  title: Text(
                                    numContenedor,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  // Removido subtítulo redundante "Viajes registrados"
                                  children: trips.map((trip) {
                                    final int idAsig = int.tryParse(trip["id_asignacion"]?.toString() ?? "") ?? 0;
                                    final String empresa = trip["nombre_empresa"] ?? "Empresa N/A";
                                    final String ruta = "${trip["origen"] ?? 'N/A'} ➔ ${trip["destino"] ?? 'N/A'}";
                                    
                                    final double? latDiesel = double.tryParse(trip["latitud"]?.toString() ?? "");
                                    final double? lngDiesel = double.tryParse(trip["longitud"]?.toString() ?? "");
                                    final double? latCarga = double.tryParse(trip["latitud_carga"]?.toString() ?? "");
                                    final double? lngCarga = double.tryParse(trip["longitud_carga"]?.toString() ?? "");
                                    final double? latFin = double.tryParse(trip["latitud_fin"]?.toString() ?? "");
                                    final double? lngFin = double.tryParse(trip["longitud_fin"]?.toString() ?? "");

                                    final List<dynamic> gastos = trip["gastos"] != null ? List.from(trip["gastos"]) : [];

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Divider(),
                                          Text("Empresa: $empresa", style: const TextStyle(fontWeight: FontWeight.w600)),
                                          Text("Ruta: $ruta", style: const TextStyle(color: Colors.black87)),
                                          Text("Fecha de inicio: ${_formatDateTime(trip["fecha_inicio"])}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          Text("Fecha de fin: ${_formatDateTime(trip["fecha_fin"])}", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                          
                                          const SizedBox(height: 15),
                                          const Text("1. Registro de Diésel", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          const SizedBox(height: 4),
                                          if (trip["fecha_carga_diesel"] != null) ...[
                                            Text("Litros: ${trip["litros"] ?? '0'} L | Costo: \$${trip["costo"] ?? '0'}"),
                                            Text("Odómetro: ${trip["odometro"] ?? '0'} km"),
                                            Text("Fecha Envío: ${_formatDateTime(trip["fecha_carga_diesel"])}"),
                                            if (latDiesel != null && lngDiesel != null)
                                              TextButton.icon(
                                                icon: const Icon(Icons.map, size: 16),
                                                label: Text("GPS: $latDiesel, $lngDiesel"),
                                                onPressed: () => _openMap(latDiesel, lngDiesel),
                                              ),
                                            const SizedBox(height: 6),
                                            if (trip["comprobante"] != null && trip["comprobante"].toString().isNotEmpty)
                                              _buildEvidencesGrid([trip["comprobante"].toString()], idAsig, 'diesel'),
                                          ] else
                                            const Text("No registrado", style: TextStyle(color: Colors.grey, fontSize: 13)),

                                          const SizedBox(height: 15),
                                          const Text("2. Registro de Urea", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          const SizedBox(height: 4),
                                          if (trip["fecha_carga_urea"] != null) ...[
                                            Text("Litros: ${trip["litros_urea"] ?? '0'} L | Costo: \$${trip["costo_urea"] ?? '0'}"),
                                            Text("Fecha Envío: ${_formatDateTime(trip["fecha_carga_urea"])}"),
                                            const SizedBox(height: 6),
                                            if (trip["comprobante_urea"] != null && trip["comprobante_urea"].toString().isNotEmpty)
                                              _buildEvidencesGrid([trip["comprobante_urea"].toString()], idAsig, 'diesel'),
                                          ] else
                                            const Text("No registrado", style: TextStyle(color: Colors.grey, fontSize: 13)),

                                          const SizedBox(height: 15),
                                          const Text("3. Evidencia Carga Contenedor", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          const SizedBox(height: 4),
                                          if (trip["viaje_iniciado"] != null) ...[
                                            Text("Fecha Envío: ${_formatDateTime(trip["viaje_iniciado"])}"),
                                            if (latCarga != null && lngCarga != null)
                                              TextButton.icon(
                                                icon: const Icon(Icons.map, size: 16),
                                                label: Text("GPS: $latCarga, $lngCarga"),
                                                onPressed: () => _openMap(latCarga, lngCarga),
                                              ),
                                            const SizedBox(height: 6),
                                            _buildEvidencesGrid(_parsePhotos(trip["fotos_carga"]), idAsig, 'carga'),
                                          ] else
                                            const Text("No registrado", style: TextStyle(color: Colors.grey, fontSize: 13)),

                                          const SizedBox(height: 15),
                                          const Text("4. Conclusión de Viaje", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          const SizedBox(height: 4),
                                          if (trip["viaje_finalizado"] != null) ...[
                                            Text("Fecha Envío: ${_formatDateTime(trip["viaje_finalizado"])}"),
                                            if (latFin != null && lngFin != null)
                                              TextButton.icon(
                                                icon: const Icon(Icons.map, size: 16),
                                                label: Text("GPS: $latFin, $lngFin"),
                                                onPressed: () => _openMap(latFin, lngFin),
                                              ),
                                            const SizedBox(height: 6),
                                            _buildEvidencesGrid(_parsePhotos(trip["fotos_fin"]), idAsig, 'entrega'),
                                          ] else
                                            const Text("No registrado", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                          
                                          // 5. Gastos Registrados en el Viaje
                                          const SizedBox(height: 15),
                                          const Text("5. Gastos Registrados en el Viaje", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                                          const SizedBox(height: 4),
                                          if (gastos.isNotEmpty) ...[
                                            ListView.builder(
                                              shrinkWrap: true,
                                              physics: const NeverScrollableScrollPhysics(),
                                              itemCount: gastos.length,
                                              itemBuilder: (context, gIndex) {
                                                final g = gastos[gIndex];
                                                final String comp = g["comprobante"]?.toString() ?? "";
                                                return Card(
                                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                                  elevation: 1,
                                                  child: ListTile(
                                                    dense: true,
                                                    title: Text(g["concepto"] ?? "Gasto"),
                                                    subtitle: Text("Monto: \$${g["monto"] ?? '0'}"),
                                                    trailing: comp.isNotEmpty
                                                        ? IconButton(
                                                            icon: const Icon(Icons.image, color: Colors.blue),
                                                            onPressed: () => _showImageDialog("$cleanBaseUrl/$comp"),
                                                          )
                                                        : null,
                                                  ),
                                                );
                                              },
                                            ),
                                          ] else
                                            const Text(
                                              "No se registraron gastos en el viaje",
                                              style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                                            ),
                                          const SizedBox(height: 10),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
