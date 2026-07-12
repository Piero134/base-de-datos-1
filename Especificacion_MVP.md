# Especificación del MVP — Sistema de Gestión de Reservas y Estadías para Cadena Hotelera

## 1. Objetivo y alcance del MVP

Según lo indicado por el profesor en la asesoría: **"el proyecto final no va a ser la aplicación al 100% desarrollada, sino centrarnos en cómo hacer un MVP que use todas las consultas que estamos viendo"**, y su exigencia explícita fue: *"la aplicación tiene que ser la interfase... puede no estar construida en un milímetro, no tan fino, pero sí tiene que haber conectividad a la base de datos, tiene que haber usado una serie de instrucciones SQL"*.

Esto fija el criterio de éxito del MVP: **no es una app pulida visualmente, es una interfaz mínima pero funcional que demuestre, con datos reales, el uso de las 27 tablas, funciones, procedimientos, vistas, triggers y roles ya construidos** (`01_Creacion_Tablas.sql` → `09_Consultas_MVP.sql`).

### Qué SÍ entra en el MVP
- Una interfaz (web, escritorio o incluso consola con menú) con conectividad real a `hotel_db`.
- Un flujo completo y ejecutable de principio a fin: reserva → pago → check-in → consumo/daño → check-out → cuenta por cobrar → pago.
- Pantallas/comandos que ejecuten explícitamente los procedimientos, funciones y vistas ya creados (no reimplementar la lógica de negocio en el frontend).
- Reportes básicos para gerencia (ocupación, ingresos, ranking de clientes).

### Qué NO entra en el MVP (explícitamente fuera de alcance)
- Diseño visual elaborado, responsive design, identidad de marca.
- Pasarela de pago real (se simula el registro del pago, no se integra Visa/Culqi/etc.).
- Notificaciones por correo/SMS, app móvil, multi-idioma.
- Módulo de facturación electrónica SUNAT (se calcula IGV, pero no se emite comprobante real).
- Autenticación robusta *(nota: se implementó de todas formas — login real con usuario/contraseña
  respaldado por la tabla `usuario`, ver sección 2 — porque terminó siendo una mejora de bajo costo
  una vez que se necesitó distinguir administrador general de administrador por hotel; sigue sin
  ser el foco del MVP: no hay recuperación de contraseña, 2FA, ni sesiones persistentes más allá de
  la cookie de Flask)*.

---

## 2. Actores del sistema

Estos actores ya están modelados como roles de base de datos en `07_Roles_Permisos.sql`. El login
real (tabla `usuario`, ver `Documentacion/01_Entregable1_Diseno_BD.md` sección 4) determina el rol
y el alcance de cada sesión — el rol de `usuario.rol` no es un valor libre, es el que quedó
asignado a ese empleado:

| Actor | Rol de BD | Qué hace en el MVP |
|---|---|---|
| **Recepcionista** | `rol_recepcion` | Reservas, check-in, check-out, pre-asignación corporativa, consulta de disponibilidad |
| **Cajero/a** | `rol_caja` | Consumos, daños, cuentas por cobrar, pagos |
| **Gerente** | `rol_gerencia` | Solo lectura: reportes de ocupación, ingresos, ranking |
| **Administrador (general)** | `rol_administrador` | `usuario.id_hotel = NULL`: crea/edita hoteles de toda la cadena y gestiona empleados/habitaciones de cualquiera |
| **Administrador (por hotel)** | `rol_administrador` | `usuario.id_hotel` = un hotel: mantenimiento de catálogos (tipos de habitación, tarifas, servicios, empleados, habitaciones) solo de su propio hotel; no puede crear ni editar hoteles |

---

## 3. Módulos funcionales

```
┌─────────────────────────────────────────────────────────────┐
│                      MVP — Menú Principal                    │
├───────────────┬───────────────┬───────────────┬─────────────┤
│  1. Reservas  │ 2. Estadía    │  3. Caja       │ 4. Reportes │
│               │  (check-in/   │  (consumos,    │ (gerencia)  │
│               │   check-out)  │   daños, pagos)│             │
├───────────────┴───────────────┴───────────────┴─────────────┤
│              5. Administración (catálogos, empleados)        │
└─────────────────────────────────────────────────────────────┘
```

---

## 4. Casos de uso detallados

### UC-01: Registrar reserva
- **Actor:** Recepcionista
- **Precondición:** el hotel, tipo de habitación y (opcionalmente) el plan tarifario ya existen.
- **Flujo principal:**
  1. El recepcionista ingresa: cliente (o lo crea si es nuevo), hotel, canal, fecha check-in/checkout, fecha límite de pago.
  2. El sistema llama `sp_registrar_reserva(...)` → obtiene `id_reserva`.
  3. Por cada tipo de habitación solicitado, el sistema llama `sp_agregar_detalle_reserva(id_reserva, tipo, plan, cantidad)`.
     - Si el plan no se especifica, `fn_plan_vigente()` lo autodetecta por fecha.
     - Internamente se valida disponibilidad real con `fn_disponibilidad_tipo_habitacion()`.
  4. El sistema muestra el `monto_total` calculado.
- **Flujo alterno:** si no hay disponibilidad o no hay tarifa vigente, el procedimiento lanza `SIGNAL` con mensaje de error, que la interfaz debe mostrar tal cual (no debe intentar "adivinar" un precio).
- **Postcondición:** reserva creada en estado `PENDIENTE`, sin habitación física asignada aún.
- **Consulta MVP relacionada:** `09_Consultas_MVP.sql` #1b, #1c, #2.

### UC-02: Confirmar pago de reserva
- **Actor:** Recepcionista o Caja
- **Flujo principal:** el sistema llama `sp_confirmar_pago(id_reserva)`; la reserva pasa a `CONFIRMADA`.
- **Postcondición:** `reserva.pagado = 1`, `fecha_pago` registrada. A partir de aquí, `sp_agregar_detalle_reserva` rechaza cualquier intento de agregar una línea nueva a esta reserva (una reserva pagada ya no cambia de alcance).
- **Consulta relacionada:** vista `vw_reservas_detalle` filtrando `pagado = 0` (reservas pendientes de pago, útil también para mostrar el caso contrario ya resuelto).

### UC-03: Asignar huéspedes a una reserva
- **Actor:** Recepcionista
- **Precondición:** reserva con detalle ya creado. Aplica a toda reserva (natural o corporativa), no solo a las de cliente `JURIDICA`.
- **Flujo principal:**
  1. Por cada línea de la reserva (tipo de habitación x cantidad), el sistema la subdivide en
     habitaciones de `capacidad_base` cupos cada una (cálculo en Python —
     `app/asignacion_huespedes.py:construir_grid_reserva` —, no persistido: se ordena por
     `id_detalle_huesped` y se agrupa de `capacidad_base` en `capacidad_base`).
  2. El recepcionista edita, en una sola tabla, todos los cupos de una línea a la vez: asigna un
     huésped a cada cupo (o lo deja vacío/sin identificar) y marca un titular por habitación.
  3. Al guardar (una línea completa por envío), el sistema valida que **cada habitación con al
     menos un huésped tenga exactamente un titular marcado**; si falta, rechaza el guardado
     completo de esa línea sin persistir nada. Si pasa la validación, inserta/actualiza
     `detalle_huesped_reserva` dentro de una única transacción.
- **Flujo alterno:** una habitación que ya tiene check-in (existe un `alojamiento` para ese cupo)
  se muestra de solo lectura — sus huéspedes ya no se editan desde esta pantalla.
- **Postcondición:** asignación (identificada o no) registrada en `detalle_huesped_reserva`,
  disponible para comparar luego contra el check-in real.
- **Consulta relacionada:** `vw_preasignacion_vs_checkin`.

### UC-04: Realizar check-in
- **Actor:** Recepcionista
- **Precondición:** reserva `CONFIRMADA`; la habitación (grupo de cupos dentro de una línea, ver
  UC-03) ya tiene su titular asignado; habitación física sin ocupación activa (ver nota de
  disponibilidad más abajo).
- **Flujo principal:** el check-in es individual por huésped (igual que la salida en UC-07), no por
  habitación completa, y el titular debe ser el primero en hacerlo (fuerza que la habitación "se
  abra" con quien realmente responde por ella). Por cada huésped ya asignado en UC-03 y todavía sin
  check-in:
  - Si es el primero de esa habitación (todavía no existe `alojamiento` para ese grupo de cupos):
    solo el titular puede iniciarlo (se rechaza si se intenta con cualquier otro huésped, incluso
    vía POST directo). El recepcionista elige la habitación física, y
    `app/db.py:call_procedures_en_transaccion` orquesta, en una sola transacción,
    `sp_realizar_checkin(id_reserva, id_detalle_reserva, id_habitacion, id_empleado)` →
    `id_alojamiento`, seguido de `sp_agregar_huesped_alojamiento(id_alojamiento, id_huesped,
    es_titular, id_detalle_huesped)` para el titular. Si falla adjuntarlo (p.ej. porque ya está
    activo en otro alojamiento, ver UC-04b), se revierte todo: nunca queda un `alojamiento` creado
    sin ningún huésped.
  - Si la habitación ya tiene `alojamiento` (el titular ya hizo check-in): los demás huéspedes de esa
    habitación se registran uno a la vez llamando solo `sp_agregar_huesped_alojamiento(...)`, sin
    volver a elegir habitación.
- **Flujo alterno:** si se excede la capacidad del tipo de habitación, `trg_huesped_alojamiento_capacidad` rechaza la inserción. Si la habitación (grupo de cupos) todavía no tiene titular, la interfaz ni siquiera ofrece el botón de check-in para ninguno de sus huéspedes; si tiene titular pero la habitación no está abierta todavía, solo el titular ve el botón de check-in.
- **Nota:** los huéspedes de una reserva se administran únicamente desde la asignación (UC-03); la pantalla de check-in y la de estadía activa (UC-05 en adelante) ya no ofrecen ninguna forma de agregar un huésped nuevo o existente.
- **Nota de disponibilidad:** la habitación física ofrecida se calcula por ocupación real (¿existe un `alojamiento` `ACTIVO` en ella ahora mismo?), no por el campo cacheado `habitacion.estado` — ese campo (`RESERVADA`/`LIMPIEZA`) requiere una acción manual de un `ADMINISTRADOR` para liberarse y no siempre refleja si la habitación está realmente ocupada.
- **Postcondición:** al primer check-in de una habitación, esta pasa a `OCUPADA` (trigger `trg_alojamiento_checkin`); cada cupo individual queda de solo lectura en la pantalla de asignación (UC-03) apenas se registra su check-in, aunque sus compañeros de habitación todavía no lo hayan hecho.
- **Consulta relacionada:** `vw_alojamientos_activos`, `vw_preasignacion_vs_checkin`.

### UC-04b: Restricción — un huésped no puede estar en dos estadías activas
- **Regla de negocio:** `sp_agregar_huesped_alojamiento` rechaza asociar un huésped a un
  alojamiento si ese huésped ya figura en `huesped_alojamiento` de otro `alojamiento` con
  `estado = 'ACTIVO'`, incluso si el intento llega directo al check-in (UC-04) sin pasar por la
  interfaz.

### UC-05: Registrar consumo de servicio
- **Actor:** Cajero o Recepcionista
- **Flujo principal:** `sp_registrar_consumo(id_alojamiento, id_servicio, cantidad)` calcula el subtotal con el precio vigente del servicio.
- **Consulta relacionada:** `vw_consumos_alojamiento`.

### UC-06: Registrar daño
- **Actor:** Recepcionista o Camarero/a (vía recepción)
- **Flujo principal:** `sp_registrar_danio(id_alojamiento, descripcion, costo)`.
- **Consulta relacionada:** `vw_danios_pendientes`.

### UC-07: Registrar salida individual de huésped
- **Actor:** Recepcionista
- **Flujo principal:** `sp_registrar_salida_huesped(id_alojamiento, id_huesped, id_empleado)`.
- **Regla de negocio clave:** si es el último huésped pendiente, el propio procedimiento finaliza el alojamiento automáticamente; si no, la habitación sigue `ACTIVA`.
- **Consulta relacionada:** `vw_historial_estadias` (columna `fecha_salida_huesped`).

### UC-08: Realizar check-out (de toda la habitación)
- **Actor:** Recepcionista
- **Flujo principal:** `sp_realizar_checkout(id_alojamiento, id_empleado)`; cierra la salida de cualquier huésped pendiente y finaliza el alojamiento.
- **Postcondición:** habitación pasa a `LIMPIEZA`.
- **Consulta relacionada:** `vw_checkouts_pendientes`.

### UC-09: Generar cuenta por cobrar
- **Actor:** Cajero
- **Precondición:** alojamiento `FINALIZADO`.
- **Flujo principal:** `sp_generar_cuenta_cobrar(id_alojamiento, id_cuenta)` suma consumos + daños pendientes, aplica IGV 18%, genera detalle línea por línea.
- **Consulta relacionada:** `vw_cuenta_cobrar_resumen`, `cuenta_cobrar_detalle`.

### UC-10: Registrar pago de cuenta
- **Actor:** Cajero
- **Flujo principal:** `sp_registrar_pago_cuenta(id_cuenta, monto, metodo_pago, id_empleado)`.
- **Postcondición:** trigger `trg_cuenta_actualizar_saldo` recalcula el saldo; si llega a 0, la cuenta pasa a `PAGADA`.

### UC-11: Consultar disponibilidad de habitaciones
- **Actor:** Recepcionista (o el propio cliente vía un formulario simple)
- **Flujo principal:** para un hotel + tipo + rango de fechas, se llama `fn_disponibilidad_tipo_habitacion(...)`.
- **Consulta relacionada:** `vw_habitaciones_disponibles` (estado puntual) + la función (disponibilidad real por fecha).

### UC-12: Ver reportes gerenciales
- **Actor:** Gerente
- **Flujo principal:** pantallas de solo lectura sobre `vw_ingresos_por_hotel`, `vw_ranking_clientes`, `vw_ocupacion_hotel`, y `sp_resumen_ocupacion_hotel(id_hotel)`.

### UC-13: Mantenimiento de catálogos
- **Actor:** Administrador (general o por hotel, ver sección 2)
- **Flujo principal:** CRUD simple (INSERT/UPDATE) sobre `hotel`, `tipo_habitacion`, `habitacion`, `categoria_servicio`, `servicio`, `plan_tarifa`, `tarifa_habitacion`, `empleado`. No requiere procedimientos especiales; son operaciones directas de mantenimiento.
- **Alcance:** `tipo_habitacion`/`categoria_servicio`/`servicio`/`plan_tarifa`/`tarifa_habitacion`
  son catálogos de toda la cadena (sin `id_hotel`), así que cualquier administrador los gestiona
  igual. `hotel`, `habitacion` y `empleado` sí son propios de un hotel: solo el administrador
  general crea/edita hoteles y puede elegir cualquier hotel al gestionar empleados/habitaciones; un
  administrador de un solo hotel queda fijo al suyo.
- **Alta de hotel (solo administrador general):** crear un hotel encadena automáticamente un
  `empleado` (cargo "Administrador de Hotel") + `usuario` (con `rol='ADMINISTRADOR'`,
  `id_hotel` = el nuevo hotel, username generado del nombre del hotel y contraseña temporal
  aleatoria mostrada una sola vez) — el hotel queda usable desde el día uno sin depender de que
  alguien le cree un empleado manualmente después.

---

## 5. Flujo end-to-end (diagrama de secuencia)

Se adjunta `04_Flujo_MVP_Secuencia.puml` (validado con PlantUML), que recorre el ciclo completo: **reserva → confirmación de pago → check-in → consumo/daño → salida individual/check-out → cuenta por cobrar → pago**, mostrando exactamente qué procedimiento y qué trigger se dispara en cada paso. Es la demostración más importante para la sustentación, porque en una sola corrida evidencia el uso de procedimientos, funciones, triggers y vistas.

---

## 6. Stack tecnológico sugerido (para no sobredimensionar el esfuerzo)

Dado que el profesor fue explícito en que la interfaz "puede no estar tan fina", conviene priorizar velocidad de desarrollo sobre sofisticación. Alternativas razonables, de menor a mayor esfuerzo:

| Opción | Cuándo conviene |
|---|---|
| **Script de consola en Python (`mysql-connector-python`) con menú numerado** | Si el tiempo es muy limitado; demuestra conectividad y uso de SPs sin necesidad de frontend. |
| **App web simple (Flask/FastAPI + HTML básico, o PHP + mysqli)** | Balance razonable: se ve como "aplicación" real en la sustentación, sigue siendo rápida de construir. |
| **Streamlit (Python)** | Genera pantallas con tablas y formularios muy rápido, ideal para mostrar vistas/reportes sin escribir HTML/CSS. |

En cualquier caso, la interfaz debe limitarse a **llamar** los procedimientos/funciones/vistas ya creados (`CALL sp_...`, `SELECT ... FROM vw_...`) — no debe reimplementar reglas de negocio (cálculo de IGV, validación de capacidad, etc.) en el código de la aplicación, porque eso es precisamente lo que el curso evalúa que esté en la base de datos.

---

## 7. Mapeo explícito con la rúbrica de evaluación

| Criterio de la rúbrica | Cómo lo cubre este MVP |
|---|---|
| **1. Logro del producto planificado** | El flujo end-to-end completo (UC-01 a UC-10) funciona de principio a fin sobre datos reales cargados en `08_Carga_Datos.sql`. |
| **2. Aplicación de herramientas para su desarrollo** | Se usan explícitamente: tablas normalizadas, FK, CHECK, UNIQUE, funciones, procedimientos almacenados, vistas, triggers, roles — y una interfaz que los invoca directamente. |
| **3. Nivel de complejidad del proyecto (alcances)** | Supertype/subtype de persona, pre-asignación corporativa vs. check-in real, autodetección de tarifa por fecha, salida individual por huésped, cuentas con abonos parciales — casos que van más allá de un CRUD básico. |
| **4. Cumplimiento de tareas y avances por fase** | Los 9 scripts numerados corresponden 1:1 a las fases del curso (creación → integridad → funciones → procedimientos → vistas → triggers → roles → carga → consultas MVP). |
| **5. Presentación y exposición** | El diagrama de secuencia (`04_Flujo_MVP_Secuencia.puml`) sirve como guion de la demo en vivo: cada paso de la exposición corresponde a una línea del diagrama. |
| **6. Aportes, recomendaciones, experiencias** | Documentar en la sustentación las decisiones tomadas a partir de la asesoría del profesor (separación cliente/huésped, cupos sin identificar vs. ocupación real siempre identificada, stock por fecha vs. contador, plan público vs. corporativo) como "aportes" propios justificados. |
| **7. Respuestas a consultas finales** | Tener a la mano los `.sql` y los diagramas (conceptual/lógico/físico) para responder preguntas puntuales sobre cualquier tabla, procedimiento o regla de negocio durante la sustentación. |

---

## 8. Recomendación de orden de desarrollo del MVP

1. Login simple (determina el rol activo).
2. Pantalla de disponibilidad (UC-11) — es la más simple y ya usa una función.
3. Flujo de reserva completo (UC-01, UC-02, UC-03) — el más largo, hazlo primero por si toma más tiempo del previsto.
4. Flujo de estadía (UC-04 a UC-08).
5. Caja (UC-09, UC-10).
6. Reportes de gerencia (UC-12) — son solo `SELECT * FROM vw_...`, rápidos de armar al final.
7. Administración de catálogos (UC-13) — la de menor prioridad si el tiempo apremia, porque los datos de prueba ya cubren la demo.
