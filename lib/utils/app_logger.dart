import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '/endpoints/api_endpoints.dart';

class AppLogger {
  static File? _logFile;
  static const int _maxFileSizeBytes = 2 * 1024 * 1024; // 2MB max
  static bool _isSyncing = false;
  static final List<Map<String, dynamic>> _pendingSyncQueue = [];

  static Future<File> _getFile() async {
    if (_logFile != null) return _logFile!;
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/app_logs.log');
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }
    return _logFile!;
  }

  static Future<void> log(String level, String message, {dynamic error, StackTrace? stackTrace}) async {
    final now = DateTime.now().toIso8601String();
    final logLine = StringBuffer('[$now] [$level] $message\n');

    if (error != null) {
      logLine.writeln('  ERROR: $error');
    }
    if (stackTrace != null) {
      logLine.writeln('  STACK: $stackTrace');
    }

    final text = logLine.toString();
    if (kDebugMode) {
      print(text.trim());
    }

    try {
      final file = await _getFile();
      if (await file.exists()) {
        final length = await file.length();
        if (length > _maxFileSizeBytes) {
          final content = await file.readAsString();
          final lines = content.split('\n');
          final half = lines.sublist(lines.length ~/ 2).join('\n');
          await file.writeAsString(half);
        }
      }
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } catch (_) {}

    // Si es un error o advertencia, encolarlo para sincronización automática
    if (level == 'ERROR' || level == 'WARN' || (level == 'HTTP' && (message.contains('ERROR') || message.contains('STATUS: 4') || message.contains('STATUS: 5')))) {
      _enqueuePendingLog({
        'timestamp': now,
        'level': (level == 'HTTP' && (message.contains('STATUS: 4') || message.contains('STATUS: 5'))) ? 'ERROR' : level,
        'message': message,
        'error': error?.toString(),
      });
      _triggerBackgroundSync();
    }
  }

  static Future<void> _enqueuePendingLog(Map<String, dynamic> logEntry) async {
    _pendingSyncQueue.add(logEntry);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_app_logs_queue', jsonEncode(_pendingSyncQueue));
    } catch (_) {}
  }

  static Future<void> logHttp({
    required String method,
    required String url,
    int? statusCode,
    dynamic error,
    int? durationMs,
    int? payloadBytes,
  }) async {
    final statusStr = statusCode != null ? 'STATUS: $statusCode' : 'ERROR: $error';
    final durStr = durationMs != null ? '(${durationMs}ms)' : '';
    final sizeStr = payloadBytes != null ? '[${(payloadBytes / 1024).toStringAsFixed(1)} KB]' : '';
    final level = (statusCode != null && statusCode >= 400) ? 'ERROR' : 'HTTP';
    await log(level, '$method $url $durStr $sizeStr -> $statusStr', error: error);

    // Si la petición fue exitosa y tenemos logs pendientes, intentamos sincronizarlos
    if (statusCode != null && statusCode >= 200 && statusCode < 300) {
      _triggerBackgroundSync();
    }
  }

  static Future<void> logInfo(String message) => log('INFO', message);
  static Future<void> logWarn(String message) => log('WARN', message);
  static Future<void> logError(String message, [dynamic error, StackTrace? st]) => log('ERROR', message, error: error, stackTrace: st);

  static void _triggerBackgroundSync() {
    if (_isSyncing) return;
    _syncLogsToServer();
  }

  static Future<void> _syncLogsToServer() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Cargar cola persistente de disco si la memoria está vacía
      if (_pendingSyncQueue.isEmpty) {
        final savedQueueStr = prefs.getString('pending_app_logs_queue');
        if (savedQueueStr != null) {
          try {
            final list = jsonDecode(savedQueueStr) as List;
            _pendingSyncQueue.addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
          } catch (_) {}
        }
      }

      if (_pendingSyncQueue.isEmpty) {
        _isSyncing = false;
        return;
      }

      final userDataStr = prefs.getString('user_data');
      String usuarioInfo = "Desconocido";
      if (userDataStr != null) {
        try {
          final uMap = jsonDecode(userDataStr);
          usuarioInfo = "${uMap['name'] ?? uMap['email'] ?? uMap['usuario'] ?? 'Op'} (ID: ${uMap['id'] ?? '?'})";
        } catch (_) {}
      }

      final batch = List<Map<String, dynamic>>.from(_pendingSyncQueue);

      final response = await http.post(
        Uri.parse(ApiEndpoints.appLogs),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'usuario': usuarioInfo,
          'device': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'logs': batch,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Remover los enviados y actualizar disco
        _pendingSyncQueue.removeWhere((item) => batch.contains(item));
        await prefs.setString('pending_app_logs_queue', jsonEncode(_pendingSyncQueue));
      }
    } catch (_) {
      // Si falla por falta de internet, se queda en disco para el siguiente intento
    } finally {
      _isSyncing = false;
    }
  }

  static Future<String> getLogs({int maxLines = 200}) async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return "No hay registros disponibles.";
      final lines = await file.readAsLines();
      if (lines.length > maxLines) {
        return lines.sublist(lines.length - maxLines).join('\n');
      }
      return lines.join('\n');
    } catch (e) {
      return "Error al leer logs: $e";
    }
  }

  static Future<void> shareLogs() async {
    try {
      final file = await _getFile();
      if (await file.exists() && await file.length() > 0) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: "Registro de diagnóstico de la app SGT",
            subject: "Logs SGT App - ${DateTime.now().toIso8601String()}",
          ),
        );
      }
    } catch (_) {}
  }

  static Future<void> clearLogs() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.writeAsString('');
      }
      _pendingSyncQueue.clear();
    } catch (_) {}
  }
}
