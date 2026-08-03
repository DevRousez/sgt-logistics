import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class FileDownloader {
  static Future<void> downloadFile({
    required BuildContext context,
    required String url,
    required String fileName,
    bool silent = false,
  }) async {
    if (!silent && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Descargando $fileName..."),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      if (kIsWeb) {
        final Uri uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception("Error de servidor: ${response.statusCode}");
      }

      final bytes = response.bodyBytes;

      if (Platform.isAndroid) {
        try {
          final dir = Directory('/storage/emulated/0/Download/SGT');
          if (!await dir.exists()) {
            await dir.create(recursive: true);
          }
          final file = File('${dir.path}/$fileName');
          await file.writeAsBytes(bytes);
          
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Guardado en carpeta Descargas: SGT/$fileName"),
                backgroundColor: Colors.green,
                action: SnackBarAction(
                  label: "VER",
                  textColor: Colors.white,
                  onPressed: () {
                    OpenFilex.open(file.path);
                  },
                ),
              ),
            );
          }
        } catch (e) {
          // Fallback to temp
          await _saveToTempAndOpen(bytes, fileName, context, silent);
        }
      } else {
        // iOS / other
        await _saveToTempAndOpen(bytes, fileName, context, silent);
      }
    } catch (e) {
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No se pudo guardar localmente. Abriendo enlace..."),
            backgroundColor: Colors.orange,
          ),
        );
      }
      try {
        final Uri uri = Uri.parse(url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (err) {
        if (!silent && context.mounted) {
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

  static Future<void> _saveToTempAndOpen(
    Uint8List bytes,
    String fileName,
    BuildContext context,
    bool silent,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    if (!silent) {
      await OpenFilex.open(file.path);
    }
  }

  static Future<void> downloadAllFiles({
    required BuildContext context,
    required List<String> urls,
    required String prefix,
  }) async {
    if (urls.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Descargando ${urls.length} archivos..."),
        backgroundColor: Colors.blue,
      ),
    );

    int count = 0;
    for (int i = 0; i < urls.length; i++) {
      final ext = urls[i].toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final fileName = "${prefix}_${i + 1}.$ext";
      try {
        await downloadFile(
          context: context,
          url: urls[i],
          fileName: fileName,
          silent: true,
        );
        count++;
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Se descargaron $count de ${urls.length} archivos con éxito."),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
