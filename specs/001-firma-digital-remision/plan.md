# Plan Técnico — Spec 001: Firma Digital del Cliente (POD)

Cubre: RF-1, RF-2, RF-3, RF-4.

## 1. Archivos y responsabilidades
- `lib/widgets/signature_pad_dialog.dart`: Diálogo modal con canvas interactivo para captura de trazo.
- `lib/services/pod_service.dart`: Conversión del trazo a archivo temporal PNG y guardado local seguro.
- `lib/api/api_service.dart`: Envío multipart de la firma y datos del receptor hacia `/api/operador/finalizar-viaje`.
- `lib/screens/viaje_detalle_screen.dart`: Integración del botón y flujo de confirmación de entrega.

## 2. Decisiones técnicas justificadas
- **Tolerancia a desconexión:** Si la llamada HTTP falla por `SocketException`, la firma se guarda en el directorio local de documentos con un flag de pendiente para reintento automático.
