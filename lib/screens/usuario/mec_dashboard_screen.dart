import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/utils/file_downloader.dart';
import '../home_screen.dart';
import 'usuario_module_screen.dart';

class MecDashboardScreen extends StatefulWidget {
  const MecDashboardScreen({super.key});

  @override
  State<MecDashboardScreen> createState() => _MecDashboardScreenState();
}

class _MecDashboardScreenState extends State<MecDashboardScreen> {
  bool _isLoading = true;
  String _userName = "Usuario";
  String _clienteNombre = "";
  List<Map<String, dynamic>> _operaciones = [];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _fetchOperaciones();
  }

  Future<void> _loadUserInfo() async {
    final data = await ApiService.getUserData();
    if (data != null) {
      final user = data["user"] ?? data;
      setState(() {
        _userName = user["name"] ?? "Usuario";
        _clienteNombre = user["cliente_nombre"] ?? "";
      });
    }
  }

  Future<void> _fetchOperaciones() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get(ApiEndpoints.clienteOperaciones);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final data = resData["data"];
          final opsList = data["operaciones"] as List? ?? [];

          setState(() {
            _operaciones = opsList.map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      } else {
        _showSnackBar("Error al cargar operaciones: ${response.statusCode}");
      }
    } catch (e) {
      _showSnackBar("Error de conexión: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isOpActiveForGps(Map<String, dynamic> op) {
    final status = (op["estatus"] ?? "").toString().toLowerCase();
    final estPlane = op["est_plane"];

    final isPlaneada = status.contains("planead") ||
        (status.contains("aprob") && estPlane == 1) ||
        status.contains("tránsito") ||
        status.contains("transito") ||
        status.contains("ruta") ||
        status.contains("proceso");

    if (!isPlaneada) return false;

    final String? fInicioStr = op["fecha_inicio"]?.toString();
    final String? fFinStr = op["fecha_fin"]?.toString();

    if (fInicioStr != null && fInicioStr.isNotEmpty && fFinStr != null && fFinStr.isNotEmpty) {
      try {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final fInicio = DateTime.parse(fInicioStr);
        final fFin = DateTime.parse(fFinStr);
        final startDate = DateTime(fInicio.year, fInicio.month, fInicio.day);
        final endDate = DateTime(fFin.year, fFin.month, fFin.day);

        return (today.isAfter(startDate) || today.isAtSameMomentAs(startDate)) &&
            (today.isBefore(endDate) || today.isAtSameMomentAs(endDate));
      } catch (e) {
        return true;
      }
    }

    return true;
  }

  int get _activeCount => _operaciones.where(_isOpActiveForGps).length;

  // Colores estandarizados de estatus
  Color _getStatusColor(dynamic status) {
    if (status == null) return Colors.grey;
    final s = status.toString().toLowerCase();
    if (s.contains('aprob') || s.contains('complet') || s.contains('list') || s.contains('dispon') || s.contains('activ')) {
      return Colors.blue.shade600;
    }
    if (s.contains('plan')) {
      return Colors.orange.shade700;
    }
    if (s.contains('pendient') || s.contains('solicit') || s.contains('espera')) {
      return Colors.amber.shade700;
    }
    if (s.contains('transito') || s.contains('tránsito') || s.contains('ruta') || s.contains('proceso')) {
      return Colors.teal.shade700;
    }
    if (s.contains('finaliz') || s.contains('termin')) {
      return Colors.green.shade600;
    }
    if (s.contains('rechaz') || s.contains('reten') || s.contains('deten') || s.contains('cancel')) {
      return Colors.red.shade600;
    }
    return Colors.blue.shade600;
  }

  // Modal para Info de Viaje (FCCP dinámico)
  Future<void> _showInfoViajeModal(int cotizacionId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiService.post(
        ApiEndpoints.clienteInfoViaje,
        {"id_cotizacion": cotizacionId},
      );

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final data = resData["data"];
          _renderInfoViajeDialog(data);
          return;
        }
      }
      _showSnackBar("No se pudo obtener la información del viaje.");
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showSnackBar("Error al obtener información: $e");
    }
  }

  void _renderInfoViajeDialog(Map<String, dynamic> data) {
    final gen = data["informacion_general"] as Map<String, dynamic>? ?? {};
    final eqOp = data["informacion_equipo_operador"] as Map<String, dynamic>?;
    final fccp = data["seccion_fccp"] as Map<String, dynamic>?;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF0F2027)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Info de Viaje - ${gen["num_contenedor"] ?? "Contenedor"}",
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Información General", Icons.local_shipping),
                _buildInfoRow("Contenedor:", gen["num_contenedor"]),
                _buildStatusBadgeRow("Estatus:", gen["estatus"]),
                _buildInfoRow("Origen:", gen["origen"]),
                _buildInfoRow("Destino:", gen["destino"]),
                _buildInfoRow("Tamaño:", gen["tamano"]),
                _buildInfoRow("Peso:", gen["peso"]),
                _buildInfoRow("Tipo de Viaje:", gen["tipo_viaje"]),
                _buildInfoRow("Terminal:", gen["terminal"]),
                _buildInfoRow("Naviera:", gen["naviera"]),
                _buildInfoRow("Boleta Liberación:", gen["boleta_liberacion"]),
                if (gen["fecha_registro"] != null) _buildInfoRow("Fecha Registro:", gen["fecha_registro"]),

                if (eqOp != null) ...[
                  const Divider(height: 24),
                  _buildSectionTitle("Equipo y Operador", Icons.person),
                  if (eqOp["operador"] != null) _buildInfoRow("Operador:", eqOp["operador"]),
                  if (eqOp["telefono_operador"] != null) _buildInfoRow("Teléfono Operador:", eqOp["telefono_operador"]),
                  if (eqOp["unidad"] != null) _buildInfoRow("Unidad:", eqOp["unidad"]),
                  if (eqOp["placas"] != null) _buildInfoRow("Placas:", eqOp["placas"]),
                  if (eqOp["transportista"] != null) _buildInfoRow("Transportista:", eqOp["transportista"]),
                ],

                if (fccp != null) ...[
                  const Divider(height: 24),
                  _buildSectionTitle("Datos de Carta Porte / Facturación", Icons.receipt_long),
                  if (fccp["uso_cfdi"] != null) _buildInfoRow("Uso CFDI:", fccp["uso_cfdi"]),
                  if (fccp["forma_pago"] != null) _buildInfoRow("Forma de Pago:", fccp["forma_pago"]),
                  if (fccp["metodo_pago"] != null) _buildInfoRow("Método de Pago:", fccp["metodo_pago"]),
                  if (fccp["direccion_recinto"] != null) _buildInfoRow("Recinto:", fccp["direccion_recinto"]),
                  if (fccp["cp_fraccion"] != null) _buildInfoRow("Fracción Arancelaria:", fccp["cp_fraccion"]),
                  if (fccp["cp_clave_sat"] != null) _buildInfoRow("Clave SAT:", fccp["cp_clave_sat"]),
                  if (fccp["cp_pedimento"] != null) _buildInfoRow("Pedimento:", fccp["cp_pedimento"]),
                  if (fccp["cp_clase_ped"] != null) _buildInfoRow("Clase Pedimento:", fccp["cp_clase_ped"]),
                  if (fccp["cp_cantidad"] != null) _buildInfoRow("Cantidad:", fccp["cp_cantidad"]),
                  if (fccp["cp_valor"] != null) _buildInfoRow("Valor Mercancía:", "${fccp["cp_valor"]} ${fccp["cp_moneda"] ?? ""}"),
                  if (fccp["cp_contacto_entrega"] != null) _buildInfoRow("Contacto Entrega:", fccp["cp_contacto_entrega"]),
                  if (fccp["cp_fecha_tentativa_entrega"] != null)
                    _buildInfoRow("Entrega Tentativa:", "${fccp["cp_fecha_tentativa_entrega"]} ${fccp["cp_hora_tentativa_entrega"] ?? ""}"),
                  if (fccp["cp_comentarios"] != null) _buildInfoRow("Comentarios:", fccp["cp_comentarios"]),
                  if (fccp["doc_ccp_url"] != null) ...[
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: () => _openUrl(fccp["doc_ccp_url"]),
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                      label: const Text("Descargar PDF Carta Porte"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                    )
                  ]
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("Cerrar"),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0F2027)),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F2027)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    final strVal = (value ?? "").toString();
    if (strVal.isEmpty || strVal == "null") return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              strVal,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadgeRow(String label, dynamic value) {
    final strVal = (value ?? "").toString();
    if (strVal.isEmpty || strVal == "null") return const SizedBox.shrink();
    final statusColor = _getStatusColor(strVal);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 13),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor, width: 1),
            ),
            child: Text(
              strVal,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Modal para Evidencias y Documentos
  Future<void> _showEvidenciasDocumentosModal(int cotizacionId, String numContenedor) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiService.get("${ApiEndpoints.clienteEvidenciasDocumentos}/$cotizacionId");

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final data = resData["data"];
          _renderEvidenciasDocumentosDialog(numContenedor, data);
          return;
        }
      }
      _showSnackBar("No se pudieron obtener los documentos y evidencias.");
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showSnackBar("Error al obtener evidencias: $e");
    }
  }

  void _renderEvidenciasDocumentosDialog(String numContenedor, Map<String, dynamic> data) {
    final docs = (data["documentos"] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    final evid = (data["evidencias"] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.folder_shared, color: Color(0xFF0F2027)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Documentos y Evidencias - $numContenedor",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(
              children: [
                const TabBar(
                  labelColor: Color(0xFF0F2027),
                  indicatorColor: Color(0xFF0F2027),
                  tabs: [
                    Tab(text: "Documentos Viaje"),
                    Tab(text: "Evidencia Operador"),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      docs.isEmpty
                          ? const Center(child: Text("No hay documentos registrados"))
                          : ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (ctx, i) {
                                final doc = docs[i];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: Icon(
                                      doc["tipo"] == "PDF" ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                      color: Colors.red.shade700,
                                    ),
                                    title: Text(doc["nombre"] ?? "Documento", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.download, color: Colors.blue),
                                          onPressed: () => _downloadFile(doc["url"], doc["nombre"] ?? "documento.pdf"),
                                          tooltip: "Descargar",
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.share, color: Colors.green),
                                          onPressed: () => _shareFile(doc["url"], doc["nombre"] ?? "documento.pdf"),
                                          tooltip: "Compartir",
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),

                      evid.isEmpty
                          ? const Center(child: Text("No hay evidencias registradas por el operador"))
                          : ListView.builder(
                              itemCount: evid.length,
                              itemBuilder: (ctx, i) {
                                final item = evid[i];
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () => _showFullImageDialog(item["url"]),
                                          child: Container(
                                            width: 60,
                                            height: 60,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              color: Colors.grey.shade200,
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(
                                                item["url"],
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(item["tipo"] ?? "Evidencia", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              const SizedBox(height: 2),
                                              Text(item["name"] ?? "", style: const TextStyle(fontSize: 11, color: Colors.black54)),
                                              if (item["date"] != null) Text(item["date"], style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.download, color: Colors.blue),
                                          onPressed: () => _downloadFile(item["url"], item["name"] ?? "evidencia.jpg"),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.share, color: Colors.green),
                                          onPressed: () => _shareFile(item["url"], item["name"] ?? "evidencia.jpg"),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImageDialog(String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Icon(Icons.broken_image, size: 64, color: Colors.grey),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Cerrar"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar("No se pudo abrir la URL.");
    }
  }

  Future<void> _downloadFile(String url, String fileName) async {
    try {
      await FileDownloader.downloadFile(
        context: context,
        url: url,
        fileName: fileName,
      );
    } catch (e) {
      _showSnackBar("Error al descargar archivo: $e");
    }
  }

  Future<void> _shareFile(String url, String fileName) async {
    try {
      _showSnackBar("Preparando archivo para compartir...");
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(response.bodyBytes);

        final xFile = XFile(file.path);
        await Share.shareXFiles([xFile], text: 'Compartiendo $fileName');
      } else {
        _showSnackBar("No se pudo descargar la imagen para compartir.");
      }
    } catch (e) {
      _showSnackBar("Error al compartir: $e");
    }
  }

  Future<void> _logout() async {
    await ApiService.setToken("");
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  void _onMonitoreoGpsTap() {
    if (_activeCount == 0) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text("Sin viajes activos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: const Text(
            "No tienes viajes activos en este momento para monitorear en el mapa GPS.",
            style: TextStyle(fontSize: 14, color: Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Entendido", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const UsuarioModuleScreen(
          module: "monitoreo",
          title: "Monitoreo GPS",
        ),
      ),
    );
  }

  void _onMisViajesTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MecMisViajesScreen(
          operaciones: _operaciones,
          onRefresh: _fetchOperaciones,
          showInfoViajeModal: _showInfoViajeModal,
          showEvidenciasDocumentosModal: _showEvidenciasDocumentosModal,
          getStatusColor: _getStatusColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          "Panel de Cliente",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _fetchOperaciones,
            tooltip: "Actualizar",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchOperaciones,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // Banner Bienvenida
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: const Color(0xFF0F2027),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.business, color: Colors.white70, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _clienteNombre.isNotEmpty ? _clienteNombre : "Cliente SGT",
                                  style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Hola, $_userName",
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Gestiona tus viajes y monitorea tus cargas en tiempo real.",
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Card 1: Mis Viajes
                  _buildDashboardCard(
                    title: "Mis Viajes",
                    subtitle: "Consulta tus viajes registrados, estatus, documentos de viaje y evidencias del operador.",
                    badgeText: "${_operaciones.length} viajes",
                    icon: Icons.alt_route,
                    iconColor: const Color(0xFF0F2027),
                    badgeColor: Colors.blue.shade700,
                    onTap: _onMisViajesTap,
                  ),

                  const SizedBox(height: 16),

                  // Card 2: Monitoreo GPS
                  _buildDashboardCard(
                    title: "Monitoreo GPS",
                    subtitle: "Rastreo GPS en tiempo real en mapa de tus unidades y contenedores en tránsito.",
                    badgeText: "$_activeCount activos",
                    icon: Icons.location_on,
                    iconColor: Colors.green.shade700,
                    badgeColor: Colors.green.shade700,
                    onTap: _onMonitoreoGpsTap,
                  ),
                ],
              ),
            ),

      // Barra inferior estandarizada: Usuario - Cliente y Botón solo icono Cerrar Sesión
      bottomNavigationBar: Container(
        color: const Color(0xFF0F2027),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  const Icon(Icons.person, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "$_userName (${_clienteNombre.isNotEmpty ? _clienteNombre : 'Cliente'})",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white, size: 20),
              onPressed: _logout,
              tooltip: "Cerrar Sesión",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color iconColor,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: badgeColor, width: 1),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}

// Sub-pantalla Mis Viajes
class MecMisViajesScreen extends StatefulWidget {
  final List<Map<String, dynamic>> operaciones;
  final Future<void> Function() onRefresh;
  final Function(int cotizacionId) showInfoViajeModal;
  final Function(int cotizacionId, String numContenedor) showEvidenciasDocumentosModal;
  final Color Function(dynamic status) getStatusColor;

  const MecMisViajesScreen({
    super.key,
    required this.operaciones,
    required this.onRefresh,
    required this.showInfoViajeModal,
    required this.showEvidenciasDocumentosModal,
    required this.getStatusColor,
  });

  @override
  State<MecMisViajesScreen> createState() => _MecMisViajesScreenState();
}

class _MecMisViajesScreenState extends State<MecMisViajesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  List<Map<String, dynamic>> _filteredOperaciones = [];

  @override
  void initState() {
    super.initState();
    _filteredOperaciones = List.from(widget.operaciones);
  }

  @override
  void didUpdateWidget(covariant MecMisViajesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _applyFilters();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    List<Map<String, dynamic>> list = List.from(widget.operaciones);

    if (_searchQuery.trim().isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list.where((op) {
        final cont = (op["contenedor"] ?? "").toString().toLowerCase();
        final orig = (op["origen"] ?? "").toString().toLowerCase();
        final dest = (op["destino"] ?? "").toString().toLowerCase();
        final oper = (op["operador"] ?? "").toString().toLowerCase();
        final unid = (op["unidad"] ?? "").toString().toLowerCase();
        final cotId = (op["id"] ?? "").toString().toLowerCase();
        return cont.contains(query) || orig.contains(query) || dest.contains(query) || oper.contains(query) || unid.contains(query) || cotId.contains(query);
      }).toList();
    }

    setState(() {
      _filteredOperaciones = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          "Mis Viajes",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: () async {
              await widget.onRefresh();
              _applyFilters();
            },
            tooltip: "Actualizar",
          ),
        ],
      ),
      body: Column(
        children: [
          // Buscador superior
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                _searchQuery = val;
                _applyFilters();
              },
              decoration: InputDecoration(
                hintText: "Buscar por contenedor, origen, destino, operador...",
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _searchController.clear();
                          _searchQuery = "";
                          _applyFilters();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey.shade100,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),

          // Lista agrupada por estatus
          Expanded(
            child: _filteredOperaciones.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          "No se encontraron viajes",
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await widget.onRefresh();
                      _applyFilters();
                    },
                    child: _buildGroupedOperacionesList(_filteredOperaciones),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedOperacionesList(List<Map<String, dynamic>> list) {
    final List<Map<String, dynamic>> planeadas = [];
    final List<Map<String, dynamic>> pendientes = [];
    final List<Map<String, dynamic>> aprobadas = [];
    final List<Map<String, dynamic>> enTransito = [];
    final List<Map<String, dynamic>> finalizadas = [];
    final List<Map<String, dynamic>> otras = [];

    for (var item in list) {
      final status = (item["estatus"] ?? "").toString().toLowerCase();
      final estPlane = item["est_plane"];

      if (status.contains("planeada") || (status.contains("aprobada") && estPlane == 1)) {
        planeadas.add(item);
      } else if (status.contains("pendiente") || status.contains("cotizada") || status.contains("solicit")) {
        pendientes.add(item);
      } else if (status.contains("aprob")) {
        aprobadas.add(item);
      } else if (status.contains("tránsito") || status.contains("transito") || status.contains("ruta") || status.contains("proceso") || status.contains("activo")) {
        enTransito.add(item);
      } else if (status.contains("finaliz") || status.contains("termin")) {
        finalizadas.add(item);
      } else {
        otras.add(item);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (planeadas.isNotEmpty)
          _buildExpansionSection("Planeadas", planeadas, Colors.orange.shade700),
        if (pendientes.isNotEmpty)
          _buildExpansionSection("Viajes Solicitados (Pendientes)", pendientes, Colors.amber.shade700),
        if (aprobadas.isNotEmpty)
          _buildExpansionSection("Aprobadas", aprobadas, Colors.blue.shade600),
        if (enTransito.isNotEmpty)
          _buildExpansionSection("En Tránsito", enTransito, Colors.teal.shade700),
        if (finalizadas.isNotEmpty)
          _buildExpansionSection("Finalizadas", finalizadas, Colors.green.shade600),
        if (otras.isNotEmpty)
          _buildExpansionSection("Otras / Canceladas", otras, Colors.red.shade600),
      ],
    );
  }

  Widget _buildExpansionSection(String title, List<Map<String, dynamic>> items, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0.5,
      color: Colors.white,
      child: ExpansionTile(
        initiallyExpanded: title.startsWith("Planeadas") || title.startsWith("Viajes Solicitados") || title.startsWith("En Tránsito"),
        title: Text(
          "$title (${items.length})",
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15),
        ),
        leading: Icon(Icons.folder, color: color),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: items.map((row) => _buildOperacionCard(row)).toList(),
      ),
    );
  }

  Widget _buildOperacionCard(Map<String, dynamic> row) {
    final cotizacionId = row["id"] as int;
    final numContenedor = row["contenedor"] ?? "S/N";
    final estatus = row["estatus"] ?? "Desconocido";
    final origen = row["origen"] ?? "N/A";
    final destino = row["destino"] ?? "N/A";
    final operador = row["operador"] ?? "Sin Asignar";
    final unidad = row["unidad"] ?? "Ninguna";
    final terminal = row["terminal"] ?? "N/A";
    final clienteName = row["cliente"] ?? "N/A";
    final statusColor = widget.getStatusColor(estatus);

    final statusLower = estatus.toString().toLowerCase();
    final estPlane = row["est_plane"];
    final isPlaneada = statusLower.contains("planead") ||
        (statusLower.contains("aprob") && estPlane == 1) ||
        statusLower.contains("tránsito") ||
        statusLower.contains("transito") ||
        statusLower.contains("ruta") ||
        statusLower.contains("proceso");

    final rawFInicio = row["fecha_inicio"]?.toString() ?? row["fecha_programacion"]?.toString() ?? row["fecha"]?.toString();
    final rawFFin = row["fecha_fin"]?.toString();
    final fechaInicio = (rawFInicio != null && rawFInicio.trim().isNotEmpty && rawFInicio != "null") ? rawFInicio : "S/N";
    final fechaFin = (rawFFin != null && rawFFin.trim().isNotEmpty && rawFFin != "null") ? rawFFin : "S/N";

    final rawEmpresa = row["empresa"]?.toString() ?? row["Empresa"]?.toString();
    final empresa = (rawEmpresa != null && rawEmpresa.trim().isNotEmpty && rawEmpresa != "null") ? rawEmpresa : "N/A";

    final rawTransp = row["transportista_nombre"]?.toString() ?? row["transportista"]?.toString();
    final transportista = (rawTransp != null && rawTransp.trim().isNotEmpty && rawTransp != "null") ? rawTransp : empresa;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.grey.shade50,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: Colors.orange.shade100,
            child: Icon(Icons.directions_bus, color: Colors.orange.shade800, size: 20),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "COT-$cotizacionId",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueGrey,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  estatus.toString(),
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                clienteName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Cont: $numContenedor",
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 13, color: Colors.blue),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "$origen → $destino",
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Inicio: $fechaInicio  |  Fin: $fechaFin",
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(Icons.business, size: 13, color: Colors.teal),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      "Empresa: $empresa  |  Transp: $transportista",
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
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
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Operador", style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text(
                              operador,
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
                              unidad,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                              textAlign: TextAlign.end,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (terminal != "N/A") ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.warehouse, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text("Terminal: $terminal", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Botones de Acción
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => widget.showInfoViajeModal(cotizacionId),
                          icon: const Icon(Icons.info_outline, size: 14),
                          label: Text(isPlaneada ? "Info" : "Info de Viaje", style: const TextStyle(fontSize: 11)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F2027),
                            side: const BorderSide(color: Color(0xFF0F2027)),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => widget.showEvidenciasDocumentosModal(cotizacionId, numContenedor),
                          icon: const Icon(Icons.folder_shared, size: 14, color: Colors.white),
                          label: Text(isPlaneada ? "Evidencias" : "Evidencias / Docs", style: const TextStyle(fontSize: 11, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F2027),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                          ),
                        ),
                      ),
                      if (isPlaneada) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const UsuarioModuleScreen(
                                    module: "monitoreo",
                                    title: "Monitoreo GPS",
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.map, size: 14, color: Colors.white),
                            label: const Text("Rastreo", style: TextStyle(fontSize: 11, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                            ),
                          ),
                        ),
                      ],
                    ],
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
