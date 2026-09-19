import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../endpoints/api_endpoints.dart';

class UpdateChecker {
  /// Versión actual compilada en esta App Móvil
  static const String currentVersion = "1.0.0";
  static const int currentBuildNumber = 1;

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
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.system_update_alt, color: Colors.blue, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Actualización v$version Disponible",
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
                  const Text(
                    "Hay una nueva versión de la aplicación SGT Logistics lista para descargar.",
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                  if (notes.isNotEmpty) ...[
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
                        notes,
                        style: const TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (!forceUpdate)
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Ahora No", style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  if (apkUrl.isNotEmpty) {
                    try {
                      final Uri uri = Uri.parse(apkUrl);
                      bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
                      if (!launched) {
                        launched = await launchUrl(uri, mode: LaunchMode.platformDefault);
                      }
                      if (!launched && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("No se pudo abrir el enlace: $apkUrl")),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Error al abrir descarga: $e")),
                        );
                      }
                    }
                  }
                },
                icon: const Icon(Icons.download, size: 18),
                label: const Text("Descargar e Instalar"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
