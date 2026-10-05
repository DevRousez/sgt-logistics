# [APP-SPEC-XXX] Título de la Especificación Móvil

## 1. Taxonomía de la Especificación
- **ID:** APP-SPEC-XXX
- **Módulo:** (Viajes / Apertura Contenedor / Telemetría GPS / Evidencias / Viáticos / Cliente)
- **Tipo:** Feature / UI Polish / Bugfix / Refactor
- **Plataformas Afectadas:** Android / iOS / Ambas
- **Prioridad:** Alta / Media / Baja
- **Endpoint(s) de SGTSITA Asociado(s):** `/api/operador/...`

---

## 2. Descripción de la Funcionalidad y Flujo del Chofer
> Explica qué acción realiza el operador en carretera o patio aduanal y qué problema resuelve esta pantalla/componente.

---

## 3. Criterios de Aceptación (Definition of Done - DoD)
- [ ] **Escenario 1 (Flujo Exitoso con Conexión):**
  - **Dado:** El operador con sesión activa y permisos de ubicación concedidos.
  - **Cuando:** Presiona el botón de acción y envía los datos requeridos.
  - **Entonces:** La app muestra indicador de carga, envía la petición al backend SGTSITA, recibe HTTP 200 y actualiza el estado localmente.
- [ ] **Escenario 2 (Falta de Conexión / Carretera sin Señal):**
  - **Dado:** El operador se encuentra en una zona sin cobertura celular.
  - **Cuando:** Intenta enviar la acción o capturar la evidencia.
  - **Entonces:** La app NO se congela ni crashea; muestra un mensaje amigable indicando que no hay conexión y permite reintentar o almacenar localmente.
- [ ] **Escenario 3 (Permisos Denegados):**
  - **Dado:** El usuario tiene apagado el GPS o bloqueó el permiso de la cámara.
  - **Cuando:** Ingresa a la pantalla correspondiente.
  - **Entonces:** Se muestra un diálogo informativo explicativo con opción para abrir la configuración del sistema.

---

## 4. Impacto Técnico y Componentes Móviles
- **Pantallas y Widgets:**
  - [ ] Nueva Pantalla: `lib/screens/xxx_screen.dart`
  - [ ] Widgets Reutilizables: `lib/widgets/...`
- **Capa de Red & Endpoints:**
  - [ ] Endpoint registrado en: `lib/endpoints/api_endpoints.dart`
  - [ ] Método en: `lib/api/api_service.dart`
- **Almacenamiento Local / Estado:**
  - [ ] Clave nueva en: `SharedPreferences` (si aplica)
- **Permisos Nativos Requeridos:**
  - [ ] `AndroidManifest.xml` / `Info.plist` (Ubicación / Cámara / Almacenamiento)

---

## 5. Plan de Ejecución (Tareas Atómicas)
- [ ] 1. Registrar endpoint en `ApiEndpoints` y verificar contra SGTSITA backend.
- [ ] 2. Crear método en `ApiService` con manejo de excepciones `SocketException` y `TimeoutException`.
- [ ] 3. Diseñar pantalla con constructores `const` y separación de widgets.
- [ ] 4. Implementar los 4 estados visuales (Loading, Empty, Success, Error).
- [ ] 5. Probar con emulador / dispositivo y verificar criterios de aceptación.
