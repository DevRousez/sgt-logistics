# Reglas de Telemetría GPS, Cámara y Resiliencia Offline (operador_appsgt)

## 1. Geolocalización y Telemetría en Ruta (`geolocator`)
- **Permisos de Ubicación:** Comprobar siempre `Geolocator.checkPermission()` y `Geolocator.isLocationServiceEnabled()` antes de solicitar coordenadas.
- **Eficiencia Energética:**
  - En paradas prolongadas o viajes inactivos, reducir la frecuencia de muestreo de GPS.
  - Usar una precisión balanceada (`LocationAccuracy.high` en movimiento, no necesariamente `bestForNavigation` salvo que sea estricto para no agotar la batería del teléfono).
- **Manejo de Errores de GPS:** Si el operador apaga el GPS del dispositivo, mostrar una alerta no bloqueante solicitando encenderlo para no detener la aplicación.

## 2. Captura y Compresión de Evidencias (`image_picker`)
- Los operadores toman fotos de sellos de contenedor, placas, llantas y remisiones en condiciones de poca luz o intemperie.
- **Regla de Compresión Obligatoria:**
  ```dart
  final XFile? photo = await picker.pickImage(
    source: ImageSource.camera,
    imageQuality: 75,      // Calidad balanceada
    maxWidth: 1600,        // Evita imágenes gigantes de 4000x3000
    maxHeight: 1600,
  );
  ```
- No almacenar fotos temporales indefinidamente; limpiar archivos residuales para evitar saturar el almacenamiento del dispositivo.
