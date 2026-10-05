# MEMORY.md — Operador App (SGTSITA Mobile)

Memoria del proyecto entre sesiones. Máximo ~50 líneas: resume o elimina lo que ya no aporte.

## Estado actual
- Aplicación móvil multiplataforma para choferes de contenedores y operaciones en ruta.
- Módulos activos: Login con token Bearer, Asignación de viajes, Checklist/Apertura de contenedor, Telemetría GPS en tiempo real (`geolocator`), Captura de evidencias fotográficas (`image_picker`) y Registro de viáticos/gastos.
- Backend vinculado: API REST de SGTSITA (`ApiConfig.baseUrl` -> `https://demo.gologipro.com/api`).
- Stack: Flutter 3.x + Dart SDK ^3.8.1 + Android / iOS.

## Decisiones (y por qué)
- Centralización de rutas en `lib/endpoints/api_endpoints.dart`: evita URLs quemadas y facilita cambios de host.
- Compresión de fotos (`imageQuality: 75`): evita agotar el plan de datos del operador y reduce tiempos de subida en carretera.
- Tolerancia a fallos de red: toda llamada HTTP maneja `SocketException` y `TimeoutException` sin crashear.

## Aprendizajes y errores a evitar
- NUNCA modificar la estructura de endpoints sin coordinar con `SGTSITA/routes/api.php`.
- Siempre verificar `if (!mounted) return;` antes de usar `BuildContext` tras llamadas asíncronas.

## Próximos pasos
- [ ] Spec 001: Módulo de Firma Digital del Cliente en Remisión / Carta Porte (POD Digital).
- [ ] Almacenamiento local temporal de coordenadas GPS cuando no haya cobertura celular.
