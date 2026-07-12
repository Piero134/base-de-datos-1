# Entregable 2 — Implementación SQL, CRUD y Procedimientos Almacenados

**Curso:** Base de Datos I — UNMSM FISI · **Fase:** II (Implementación en el SGBD)

Este documento cataloga lo ya implementado en `Scripts/01_Creacion_Tablas.sql` →
`Scripts/09_Consultas_MVP.sql` y consumido por la aplicación en `mvp_app/`. No repite el código
fuente: indica **qué** existe, **para qué** y **dónde** verificarlo.

---

## 1. Motor y creación de la base de datos

MySQL 8.0+, `CREATE DATABASE hotel_db CHARACTER SET utf8mb4 COLLATE utf8mb4_spanish_ci`. Orden de
ejecución obligatorio (cada script depende del anterior):

| Orden | Script | Contenido |
|---|---|---|
| 1 | `01_Creacion_Tablas.sql` | `CREATE DATABASE`, `CREATE TABLE` de las 27 tablas (sin FK) |
| 2 | `02_Reglas_Integridad.sql` | `ALTER TABLE ... ADD CONSTRAINT` (FK, `CHECK`, `UNIQUE`) |
| 3 | `03_Funciones.sql` | 6 funciones (`CREATE FUNCTION`) |
| 4 | `04_Procedimientos.sql` | 14 procedimientos (`CREATE PROCEDURE`) |
| 5 | `05_Vistas.sql` | 14 vistas (`CREATE OR REPLACE VIEW`) |
| 6 | `06_Triggers.sql` | 23 triggers (`CREATE TRIGGER`) |
| 7 | `07_Roles_Permisos.sql` | 4 roles MySQL (`CREATE ROLE` + `GRANT`) |
| 8 | `08_Carga_Datos.sql` | Datos de prueba (`INSERT`) que recorren todos los escenarios |
| 9 | `09_Consultas_MVP.sql` | Consultas de demostración sobre vistas/funciones/procedimientos |

> `Scripts/10_Ejemplo_Flujo_Huespedes.sql` es opcional, fuera del pipeline obligatorio 01→09:
> demuestra el flujo completo de una reserva corporativa con cupos sin identificar
> (`detalle_huesped_reserva.id_huesped = NULL`), su resolución, una sustitución de último momento y
> el check-in final.

## 2. Operaciones CRUD

| Operación | Dónde vive | Ejemplo |
|---|---|---|
| **Create** con reglas de negocio | Procedimientos almacenados | `sp_registrar_reserva`, `sp_realizar_checkin`, `sp_generar_cuenta_cobrar` |
| **Create** de datos maestros (sin reglas de negocio) | `INSERT` directo desde la app, parametrizado | Alta de cliente/huésped (`mvp_app/app/reservas/routes.py`), catálogos (`mvp_app/app/administracion/routes.py`) |
| **Read** | Vistas (`SELECT * FROM vw_...`) y `SELECT` directos sobre catálogos | 14 vistas en `05_Vistas.sql` |
| **Update** con reglas de negocio | Procedimientos almacenados | `sp_confirmar_pago`, `sp_registrar_pago_cuenta`, `sp_cambiar_estado_habitacion` |
| **Update** de mantenimiento | `UPDATE` directo parametrizado | Edición de catálogos en `administracion/routes.py` |
| **Delete** | No se expone borrado físico en el MVP (los estados `CANCELADA`/`DISPENSADO`/`activo=0` modelan las "bajas lógicas") | `danio.estado = 'DISPENSADO'`, `hotel.activo`, `empleado.activo`, `huesped.activo` |

Toda operación que involucra una regla de negocio (cálculo de precio, IGV, validación de
disponibilidad/capacidad, actualización de saldo) pasa por un procedimiento o trigger — nunca se
reimplementa en la aplicación (ver `RNF-02` en el Entregable 1).

## 3. Cláusulas y funciones SQL avanzadas efectivamente usadas

Se listan solo las que están realmente presentes en el código (verificado por búsqueda directa en
los scripts, sin inventar cobertura):

| Cláusula/función | Dónde se usa (ejemplo real) |
|---|---|
| `JOIN` (múltiples por consulta) | Casi todas las 14 vistas de `05_Vistas.sql`; ej. `vw_alojamientos_activos` combina 6 tablas |
| `LEFT JOIN` | `vw_alojamientos_activos`, `vw_preasignacion_vs_checkin`, `vw_ingresos_por_hotel` |
| Subconsulta como tabla derivada (`LEFT JOIN (SELECT ...) x ON ...`) | `vw_ingresos_por_hotel` (`05_Vistas.sql:197`), para sumar consumos por reserva |
| `GROUP BY` | `sp_resumen_ocupacion_hotel` (`04_Procedimientos.sql:503`), `vw_ingresos_por_hotel`, `vw_ranking_clientes`, `vw_ocupacion_hotel` |
| `ORDER BY` (multi-columna) | `fn_plan_vigente` (para elegir el plan más específico) y en casi todas las consultas de `09_Consultas_MVP.sql` |
| Funciones agregadas `SUM`, `COUNT`, `AVG`/`MAX`/`MIN` | `SUM` en `vw_ingresos_por_hotel`/`vw_ranking_clientes`/procedimientos de cuenta; `COUNT`/`COUNT(DISTINCT ...)` en `fn_disponibilidad_tipo_habitacion`, `vw_ingresos_por_hotel`, `sp_resumen_ocupacion_hotel` |
| Función de ventana `RANK() OVER (ORDER BY ...)` | `vw_ranking_clientes` (`05_Vistas.sql:217`), ranking de clientes por monto gastado |
| `DISTINCT` / `COUNT(DISTINCT ...)` | `fn_disponibilidad_tipo_habitacion`, `vw_ingresos_por_hotel` |
| `CASE`/`IF` condicional en `SELECT` | `IF(ha.es_titular, 'SÍ', 'NO')` en varias vistas; `IF(fn_saldo_cuenta(...) <= 0, 'PAGADA', 'PENDIENTE')` en `trg_cuenta_actualizar_saldo` |
| `SIGNAL SQLSTATE` para errores de negocio | Los 14 procedimientos y varios triggers (ver sección 5) |
| Fechas: `DATEDIFF`, `BETWEEN`, `TIMESTAMPDIFF` | `fn_calcular_noches`, `fn_plan_vigente`, `fn_calcular_edad`, `vw_historial_estadias` |

> Nota de transparencia: no se usa `HAVING` en el proyecto actual (los filtros de agregación que se
> necesitaron se resolvieron con `WHERE` antes de agrupar, ej. `WHERE d.estado = 'PENDIENTE'` en
> `vw_danios_pendientes`); no se afirma su uso donde no existe.

## 4. Catálogo de funciones (6)

| Función | Propósito |
|---|---|
| `fn_calcular_noches(checkin, checkout)` | Noches entre dos fechas (`DATEDIFF`), reutilizada en reservas y consultas |
| `fn_disponibilidad_tipo_habitacion(hotel, tipo, checkin, checkout)` | Disponibilidad real por rango de fechas (no el estado puntual de la habitación) |
| `fn_calcular_edad(fecha_nacimiento)` | Edad actual, para reportes/validaciones |
| `fn_plan_vigente(tipo, fecha)` | Autodetecta el plan tarifario **público** vigente más específico para una fecha |
| `fn_precio_vigente(tipo, plan, fecha)` | Precio por noche de un plan ya determinado (público o corporativo) |
| `fn_saldo_cuenta(id_cuenta)` | Saldo pendiente real (auditoría contra el campo `saldo` mantenido por trigger) |

## 5. Catálogo de procedimientos almacenados (14)

| Procedimiento | Propósito |
|---|---|
| `sp_registrar_reserva` | Crea la cabecera de una reserva (estado inicial `PENDIENTE`) |
| `sp_agregar_detalle_reserva` | Agrega una línea tipo+plan+cantidad, valida disponibilidad y calcula el subtotal |
| `sp_confirmar_pago` | Marca la reserva como pagada y `CONFIRMADA` |
| `sp_realizar_checkin` | Crea el alojamiento (ocupación real) para una línea de reserva y habitación física, por ocupación real |
| `sp_agregar_huesped_alojamiento` | Asocia un huésped a un alojamiento, validando capacidad máxima |
| `sp_realizar_checkin_con_huesped` | Envuelve `sp_realizar_checkin` + `sp_agregar_huesped_alojamiento` en una sola transacción: el check-in exige registrar al huésped titular en el mismo paso |
| `sp_registrar_consumo` | Registra el consumo de un servicio con su precio vigente |
| `sp_registrar_danio` | Registra un daño en la habitación |
| `sp_registrar_salida_huesped` | Salida individual de un huésped; finaliza el alojamiento si era el último pendiente |
| `sp_realizar_checkout` | Checkout conjunto de toda la habitación |
| `sp_generar_cuenta_cobrar` | Genera la cuenta por cobrar (consumos + daños pendientes + IGV 18 %) |
| `sp_registrar_pago_cuenta` | Registra un pago/abono sobre una cuenta por cobrar |
| `sp_cambiar_estado_habitacion` | Cambia el estado de una habitación (mantenimiento/limpieza) |
| `sp_resumen_ocupacion_hotel` | Resumen de habitaciones por estado para un hotel |

Todos los procedimientos que representan una regla de negocio usan `SIGNAL SQLSTATE '45000'` con
un `MESSAGE_TEXT` legible cuando la operación no es válida (ej. *"No hay disponibilidad suficiente
de ese tipo de habitación en las fechas solicitadas"*); la aplicación captura esa excepción y la
muestra tal cual, sin reinterpretarla (`mvp_app/app/errors.py`).

## 6. Catálogo de vistas (14)

`vw_reservante`, `vw_habitaciones_disponibles`, `vw_reservas_detalle`, `vw_alojamientos_activos`,
`vw_historial_estadias`, `vw_consumos_alojamiento`, `vw_danios_pendientes`,
`vw_cuenta_cobrar_resumen`, `vw_ingresos_por_hotel`, `vw_ranking_clientes`, `vw_ocupacion_hotel`,
`vw_reservas_corporativas`, `vw_preasignacion_vs_checkin`, `vw_checkouts_pendientes` — detalle de
cada una y su propósito en `Scripts/05_Vistas.sql` (comentado línea por línea).

## 7. Triggers (23) y roles (4)

- **Triggers** (`Scripts/06_Triggers.sql`): sincronizan el estado de la habitación con el ciclo de
  vida del alojamiento (`trg_alojamiento_checkin/checkout/cancelar`), validan que no se finalice un
  alojamiento con huéspedes pendientes de salida, inicializan y recalculan el saldo de una cuenta
  por cobrar, validan fechas de check-in/checkout, validan capacidad máxima de huéspedes, y
  garantizan consistencia del discriminador `persona.tipo` frente a sus subtipos. A partir de una
  auditoría explícita de normalización de la base de datos se agregaron triggers que mantienen
  `reserva.monto_total` y `cuenta_cobrar.subtotal/total/saldo` siempre sincronizados con sus líneas
  de detalle y pagos (antes solo se mantenían por disciplina de los procedimientos, no por una regla
  garantizada por el motor) y exigen que el alcance de un `usuario` operativo coincida con el hotel
  de su `empleado`. Un rediseño posterior de `huesped` (ver `01_Entregable1_Diseno_BD.md` sección 4)
  eliminó dos triggers de sincronización que ya no hacían falta (`huesped` dejó de duplicar columnas
  de `persona_natural`) y agregó `trg_valida_cupos_reserva`, que limita el total de cupos —
  identificados o no — de una línea de reserva a `cantidad_habitaciones × capacidad_base`.
- **Roles MySQL** (`Scripts/07_Roles_Permisos.sql`): `rol_administrador` (control total),
  `rol_recepcion`, `rol_caja` (cada uno con `GRANT` de `SELECT` global + `INSERT`/`UPDATE` y
  `EXECUTE` solo sobre las tablas/procedimientos que su función requiere) y `rol_gerencia`
  (solo lectura). La app Flask usa autenticación real (usuario + contraseña, tabla `usuario`) que
  fija el rol y el alcance de la sesión (ver `mvp_app/app/auth/routes.py`), sin necesidad de
  credenciales MySQL distintas por rol para el MVP.

## 8. Evidencia de pruebas CRUD

- Consultas de demostración: `Scripts/09_Consultas_MVP.sql` (13 bloques, cubren cada vista/función
  y un bloque comentado con el ciclo completo vía `CALL`).
- Checklist de verificación end-to-end contra la base de datos real, con valores concretos
  (montos, IGV, saldos) obtenidos en una corrida real de la aplicación: `mvp_app/tests/test_flujo_manual.md`.
