import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../endpoints/api_endpoints.dart';

class UpdateChecker {
  /// Versión actual compilada en esta App Móvil
  static const String currentVersion = "1.0.3";
  static const int currentBuildNumber = 3;

  static bool _dialogShown = false;

  /// Consulta el endpoint `/api/app/version-check` y muestra un diálogo de actualización si hay una versión superior disponible.
  static Future<void> check(BuildContext context) async {
    if (_dialogShown) return;

    try {
      final response = await http.get(
        Uri.parse(ApiEndpoints.appVersionCheck),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final String latestVersion = data['latest_version']?.toString() ?? currentVersion;
          final int latestBuild = int.tryParse(data['build_number']?.toString() ?? '') ?? currentBuildNumber;
          final bool forceUpdate = data['force_update'] == true || data['force_update'] == 1 || data['force_update'] == '1';
          final String apkUrl = data['apk_url']?.toString() ?? '';
          final String releaseNotes = data['release_notes']?.toString() ?? '';

          if (latestBuild > currentBuildNumber || _isVersionHigher(latestVersion, currentVersion)) {
            _dialogShown = true;
            if (context.mounted) {
              _showUpdateDialog(
                context,
                version: latestVersion,
                apkUrl: apkUrl,
                notes: releaseNotes,
                forceUpdate: forceUpdate,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error checking app version update: $e");
    }
  }

  static bool _isVersionHigher(String latest, String current) {
    try {
      List<int> latestParts = latest.split('.').map((e) => int.parse(e.trim())).toList();
      List<int> currentParts = current.split('.').map((e) => int.parse(e.trim())).toList();

      for (int i = 0; i < latestParts.length && i < currentParts.length; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (_) {
      return false;
    }
  }

  static void _showUpdateDialog(
    BuildContext context, {
    required String version,
    required String apkUrl,
    required String notes,
    required bool forceUpdate,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !forceUpdate,
      builder: (context) {
        return PopScope(
          canPop: !forceUpdate,
          child: _UpdateDialogWidget(
            version: version,
            apkUrl: apkUrl,
            notes: notes,
            forceUpdate: forceUpdate,
          ),
        );
      },
    );
  }
}

class _UpdateDialogWidget extends StatefulWidget {
  final String version;
  final String apkUrl;
  final String notes;
  final bool forceUpdate;

  const _UpdateDialogWidget({
    required this.version,
    required this.apkUrl,
    required this.notes,
    required this.forceUpdate,
  });

  @override
  State<_UpdateDialogWidget> createState() => _UpdateDialogWidgetState();
}

enum _UpdateStatus { idle, downloading, completed, error }

class _UpdateDialogWidgetState extends State<_UpdateDialogWidget> {
  _UpdateStatus _status = _UpdateStatus.idle;
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String _errorMessage = '';
  String? _downloadedFilePath;

  Future<void> _startDownloadAndInstall() async {
    if (widget.apkUrl.isEmpty) {
      setState(() {
        _status = _UpdateStatus.error;
        _errorMessage = 'URL de actualización no válida.';
      });
      return;
    }

    setState(() {
      _status = _UpdateStatus.downloading;
      _progress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
      _errorMessage = '';
    });

    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(widget.apkUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      _totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final apkFile = File('${tempDir.path}/sgt_logistics_v${widget.version}.apk');

      final sink = apkFile.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        _downloadedBytes += chunk.length;
        if (mounted && _totalBytes > 0) {
          setState(() {
            _progress = _downloadedBytes / _totalBytes;
          });
        }
      }

      await sink.flush();
      await sink.close();
      client.close();

      _downloadedFilePath = apkFile.path;

      if (mounted) {
        setState(() {
          _status = _UpdateStatus.completed;
          _progress = 1.0;
        });
      }

      await _installApk(apkFile.path);
    } catch (e) {
      debugPrint("Error downloading APK: $e");
      if (mounted) {
        setState(() {
          _status = _UpdateStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _installApk(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      debugPrint("OpenFilex result: ${result.message} - type: ${result.type}");
      if (result.type != ResultType.done) {
        final Uri uri = Uri.parse(widget.apkUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint("Error launching installer: $e");
      final Uri uri = Uri.parse(widget.apkUrl);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatMB(int bytes) {
    if (bytes <= 0) return '0 MB';
    double mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            _status == _UpdateStatus.completed
                ? Icons.check_circle
                : (_status == _UpdateStatus.downloading
                    ? Icons.downloading
                    : Icons.system_update_alt),
            color: _status == _UpdateStatus.completed
                ? Colors.green
                : (_status == _UpdateStatus.downloading ? Colors.orange : Colors.blue),
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status == _UpdateStatus.downloading
                  ? "Descargando Actualización..."
                  : (_status == _UpdateStatus.completed
                      ? "¡Descarga Completa!"
                      : "Actualización v${widget.version}"),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status == _UpdateStatus.idle) ...[
              Text(
                "Hay una nueva versión (v${widget.version}) de SGT Logistics lista para actualizar.",
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              if (widget.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  "Novedades:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Text(
                    widget.notes,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ] else if (_status == _UpdateStatus.downloading) ...[
              const Text(
                "Descargando archivo APK de SGT Logistics...",
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
                backgroundColor: Colors.grey.shade200,
                color: Colors.blue.shade800,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "${(_progress * 100).toInt()}%",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _totalBytes > 0
                        ? "${_formatMB(_downloadedBytes)} / ${_formatMB(_totalBytes)}"
                        : _formatMB(_downloadedBytes),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ] else if (_status == _UpdateStatus.completed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified, color: Colors.green, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Descarga finalizada con éxito",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Iniciando el instalador de Android... Por favor presiona 'Instalar' o 'Actualizar' en la pantalla del sistema.",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Al concluir la instalación, abre la app SGT Logistics y verás reflejada la versión v${widget.version} en el inicio.",
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.black54),
              ),
            ] else if (_status == _UpdateStatus.error) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  "No se pudo descargar automáticamente: $_errorMessage",
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.forceUpdate && _status != _UpdateStatus.downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cerrar", style: TextStyle(color: Colors.grey)),
          ),
        if (_status == _UpdateStatus.idle)
          ElevatedButton.icon(
            onPressed: _startDownloadAndInstall,
            icon: const Icon(Icons.download, size: 18),
            label: const Text("Descargar e Instalar"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )
        else if (_status == _UpdateStatus.completed && _downloadedFilePath != null)
          ElevatedButton.icon(
            onPressed: () => _installApk(_downloadedFilePath!),
            icon: const Icon(Icons.system_update, size: 18),
            label: const Text("Reinstalar / Abrir"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          )
        else if (_status == _UpdateStatus.error)
          ElevatedButton.icon(
            onPressed: () async {
              final Uri uri = Uri.parse(widget.apkUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_browser, size: 18),
            label: const Text("Abrir en Navegador"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
      ],
    );
  }
}
