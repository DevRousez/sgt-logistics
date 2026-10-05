# Constitución — Operador App (SGTSITA Mobile)

Principios innegociables. Toda spec, plan y tarea debe cumplirlos.

1. **Cero Crashes y Manejo Seguro de Red**: toda petición HTTP debe estar envuelta en manejo de excepciones (`SocketException`, `TimeoutException`). La app nunca debe cerrarse inesperadamente en carretera.
2. **Resiliencia ante Desconexión**: los flujos deben tolerar la falta de cobertura celular en carretera y patios de contenedores sin bloquear al chofer.
3. **Contratos de API Centralizados y Sagrados**: prohibido quemar URLs en pantallas; toda ruta debe consumirse a través de `lib/endpoints/api_endpoints.dart` alineado con SGTSITA.
4. **Optimización de Batería y Datos**: fotos de evidencias siempre comprimidas (máx 1600px / 75% calidad); GPS balanceado para no agotar la batería del teléfono.
5. **La spec manda**: toda nueva pantalla o función se especifica en `specs/NNN-*/spec.md` con notación EARS y manejo de 4 estados visuales (Loading, Empty, Success, Error).
6. **Verificación como Puerta**: comprobar sintaxis y análisis estático con `flutter analyze` y pruebas en emulador o dispositivo antes de cerrar tareas.
