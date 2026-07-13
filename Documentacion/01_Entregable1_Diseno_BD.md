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
| RF-05 | Registrar el check-in asignando una habitación física disponible, y agregar uno o más huéspedes ya identificados (la ocupación real nunca queda sin identidad completa; el "todavía no sé quién" solo existe antes del check-in, como cupo sin resolver en la pre-asignación). |
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
- **`cliente`**: quien reserva y paga — distinto de **huésped**, quien físicamente ocupa la
  habitación. Esta separación (decisión tomada tras la asesoría del profesor: *"cliente = quien
  paga/factura; huésped = quien duerme"*) permite modelar reservas corporativas donde la empresa
  paga pero sus empleados son quienes se hospedan. **"Huésped" es un rol, no una tabla**: no existe
  ninguna entidad `huesped` en el modelo actual (se eliminó, ver punto correspondiente en el modelo
  lógico) — `detalle_huesped_reserva.id_huesped` y `huesped_alojamiento.id_huesped` referencian
  directo a `persona_natural.id_persona`. La incertidumbre de "quién" en una reserva corporativa (N
  habitaciones reservadas sin saber aún quién las ocupará) vive en
  `detalle_huesped_reserva.id_huesped` (nulable = cupo sin identificar); por exigencia legal
  (registro de huéspedes, normativa MINCETUR) una ocupación real (`huesped_alojamiento`) nunca puede
  existir sin identidad completa, por eso ahí esa misma columna es `NOT NULL`.
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

27 tablas, con tipos de dato, PK/FK y cardinalidades ya resueltas a nivel relacional. Puntos
destacables del esquema relacional:

- Todas las claves primarias son `INT AUTO_INCREMENT`, excepto `huesped_alojamiento` que usa clave
  compuesta (`id_alojamiento`, `id_huesped`) porque modela una relación N:M con atributos propios
  (`es_titular`, `fecha_salida_real`), y `usuario`, que usa `id_empleado` como PK y FK a la vez
  (subtipo 1:1, mismo patrón que `persona_natural`/`persona_juridica`).
- `reserva.monto_total` y `reserva_detalle.subtotal`/`precio_unitario` se **congelan** al momento
  de crear la reserva (no se recalculan si la tarifa cambia después), preservando el histórico de
  lo efectivamente cobrado.
- `plan_tarifa.es_publico` distingue tarifas autodetectables por fecha (público) de tarifas
  negociadas que solo se aplican si el operador las elige explícitamente (corporativo).
- **`empleado` vs. `usuario`: identidad separada de autorización.** `empleado` es el registro de
  RR.HH. (siempre existe, nunca se borra, atado a un hotel). `usuario` es un subtipo opcional
  — no todo empleado necesita iniciar sesión — con las credenciales (`username`,
  `password_hash`), el rol (`RECEPCION`/`CAJA`/`GERENCIA`/`ADMINISTRADOR`) y el alcance
  (`id_hotel`, nulable: `NULL` solo tiene sentido para `ADMINISTRADOR` y significa "toda la
  cadena"). Se evaluó y descartó una tabla adicional de otorgamientos (`usuario_rol`, uno o más
  roles por empleado): ningún dato real del proyecto necesita que un mismo empleado tenga más de
  un rol a la vez, así que esa generalidad se descartó por el mismo motivo que ya se aplicó a
  `cargo_empleado` — no diseñar estructura para casos sin uso real (`cargo_empleado` incluye
  "Camarero/a", un valor que nunca se referencia en ninguna consulta ni lógica de negocio; sirve
  como recordatorio de no repetir el patrón). Mantener `usuario` como tabla aparte de `empleado`
  (en vez de agregarle columnas) sí se justifica técnicamente: distinto disparador de cambio
  (RR.HH. vs. seguridad), aislamiento de `password_hash` frente a consultas `SELECT *` sobre
  `empleado` (la app corre con `debug=True`, que expone variables locales en cualquier traceback
  no capturado), y ciclo de vida independiente (`empleado` nunca se borra por el historial que
  referencia; el acceso sí debe poder revocarse al instante).
- **La tabla `huesped` (rol puro sobre `persona_natural`, sin datos propios) se eliminó por
  completo — "huésped" es un rol, no una entidad.** Es la corrección más profunda del modelo,
  llegada en dos pasos:
  1. Primero, una auditoría de normalización agregó `huesped.id_persona` como vínculo *opcional* y
     dos triggers de sincronización para mantener las columnas duplicadas de `huesped` (nombres,
     documento, fecha de nacimiento, etc.) al día con `persona_natural` — una solución válida pero
     que atacaba el síntoma, no la causa: la duplicación seguía existiendo, solo quedaba
     sincronizada.
  2. Una segunda corrección de raíz, motivada por la misma regla de negocio (en una reserva
     corporativa la empresa reserva N habitaciones sin saber aún quién las ocupará — se conoce la
     cantidad, no las personas; los nombres se resuelven después, vía lista de la empresa o recién
     en el check-in), eliminó las columnas de `huesped` por completo y dejó `id_persona` **`NOT
     NULL`** referenciando **`persona_natural`** (no `persona`).
  3. **Corrección final:** con `huesped` reducida a una sola columna útil (`id_persona`) más una PK
     autoincremental que no aportaba nada, se eliminó la tabla entera. `detalle_huesped_reserva.
     id_huesped` y `huesped_alojamiento.id_huesped` pasaron a referenciar directo a
     `persona_natural.id_persona` (mismo nombre de columna, por continuidad con el código; el FK
     sigue garantizando a nivel de esquema que el ocupante sea siempre una persona natural). Este
     último paso no fue solo estético: la tabla `huesped` intermedia permitía que la misma
     `persona_natural` tuviera **varias filas de huésped simultáneas** (no llevaba `UNIQUE` sobre
     `id_persona`, a propósito, para que una persona pudiera volver a hospedarse y generar otra fila
     en otra estadía), y eso rompía en la práctica la regla de negocio "un huésped no puede estar en
     dos alojamientos activos a la vez" (`sp_agregar_huesped_alojamiento`): esa regla compara por id
     de huésped, así que con dos filas de huésped para la misma persona el chequeo no detectaba el
     choque — la misma persona física podía terminar, en teoría, hospedada en dos habitaciones a la
     vez. Al eliminar la tabla intermedia y usar `id_persona` directo, la identidad vuelve a ser
     única por definición y ese hueco se cierra sin necesitar ningún trigger ni `UNIQUE` adicional.
     La incertidumbre de "quién" se mantiene donde siempre vivió: `detalle_huesped_reserva.
     id_huesped` sigue siendo nulable (`trg_valida_cupos_reserva` limita el total de cupos —
     identificados o no — de una línea a `cantidad_habitaciones × capacidad_base`); en
     `huesped_alojamiento` sigue siendo `NOT NULL`, por exigencia legal (registro de huéspedes,
     normativa MINCETUR): una ocupación real nunca existe sin identidad completa. Esto también
     eliminó de raíz el antiguo "huésped genérico" (`es_generico`): la propia carga de datos ya
     demostraba que ese diseño no funcionaba en la práctica — la app prometía "se completa después"
     pero ningún código actualizaba jamás un huésped genérico con datos reales.
  **Nota:** los diagramas `Diagramas/Diagrama de Base de Datos/01_Modelo_Conceptual.puml`,
  `02_Modelo_Logico.puml` y `03_Modelo_Fisico.puml` (y sus PNG) ya se actualizaron para reflejar
  esto: `huesped` no aparece como entidad, y `detalle_huesped_reserva`/`huesped_alojamiento` se
  relacionan directo con `persona_natural`. De paso se agregó `auditoria` (no estaba en ningún
  diagrama) y el modelo físico ahora incluye las 27 tablas (antes omitía `ubigeo`,
  `cargo_empleado`, `persona`, `cliente`, `tipo_documento` y `plan_tarifa`).
- **Columna eliminada: `tarifa_habitacion.capacidad_maxima`.** La misma auditoría encontró que esta
  columna nunca se leía en ningún procedimiento/trigger/vista (la capacidad siempre se valida contra
  `tipo_habitacion.capacidad_base`) y en los datos de prueba siempre coincidía con ese valor — era
  redundancia sin ningún caso de uso real, no una regla de negocio. Se eliminó en vez de mantenerla
  sin sentido.
- **Reglas de negocio reforzadas a nivel de motor tras la auditoría de normalización:** además de
  los dos puntos anteriores, se agregaron triggers para que `reserva.monto_total` y
  `cuenta_cobrar.subtotal/total/saldo` nunca puedan desincronizarse de sus líneas de detalle (antes
  solo se mantenían por disciplina de los procedimientos, no por una regla que el motor garantizara
  ante un `INSERT`/`UPDATE`/`DELETE` directo), una restricción `UNIQUE(id_alojamiento)` en
  `cuenta_cobrar` más un guard en `sp_generar_cuenta_cobrar` para impedir doble facturación, un
  trigger que exige que el alcance de un `usuario` operativo coincida con el hotel donde trabaja su
  `empleado`, y `UNIQUE` faltantes en `cliente.id_persona`, `ubigeo.codigo`, `tipo_documento.nombre`
  y `detalle_huesped_reserva(id_detalle_reserva, id_huesped)`.

## 5. Modelo físico

Ver `Diagramas/Diagrama de Base de Datos/03_Modelo_Fisico.png` (fuente: `03_Modelo_Fisico.puml`) y
el DDL ejecutable en `Scripts/01_Creacion_Tablas.sql` (creación) y `Scripts/02_Reglas_Integridad.sql`
(FK, `CHECK`, `UNIQUE`, índices).

Decisiones de implementación física en MySQL 8.0:

- Charset `utf8mb4` / collation `utf8mb4_spanish_ci` a nivel de base de datos completa.
- `ENUM` para dominios cerrados y estables (`estado` de reserva/habitación/alojamiento/daño/cuenta,
  `canal`, `metodo_pago`, `genero`, `tipo` de persona) en vez de tablas catálogo adicionales,
  cuando el dominio es fijo y no requiere atributos propios; se usan tablas catálogo
  (`tipo_documento`, `cargo_empleado`, `categoria_servicio`) cuando el dominio sí necesita nombre
  descriptivo administrable sin migración de esquema. `reserva.estado` empezó como tabla catálogo
  (`estado_reserva`) y se corrigió a `ENUM` directo: el código ya la trataba como un enum de todos
  modos (comparaba `id_estado_reserva` contra literales numéricos con un comentario al lado, ej.
  `= 2 -- CONFIRMADA`, en vez de nombres legibles), y cada transición de estado ya requiere lógica
  de negocio propia en un procedimiento — "agregar un estado sin migración" nunca fue una ventaja
  real para este caso, a diferencia de un catálogo genuinamente abierto como `categoria_servicio`.
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
