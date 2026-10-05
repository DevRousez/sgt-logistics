---
name: endpoint-sync
description: Protocolo para auditar, sincronizar y crear endpoints en la app Flutter alineados con el backend Laravel de SGTSITA.
---

# Procedimiento de Sincronización de Endpoints con SGTSITA

Utiliza este procedimiento cuando se agregue una nueva función en la app que requiera consumir datos de SGTSITA o cuando se actualice una ruta del backend.

## 1. Verificación en el Backend SGTSITA
1. Abrir `C:\Users\carlo\Documents\desarrollo\JoseMXN\SGTSITA\routes\api.php`.
2. Verificar el método HTTP (`GET`, `POST`, `PUT`, `DELETE`).
3. Verificar si la ruta requiere middleware de autenticación (`auth:sanctum`).
4. Revisar el FormRequest asociado para conocer los campos exactos requeridos (nombres en snake_case, tipos de datos, archivos multipart).

## 2. Actualización en Flutter (`operador_appsgt`)
1. Registrar el getter en `lib/endpoints/api_endpoints.dart`:
   ```dart
   static String get nuevaRuta => "${ApiConfig.baseUrl}/operador/nueva-ruta";
   ```
2. Crear o actualizar el método correspondiente en `lib/api/api_service.dart`.
3. Manejar siempre el token de autenticación desde `SharedPreferences`:
   ```dart
   final prefs = await SharedPreferences.getInstance();
   final token = prefs.getString('auth_token');
   ```
4. Procesar el JSON recibido y capturar posibles errores HTTP (422, 500, 401).
