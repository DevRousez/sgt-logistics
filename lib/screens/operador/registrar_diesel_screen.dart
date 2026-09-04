import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '../../utils/file_downloader.dart';
import '../../services/operador_sync_service.dart';

class RegistrarDieselScreen extends StatefulWidget {
  const RegistrarDieselScreen({super.key});

  @override
  State<RegistrarDieselScreen> createState() => _RegistrarDieselScreenState();
}

class _RegistrarDieselScreenState extends State<RegistrarDieselScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _litrosController = TextEditingController();
  final TextEditingController _costoController = TextEditingController();
  final TextEditingController _odometroController = TextEditingController();
  final TextEditingController _litrosUreaController = TextEditingController();
  final TextEditingController _costoUreaController = TextEditingController();
  
  final List<XFile> _ticketImages = [];
  final List<XFile> _ureaImages = [];
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = false;

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
  String? _gpsCoordinates;
  double? _latitude;
  double? _longitude;
  
  bool _yaRegistrado = false;
  bool _validandoEstatus = true;
  Map<String, dynamic>? _dieselDatos;
  int? _idAsignacion;
  String _numContenedor = "N/A";
  String _unidad = "N/A";

  @override
  void initState() {
    super.initState();
    _obtenerCoordenadasGps();
    _checkStatus();
  }

  Future<void> _guardarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'litros': _litrosController.text,
        'costo': _costoController.text,
        'odometro': _odometroController.text,
        'litros_urea': _litrosUreaController.text,
        'costo_urea': _costoUreaController.text,
        'latitud': _latitude,
        'longitud': _longitude,
        'gps_text': _gpsCoordinates,
        'ticket_paths': _ticketImages.map((e) => e.path).toList(),
        'urea_paths': _ureaImages.map((e) => e.path).toList(),
      };
      await prefs.setString('draft_diesel_$_idAsignacion', jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _cargarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString('draft_diesel_$_idAsignacion');
      if (draftStr != null && !_yaRegistrado) {
        final draft = jsonDecode(draftStr) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            if (_litrosController.text.isEmpty && draft['litros'] != null) _litrosController.text = draft['litros'].toString();
            if (_costoController.text.isEmpty && draft['costo'] != null) _costoController.text = draft['costo'].toString();
            if (_odometroController.text.isEmpty && draft['odometro'] != null) _odometroController.text = draft['odometro'].toString();
            if (_litrosUreaController.text.isEmpty && draft['litros_urea'] != null) _litrosUreaController.text = draft['litros_urea'].toString();
            if (_costoUreaController.text.isEmpty && draft['costo_urea'] != null) _costoUreaController.text = draft['costo_urea'].toString();
            if (_latitude == null && draft['latitud'] != null) {
              _latitude = double.tryParse(draft['latitud'].toString());
              _longitude = double.tryParse(draft['longitud'].toString());
              _gpsCoordinates = draft['gps_text']?.toString() ?? _gpsCoordinates;
            }
            if (_ticketImages.isEmpty && draft['ticket_paths'] != null) {
              for (var p in (draft['ticket_paths'] as List)) {
                if (File(p.toString()).existsSync()) {
                  _ticketImages.add(XFile(p.toString()));
                }
              }
            }
            if (_ureaImages.isEmpty && draft['urea_paths'] != null) {
              for (var p in (draft['urea_paths'] as List)) {
                if (File(p.toString()).existsSync()) {
                  _ureaImages.add(XFile(p.toString()));
                }
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _limpiarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('draft_diesel_$_idAsignacion');
    } catch (_) {}
  }

  Future<void> _checkStatus() async {
    setState(() {
      _validandoEstatus = true;
    });
    try {
      Map<String, dynamic>? opData = await ApiService.getUserData();
      final int? asigId = int.tryParse(opData?["id_asignacion"]?.toString() ?? "");
      final String? numCont = opData?["num_contenedor"]?.toString();

      if (asigId == null || numCont == null || numCont.isEmpty || numCont == "N/A") {
        final synced = await OperadorSyncService.sincronizarSiEsNecesario();
        if (synced != null) {
          opData = synced;
        }
      }

      if (opData != null) {
        final dynamic asigId = opData["id_asignacion"];
        setState(() {
          _idAsignacion = int.tryParse(asigId?.toString() ?? "");
          _numContenedor = opData!["num_contenedor"]?.toString() ?? "N/A";
          _unidad = opData["unidad"]?.toString() ?? "N/A";
        });
        if (_idAsignacion != null) {
          final prefs = await SharedPreferences.getInstance();
          final localKey = 'diesel_registrado_$_idAsignacion';
          
          try {
            final response = await ApiService.post(
              ApiEndpoints.estatusFlujo,
              {"id_asignacion": _idAsignacion},
            );
            if (response.statusCode == 200) {
              final resData = jsonDecode(response.body);
              if (resData["data"] != null) {
                final data = resData["data"];
                final bool reg = data["diesel_registrado"] == true;
                
                // Guardar localmente
                await prefs.setBool(localKey, reg);
                
                setState(() {
                  _yaRegistrado = reg;
                  _dieselDatos = reg ? data["diesel_datos"] : null;
                });
              }
            } else {
              // Fallback a caché local si la API responde con error
              if (prefs.getBool(localKey) == true) {
                setState(() {
                  _yaRegistrado = true;
                });
              }
            }
          } catch (e) {
            print("Error checking flow status: $e");
            // Fallback a caché local si falla la conexión
            if (prefs.getBool(localKey) == true) {
              setState(() {
                _yaRegistrado = true;
              });
            }
          }

          if (!_yaRegistrado) {
            await _cargarBorradorLocal();
          }
        }
      }
    } catch (e) {
      print("Error loading operator data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _validandoEstatus = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _litrosController.dispose();
    _costoController.dispose();
    _odometroController.dispose();
    _litrosUreaController.dispose();
    _costoUreaController.dispose();
    super.dispose();
  }

  /// Método para obtener la ubicación actual del operador
  Future<void> _obtenerCoordenadasGps() async {
    setState(() {
      _gpsCoordinates = "Obteniendo ubicación GPS...";
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _gpsCoordinates = "Servicio GPS apagado";
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _gpsCoordinates = "Permisos denegados";
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _gpsCoordinates = "Permisos permanentemente denegados";
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _gpsCoordinates = "Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsCoordinates = "Error GPS: $e";
        });
      }
    }
  }

  Future<void> _pickMultiImages(String target) async {
    final currentCount = target == 'diesel' ? _ticketImages.length : _ureaImages.length;
    if (currentCount >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Límite alcanzado: Máximo 3 imágenes permitidas para ${target == 'diesel' ? 'diésel' : 'urea'}"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          final spaceLeft = 3 - currentCount;
          if (pickedFiles.length > spaceLeft) {
            if (target == 'diesel') {
              _ticketImages.addAll(pickedFiles.take(spaceLeft));
            } else {
              _ureaImages.addAll(pickedFiles.take(spaceLeft));
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Solo se agregaron las primeras imágenes para no exceder el límite de 3"),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            if (target == 'diesel') {
              _ticketImages.addAll(pickedFiles);
            } else {
              _ureaImages.addAll(pickedFiles);
            }
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar imágenes de galería: $e")),
      );
    }
  }

  Widget _buildImageSelector({
    required List<XFile> images,
    required String target,
    required String label,
  }) {
    final isDiesel = target == 'diesel';
    final primaryColor = isDiesel ? Colors.blue.shade800 : Colors.blueGrey.shade800;
    final showAddButton = images.length < 3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDiesel ? Colors.black87 : Colors.blueGrey),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: showAddButton ? images.length + 1 : images.length,
            itemBuilder: (context, index) {
              if (index == images.length) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0, top: 4.0, bottom: 4.0),
                  child: InkWell(
                    onTap: () => _pickMultiImages(target),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 100,
                      decoration: BoxDecoration(
                        border: Border.all(color: primaryColor, width: 1.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library, color: primaryColor),
                          const SizedBox(height: 4),
                          Text(
                            "Galería",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final image = images[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 4.0, bottom: 4.0),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: kIsWeb
                          ? Image.network(
                              image.path,
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            )
                          : Image.file(
                              File(image.path),
                              width: 100,
                              height: 100,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            images.removeAt(index);
                          });
                        },
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildComprobanteList(dynamic data, String typeLabel, String filePrefix) {
    if (data == null) return const SizedBox.shrink();
    
    List<String> urls = [];
    if (data is List) {
      urls = data.map((e) => e.toString()).toList();
    } else if (data is String) {
      final trimmed = data.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            urls = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {
          urls = [data];
        }
      } else if (trimmed.contains(',')) {
        urls = trimmed.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      } else {
        urls = [data];
      }
    }
    
    if (urls.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 15),
        Text(
          typeLabel,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            itemBuilder: (context, index) {
              final url = urls[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: SizedBox(
                  width: 150,
                  child: Stack(
                    children: [
                      InkWell(
                        onTap: () {
                          _descargarYVerArchivo(
                            context,
                            url,
                            "${filePrefix}_${index + 1}_${_idAsignacion ?? 'registro'}.jpg",
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            height: 150,
                            width: 150,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => Container(
                              height: 150,
                              width: 150,
                              color: Colors.grey.shade200,
                              child: const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(6),
                            icon: const Icon(Icons.download, color: Colors.white, size: 18),
                            onPressed: () {
                              FileDownloader.downloadFile(
                                context: context,
                                url: url,
                                fileName: "${filePrefix}_${index + 1}_${_idAsignacion ?? 'registro'}.jpg",
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _guardarRegistro() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ticketImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Favor de capturar o tomar foto del ticket de diésel"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    List<String> base64Images = [];
    try {
      for (var img in _ticketImages) {
        final bytes = await img.readAsBytes();
        base64Images.add(base64Encode(bytes));
      }
    } catch (e) {
      print("Error encoding image: $e");
    }

    List<String> base64UreaImages = [];
    try {
      for (var img in _ureaImages) {
        final bytes = await img.readAsBytes();
        base64UreaImages.add(base64Encode(bytes));
      }
    } catch (e) {
      print("Error encoding urea image: $e");
    }

    final opData = await ApiService.getUserData();
    final dynamic idAsignacion = opData?["id_asignacion"];
    final dynamic idContenedor = opData?["id_contenedor"];

    // Estructura del cuerpo que se enviará a la API de Laravel
    final Map<String, dynamic> body = {
      "id_asignacion": idAsignacion,
      "id_contenedor": idContenedor,
      "litros": double.tryParse(_litrosController.text.replaceAll(',', '')) ?? 0.0,
      "costo": double.tryParse(_costoController.text.replaceAll(',', '')) ?? 0.0,
      "odometro": double.tryParse(_odometroController.text.replaceAll(',', '')) ?? 0.0,
      "latitud": _latitude ?? 0.0,
      "longitud": _longitude ?? 0.0,
      "fecha_registro": DateTime.now().toIso8601String(),
      "ticket_foto_base64": base64Images,
      "litros_urea": double.tryParse(_litrosUreaController.text.replaceAll(',', '')),
      "costo_urea": double.tryParse(_costoUreaController.text.replaceAll(',', '')),
      "ticket_foto_urea_base64": base64UreaImages.isNotEmpty ? base64UreaImages : null,
    };

    await _guardarBorradorLocal();

    try {
      final response = await ApiService.post(
        ApiEndpoints.guardarCoordenadas,
        body,
      );

      if (mounted) {
        if (response.statusCode == 404) {
          final userData = await ApiService.getUserData() ?? {};
          userData["id_asignacion"] = null;
          userData["num_contenedor"] = "N/A";
          userData["unidad"] = "N/A";
          userData["id_equipo"] = "N/A";
          await ApiService.saveUserData(userData);
          await _limpiarBorradorLocal();
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text("Viaje Cancelado"),
              content: const Text("Este viaje ya no se encuentra disponible o fue cancelado. Los datos locales de este contenedor han sido limpiados."),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context); // Cierra dialogo
                    Navigator.pop(context); // Regresa al Dashboard
                  },
                  child: const Text("Aceptar"),
                )
              ],
            ),
          );
          return;
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          await _limpiarBorradorLocal();
          if (_idAsignacion != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('diesel_registrado_$_idAsignacion', true);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("¡Registro guardado y coordenadas enviadas con éxito!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          _mostrarErrorEnvio(errorDetails: "HTTP ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      _mostrarErrorEnvio(errorDetails: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
                "No se pudo contactar al servidor debido a señal débil o falta de internet en carretera.",
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
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Todos tus datos (Odómetro, Diésel, Coordenadas y Fotos) se conservaron intactos en la pantalla para no perderlos.",
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              if (kDebugMode && errorDetails != null) ...[
                const SizedBox(height: 10),
                const Text(
                  "Error Técnico Detallado:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      errorDetails,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87),
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
              Navigator.pop(context); // SOLO cierra el diálogo, NO sale de la pantalla
            },
            child: const Text("Conservar datos"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              _guardarRegistro(); // Reintentar
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registrar Diésel / Carga"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resumen de viaje activo
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.assignment, color: Colors.blue.shade800, size: 36),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Contenedor: $_numContenedor",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Unidad: $_unidad",
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            _validandoEstatus
                ? Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(strokeWidth: 3),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              "Cargando información...",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.blue.shade800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Center(
                            child: Text(
                              "Validando el estatus actual con el servidor.",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : _yaRegistrado
                    ? Card(
                    color: Colors.green.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Center(
                        child: Icon(Icons.check_circle, color: Colors.green, size: 64),
                      ),
                      const SizedBox(height: 15),
                      const Center(
                        child: Text(
                          "Registro Existente",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Ya se ha registrado correctamente el ticket y datos de combustible para este viaje. No es necesario realizar una nueva captura.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                      if (_dieselDatos != null) ...[
                        const Divider(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Importe Registrado:", style: TextStyle(fontWeight: FontWeight.bold)),
                            Text("\$${_dieselDatos!['costo']}"),
                          ],
                        ),
                        if (_dieselDatos!['litros'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Litros Cargados:", style: TextStyle(fontWeight: FontWeight.bold)),
                              Text("${_dieselDatos!['litros']} Lts"),
                            ],
                          ),
                        ],
                        if (_dieselDatos!['odometro'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Odómetro:", style: TextStyle(fontWeight: FontWeight.bold)),
                              Text("${_dieselDatos!['odometro']} Km"),
                            ],
                          ),
                        ],
                        if (_dieselDatos!['latitud'] != null && _dieselDatos!['longitud'] != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Ubicación GPS:", style: TextStyle(fontWeight: FontWeight.bold)),
                              Text("${_dieselDatos!['latitud']}, ${_dieselDatos!['longitud']}"),
                            ],
                          ),
                        ],
                        _buildComprobanteList(
                          _dieselDatos!['comprobante'],
                          "Comprobantes Diésel Cargados:",
                          "ticket_diesel",
                        ),
                        if (_dieselDatos!['litros_urea'] != null || _dieselDatos!['costo_urea'] != null) ...[
                          const Divider(height: 30),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Detalles de Urea Registrados:",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_dieselDatos!['costo_urea'] != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Importe Total Urea:", style: TextStyle(fontWeight: FontWeight.bold)),
                                Text("\$${_dieselDatos!['costo_urea']}"),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_dieselDatos!['litros_urea'] != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Litros Urea:", style: TextStyle(fontWeight: FontWeight.bold)),
                                Text("${_dieselDatos!['litros_urea']} Lts"),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          _buildComprobanteList(
                            _dieselDatos!['comprobante_urea'],
                            "Comprobantes Urea Cargados:",
                            "ticket_urea",
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              )
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // Banner informativo del GPS
              Card(
                color: Colors.blue.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location, color: Colors.blue, size: 28),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Geolocalización Automática",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _gpsCoordinates ?? "Obteniendo...",
                              style: const TextStyle(fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.blue),
                        onPressed: _obtenerCoordenadasGps,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 25),
              
              const Text(
                "Detalles de la Carga de Combustible",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _litrosController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Litros cargados",
                  prefixIcon: Icon(Icons.local_gas_station),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Favor de ingresar los litros";
                  }
                  final cleanValue = value.replaceAll(',', '');
                  final double? val = double.tryParse(cleanValue);
                  if (val == null || val <= 0) {
                    return "Favor de ingresar una cantidad de litros válida y mayor a 0";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _costoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Importe Total Diesel(\$)",
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Favor de ingresar el importe total del tiket de carga";
                  }
                  final cleanValue = value.replaceAll(',', '');
                  final double? val = double.tryParse(cleanValue);
                  if (val == null || val <= 0) {
                    return "Favor de ingresar un importe válido mayor a 0";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _odometroController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Odómetro Actual (Km)",
                  prefixIcon: Icon(Icons.speed),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Favor de ingresar el kilometraje";
                  }
                  final cleanValue = value.replaceAll(',', '');
                  final double? val = double.tryParse(cleanValue);
                  if (val == null || val <= 0) {
                    return "Favor de ingresar un kilometraje válido mayor a 0";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _buildImageSelector(
                images: _ticketImages,
                target: 'diesel',
                label: "Ticket de Carga, max 3 imagenes",
              ),
              const SizedBox(height: 25),
              const Divider(),
              const SizedBox(height: 15),
              const Text(
                "Carga de Urea (Opcional)",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey),
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _litrosUreaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Litros de Urea",
                  prefixIcon: Icon(Icons.opacity),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final bool hasUreaData = _litrosUreaController.text.trim().isNotEmpty ||
                      _costoUreaController.text.trim().isNotEmpty ||
                      _ureaImages.isNotEmpty;
                  if (hasUreaData) {
                    if (value == null || value.trim().isEmpty) {
                      return "Favor de ingresar los litros de urea";
                    }
                    final cleanValue = value.replaceAll(',', '');
                    final double? val = double.tryParse(cleanValue);
                    if (val == null || val <= 0) {
                      return "Favor de ingresar una cantidad válida mayor a 0";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _costoUreaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Importe Total de Urea (\$)",
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final bool hasUreaData = _litrosUreaController.text.trim().isNotEmpty ||
                      _costoUreaController.text.trim().isNotEmpty ||
                      _ureaImages.isNotEmpty;
                  if (hasUreaData) {
                    if (value == null || value.trim().isEmpty) {
                      return "Favor de ingresar el importe de urea";
                    }
                    final cleanValue = value.replaceAll(',', '');
                    final double? val = double.tryParse(cleanValue);
                    if (val == null || val <= 0) {
                      return "Favor de ingresar un importe válido mayor a 0";
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              _buildImageSelector(
                images: _ureaImages,
                target: 'urea',
                label: "Ticket de Urea (Opcional)",
              ),
              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: _isLoading 
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.save_alt),
                  label: Text(_isLoading ? "Guardando..." : "Confirmar Datos e Iniciar Envío"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _guardarRegistro,
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
