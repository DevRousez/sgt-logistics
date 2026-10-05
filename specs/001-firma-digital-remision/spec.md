# Spec 001 — Módulo de Firma Digital del Cliente en Remisión (POD Digital)

Estado: borrador

## Contexto y objetivo
Al entregar un contenedor o carga en destino, el chofer requiere que el receptor/cliente firme directamente en la pantalla de la app móvil para confirmar la entrega y generar la remisión/carta porte firmada digitalmente.

## Usuarios / actores
- Operador / Chofer de tractocamión: Solicita la firma al cliente en destino.
- Cliente / Receptor en patio o bodega: Firma con el dedo o stylus en la pantalla del teléfono.
- Despachador de SGTSITA: Recibe la firma y el POD en tiempo real en la plataforma web.

## Requisitos funcionales (criterios de aceptación en EARS)
- RF-1: CUANDO el operador presiona "Finalizar Entrega", EL SISTEMA muestra un canvas de dibujo para capturar la firma digital del cliente.
- RF-2: SI el canvas de firma está vacío, ENTONCES EL SISTEMA deshabilita el botón de confirmar y muestra el mensaje "Se requiere la firma del receptor".
- RF-3: CUANDO el cliente firma y presiona confirmar, EL SISTEMA convierte el trazo en imagen PNG, adjunta nombre e identificación del receptor y envía la petición multipart a SGTSITA (`/api/operador/finalizar-viaje`).
- RF-4: SI no hay cobertura de internet en la bodega, ENTONCES EL SISTEMA almacena la firma localmente y muestra el aviso de "Entrega guardada, se sincronizará al recuperar señal".

## Criterios de finalización
- Pantalla de firma digital integrada con `Signature` o canvas nativo.
- Subida multipart al backend SGTSITA validada.
- Verificación con `flutter analyze` sin advertencias.
