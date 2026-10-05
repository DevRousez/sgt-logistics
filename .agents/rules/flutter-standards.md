# Estándares de Código Flutter & Dart (operador_appsgt)

## 1. Calidad de Widgets y Rendimiento
- **Uso de Constructores `const`:** Declarar widgets estáticos con `const` para prevenir reconstrucciones innecesarias en el árbol de renderizado.
- **Descomposición:** Si un widget supera las 150 líneas en su método `build()`, extraer sub-widgets en clases privadas o archivos en `lib/widgets/`.
- **Async Gaps (`mounted` check):**
  - Todo bloque asíncrono que use `Navigator`, `ScaffoldMessenger` o `showDialog` debe validar:
    ```dart
    final result = await apiService.enviarDatos();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(...);
    ```

## 2. Gestión de Estados y Peticiones HTTP
- Separar la lógica de negocio y llamadas a API (`lib/api/` y `lib/services/`) de la presentación en pantalla (`lib/screens/`).
- Las pantallas deben manejar siempre 4 estados visuales claros:
  1. **Inicial / Vacío**
  2. **Cargando (`CircularProgressIndicator`)**
  3. **Éxito (Renderizado de datos)**
  4. **Error (Mensaje comprensible con botón de reintentar)**

## 3. Manejo de Excepciones
- Nunca silenciar excepciones con bloques `catch (e) {}` vacíos.
- Capturar tipos específicos:
  - `SocketException`: Sin conexión a internet.
  - `TimeoutException`: El servidor tardó demasiado en responder.
  - `FormatException`: La API retornó un JSON inesperado o malformado.
