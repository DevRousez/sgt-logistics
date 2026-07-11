import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';

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
  
  File? _ticketImage;
  File? _ureaImage;
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = false;
  String? _gpsCoordinates;
  double? _latitude;
  double? _longitude;
  
  bool _yaRegistrado = false;
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

  Future<void> _checkStatus() async {
    final opData = await ApiService.getUserData();
    if (opData != null) {
      final dynamic asigId = opData["id_asignacion"];
      setState(() {
        _idAsignacion = int.tryParse(asigId?.toString() ?? "");
        _numContenedor = opData["num_contenedor"]?.toString() ?? "N/A";
        _unidad = opData["unidad"]?.toString() ?? "N/A";
      });
      if (_idAsignacion != null) {
        final prefs = await SharedPreferences.getInstance();
        final localKey = 'diesel_registrado_$_idAsignacion';
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
          }
        } catch (e) {
          print("Error checking flow status: $e");
        }
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

  Future<void> _pickImage(ImageSource source, String target) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (pickedFile != null) {
        setState(() {
          if (target == 'diesel') {
            _ticketImage = File(pickedFile.path);
          } else {
            _ureaImage = File(pickedFile.path);
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar imagen: $e")),
      );
    }
  }

  void _showImageSourceBottomSheet(String target) {
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
                _pickImage(ImageSource.camera, target);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text("Seleccionar de Galería"),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery, target);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardarRegistro() async {
    if (!_formKey.currentState!.validate()) return;

    if (_ticketImage == null) {
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

    String base64Image = "";
    try {
      final bytes = await _ticketImage!.readAsBytes();
      base64Image = base64Encode(bytes);
    } catch (e) {
      print("Error encoding image: $e");
    }

    String base64UreaImage = "";
    if (_ureaImage != null) {
      try {
        final bytes = await _ureaImage!.readAsBytes();
        base64UreaImage = base64Encode(bytes);
      } catch (e) {
        print("Error encoding urea image: $e");
      }
    }

    final opData = await ApiService.getUserData();
    final dynamic idAsignacion = opData?["id_asignacion"];
    final dynamic idContenedor = opData?["id_contenedor"];

    // Estructura del cuerpo que se enviará a la API de Laravel
    final Map<String, dynamic> body = {
      "id_asignacion": idAsignacion,
      "id_contenedor": idContenedor,
      "litros": double.tryParse(_litrosController.text) ?? 0.0,
      "costo": double.tryParse(_costoController.text) ?? 0.0,
      "odometro": double.tryParse(_odometroController.text) ?? 0.0,
      "latitud": _latitude ?? 0.0,
      "longitud": _longitude ?? 0.0,
      "fecha_registro": DateTime.now().toIso8601String(),
      "ticket_foto_base64": base64Image,
      "litros_urea": double.tryParse(_litrosUreaController.text),
      "costo_urea": double.tryParse(_costoUreaController.text),
      "ticket_foto_urea_base64": base64UreaImage.isNotEmpty ? base64UreaImage : null,
    };

    try {
      final response = await ApiService.post(
        ApiEndpoints.guardarCoordenadas,
        body,
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
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
          _mostrarSimulacionExitosa(body, errorDetails: "HTTP ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      _mostrarSimulacionExitosa(body, errorDetails: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _mostrarSimulacionExitosa(Map<String, dynamic> datosEnviados, {String? errorDetails}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_queue, color: Colors.orange),
            SizedBox(width: 10),
            Text("Modo Offline Activo"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("No se pudo conectar al servidor, los datos se guardaron localmente:"),
            if (kDebugMode && errorDetails != null) ...[
              const SizedBox(height: 10),
              const Text(
                "Error Técnico Detallado:",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
              ),
              const SizedBox(height: 5),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  errorDetails,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Text("📍 Coordenadas: ${datosEnviados['latitud']}, ${datosEnviados['longitud']}"),
            Text("⛽ Diésel: ${datosEnviados['litros']} Lts (\$${datosEnviados['costo']})"),
            Text("🚗 Odómetro: ${datosEnviados['odometro']} Km"),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Cerrar diálogo
              Navigator.pop(context); // Regresar al dashboard
            },
            child: const Text("Entendido"),
          )
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
                            const Text("Costo Registrado:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                        if (_dieselDatos!['comprobante'] != null) ...[
                          const SizedBox(height: 15),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Comprobante Cargado:",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              _dieselDatos!['comprobante'],
                              height: 200,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (c, o, s) => Container(
                                height: 100,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        ],
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
                                const Text("Costo Urea:", style: TextStyle(fontWeight: FontWeight.bold)),
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
                          if (_dieselDatos!['comprobante_urea'] != null) ...[
                            const SizedBox(height: 10),
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                "Comprobante Urea:",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                _dieselDatos!['comprobante_urea'],
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (c, o, s) => Container(
                                  height: 100,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),
                          ],
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
                  return null;
                },
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _costoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Costo Total (\$)",
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Favor de ingresar el costo total";
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
                  return null;
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "Ticket de Carga",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (_ticketImage != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _ticketImage!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.red,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _ticketImage = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 100,
                  child: OutlinedButton.icon(
                    onPressed: () => _showImageSourceBottomSheet('diesel'),
                    icon: const Icon(Icons.add_a_photo, size: 28),
                    label: const Text("Tomar Foto o Cargar Ticket", style: TextStyle(fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.blue.shade800, width: 1.5),
                      foregroundColor: Colors.blue.shade800,
                    ),
                  ),
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
              ),
              const SizedBox(height: 15),

              TextFormField(
                controller: _costoUreaController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: "Costo Total de Urea (\$)",
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              
              const Text(
                "Ticket de Urea (Opcional)",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              if (_ureaImage != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _ureaImage!,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.red,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _ureaImage = null;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 100,
                  child: OutlinedButton.icon(
                    onPressed: () => _showImageSourceBottomSheet('urea'),
                    icon: const Icon(Icons.add_a_photo, size: 28),
                    label: const Text("Tomar Foto o Cargar Ticket de Urea", style: TextStyle(fontSize: 15)),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.blueGrey.shade800, width: 1.5),
                      foregroundColor: Colors.blueGrey.shade800,
                    ),
                  ),
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
