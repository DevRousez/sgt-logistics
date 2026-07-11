import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static String baseUrl = "https://sgt.gologipro.com/api";

  static Future<void> loadConfig() async {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_api_host', host);
    if (host.startsWith('http://') || host.startsWith('https://')) {
      baseUrl = "$host/api";
    } else {
      baseUrl = "http://$host/api";
    }
  }
}