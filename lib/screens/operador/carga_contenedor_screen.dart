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

class CargaContenedorScreen extends StatefulWidget {
  const CargaContenedorScreen({super.key});

  @override
  State<CargaContenedorScreen> createState() => _CargaContenedorScreenState();
}

class _CargaContenedorScreenState extends State<CargaContenedorScreen> {
  final List<XFile> _photos = [];
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  String _buildImageUrl(String path) {
    if (path.isEmpty) return "";
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final cleanBaseUrl = ApiConfig.baseUrl.replaceAll('/api', '');
    if (path.contains('uploads/')) {
      return "$cleanBaseUrl/$path";
    }
    return "$cleanBaseUrl/uploads/carga_contenedor/$_idAsignacion/$path";
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
  double? _latitude;
  double? _longitude;

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
        _idAsignacion = int.tryParse(data["id_asignacion"]?.toString() ?? "");
      });
      _checkStatus();
    } else {
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
      await prefs.setString('draft_carga_$_idAsignacion', jsonEncode(draft));
    } catch (_) {}
  }

  Future<void> _cargarBorradorLocal() async {
    if (_idAsignacion == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftStr = prefs.getString('draft_carga_$_idAsignacion');
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
      await prefs.remove('draft_carga_$_idAsignacion');
    } catch (_) {}
  }

  Future<void> _checkStatus() async {
    if (_idAsignacion == null) {
      if (mounted) {
        setState(() {
          _validandoEstatus = false;
        });
      }
      return;
    }
    
    setState(() {
      _validandoEstatus = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final localKey = 'viaje_iniciado_$_idAsignacion';

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
          
          List<String> parsedFotos = [];
          if (reg) {
            final dynamic rawFotos = data["fotos"] ?? data["fotos_inicio"] ?? data["fotos_contenedor"] ?? data["evidencias"];
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
          
          setState(() {
            _yaRegistrado = reg;
            _fotosGuardadas = parsedFotos;
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
    } finally {
      if (mounted) {
        setState(() {
          _validandoEstatus = false;
        });
      }
    }

    if (!_yaRegistrado) {
      await _cargarBorradorLocal();
    }
  }

  Future<void> _pickGalleryImages() async {
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
      final pickedFiles = await _picker.pickMultiImage(
        maxWidth: 1280,
        maxHeight: 720,
        imageQuality: 70,
      );
      if (pickedFiles.isNotEmpty) {
        setState(() {
          final spaceLeft = 10 - _photos.length;
          if (pickedFiles.length > spaceLeft) {
            _photos.addAll(pickedFiles.take(spaceLeft));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Solo se agregaron las fotos necesarias para completar el límite de 10"),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            _photos.addAll(pickedFiles);
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error al seleccionar fotos de galería: $e")),
      );
    }
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

    await _guardarBorradorLocal();

    try {
      final response = await ApiService.post(
        ApiEndpoints.iniciarViaje,
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
                "No se pudo contactar al servidor debido a la señal débil o falta de internet en carretera.",
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
              Navigator.pop(context); // SOLO cierra diálogo, NO sale de la pantalla
            },
            child: const Text("Conservar fotos"),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _iniciarViaje(); // Reintentar
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

            if (_validandoEstatus)
              Card(
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
            else if (_yaRegistrado)
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Fotos Registradas:",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            if (_fotosGuardadas.length > 1)
                              TextButton.icon(
                                icon: const Icon(Icons.download_for_offline, size: 18),
                                label: const Text("Descargar todas", style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  final List<String> urls = _fotosGuardadas.map((url) => _buildImageUrl(url)).toList();
                                  FileDownloader.downloadAllFiles(
                                    context: context,
                                    urls: urls,
                                    prefix: "carga_contenedor_${_idAsignacion ?? 'viaje'}",
                                  );
                                },
                              ),
                          ],
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
                            final rawUrl = _fotosGuardadas[index];
                            final imageUrl = _buildImageUrl(rawUrl);
                            return Stack(
                              children: [
                                Positioned.fill(
                                  child: InkWell(
                                    onTap: () {
                                      if (imageUrl.isNotEmpty) {
                                        _descargarYVerArchivo(
                                          context,
                                          imageUrl,
                                          "carga_contenedor_${index + 1}.jpg",
                                        );
                                      }
                                    },
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        imageUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (c, o, s) => Container(
                                          color: Colors.grey.shade300,
                                          child: const Icon(Icons.broken_image, color: Colors.grey),
                                        ),
                                      ),
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
                                      icon: const Icon(Icons.download, color: Colors.white, size: 18),
                                      onPressed: () {
                                        if (imageUrl.isNotEmpty) {
                                          FileDownloader.downloadFile(
                                            context: context,
                                            url: imageUrl,
                                            fileName: "carga_contenedor_${index + 1}.jpg",
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
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
                        onTap: _pickGalleryImages,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.shade800, width: 1.5),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.blue.shade50,
                          ),
                          child: Icon(Icons.add_photo_alternate, color: Colors.blue.shade800, size: 30),
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
                  onTap: _pickGalleryImages,
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
                        Icon(Icons.photo_library, size: 40, color: Colors.blue.shade700),
                        const SizedBox(height: 10),
                        Text(
                          "Presiona aquí para seleccionar fotos de la galería",
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "(Toma las fotos con tu cámara y selecciónalas aquí)",
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
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
