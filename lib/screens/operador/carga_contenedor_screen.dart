import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';

class CargaContenedorScreen extends StatefulWidget {
  const CargaContenedorScreen({super.key});

  @override
  State<CargaContenedorScreen> createState() => _CargaContenedorScreenState();
}

class _CargaContenedorScreenState extends State<CargaContenedorScreen> {
  final List<File> _photos = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  
  bool _yaRegistrado = false;
  List<String> _fotosGuardadas = [];

  Map<String, dynamic>? _operatorData;
  String _numContenedor = "N/A";
  String _unidad = "N/A";
  int? _idAsignacion;

  @override
  void initState() {
    super.initState();
    _loadOperatorInfo();
  }

  Future<void> _loadOperatorInfo() async {
    final data = await ApiService.getUserData();
    if (data != null && mounted) {
      setState(() {
        _operatorData = data;
        _numContenedor = data["num_contenedor"]?.toString() ?? "N/A";
        _unidad = data["unidad"]?.toString() ?? "N/A";
        _idAsignacion = int.tryParse(data["id_asignacion"]?.toString() ?? "");
      });
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    if (_idAsignacion == null) return;
    final prefs = await SharedPreferences.getInstance();
    final localKey = 'viaje_iniciado_$_idAsignacion';
    if (prefs.getBool(localKey) == true) {
      setState(() {
        _yaRegistrado = true;
      });
    }

    try {
      final response = await ApiService.post(
        ApiEndpoints.estatusFlujo,
        {"id_asignacion": _idAsignacion},
      );
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        if (resData["success"] == true && resData["data"] != null) {
          final data = resData["data"];
          final bool reg = data["viaje_iniciado"] == true;
          await prefs.setBool(localKey, reg);
          setState(() {
            _yaRegistrado = reg;
            _fotosGuardadas = reg ? List<String>.from(data["fotos"] ?? []) : [];
          });
        }
      }
    } catch (e) {
      print("Error checking flow status: $e");
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_photos.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Se ha alcanzado el límite máximo de 10 fotos"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          _photos.add(File(pickedFile.path));
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al capturar foto: $e")),
      );
    }
  }

  void _showImageSourceBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text("Tomar Foto (Cámara)"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Seleccionar de Galería"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _iniciarViaje() async {
    if (_photos.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debes tomar un mínimo de 5 fotos para iniciar el viaje"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    double? latitude;
    double? longitude;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          Position position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
          );
          latitude = position.latitude;
          longitude = position.longitude;
        }
      }
    } catch (e) {
      print("Error getting GPS for trip start: $e");
    }

    List<String> imagesBase64 = [];
    try {
      for (var file in _photos) {
        final bytes = await file.readAsBytes();
        imagesBase64.add(base64Encode(bytes));
      }
    } catch (e) {
      print("Error encoding images: $e");
    }

    final Map<String, dynamic> body = {
      "id_asignacion": _idAsignacion,
      "id_contenedor": _operatorData?["id_contenedor"],
      "fotos_base64": imagesBase64,
      "latitud": latitude,
      "longitud": longitude,
    };

    try {
      final response = await ApiService.post(
        ApiEndpoints.iniciarViaje,
        body,
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (_idAsignacion != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('viaje_iniciado_$_idAsignacion', true);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("¡Fotos guardadas e inicio de viaje registrado con éxito!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          _mostrarOfflineDialog(body, errorDetails: "HTTP ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      _mostrarOfflineDialog(body, errorDetails: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _mostrarOfflineDialog(Map<String, dynamic> body, {String? errorDetails}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_off, color: Colors.orange),
            SizedBox(width: 10),
            Text("Modo Offline"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "No se pudo conectar al servidor. El viaje se iniciará de forma local y las ${_photos.length} fotos se subirán al sincronizar.",
            ),
            if (kDebugMode && errorDetails != null) ...[
              const SizedBox(height: 15),
              const Text(
                "Detalle Técnico del Error:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
              ),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  errorDetails,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pop(context); // Regresar al panel anterior
            },
            child: const Text("Entendido"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = _photos.length >= 5;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Carga Contenedor"),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
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
            const SizedBox(height: 25),

            if (_yaRegistrado)
              Card(
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
                          "Viaje Iniciado",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Las fotos del contenedor han sido cargadas exitosamente y el viaje está en curso.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black87, fontSize: 14),
                      ),
                      if (_fotosGuardadas.isNotEmpty) ...[
                        const Divider(height: 30),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Fotos Registradas:",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _fotosGuardadas.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemBuilder: (context, index) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _fotosGuardadas[index],
                                fit: BoxFit.cover,
                                errorBuilder: (c, o, s) => Container(
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else ...[
              // Encabezado sección de fotos
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Fotos de Carga / Contenedor",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Mínimo 5, máximo 10 fotos",
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  Text(
                    "${_photos.length} / 10",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: canSubmit ? Colors.green : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),

              // GridView de fotos tomadas
              if (_photos.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _photos.length + (_photos.length < 10 ? 1 : 0),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    if (index == _photos.length) {
                      return InkWell(
                        onTap: _showImageSourceBottomSheet,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade800, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.blue.shade50,
                          ),
                          child: Icon(Icons.add_a_photo, color: Colors.blue.shade800),
                        ),
                      );
                    }
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(_photos[index], fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.red.withOpacity(0.8),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(Icons.close, color: Colors.white, size: 16),
                              onPressed: () {
                                setState(() {
                                  _photos.removeAt(index);
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                )
              else
                // Estado vacío cuando no hay fotos
                InkWell(
                  onTap: _showImageSourceBottomSheet,
                  child: Container(
                    width: double.infinity,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, size: 40, color: Colors.grey.shade600),
                        const SizedBox(height: 10),
                        Text(
                          "Presiona aquí para capturar fotos",
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 40),

              // Botón de Iniciar Viaje / Confirmar carga
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  icon: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(Icons.play_arrow),
                  label: Text(_isLoading ? "Procesando..." : "Iniciar Viaje"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSubmit ? Colors.green.shade700 : Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: (_isLoading || !canSubmit) ? null : _iniciarViaje,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
