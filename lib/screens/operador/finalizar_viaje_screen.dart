import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/config/api_config.dart';
import '../../utils/file_downloader.dart';
import '../../services/operador_sync_service.dart';

class FinalizarViajeScreen extends StatefulWidget {
  const FinalizarViajeScreen({super.key});

  @override
  State<FinalizarViajeScreen> createState() => _FinalizarViajeScreenState();
}

class _FinalizarViajeScreenState extends State<FinalizarViajeScreen> {
  final List<XFile> _photos = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;
  String _rawResponseData = "";

  String _buildImageUrl(String path, {String defaultFolder = 'entrega_contenedor'}) {
    if (path.isEmpty) return "";
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    String cleanPath = path.startsWith('/') ? path.substring(1) : path;
    if (cleanPath.contains('uploads/')) {
      return "$cleanBaseUrl/$cleanPath";
    }
    return "$cleanBaseUrl/uploads/$defaultFolder/$_idAsignacion/$cleanPath";
  }

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
  
  bool _yaRegistrado = false;
  bool _validandoEstatus = true;
  List<String> _fotosGuardadas = [];
  
  bool _aperturaRegistrada = false;
  List<String> _fotosAperturaGuardadas = [];
  final List<XFile> _photosApertura = [];
  bool _isLoadingApertura = false;

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
    setState(() {
      _validandoEstatus = true;
    });

    try {
      Map<String, dynamic>? data = await ApiService.getUserData();
      final int? asigId = int.tryParse(data?["id_asignacion"]?.toString() ?? "");
      final String? numCont = data?["num_contenedor"]?.toString();

      if (asigId == null || numCont == null || numCont.isEmpty || numCont == "N/A") {
        final synced = await OperadorSyncService.sincronizarSiEsNecesario();
        if (synced != null) {
          data = synced;
        }
      }

      if (data != null && mounted) {
        setState(() {
          _operatorData = data;
          _numContenedor = data!["num_contenedor"]?.toString() ?? "N/A";
          _unidad = data["unidad"]?.toString() ?? "N/A";
          final dynamic asigId = data["id_asignacion"];
          _idAsignacion = int.tryParse(asigId?.toString() ?? "");
        });

        if (_idAsignacion != null) {
          final prefs = await SharedPreferences.getInstance();
          final localKey = 'viaje_finalizado_$_idAsignacion';
          final localKeyApertura = 'apertura_registrada_$_idAsignacion';

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
                final bool aperturaDone = dataObj["apertura_registrada"] == true;
                
                await prefs.setBool(localKey, finished);
                await prefs.setBool(localKeyApertura, aperturaDone);

                List<String> parsedFotos = [];
                if (finished) {
                  final dynamic rawFotos = dataObj["fotos_fin"] ?? dataObj["fotos_entrega"] ?? dataObj["evidencias_entrega"] ?? dataObj["fotos"];
                  if (rawFotos is List) {
                    parsedFotos = List<String>.from(rawFotos.map((e) => e.toString()));
                  } else if (rawFotos is String && rawFotos.isNotEmpty) {
                    try {
                      final decoded = jsonDecode(rawFotos);
                      if (decoded is List) {
                        parsedFotos = List<String>.from(decoded.map((e) => e.toString()));
                      } else {
                        parsedFotos = [rawFotos];
                      }
                    } catch (_) {
                      parsedFotos = [rawFotos];
                    }
                  }
                }

                List<String> parsedFotosApertura = [];
                final dynamic rawFotosApertura = dataObj["fotos_apertura"];
                if (rawFotosApertura is List) {
                  parsedFotosApertura = List<String>.from(rawFotosApertura.map((e) => e.toString()));
                } else if (rawFotosApertura is String && rawFotosApertura.isNotEmpty) {
                  try {
                    final decoded = jsonDecode(rawFotosApertura);
                    if (decoded is List) {
                      parsedFotosApertura = List<String>.from(decoded.map((e) => e.toString()));
                    } else {
                      parsedFotosApertura = [rawFotosApertura];
                    }
                  } catch (_) {
                    parsedFotosApertura = [rawFotosApertura];
                  }
                }

                setState(() {
                  _rawResponseData = response.body;
                  _yaRegistrado = finished;
                  _fotosGuardadas = parsedFotos;
                  _aperturaRegistrada = aperturaDone;
                  _fotosAperturaGuardadas = parsedFotosApertura;
                });
              }
            } else {
              // Fallback a caché local si la API responde con error
              if (prefs.getBool(localKey) == true) {
                setState(() {
                  _yaRegistrado = true;
                });
              }
              if (prefs.getBool(localKeyApertura) == true) {
                setState(() {
                  _aperturaRegistrada = true;
                });
              }
            }
          } catch (e) {
            print("Error retrieving flow status: $e");
            // Fallback a caché local si falla la conexión
            if (prefs.getBool(localKey) == true) {
              setState(() {
                _yaRegistrado = true;
              });
            }
            if (prefs.getBool(localKeyApertura) == true) {
              setState(() {
                _aperturaRegistrada = true;
              });
            }
          }

          if (!_yaRegistrado) {
            await _cargarBorradorLocal();
          }
          if (!_aperturaRegistrada) {
            await _cargarBorradorLocalApertura();
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

  Future<void> _guardarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'photo_paths': _photos.map((e) => e.path).toList(),
        'latitud': _latitude,
        'longitud': _longitude,
      };
      await prefs.setString('draft_finalizar_$_idAsignacion', jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _cargarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString('draft_finalizar_$_idAsignacion');
      if (draftStr != null && !_yaRegistrado) {
        final draft = jsonDecode(draftStr) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            if (_latitude == null && draft['latitud'] != null) {
              _latitude = double.tryParse(draft['latitud'].toString());
              _longitude = double.tryParse(draft['longitud'].toString());
            }
            if (_photos.isEmpty && draft['photo_paths'] != null) {
              for (var p in (draft['photo_paths'] as List)) {
                if (File(p.toString()).existsSync()) {
                  _photos.add(XFile(p.toString()));
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
      await prefs.remove('draft_finalizar_$_idAsignacion');
    } catch (_) {}
  }

  Future<void> _guardarBorradorLocalApertura() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = {
        'photo_paths': _photosApertura.map((e) => e.path).toList(),
        'latitud': _latitude,
        'longitud': _longitude,
      };
      await prefs.setString('draft_apertura_$_idAsignacion', jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _cargarBorradorLocalApertura() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString('draft_apertura_$_idAsignacion');
      if (draftStr != null && !_aperturaRegistrada) {
        final draft = jsonDecode(draftStr) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            if (_latitude == null && draft['latitud'] != null) {
              _latitude = double.tryParse(draft['latitud'].toString());
              _longitude = double.tryParse(draft['longitud'].toString());
            }
            if (_photosApertura.isEmpty && draft['photo_paths'] != null) {
              for (var p in (draft['photo_paths'] as List)) {
                if (File(p.toString()).existsSync()) {
                  _photosApertura.add(XFile(p.toString()));
                }
              }
            }
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _limpiarBorradorLocalApertura() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('draft_apertura_$_idAsignacion');
    } catch (_) {}
  }

  Future<void> _pickGalleryImagesApertura() async {
    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          _photosApertura.addAll(pickedFiles);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar fotos de galería: $e")),
      );
    }
  }

  Future<void> _enviarAperturaContenedor() async {
    if (_photosApertura.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debes anexar al menos 1 foto de evidencia de la apertura de contenedor."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_latitude == null || _longitude == null) {
      await _obtenerCoordenadasGps();
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Se requieren las coordenadas GPS actuales. Por favor verifica que la ubicación esté activa."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isLoadingApertura = true;
    });

    List<String> imagesBase64 = [];
    try {
      for (var file in _photosApertura) {
        final bytes = await file.readAsBytes();
        imagesBase64.add(base64Encode(bytes));
      }
    } catch (e) {
      print("Error encoding apertura images: $e");
    }

    final Map<String, dynamic> body = {
      "id_asignacion": _idAsignacion,
      "fotos_base64": imagesBase64,
      "latitud": _latitude,
      "longitud": _longitude,
    };

    await _guardarBorradorLocalApertura();

    try {
      final response = await ApiService.post(
        ApiEndpoints.aperturaContenedor,
        body,
      );

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          await _limpiarBorradorLocalApertura();
          if (_idAsignacion != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('apertura_registrada_$_idAsignacion', true);
          }

          setState(() {
            _aperturaRegistrada = true;
          });

          await _loadOperatorInfo();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("¡Apertura de contenedor registrada con éxito! Ahora puedes concluir el viaje."),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _mostrarErrorEnvio(errorDetails: "HTTP ${response.statusCode}: ${response.body}");
        }
      }
    } catch (e) {
      _mostrarErrorEnvio(errorDetails: e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingApertura = false;
        });
      }
    }
  }

  Future<void> _pickGalleryImages() async {
    try {
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (pickedFiles.isNotEmpty && mounted) {
        setState(() {
          _photos.addAll(pickedFiles);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar fotos de galería: $e")),
      );
    }
  }

  Future<void> _finalizarViaje() async {
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Debes anexar al menos 1 foto de evidencia para concluir el viaje."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_latitude == null || _longitude == null) {
      await _obtenerCoordenadasGps();
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Se requieren las coordenadas GPS actuales. Por favor verifica que la ubicación esté activa."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

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

    await _guardarBorradorLocal();

    try {
      final response = await ApiService.post(
        ApiEndpoints.finalizarViajeOperador,
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
          await _limpiarBorradorLocalApertura();
          if (_idAsignacion != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('viaje_finalizado_$_idAsignacion', true);
            await prefs.remove('draft_finalizar_$_idAsignacion');
            await prefs.remove('draft_apertura_$_idAsignacion');
          }

          final data = await ApiService.getUserData() ?? {};
          data["id_asignacion"] = null;
          data["num_contenedor"] = "N/A";
          data["unidad"] = "N/A";
          data["id_equipo"] = "N/A";
          await ApiService.saveUserData(data);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("¡Entrega y conclusión de viaje registradas con éxito!"),
                backgroundColor: Colors.green,
              ),
            );
            Navigator.pop(context, true);
          }
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
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Las ${_photos.length} fotos y coordenadas se conservan intactas en pantalla.",
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
              ),
              if (kDebugMode && errorDetails != null) ...[
                const SizedBox(height: 10),
                const Text(
                  "Detalle Técnico del Error:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 140),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      errorDetails,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.black87),
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
              Navigator.pop(context); // SOLO cierra diálogo
            },
            child: const Text("Conservar fotos"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _finalizarViaje(); // Reintentar
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
        title: const Text("Concluir Viaje"),
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
                    ? GestureDetector(
                        onDoubleTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text("Debug: Respuesta JSON de API"),
                              content: SingleChildScrollView(
                                child: SelectableText(
                                  _rawResponseData.isEmpty ? "No hay datos recibidos de la API aún" : _rawResponseData,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Cerrar"),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Card(
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
                              "Viaje Concluido",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Has registrado correctamente la conclusión y entrega de este viaje.",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.black87, fontSize: 14),
                          ),
                          if (_fotosGuardadas.isNotEmpty) ...[
                            const Divider(height: 30),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Evidencias de Entrega:",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                if (_fotosGuardadas.length > 1)
                                  TextButton.icon(
                                    icon: const Icon(Icons.download_for_offline, size: 18),
                                    label: const Text("Descargar todas", style: TextStyle(fontSize: 12)),
                                    onPressed: () {
                                      FileDownloader.downloadAllFiles(
                                        context: context,
                                        urls: _fotosGuardadas,
                                        prefix: "evidencia_entrega_${_idAsignacion ?? 'viaje'}",
                                      );
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 120,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: _fotosGuardadas.length,
                                itemBuilder: (context, index) {
                                  final imageUrl = _fotosGuardadas[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Stack(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            imageUrl,
                                            width: 120,
                                            height: 120,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, o, s) => Container(
                                              width: 120,
                                              height: 120,
                                              color: Colors.grey.shade200,
                                              child: const Icon(Icons.broken_image),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          right: 4,
                                          bottom: 4,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.6),
                                              shape: BoxShape.circle,
                                            ),
                                            child: IconButton(
                                              constraints: const BoxConstraints(),
                                              padding: const EdgeInsets.all(4),
                                              icon: const Icon(Icons.download, color: Colors.white, size: 16),
                                              onPressed: () {
                                                FileDownloader.downloadFile(
                                                  context: context,
                                                  url: imageUrl,
                                                  fileName: "evidencia_entrega_${index + 1}.jpg",
                                                );
                                              },
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

                        ],
                      ),
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
                      const SizedBox(height: 20),

                      // SECCIÓN 1: APERTURA DE CONTENEDOR
                      if (_aperturaRegistrada)
                        Card(
                          elevation: 1,
                          color: Colors.green.shade50,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.green.shade200),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ExpansionTile(
                            initiallyExpanded: false,
                            leading: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                            title: const Text(
                              "Apertura de Contenedor (Registrado)",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green),
                            ),
                            subtitle: const Text(
                              "Toca para expandir y ver las evidencias registradas",
                              style: TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_fotosAperturaGuardadas.isNotEmpty) ...[
                                      const Text(
                                        "Evidencias de Apertura:",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        height: 110,
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _fotosAperturaGuardadas.length,
                                          itemBuilder: (context, index) {
                                            final rawPath = _fotosAperturaGuardadas[index];
                                            final imgUrl = _buildImageUrl(rawPath, defaultFolder: 'apertura_contenedor');
                                            return Padding(
                                              padding: const EdgeInsets.only(right: 10),
                                              child: Stack(
                                                children: [
                                                  ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.network(
                                                      imgUrl,
                                                      width: 100,
                                                      height: 100,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (c, o, s) => Container(
                                                        width: 100,
                                                        height: 100,
                                                        color: Colors.grey.shade200,
                                                        child: const Icon(Icons.broken_image),
                                                      ),
                                                    ),
                                                  ),
                                                  Positioned(
                                                    right: 2,
                                                    bottom: 2,
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withOpacity(0.6),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: IconButton(
                                                        constraints: const BoxConstraints(),
                                                        padding: const EdgeInsets.all(4),
                                                        icon: const Icon(Icons.download, color: Colors.white, size: 14),
                                                        onPressed: () {
                                                          FileDownloader.downloadFile(
                                                            context: context,
                                                            url: imgUrl,
                                                            fileName: "apertura_${index + 1}.jpg",
                                                          );
                                                        },
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ] else ...[
                                      const Text(
                                        "Información de apertura enviada correctamente al servidor.",
                                        style: TextStyle(color: Colors.black54, fontSize: 13),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.lock_open, color: Colors.orange.shade900, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Etapa 1: Apertura de Contenedor",
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            "Anexa evidencias fotográficas de la apertura.",
                                            style: TextStyle(color: Colors.black54, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),
                                if (_photosApertura.isNotEmpty)
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: _photosApertura.length + 1,
                                    itemBuilder: (context, index) {
                                      if (index == _photosApertura.length) {
                                        return GestureDetector(
                                          onTap: _pickGalleryImagesApertura,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.orange.shade800, width: 1.5),
                                              borderRadius: BorderRadius.circular(12),
                                              color: Colors.orange.shade50,
                                            ),
                                            child: Icon(Icons.add_photo_alternate, color: Colors.orange.shade800, size: 28),
                                          ),
                                        );
                                      }
                                      return Stack(
                                        children: [
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: kIsWeb
                                                  ? Image.network(_photosApertura[index].path, fit: BoxFit.cover)
                                                  : Image.file(File(_photosApertura[index].path), fit: BoxFit.cover),
                                            ),
                                          ),
                                          Positioned(
                                            top: 4,
                                            right: 4,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  _photosApertura.removeAt(index);
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
                                    height: 90,
                                    child: OutlinedButton.icon(
                                      onPressed: _pickGalleryImagesApertura,
                                      icon: const Icon(Icons.photo_camera, size: 26),
                                      label: const Text("Anexar Fotos de Apertura", style: TextStyle(fontSize: 14)),
                                      style: OutlinedButton.styleFrom(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        side: BorderSide(color: Colors.orange.shade800, width: 1.5),
                                        foregroundColor: Colors.orange.shade800,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 20),
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    icon: _isLoadingApertura
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.send),
                                    label: Text(_isLoadingApertura ? "Guardando..." : "Enviar Apertura de Contenedor"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange.shade800,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _isLoadingApertura ? null : _enviarAperturaContenedor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // SECCIÓN 2: CONCLUIR VIAJE
                      if (!_aperturaRegistrada)
                        Card(
                          elevation: 1,
                          color: Colors.grey.shade100,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: const Padding(
                            padding: EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Icon(Icons.lock, color: Colors.grey, size: 28),
                                SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "Etapa 2: Concluir Viaje",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        "Para habilitar este paso, debes registrar primero la 'Apertura de Contenedor'.",
                                        style: TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.check_circle_outline, color: Colors.blue.shade800, size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Etapa 2: Concluir Viaje",
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                          ),
                                          SizedBox(height: 2),
                                          Text(
                                            "Sube las fotos de contenedor vacío y formato firmado.",
                                            style: TextStyle(color: Colors.black54, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 24),

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
                                          onTap: _pickGalleryImages,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              border: Border.all(color: Colors.blue.shade800, width: 1.5),
                                              borderRadius: BorderRadius.circular(12),
                                              color: Colors.blue.shade50,
                                            ),
                                            child: Icon(Icons.add_photo_alternate, color: Colors.blue.shade800, size: 28),
                                          ),
                                        );
                                      }
                                      return Stack(
                                        children: [
                                          Positioned.fill(
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: kIsWeb
                                                  ? Image.network(_photos[index].path, fit: BoxFit.cover)
                                                  : Image.file(File(_photos[index].path), fit: BoxFit.cover),
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
                                      onPressed: _pickGalleryImages,
                                      icon: const Icon(Icons.photo_library, size: 28),
                                      label: const Text("Seleccionar Fotos de Galería", style: TextStyle(fontSize: 15)),
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

                                SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton.icon(
                                    icon: _isLoading 
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Icon(Icons.check_circle_outline),
                                    label: Text(_isLoading ? "Concluyendo..." : "Concluir Viaje"),
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
