---
name: sdd-spec
description: Procedimiento para crear especificaciones funcionales móviles bajo la metodología Spec-Driven Development (SDD) en la app del Operador SGTSITA.
---

# Procedimiento de Spec-Driven Development (Mobile)

Utiliza este procedimiento cuando se solicite desarrollar una nueva pantalla, flujo del chofer o servicio nativo (ej: firma digital, checklist fuera de línea, o reporte de incidencias mecánicas).

## Paso 1: Analizar el Impacto en el Dispositivo y en el Backend
- ¿Requiere hardware nativo (Cámara, GPS, Notificaciones, Almacenamiento local)?
- ¿Requiere un endpoint nuevo o existente en `SGTSITA`?
- ¿Cómo se comportará si el operador no tiene conexión en carretera?

## Paso 2: Crear el archivo en `specs/`
- Asignar número correlativo (ej: `specs/001-inspeccion-mecanica-checklist.spec.md`).
- Utilizar la plantilla `specs/template.spec.md`.

## Paso 3: Criterios de Aceptación (DoD)
- Detallar los 4 estados de la pantalla (Loading, Empty, Success, Error).
- Especificar el comportamiento ante permisos denegados (GPS desactivado o cámara denegada).
- Definir la estructura exacta del JSON enviado y recibido desde el backend SGTSITA.

## Paso 4: Implementación
- Crear o actualizar widgets, modelos Dart, servicios y endpoints.
