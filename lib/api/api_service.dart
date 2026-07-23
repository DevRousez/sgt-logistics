import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static String? token;
  static String? sessionType;

  static Future<void> setToken(String newToken, {String? type}) async {
    token = newToken;
    final prefs = await SharedPreferences.getInstance();
    if (newToken.isEmpty) {
      print("ApiService: Cleared session and user data");
      await prefs.remove('auth_token');
      await prefs.remove('session_type');
      await prefs.remove('user_data');
      sessionType = null;
    } else {
      print("ApiService: Saving auth_token=$newToken, type=$type");
      await prefs.setString('auth_token', newToken);
      if (type != null) {
        sessionType = type;
        await prefs.setString('session_type', type);
      }
    }
  }

  static Future<void> saveUserData(Map<dynamic, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    print("ApiService: Saving user data: $data");
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
    print("ApiService: Loaded session token=$token, type=$sessionType");
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

    print("=== ApiService GET Request ===");
    print("URL: $url");
    print("Headers: ${_headers()}");

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _headers(),
      ).timeout(const Duration(seconds: 30));

      print("=== ApiService GET Response ===");
      print("Status Code: ${response.statusCode}");
      print("Body: ${response.body}");
      return response;
    } catch (e) {
      print("=== ApiService GET Error ===");
      print("Error: $e");
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
      // Create a mutable copy of body to avoid modifying immutable inputs
      body = Map<String, dynamic>.from(body);
      body['id_empresa'] = selectedEmpresaId;
    }

    print("=== ApiService POST Request ===");
    print("URL: $url");
    print("Headers: ${_headers()}");
    print("Body: ${jsonEncode(body)}");

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: _headers(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));

      print("=== ApiService POST Response ===");
      print("Status Code: ${response.statusCode}");
      print("Body: ${response.body}");
      return response;
    } catch (e) {
      print("=== ApiService POST Error ===");
      print("Error: $e");
      rethrow;
    }
  }
}