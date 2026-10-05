# AGENTS.md — Operador App (SGTSITA Mobile)

Aplicación móvil multiplataforma en Flutter para operadores de transporte de carga pesada y viajes de contenedores SGT. Conectada a la API REST de SGTSITA.

## Stack y estructura
- Flutter 3.x, Dart (SDK ^3.8.1), Android & iOS.
- `lib/endpoints/api_endpoints.dart`: catálogo centralizado de rutas del backend SGTSITA.
- `lib/api/api_service.dart`: cliente HTTP con soporte para token Bearer y subida multipart.
- `lib/screens/`: pantallas de interfaz de usuario.
- `lib/services/`: servicios de geolocalización GPS, notificaciones y almacenamiento local.
- `docs/constitution.md`: 6 principios innegociables de estabilidad móvil y resiliencia en carretera.
- `MEMORY.md`: memoria viva del proyecto entre sesiones.
- `specs/`: especificaciones funcionales móviles bajo metodología SDD.

## Comandos
- Iniciar en emulador / dispositivo: `flutter run`
- Análisis estático de código: `flutter analyze`
- Pruebas unitarias: `flutter test`
- Obtener dependencias: `flutter pub get`

## Convenciones
- Constructores `const` para optimizar el árbol de renderizado de widgets.
- Validación de `if (!mounted) return;` en llamadas asíncronas con `BuildContext`.
- Manejo estricto de 4 estados visuales: Loading, Empty, Success y Error con botón de reintentar.

## Reglas de dominio / trampas conocidas
- Las carreteras tienen señal celular deficiente. Nunca lanzar peticiones HTTP sin envolverlas en `try / catch` (`SocketException`).
- Las evidencias fotográficas deben comprimirse a 75% de calidad (`imageQuality: 75`) antes de subirlas al servidor.
- Si la API responde HTTP 401 Unauthorized, limpiar la sesión y redirigir limpiamente a la pantalla de Login.

## Forma de trabajar
- Para nuevas pantallas o funciones: seguir el flujo SDD en `specs/NNN-nombre/` con `spec.md`, `plan.md` y `tasks.md`.
- No toques código hasta que el usuario apruebe la spec y el plan.

## Memoria
- Al empezar, lee `MEMORY.md` para conocer el estado del proyecto y las decisiones tomadas.
- Al terminar una tarea, actualízalo: estado actual, decisiones importantes (con su porqué) y errores a evitar.
- Mantenlo breve (máximo ~50 líneas): resume o elimina lo que ya no aporte.
- Si algo se convierte en una regla permanente, propón moverlo a `AGENTS.md` en lugar de dejarlo en la memoria.
- No guardes nunca tokens o contraseñas en la memoria.

## Límites
- ✅ Siempre: actualizar `MEMORY.md` al terminar cada tarea, comprimir fotos, validar `mounted`.
- ⚠️ Pregunta antes: agregar dependencias nativas a `pubspec.yaml` que requieran permisos especiales de Android/iOS.
- 🚫 Nunca: modificar URLs o firmas de payloads JSON sin confirmar sincronía con `SGTSITA/routes/api.php`.

## Verificación
- Ejecutar `flutter analyze` para garantizar que no existan advertencias ni errores de tipos o lint.
- Verificar el comportamiento visual en emulador Android o dispositivo físico.

## Reglas SDD
- Lee `docs/constitution.md` y la spec activa (`specs/NNN-*/`) antes de tocar código en nuevas funcionalidades.
