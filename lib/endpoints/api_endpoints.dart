import '/config/api_config.dart';

class ApiEndpoints {
  static String get login => "${ApiConfig.baseUrl}/login";

  static String get cotizaciones => "${ApiConfig.baseUrl}/dashboard/cotizaciones";
  static String get viajes => "${ApiConfig.baseUrl}/dashboard/viajes";
  static String get contenedores => "${ApiConfig.baseUrl}/dashboard/contenedores";
  static String get operaciones => "${ApiConfig.baseUrl}/dashboard/operacion-activa";
  static String get monitoreo => "${ApiConfig.baseUrl}/dashboard/monitoreo";
  static String get planeacion => "${ApiConfig.baseUrl}/dashboard/planeacion";
  static String get reportes => "${ApiConfig.baseUrl}/dashboard/reportes";
  static String get empresasPropias => "${ApiConfig.baseUrl}/dashboard/empresas-propias";
  static String get documentosEmpresasContenedores =>
      "${ApiConfig.baseUrl}/documentos-empresas/contenedores";

  static String get infoViaje => "${ApiConfig.baseUrl}/dashboard/info-viaje";
  static String get finalizarViaje => "${ApiConfig.baseUrl}/dashboard/finalizar-viaje";
  static String get iniciarViaje => "${ApiConfig.baseUrl}/operador/iniciar-viaje";
  static String get aperturaContenedor => "${ApiConfig.baseUrl}/operador/apertura-contenedor";
  static String get estatusFlujo => "${ApiConfig.baseUrl}/operador/estatus-flujo";
  static String get guardarCoordenadas => "${ApiConfig.baseUrl}/operador/coordenadas";
  static String get finalizarViajeOperador => "${ApiConfig.baseUrl}/operador/finalizar-viaje";
  static String get checkAsignacion => "${ApiConfig.baseUrl}/operador/check-asignacion";
  static String get aceptarAsignacion => "${ApiConfig.baseUrl}/operador/aceptar-asignacion";
  static String get historialOperador => "${ApiConfig.baseUrl}/operador/historial";
  static String get viajesPendientesLiquidar => "${ApiConfig.baseUrl}/operador/viajes-pendientes-liquidar";
  static String get registrarGastosViaje => "${ApiConfig.baseUrl}/operador/registrar-gastos-viaje";
  static String get obtenerGastosViaje => "${ApiConfig.baseUrl}/operador/obtener-gastos-viaje";
  static String get eliminarGastoViaje => "${ApiConfig.baseUrl}/operador/eliminar-gasto-viaje";
  static String get notificationConfig => "${ApiConfig.baseUrl}/operador/notification-config";
  static String get reporteViaticosPdf => "${ApiConfig.baseUrl}/operador/reporte-viaticos-pdf";
  static String get appVersionCheck => "${ApiConfig.baseUrl}/app/version-check";
  static String get appLogs => "${ApiConfig.baseUrl}/app-logs";

  // Módulo Cliente
  static String get clienteOperaciones => "${ApiConfig.baseUrl}/dashboard/cliente-operaciones";
  static String get clienteInfoViaje => "${ApiConfig.baseUrl}/dashboard/cliente-info-viaje";
  static String get clienteEvidenciasDocumentos => "${ApiConfig.baseUrl}/dashboard/cliente-evidencias-documentos";
}