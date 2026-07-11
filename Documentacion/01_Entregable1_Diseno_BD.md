# Entregable 1 — Diseño de la Base de Datos

**Curso:** Base de Datos I — UNMSM FISI · **Fase:** I (Selección del caso de negocio y diseño)

Este documento cubre lo exigido por la directiva del proyecto para la Fase I: selección del caso
de negocio, documentación de requisitos, y modelo conceptual/lógico/físico. Los diagramas y el
DDL completo **no se repiten aquí**: se referencian directamente para evitar duplicidad entre el
documento y el código fuente de la base de datos.

---

## 1. Caso de negocio

**Sistema de Gestión de Reservas y Estadías para una Cadena Hotelera** (Hotel San Marcos, con
sedes en Lima, Ica, Arequipa y Cusco — ver `Scripts/08_Carga_Datos.sql`).

El sistema resuelve la necesidad operativa de una cadena de hoteles de coordinar, en una sola
base de datos compartida entre sedes:

- La reserva de habitaciones por distintos canales (directo, web, teléfono, agencia, OTA), con
  tarifas que varían según temporada y según si el cliente es un particular o una empresa con
  convenio corporativo.
- El registro real de la estadía (check-in/check-out), que no siempre coincide exactamente con lo
  reservado (habitación física asignada al momento, huéspedes que llegan después que el titular,
  acompañantes que se retiran antes que el resto).
- El consumo de servicios adicionales y los daños ocasionados durante la estadía, que se cobran al
  finalizar mediante una cuenta por cobrar independiente del pago del hospedaje (que se cobra por
  adelantado en la reserva).
- Reportes gerenciales de ocupación, ingresos y ranking de clientes para la toma de decisiones.

## 2. Requisitos

### 2.1 Requisitos funcionales

| # | Requisito |
|---|---|
| RF-01 | Registrar reservas con una o varias líneas de tipo de habitación (ej. 2 simples + 1 doble) y calcular el monto total automáticamente según tarifa vigente. |
| RF-02 | Autodetectar la tarifa pública vigente según la fecha de check-in (regular vs. temporada alta), permitiendo también indicar explícitamente una tarifa corporativa negociada. |
| RF-03 | Confirmar el pago de una reserva y pasarla al estado CONFIRMADA. |
| RF-04 | Pre-asignar huéspedes a una reserva corporativa antes del check-in, y poder comparar luego esa pre-asignación contra quién hizo el check-in real. |
| RF-05 | Registrar el check-in asignando una habitación física disponible, y agregar uno o más huéspedes (reales o "genéricos", cuando aún no se conoce el nombre). |
| RF-06 | Validar que no se exceda la capacidad máxima de huéspedes de una habitación. |
| RF-07 | Registrar consumos de servicios y daños durante la estadía. |
| RF-08 | Registrar la salida individual de un huésped (sin cerrar la habitación si quedan otros huéspedes presentes) y el check-out completo de la habitación. |
| RF-09 | Generar una cuenta por cobrar al finalizar la estadía, sumando consumos y daños pendientes, aplicando IGV (18 %). |
| RF-10 | Registrar pagos (totales o parciales/abonos) sobre una cuenta por cobrar y actualizar su saldo automáticamente. |
| RF-11 | Consultar disponibilidad real de habitaciones por tipo, hotel y rango de fechas (no solo el estado puntual de la habitación). |
| RF-12 | Generar reportes de ocupación, ingresos por hotel y ranking de clientes. |
| RF-13 | Mantener catálogos maestros (hoteles, tipos de habitación, habitaciones, servicios, planes tarifarios, tarifas, empleados). |
| RF-14 | Restringir las operaciones disponibles según el rol del usuario (recepción, caja, gerencia, administrador). |

### 2.2 Requisitos no funcionales

| # | Requisito |
|---|---|
| RNF-01 | Integridad referencial estricta (FK, `CHECK`, `UNIQUE`) definida a nivel de motor, no confiada a la aplicación. |
| RNF-02 | Toda regla de negocio (cálculo de precios, IGV, disponibilidad, capacidad, saldos) vive en la base de datos (funciones, procedimientos, triggers), no en el código de la aplicación — la interfaz solo invoca. |
| RNF-03 | Motor: MySQL 8.0+, charset `utf8mb4` para soporte completo de acentos y símbolos en español. |
| RNF-04 | Control de acceso por rol tanto a nivel de base de datos (`GRANT`/roles MySQL) como de aplicación (sesión por rol). |
| RNF-05 | La interfaz debe ser mínima pero con conectividad real y datos reales (no mockeados), priorizando velocidad de desarrollo sobre estética avanzada. |

## 3. Modelo conceptual

Ver `Diagramas/Diagrama de Base de Datos/01_Modelo_Conceptual.png` (fuente editable:
`01_Modelo_Conceptual.puml`).

Entidades principales y su razón de ser:

- **`persona`** (supertype) con subtipos **`persona_natural`** / **`persona_juridica`**: modela que
  quien reserva/factura puede ser una persona individual o una empresa, compartiendo atributos
  comunes (teléfono, email, ubigeo) pero con atributos propios de cada subtipo (DNI/RUC,
  nombres/razón social).
- **`cliente`**: quien reserva y paga — distinto de **`huesped`**, quien físicamente ocupa la
  habitación. Esta separación (decisión tomada tras la asesoría del profesor: *"cliente = quien
  paga/factura; huésped = quien duerme"*) permite modelar reservas corporativas donde la empresa
  paga pero sus empleados son quienes se hospedan.
- **`huesped`** admite un huésped **genérico** (`es_generico = 1`) como placeholder cuando se
  reserva sin conocer aún el nombre de todos los ocupantes.
- **`reserva`** → **`reserva_detalle`**: una reserva puede combinar varias líneas de tipo de
  habitación + plan tarifario + cantidad (ej. 2 simples + 1 doble en la misma reserva).
- **`detalle_huesped_reserva`**: pre-asignación de huéspedes a una línea de reserva, usada en el
  escenario corporativo, independiente del check-in real.
- **`alojamiento`** → **`huesped_alojamiento`**: la ocupación real de una habitación física, con
  salida individual por huésped (`fecha_salida_real`) distinta del checkout general de la
  habitación.
- **`consumo_servicio`**, **`danio`**, **`cuenta_cobrar`** → **`cuenta_cobrar_detalle`** →
  **`pago_cuenta_cobrar`**: ciclo de facturación posterior al hospedaje (que ya se pagó en la
  reserva), con abonos parciales registrados como historial, no solo un campo de saldo.

## 4. Modelo lógico

Ver `Diagramas/Diagrama de Base de Datos/02_Modelo_Logico.png` (fuente: `02_Modelo_Logico.puml`),
que corresponde 1:1 con `Scripts/01_Creacion_Tablas.sql` + `Scripts/02_Reglas_Integridad.sql`.

25 tablas, con tipos de dato, PK/FK y cardinalidades ya resueltas a nivel relacional. Puntos
destacables del esquema relacional:

- Todas las claves primarias son `INT AUTO_INCREMENT`, excepto `huesped_alojamiento` que usa clave
  compuesta (`id_alojamiento`, `id_huesped`) porque modela una relación N:M con atributos propios
  (`es_titular`, `fecha_salida_real`).
- `reserva.monto_total` y `reserva_detalle.subtotal`/`precio_unitario` se **congelan** al momento
  de crear la reserva (no se recalculan si la tarifa cambia después), preservando el histórico de
  lo efectivamente cobrado.
- `plan_tarifa.es_publico` distingue tarifas autodetectables por fecha (público) de tarifas
  negociadas que solo se aplican si el operador las elige explícitamente (corporativo).

## 5. Modelo físico

Ver `Diagramas/Diagrama de Base de Datos/03_Modelo_Fisico.png` (fuente: `03_Modelo_Fisico.puml`) y
el DDL ejecutable en `Scripts/01_Creacion_Tablas.sql` (creación) y `Scripts/02_Reglas_Integridad.sql`
(FK, `CHECK`, `UNIQUE`, índices).

Decisiones de implementación física en MySQL 8.0:

- Charset `utf8mb4` / collation `utf8mb4_spanish_ci` a nivel de base de datos completa.
- `ENUM` para dominios cerrados y estables (`estado` de reserva/habitación/alojamiento/daño/cuenta,
  `canal`, `metodo_pago`, `genero`, `tipo` de persona) en vez de tablas catálogo adicionales,
  cuando el dominio es fijo y no requiere atributos propios; se usan tablas catálogo
  (`estado_reserva`, `tipo_documento`, `cargo_empleado`) cuando el dominio sí necesita nombre
  descriptivo administrable sin migración de esquema.
- Claves foráneas declaradas explícitamente en `02_Reglas_Integridad.sql`, separadas del DDL base,
  para poder crear primero todas las tablas sin preocuparse por el orden de dependencias y luego
  cerrar la integridad referencial en un segundo paso auditable.
- No se implementó particionamiento ni tablespaces adicionales: el volumen de datos de un proyecto
  académico no lo justifica: la prioridad fue la integridad y la expresividad del modelo relacional
  sobre la optimización física a gran escala.

## 6. Referencias cruzadas

| Necesitas ver... | Dónde está |
|---|---|
| Casos de uso funcionales detallados (actor, flujo, procedimiento invocado) | `Especificacion_MVP.md` sección 4 |
| Diagrama de secuencia end-to-end | `Diagramas/04_Flujo_MVP_Secuencia.puml` / `.png` |
| DDL completo | `Scripts/01_Creacion_Tablas.sql` |
| Integridad referencial | `Scripts/02_Reglas_Integridad.sql` |
