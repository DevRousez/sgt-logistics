# Reglas de Alineación de API con el Backend SGTSITA (Laravel)

## 1. Centralización de Endpoints
- Queda prohibido escribir URLs quemadas en pantallas o widgets (`http.get('https://...')`).
- Toda URL debe registrarse y consumirse desde `lib/endpoints/api_endpoints.dart`.
- La URL base se administra a través de `lib/config/api_config.dart`.

## 2. Autenticación con Token Bearer
- Todas las peticiones autenticadas deben adjuntar el header estándar:
  ```dart
  'Authorization': 'Bearer $token',
  'Accept': 'application/json',
  ```
- Si la respuesta del backend de SGTSITA es HTTP 401 Unauthorized:
  - Limpiar el token de `SharedPreferences`.
  - Redirigir al usuario al Login sin permitir acciones adicionales.

## 3. Subida Multipart de Evidencias y Gastos
- Para subir tickets de viáticos y fotos de contenedores, utilizar `http.MultipartRequest('POST', Uri.parse(...))`.
- Añadir campos de texto con `request.fields['...']` y archivos con `http.MultipartFile.fromPath(...)`.
- Validar siempre que el backend responda con JSON y código HTTP 200/201 antes de marcar la evidencia como subida.
