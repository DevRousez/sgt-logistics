import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';

class FinalizarViajeScreen extends StatefulWidget {
  const FinalizarViajeScreen({super.key});

  @override
  State<FinalizarViajeScreen> createState() => _FinalizarViajeScreenState();
}

class _FinalizarViajeScreenState extends State<FinalizarViajeScreen> {
  final List<File> _photos = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  
  bool _yaRegistrado = false;
  List<String> _fotosGuardadas = [];
  
  String? _gpsCoordinates;
  double? _latitude;
  double? _longitude;

  Map<String, dynamic>? _operatorData;
  String _numContenedor = "N/A";
  String _unidad = "N/A";
  int? _idAsignacion;

  @override
  void initState() {
    super.initState();
    _obtenerCoordenadasGps();
    _loadOperatorInfo();
  }

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

  Future<void> _loadOperatorInfo() async {
    final data = await ApiService.getUserData();
    if (data != null && mounted) {
      setState(() {
        _operatorData = data;
        _numContenedor = data["num_contenedor"]?.toString() ?? "N/A";
        _unidad = data["unidad"]?.toString() ?? "N/A";
        final dynamic asigId = data["id_asignacion"];
        _idAsignacion = int.tryParse(asigId?.toString() ?? "");
      });

      if (_idAsignacion != null) {
        final prefs = await SharedPreferences.getInstance();
        final localKey = 'viaje_finalizado_$_idAsignacion';
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

          if (response.statusCode == 200 && mounted) {
            final resData = jsonDecode(response.body);
            if (resData["data"] != null) {
              final dataObj = resData["data"];
              final bool finished = dataObj["viaje_finalizado"] == true;
              
              await prefs.setBool(localKey, finished);

              setState(() {
                _yaRegistrado = finished;
                if (dataObj["fotos_fin"] != null) {
                  _fotosGuardadas = List<String>.from(dataObj["fotos_fin"]);
                }
              });
            }
          }
        } catch (e) {
          print("Error retrieving flow status: $e");
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null && mounted) {
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

  Future<void> _finalizarViaje() async {
    setState(() {
      _isLoading = true;
    });

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
      "fotos_base64": imagesBase64,
      "latitud": _latitude,
      "longitud": _longitude,
    };

    try {
      final response = await ApiService.post(
        ApiEndpoints.finalizarViajeOperador,
        body,
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          if (_idAsignacion != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('viaje_finalizado_$_idAsignacion', true);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("¡Entrega y finalización de viaje registradas con éxito!"),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Error al finalizar viaje: ${response.body}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error de conexión: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Finalizar Viaje"),
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

            _yaRegistrado
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
                              "Viaje Finalizado",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Has registrado correctamente la finalización y entrega de este viaje.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                          ),
                          if (_fotosGuardadas.isNotEmpty) ...[
                            const Divider(height: 30),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Evidencias de Entrega:",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _fotosGuardadas.length,
                                itemBuilder: (context, index) {
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _fotosGuardadas[index],
                                        width: 120,
                                        height: 120,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, o, s) => Container(
                                          width: 120,
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.broken_image),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ubicación GPS Info Card
                      Card(
                        elevation: 1,
                        color: Colors.grey.shade50,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Icon(Icons.gps_fixed, color: Colors.blue.shade800),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Text(
                                  _gpsCoordinates ?? "Cargando coordenadas...",
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                        "Comprobante o Evidencia de Entrega (Opcional)",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),

                      if (_photos.isNotEmpty)
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _photos.length + 1,
                          itemBuilder: (context, index) {
                            if (index == _photos.length) {
                              return GestureDetector(
                                onTap: _showImageSourceBottomSheet,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.blue.shade800, width: 1.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.add_a_photo, color: Colors.blue.shade800, size: 28),
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
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _photos.removeAt(index);
                                      });
                                    },
                                    child: const CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.red,
                                      child: Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 100,
                          child: OutlinedButton.icon(
                            onPressed: _showImageSourceBottomSheet,
                            icon: const Icon(Icons.add_a_photo, size: 28),
                            label: const Text("Tomar Foto / Evidencia", style: TextStyle(fontSize: 15)),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              side: BorderSide(color: Colors.blue.shade800, width: 1.5),
                              foregroundColor: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      const SizedBox(height: 35),

                      SizedBox(
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          icon: _isLoading 
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_isLoading ? "Registrando Fin..." : "Finalizar Viaje"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade800,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isLoading ? null : _finalizarViaje,
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
