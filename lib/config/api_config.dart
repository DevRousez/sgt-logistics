import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  // Define si la aplicación está en entorno de producción.
  // Si está en true, se oculta la configuración del host y se usa la URL de producción.
  static const bool isProduction = false;

  static String baseUrl = "https://demo.gologipro.com/api";

  static Future<void> loadConfig() async {
    if (isProduction) {
      baseUrl = "https://sgt.gologipro.com/api";
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('custom_api_host');
    if (savedIp != null && savedIp.isNotEmpty) {
      if (savedIp.startsWith('http://') || savedIp.startsWith('https://')) {
        baseUrl = "$savedIp/api";
      } else {
        baseUrl = "http://$savedIp/api";
      }
    }
  }

  static Future<void> saveConfig(String host) async {
    if (isProduction) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_api_host', host);
    if (host.startsWith('http://') || host.startsWith('https://')) {
      baseUrl = "$host/api";
    } else {
      baseUrl = "http://$host/api";
    }
  }
}