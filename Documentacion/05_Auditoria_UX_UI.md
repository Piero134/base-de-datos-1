# Auditoría UX/UI — MVP Hotelero (`mvp_app`)

**Reporte completo e interactivo (recomendado):** https://claude.ai/code/artifact/9de33166-8c52-4b67-93f0-2dcab3eb6783

Este documento es el resumen ejecutivo versionado en el repositorio. El reporte interactivo
enlazado arriba tiene los 29 hallazgos completos con cita archivo:línea, comparativas de código
antes/después, y el detalle de cada una de las 14 dimensiones evaluadas.

## Metodología y calibración

Se auditaron las 32 plantillas Jinja, las 194 líneas de `mvp_app/app/static/style.css` y los 7
`routes.py` de los blueprints (auth, disponibilidad, reservas, estadía, caja, reportes,
administración), leyendo el código real — no se hicieron afirmaciones genéricas.

**Calibración deliberada:** el profesor del curso pidió explícitamente una interfaz mínima ("no tan
fina"), no un producto comercial pulido. Por eso toda recomendación de este informe es alcanzable
con HTML/CSS/Jinja + JavaScript vanilla mínimo, sin frameworks nuevos ni dependencias adicionales
al stack ya elegido.

## Puntuación final

| Categoría | Puntaje |
|---|---|
| Diseño visual | 6 / 10 |
| Usabilidad | 5 / 10 |
| Accesibilidad | 4 / 10 |
| Consistencia | 5 / 10 |
| Experiencia móvil | 2 / 10 |
| **Experiencia general** | **5 / 10** |

La paleta, tipografía y contraste de color son un punto fuerte confirmado (todas las combinaciones
auditadas pasan WCAG AA). El problema es estructural: pérdida de datos de formulario ante errores,
accesibilidad de teclado/lectores de pantalla incompleta, y cero soporte responsive.

## Hallazgos de mayor impacto (top 8 de 29)

| # | Hallazgo | Dimensión | Prioridad |
|---|---|---|---|
| 1 | Errores de negocio (`SIGNAL`) vacían el formulario completo en casi todos los `POST`, excepto en `disponibilidad/routes.py` (el único patrón correcto) | Flujo / fricción | Alta |
| 2 | `label for=` sin `id` correspondiente en ~90% de los formularios (única excepción: `auth/login.html`) | Accesibilidad | Alta |
| 3 | Cero `<meta viewport>` y cero media queries en todo el CSS → no usable en móvil | Responsive | Alta |
| 4 | Ninguna de las ~20 tablas usa `<thead>`/`<tbody>` | Accesibilidad | Alta |
| 5 | 13 de 14 listados no manejan el estado vacío (sin mensaje "no hay datos") | Estados de UI | Alta |
| 6 | Sin indicador de "sección activa" en el menú ni breadcrumbs (CSS ya definido, sin usar) | Navegación | Alta |
| 7 | Confirmación de acciones sensibles: solo 1 de ≥5 casos (pago, checkout, cambio de estado) | Flujo / estados | Alta |
| 8 | Nombres de procedimientos/vistas SQL filtrados en títulos y botones de cara al usuario | Jerarquía visual | Alta |

## Quick Wins (sin dependencias nuevas)

1. Agregar `id` a cada control con `label for=` (~1–2 h).
2. Envolver encabezados de tabla en `<thead>`/cuerpo en `<tbody>` (~30 min).
3. Agregar `<meta name="viewport">` (~2 min).
4. Aplicar la clase `.badge` (ya definida, sin uso) a las columnas de estado (~1 h).
5. Mensaje de "no hay datos" en los 13 listados que faltan (~1 h).
6. Deshabilitar el botón de envío al hacer submit, anti doble-clic (~20 min).
7. Envolver cada tabla en un contenedor `overflow-x:auto` (~30 min).
8. Retirar nombres de SP/vistas de títulos y botones visibles (~45 min).

## Plan de rediseño por fases

1. **Crítico — no perder datos del usuario:** sticky-form en errores de negocio, `label`/`id`
   correctos, viewport + semántica de tabla, foco de teclado visible, `?next=` en el login forzado.
2. **Consistencia de componentes:** badges de estado, `.page-header`/breadcrumb en todas las
   pantallas, un solo patrón de filtrado, confirmación consistente de acciones sensibles, retirar
   nombres de SP/vistas de la UI.
3. **Responsive básico:** media queries para el grid de KPIs y el nav, scroll horizontal en
   tablas, menú compacto para el rol Administrador en móvil.
4. **Opcional (solo si el proyecto trasciende el curso):** modo oscuro (los tokens CSS ya están
   listos), `<dialog>` nativo en vez de `confirm()`, iconografía mínima inline.

Ver el reporte interactivo para el detalle completo de cada hallazgo, ejemplos de código y las 14
dimensiones evaluadas en profundidad.
