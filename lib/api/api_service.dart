import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '/utils/app_logger.dart';

class ApiService {
  static String? token;
  static String? sessionType;

  static Future<void> setToken(String newToken, {String? type}) async {
    token = newToken;
    final prefs = await SharedPreferences.getInstance();
    if (newToken.isEmpty) {
      AppLogger.logInfo("ApiService: Cleared session and user data");
      await prefs.remove('auth_token');
      await prefs.remove('session_type');
      await prefs.remove('user_data');
      sessionType = null;
    } else {
      AppLogger.logInfo("ApiService: Saving auth_token (type=$type)");
      await prefs.setString('auth_token', newToken);
      if (type != null) {
        sessionType = type;
        await prefs.setString('session_type', type);
      }
    }
  }

  static Future<void> saveUserData(Map<dynamic, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(Map<String, dynamic>.from(data)));
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('user_data');
    if (dataStr != null) {
      return jsonDecode(dataStr) as Map<String, dynamic>;
    }
    return null;
  }

  static Future<void> initSession() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('auth_token');
    sessionType = prefs.getString('session_type');
    AppLogger.logInfo("ApiService: Loaded session token (type=$sessionType)");
  }

  static Map<String, String> _headers() {
    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  static Future<http.Response> get(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedEmpresaId = prefs.getInt('selected_empresa_id');
    if (selectedEmpresaId != null) {
      final uri = Uri.parse(url);
      final newQueryParams = Map<String, String>.from(uri.queryParameters);
      if (!newQueryParams.containsKey('id_empresa')) {
        newQueryParams['id_empresa'] = selectedEmpresaId.toString();
      }
      url = uri.replace(queryParameters: newQueryParams).toString();
    }

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _headers(),
      ).timeout(const Duration(seconds: 35));

      stopwatch.stop();
      AppLogger.logHttp(
        method: 'GET',
        url: url,
        statusCode: response.statusCode,
        error: response.statusCode >= 400 ? response.body : null,
        durationMs: stopwatch.elapsedMilliseconds,
        payloadBytes: response.bodyBytes.length,
      );

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.logHttp(
        method: 'GET',
        url: url,
        error: e,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      rethrow;
    }
  }

  static Future<http.Response> post(
    String url,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final selectedEmpresaId = prefs.getInt('selected_empresa_id');
    if (selectedEmpresaId != null && !body.containsKey('id_empresa')) {
      body = Map<String, dynamic>.from(body);
      body['id_empresa'] = selectedEmpresaId;
    }

    final stopwatch = Stopwatch()..start();
    final encodedBody = jsonEncode(body);
    final payloadSize = encodedBody.length;

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers(),
        body: encodedBody,
      ).timeout(const Duration(seconds: 45));

      stopwatch.stop();
      AppLogger.logHttp(
        method: 'POST',
        url: url,
        statusCode: response.statusCode,
        error: response.statusCode >= 400 ? response.body : null,
        durationMs: stopwatch.elapsedMilliseconds,
        payloadBytes: payloadSize,
      );

      return response;
    } catch (e) {
      stopwatch.stop();
      AppLogger.logHttp(
        method: 'POST',
        url: url,
        error: e,
        durationMs: stopwatch.elapsedMilliseconds,
        payloadBytes: payloadSize,
      );
      rethrow;
    }
  }
}