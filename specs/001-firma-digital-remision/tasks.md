# Tareas — Spec 001: Firma Digital del Cliente (POD)

- [ ] **T1. Diseñar el widget modal de captura de firma con canvas.** RF-1, RF-2
  - Hecho cuando: El usuario pueda trazar su firma en pantalla, borrar y validar que no esté vacío.
- [ ] **T2. Implementar servicio de conversión a PNG y almacenamiento temporal.** RF-3
  - Hecho cuando: Se exporte la imagen con fondo transparente/blanco optimizado en disco.
- [ ] **T3. Conectar envío multipart en `ApiService` con manejo offline.** RF-3, RF-4
  - Hecho cuando: La llamada HTTP funcione con conexión y encole la firma si no hay señal.
- [ ] **T4. Integrar en pantalla de viaje y validar con `flutter analyze`.** RF-1, RF-3
  - Hecho cuando: El flujo completo desde la pantalla de viaje funcione y no haya advertencias en el análisis.
