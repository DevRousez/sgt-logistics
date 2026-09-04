import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '/utils/app_logger.dart';

class FileDownloader {
  static const MethodChannel _channel = MethodChannel('com.akdyasoft.operador_appsgt/media_store');

  /// Limpia nombres de archivo removiendo caracteres no permitidos en el sistema de archivos.
  static String sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  /// Detecta la extensión a partir de la URL eliminando parámetros de consulta.
  static String detectExtension(String url, {String defaultExt = 'jpg'}) {
    try {
      final clean = url.split('?').first.split('#').first.toLowerCase();
      if (clean.endsWith('.pdf')) return 'pdf';
      if (clean.endsWith('.xml')) return 'xml';
      if (clean.endsWith('.png')) return 'png';
      if (clean.endsWith('.jpg') || clean.endsWith('.jpeg')) return 'jpg';
      if (clean.endsWith('.webp')) return 'webp';
      if (clean.endsWith('.xlsx')) return 'xlsx';
      if (clean.endsWith('.xls')) return 'xls';
      if (clean.endsWith('.docx')) return 'docx';
      if (clean.endsWith('.doc')) return 'doc';
      if (clean.endsWith('.zip')) return 'zip';

      final lastDot = clean.lastIndexOf('.');
      if (lastDot != -1 && lastDot < clean.length - 1) {
        final ext = clean.substring(lastDot + 1);
        if (RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext)) {
          return ext;
        }
      }
    } catch (_) {}
    return defaultExt;
  }

  /// Verifica los bytes mágicos del contenido descargado para evitar archivos corruptos por extensión incorrecta.
  static String fixFileNameExtension(Uint8List bytes, String fileName) {
    String cleanName = sanitizeFileName(fileName);
    final dotIndex = cleanName.lastIndexOf('.');
    String baseName = dotIndex != -1 ? cleanName.substring(0, dotIndex) : cleanName;
    String currentExt = dotIndex != -1 ? cleanName.substring(dotIndex + 1).toLowerCase() : '';

    if (bytes.length >= 4) {
      // PDF: %PDF- (0x25 0x50 0x44 0x46)
      if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) {
        return '$baseName.pdf';
      }
      // PNG: \x89PNG (0x89 0x50 0x4E 0x47)
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        return '$baseName.png';
      }
      // JPEG: 0xFF 0xD8 0xFF
      if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return '$baseName.jpg';
      }
      // XML: <?xml o tags XML (con o sin UTF-8 BOM)
      int startIdx = 0;
      if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        startIdx = 3;
      }
      while (startIdx < bytes.length &&
          (bytes[startIdx] == 0x20 || bytes[startIdx] == 0x09 || bytes[startIdx] == 0x0A || bytes[startIdx] == 0x0D)) {
        startIdx++;
      }
      if (startIdx < bytes.length && bytes[startIdx] == 0x3C) {
        final sampleLen = (bytes.length - startIdx > 120) ? 120 : (bytes.length - startIdx);
        final sampleStr = utf8.decode(bytes.sublist(startIdx, startIdx + sampleLen), allowMalformed: true).toLowerCase();
        if (sampleStr.contains('<?xml') ||
            sampleStr.contains('<cfdi') ||
            sampleStr.contains('<comprobante') ||
            sampleStr.contains('<cartaporte') ||
            sampleStr.contains('<tfd:')) {
          return '$baseName.xml';
        }
      }
    }

    if (currentExt.isEmpty) {
      return '$baseName.pdf';
    }
    return cleanName;
  }

  /// Guarda el archivo mediante MediaStore en Android para garantizar compatibilidad con Scoped Storage
  /// y registrar el archivo de forma nativa en la carpeta pública Descargas/SGT.
  static Future<bool> _saveViaMediaStore(Uint8List bytes, String fileName, {String subDir = "SGT"}) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<String>('saveToDownloads', {
        'bytes': bytes,
        'fileName': fileName,
        'subDir': subDir,
      });
      AppLogger.logInfo("FileDownloader: Guardado en MediaStore exitosamente: $result");
      return result != null && result.isNotEmpty;
    } catch (e) {
      AppLogger.logInfo("FileDownloader: Fallback de MediaStore a almacenamiento directo: $e");
      return false;
    }
  }

  /// Intento secundario de escritura directa en el almacenamiento público
  static Future<File?> _saveToPublicStorage(Uint8List bytes, String fileName, {String subDir = "SGT"}) async {
    if (!Platform.isAndroid) return null;
    try {
      final dir = Directory('/storage/emulated/0/Download/$subDir');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      try {
        await _channel.invokeMethod('scanFile', {'path': file.path});
      } catch (_) {}
      return file;
    } catch (e) {
      AppLogger.logInfo("FileDownloader: No se pudo escribir en /storage/emulated/0/Download/$subDir: $e");
      return null;
    }
  }

  static Future<File> _saveToTemp(Uint8List bytes, String fileName) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<File?> downloadFile({
    required BuildContext context,
    required String url,
    required String fileName,
    bool silent = false,
  }) async {
    if (url.trim().isEmpty) return null;

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
        final Uri uri = Uri.parse(url.contains(' ') ? Uri.encodeFull(url) : url);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return null;
      }

      final uri = Uri.parse(url.contains(' ') ? Uri.encodeFull(url) : url);
      final response = await http.get(uri).timeout(const Duration(seconds: 35));
      if (response.statusCode != 200) {
        throw Exception("Error de servidor: HTTP ${response.statusCode}");
      }

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        throw Exception("El archivo descargado está vacío.");
      }

      final finalFileName = fixFileNameExtension(bytes, fileName);

      // 1. Guardar copia local en caché para visualización inmediata
      final tempFile = await _saveToTemp(bytes, finalFileName);

      // 2. En Android, guardar en Descargas/SGT vía MediaStore y almacenamiento público
      bool savedInPublic = false;
      if (Platform.isAndroid) {
        savedInPublic = await _saveViaMediaStore(bytes, finalFileName, subDir: "SGT");
        if (!savedInPublic) {
          final directFile = await _saveToPublicStorage(bytes, finalFileName, subDir: "SGT");
          savedInPublic = directFile != null;
        }
      }

      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              savedInPublic
                  ? "Guardado en Descargas: SGT/$finalFileName"
                  : "Descargado: $finalFileName",
            ),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: "VER",
              textColor: Colors.white,
              onPressed: () {
                OpenFilex.open(tempFile.path);
              },
            ),
          ),
        );
        // Abrir automáticamente el archivo si fue descarga individual
        await OpenFilex.open(tempFile.path);
      }

      return tempFile;
    } catch (e) {
      AppLogger.logInfo("FileDownloader: Error descargando $fileName desde $url: $e");
      if (!silent && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al descargar $fileName: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  static Future<int> downloadAllFiles({
    required BuildContext context,
    required List<String> urls,
    String? prefix,
    List<String>? fileNames,
  }) async {
    if (urls.isEmpty) return 0;

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Iniciando descarga de ${urls.length} archivos a Descargas/SGT..."),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 3),
        ),
      );
    }

    int count = 0;
    final List<XFile> savedFiles = [];

    for (int i = 0; i < urls.length; i++) {
      final url = urls[i];
      if (url.trim().isEmpty) continue;

      String resolvedName;
      if (fileNames != null && i < fileNames.length && fileNames[i].trim().isNotEmpty) {
        resolvedName = sanitizeFileName(fileNames[i].trim());
      } else {
        final ext = detectExtension(url);
        final p = prefix ?? "archivo";
        resolvedName = "${p}_${i + 1}.$ext";
      }

      final downloadedFile = await downloadFile(
        context: context,
        url: url,
        fileName: resolvedName,
        silent: true,
      );

      if (downloadedFile != null) {
        count++;
        savedFiles.add(XFile(downloadedFile.path));
      }
    }

    if (context.mounted) {
      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Se guardaron $count de ${urls.length} archivos en Descargas/SGT"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: "COMPARTIR",
              textColor: Colors.white,
              onPressed: () {
                SharePlus.instance.share(
                  ShareParams(
                    files: savedFiles,
                    text: "Documentos del Viaje SGT",
                  ),
                );
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No se pudo descargar ningún archivo. Verifique su conexión."),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }

    return count;
  }
}
