import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '/api/api_service.dart';
import '/endpoints/api_endpoints.dart';
import '/utils/app_logger.dart';

class OperadorSyncService {
  /// Sincroniza la información del viaje activo indicado por [activeIdBackend].
  /// Si se proporciona [checkData], intenta extraer datos previos de allí.
  /// Luego consulta estatusFlujo, viajesPendientesLiquidar e historial como fallbacks
  /// para garantizar que num_contenedor, unidad e IDs queden guardados en local.
  static Future<Map<String, dynamic>?> sincronizarViajeActivo(
    int activeIdBackend, {
    Map<String, dynamic>? checkData,
  }) async {
    try {
      AppLogger.logInfo("OperadorSyncService: Iniciando sincronización para viaje_activo_id=$activeIdBackend");

      String? numContenedor;
      String? unidad;
      String? idEquipo;
      dynamic idContenedor;
      dynamic cotizacionId;
      bool? viajeIniciado;
      bool? viajeFinalizado;
      bool? dieselRegistrado;

      // 1. Extraer lo disponible de checkData (ej: checkAsignacion)
      if (checkData != null) {
        final dynamic cand = checkData["viaje_activo"] ?? checkData["asignacion"] ?? checkData["data"];
        if (cand is Map) {
          numContenedor ??= _extractString(cand, ["num_contenedor", "numero_contenedor", "contenedor"]);
          unidad ??= _extractString(cand, ["camion", "unidad", "economico_camion", "numero_unidad"]);
          idEquipo ??= _extractString(cand, ["id_equipo", "equipo_id"]);
          idContenedor ??= cand["id_contenedor"] ?? cand["contenedor_id"];
        }
      }

      // 2. Consultar ApiEndpoints.estatusFlujo
      try {
        final flowResp = await ApiService.post(
          ApiEndpoints.estatusFlujo,
          {"id_asignacion": activeIdBackend},
        );
        if (flowResp.statusCode == 200) {
          final resData = jsonDecode(flowResp.body);
          if (resData["data"] != null && resData["data"] is Map) {
            final flow = resData["data"] as Map<String, dynamic>;
            if (flow["viaje_iniciado"] != null) {
              viajeIniciado = flow["viaje_iniciado"] == true;
            }
            if (flow["viaje_finalizado"] != null) {
              viajeFinalizado = flow["viaje_finalizado"] == true;
            }
            if (flow["diesel_registrado"] != null) {
              dieselRegistrado = flow["diesel_registrado"] == true;
            }

            numContenedor ??= _extractString(flow, ["num_contenedor", "numero_contenedor", "contenedor"]);
            unidad ??= _extractString(flow, ["unidad", "camion", "economico", "numero_unidad", "economico_camion"]);
            idEquipo ??= _extractString(flow, ["id_equipo", "equipo_id"]);
            idContenedor ??= flow["id_contenedor"] ?? flow["contenedor_id"] ?? (flow["contenedor"] is Map ? flow["contenedor"]["id"] : null);
            cotizacionId ??= flow["cotizacion_id"] ?? flow["id_cotizacion"];
          }
        }
      } catch (e) {
        AppLogger.logInfo("OperadorSyncService: Error consultando estatusFlujo: $e");
      }

      // 3. Si falta contenedor o unidad, consultar viajesPendientesLiquidar
      if (numContenedor == null || numContenedor.isEmpty || numContenedor == "N/A" ||
          unidad == null || unidad.isEmpty || unidad == "N/A") {
        try {
          final liquidarResp = await ApiService.get(ApiEndpoints.viajesPendientesLiquidar);
          if (liquidarResp.statusCode == 200) {
            final resData = jsonDecode(liquidarResp.body);
            if (resData["data"] != null && resData["data"] is List) {
              final list = resData["data"] as List;
              Map<String, dynamic>? matchingTrip;
              for (var item in list) {
                if (item is Map) {
                  final asigId = item["id_asignacion"]?.toString();
                  if (asigId == activeIdBackend.toString()) {
                    matchingTrip = Map<String, dynamic>.from(item);
                    break;
                  }
                }
              }

              // Si sólo hay 1 viaje pendiente, tomarlo como respaldo
              if (matchingTrip == null && list.length == 1 && list.first is Map) {
                matchingTrip = Map<String, dynamic>.from(list.first);
              }

              if (matchingTrip != null) {
                numContenedor ??= _extractString(matchingTrip, ["num_contenedor", "numero_contenedor", "contenedor"]);
                unidad ??= _extractString(matchingTrip, ["economico_camion", "camion", "unidad", "numero_unidad"]);
                idEquipo ??= _extractString(matchingTrip, ["id_equipo", "equipo_id"]);
                idContenedor ??= matchingTrip["id_contenedor"] ?? matchingTrip["contenedor_id"];
              }
            }
          }
        } catch (e) {
          AppLogger.logInfo("OperadorSyncService: Error consultando viajesPendientesLiquidar: $e");
        }
      }

      // 4. Si aún falta, consultar historial de este mes
      if (numContenedor == null || numContenedor.isEmpty || numContenedor == "N/A") {
        try {
          final now = DateTime.now();
          final startStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-01";
          final endStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
          final histResp = await ApiService.get("${ApiEndpoints.historialOperador}?fecha_inicio=$startStr&fecha_fin=$endStr");
          if (histResp.statusCode == 200) {
            final resData = jsonDecode(histResp.body);
            if (resData["data"] != null && resData["data"] is List) {
              for (var item in resData["data"]) {
                if (item is Map && item["id_asignacion"]?.toString() == activeIdBackend.toString()) {
                  numContenedor ??= item["num_contenedor"]?.toString();
                  unidad ??= item["camion"]?.toString() ?? item["unidad"]?.toString();
                  idEquipo ??= item["id_equipo"]?.toString();
                  idContenedor ??= item["id_contenedor"];
                  break;
                }
              }
            }
          }
        } catch (e) {
          AppLogger.logInfo("OperadorSyncService: Error consultando historial: $e");
        }
      }

      // 5. Guardar banderas locales de estatus en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      if (viajeIniciado != null) {
        await prefs.setBool('viaje_iniciado_$activeIdBackend', viajeIniciado);
      }
      if (viajeFinalizado != null) {
        await prefs.setBool('viaje_finalizado_$activeIdBackend', viajeFinalizado);
      }
      if (dieselRegistrado != null) {
        await prefs.setBool('diesel_registrado_$activeIdBackend', dieselRegistrado);
      }

      // 6. Guardar en userData
      final userData = await ApiService.getUserData() ?? {};
      userData["id_asignacion"] = activeIdBackend;
      if (numContenedor != null && numContenedor.isNotEmpty && numContenedor != "N/A") {
        userData["num_contenedor"] = numContenedor;
      }
      if (unidad != null && unidad.isNotEmpty && unidad != "N/A") {
        userData["unidad"] = unidad;
      }
      if (idEquipo != null && idEquipo.isNotEmpty && idEquipo != "N/A") {
        userData["id_equipo"] = idEquipo;
      }
      if (idContenedor != null) {
        userData["id_contenedor"] = idContenedor;
      }
      if (cotizacionId != null) {
        userData["cotizacion_id"] = cotizacionId;
      }

      await ApiService.saveUserData(userData);
      AppLogger.logInfo(
        "OperadorSyncService: Sincronización exitosa. Asignacion: $activeIdBackend, "
        "Contenedor: ${userData["num_contenedor"]}, Unidad: ${userData["unidad"]}",
      );
      return userData;
    } catch (e) {
      AppLogger.logInfo("OperadorSyncService: Error general en sincronizarViajeActivo: $e");
      return null;
    }
  }

  /// Verifica si la sesión actual carece de asignación o contenedor activo y,
  /// de ser necesario, consulta check-asignacion para recuperar el viaje activo del servidor.
  static Future<Map<String, dynamic>?> sincronizarSiEsNecesario({bool force = false}) async {
    try {
      final userData = await ApiService.getUserData();
      final dynamic asigIdRaw = userData?["id_asignacion"];
      final int? currentAsigId = asigIdRaw != null ? int.tryParse(asigIdRaw.toString()) : null;
      final String? currentNumCont = userData?["num_contenedor"]?.toString();
      final String? currentUnidad = userData?["unidad"]?.toString();

      final bool requiereSync = force ||
          currentAsigId == null ||
          currentNumCont == null ||
          currentNumCont.isEmpty ||
          currentNumCont == "N/A" ||
          currentUnidad == null ||
          currentUnidad.isEmpty ||
          currentUnidad == "N/A";

      if (!requiereSync) {
        return userData;
      }

      final response = await ApiService.get(ApiEndpoints.checkAsignacion);
      if (response.statusCode == 200) {
        final resData = jsonDecode(response.body);
        final dynamic activeIdRaw = resData["viaje_activo_id"];
        final int? activeIdBackend = activeIdRaw != null ? int.tryParse(activeIdRaw.toString()) : null;

        if (activeIdBackend != null && activeIdBackend > 0) {
          return await sincronizarViajeActivo(activeIdBackend, checkData: resData);
        } else if (currentAsigId != null && activeIdBackend == null) {
          // Viaje cancelado o concluido en web
          final data = userData ?? {};
          data["id_asignacion"] = null;
          data["num_contenedor"] = "N/A";
          data["unidad"] = "N/A";
          data["id_equipo"] = "N/A";
          await ApiService.saveUserData(data);
          return data;
        }
      }
      return userData;
    } catch (e) {
      AppLogger.logInfo("OperadorSyncService: Error en sincronizarSiEsNecesario: $e");
      return await ApiService.getUserData();
    }
  }

  static String? _extractString(Map map, List<String> candidateKeys) {
    for (var key in candidateKeys) {
      if (map.containsKey(key)) {
        final val = map[key];
        if (val == null) continue;
        if (val is String && val.trim().isNotEmpty && val.trim() != "N/A") {
          return val.trim();
        }
        if (val is num) {
          return val.toString();
        }
        if (val is Map) {
          final sub = _extractString(val, ["num_contenedor", "numero_contenedor", "numero", "numero_unidad", "nombre", "economico"]);
          if (sub != null) return sub;
        }
      }
    }
    return null;
  }
}
