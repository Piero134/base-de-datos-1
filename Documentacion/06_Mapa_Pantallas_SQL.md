# Mapa de pantallas → SQL invocado

Referencia rápida de qué consulta/procedimiento dispara cada pantalla o botón de `mvp_app`,
construida directamente a partir de `routes.py` de cada blueprint. Complementa
[`Especificacion_MVP.md`](../Especificacion_MVP.md), que mapea cada caso de uso (UC) a su
procedimiento/vista a nivel de flujo de negocio; esta tabla baja un nivel más, a la pantalla y
ruta Flask concreta, útil durante la sustentación para responder "¿qué consulta corre este botón?"
sin tener que abrir el código.

Los diagramas `Diagramas/05_Flujo_Navegacion_*.puml`, `06_..._Estadia.puml` y `07_..._Caja.puml`
incluyen las mismas anotaciones de SQL como notas sobre cada paso del flujo TO-BE.

## Reservas (`app/reservas/routes.py`)

| Pantalla | Ruta Flask | Acción del usuario | SQL invocado | Efecto / trigger disparado |
|---|---|---|---|---|
| Listado de reservas | `GET /reservas/` | Recepción/Administrador: filtro por tipo de reservante (natural/jurídica), documento/RUC y estado de la reserva. Caja: siempre solo pendientes de pago, sin filtros | `SELECT` sobre `reserva`+`vw_reservante`+`hotel` directo (no `vw_reservas_detalle`: esa vista no expone `tipo_persona`/`documento` del reservante) | — |
| Nueva reserva (cabecera) | `GET /reservas/nuevo` | Cargar catálogos (clientes, hoteles, tipos de documento) | `SELECT` sobre `vw_reservante`, `hotel`, `tipo_documento` | — |
| Crear cliente | `POST /reservas/cliente/nuevo` | Alta de cliente natural o jurídico | `INSERT` en `persona` → `persona_natural`/`persona_juridica` → `cliente` (transacción directa, sin SP) | — |
| Crear reserva | `POST /reservas/nuevo` | Confirmar cabecera de la reserva | `CALL sp_registrar_reserva(...)` | Crea reserva en estado `PENDIENTE` |
| Detalle de reserva | `GET/POST /reservas/<id>/detalle` | Agregar línea (tipo de habitación) | `CALL sp_agregar_detalle_reserva(...)` (usa `fn_plan_vigente`, `fn_disponibilidad_tipo_habitacion` internamente; rechaza si `reserva.pagado = 1`) | Recalcula `monto_total` |
| Confirmación de pago | `GET /reservas/<id>/pago` (solo Caja/Administrador) / `POST` (solo Caja/Administrador) | Pantalla exclusiva de Caja: Recepción no tiene ni el link (detalle, stepper) ni acceso a la ruta | `CALL sp_confirmar_pago(id_reserva)` | El propio SP hace `estado = 'CONFIRMADA'` (sin trigger de por medio) |
| Asignación de huéspedes | `GET /reservas/<id>/preasignar` | Ver la tabla de asignación (toda reserva, no solo corporativa): por línea, subdividida en habitaciones de `capacidad_base` cupos (calculado en Python, ver `app/asignacion_huespedes.py:construir_grid_reserva`) | `SELECT` sobre `reserva_detalle`+`tipo_habitacion`+`detalle_huesped_reserva` | — |
| Guardar asignación de una línea | `POST /reservas/<id>/asignacion/<id_detalle_reserva>` | Editar en la misma tabla todos los cupos de una línea a la vez (huésped + titular por habitación) | `INSERT`/`UPDATE` sobre `detalle_huesped_reserva` en una sola transacción; valida en Python que cada habitación con huéspedes tenga exactamente un titular antes de guardar | Trigger `trg_valida_cupos_reserva` limita el total de cupos por línea; las habitaciones ya con check-in se ignoran (solo lectura) |
| Huésped nuevo (desde reservas) | `POST /reservas/huesped/nuevo` | Alta de huésped (siempre identificado) | `INSERT INTO persona` → `persona_natural` → `huesped` vía `app/huespedes.py:crear_huesped_desde_formulario` (o solo `huesped` si ya existe la persona con ese documento) | — |

## Estadía (`app/estadia/routes.py`)

| Pantalla | Ruta Flask | Acción del usuario | SQL invocado | Efecto / trigger disparado |
|---|---|---|---|---|
| Alojamientos activos | `GET /estadia/activos` | Ver habitaciones ocupadas | `SELECT * FROM vw_alojamientos_activos` | — |
| Daños pendientes | `GET /estadia/danios-pendientes` | Ver daños sin cobrar | `SELECT * FROM vw_danios_pendientes` (+ `SELECT id_danio, id_alojamiento FROM danio` para enlazar cada fila a su alojamiento) | — |
| Check-outs pendientes | `GET /estadia/checkouts-pendientes` | Ver salidas vencidas/próximas | `SELECT * FROM vw_checkouts_pendientes` | — |
| Historial de estadías | `GET /estadia/historial` | Ver historial (global o por huésped) | `SELECT * FROM vw_historial_estadias [WHERE id_huesped = ...]` | — |
| Listado de check-in | `GET /estadia/checkin?buscar=` | Tabla plana, una fila por HABITACIÓN todavía sin check-in (no por reserva), de todas las reservas `CONFIRMADA`; búsqueda por nombre/documento del titular o nombre del reservante; cada fila enlaza directo (con ancla) al bloque de esa habitación en el check-in de la reserva | `SELECT r.id_reserva, v.nombre_reservante, r.fecha_checkin FROM reserva r JOIN vw_reservante v ... WHERE r.estado='CONFIRMADA'`; por cada reserva, `app/asignacion_huespedes.py:construir_grid_reserva(con_estado_estadia=True)` para listar las habitaciones sin `id_alojamiento`; filtrado por `buscar` en Python | — |
| Check-in de una reserva | `GET /estadia/checkin/<id_reserva>` | Ver, por habitación (mismo grid que la asignación de reservas, `app/asignacion_huespedes.py:construir_grid_reserva` con `con_estado_estadia=True`), quién ya tiene check-in y quién tiene el botón de check-in habilitado | `SELECT` sobre `reserva_detalle`, `tipo_habitacion`, `detalle_huesped_reserva`, `huesped_alojamiento`+`alojamiento`, `habitacion` | — |
| Realizar check-in | `POST /estadia/checkin` | Check-in individual de UN huésped ya asignado (igual de individual que la salida); el titular de la habitación debe ser el primero (rechazado si no lo es). Si es el primero de la habitación, además elige la habitación física | Primer huésped de la habitación (siempre el titular): `app/db.py:call_procedures_en_transaccion` → `CALL sp_realizar_checkin(...)` + `CALL sp_agregar_huesped_alojamiento(...)`, atómico. Siguientes huéspedes de la misma habitación: solo `CALL sp_agregar_huesped_alojamiento(...)` | Trigger `trg_alojamiento_checkin` → habitación pasa a `OCUPADA` en el primer check-in; rechaza si el huésped ya está activo en otro alojamiento |
| Alojamiento (hub) | `GET /estadia/<id_alojamiento>` | Ver huéspedes, consumos, daños (ya no se agregan huéspedes desde aquí: eso se hace desde la asignación en reservas) | `SELECT` sobre `alojamiento`, `huesped_alojamiento`, `vw_consumos_alojamiento`, `servicio`, `danio` | — |
| Registrar consumo | `POST /estadia/<id>/consumo` | Cargar un servicio consumido | `CALL sp_registrar_consumo(...)` | Calcula subtotal con precio vigente |
| Registrar daño | `POST /estadia/<id>/danio` | Reportar daño en la habitación | `CALL sp_registrar_danio(...)` | — |
| Salida individual | `POST /estadia/<id>/salida-huesped` | Registrar salida de un huésped | `CALL sp_registrar_salida_huesped(...)` | Si es el último huésped, finaliza el alojamiento automáticamente |
| Check-out completo | `POST /estadia/<id>/checkout` | Cerrar la habitación completa | `CALL sp_realizar_checkout(...)` | Triggers `trg_alojamiento_checkout_validar` y `trg_alojamiento_checkout` → habitación pasa a `LIMPIEZA` |

## Caja (`app/caja/routes.py`)

| Pantalla | Ruta Flask | Acción del usuario | SQL invocado | Efecto / trigger disparado |
|---|---|---|---|---|
| Cuentas por cobrar | `GET /caja/cuentas` | Ver cuentas (todas / pendientes / pagadas) | `SELECT * FROM vw_cuenta_cobrar_resumen` | — |
| Generar cuenta (form) | `GET /caja/generar-cuenta` | Elegir alojamiento `FINALIZADO` sin cuenta | `SELECT` sobre `alojamiento`/`habitacion`/`hotel` con `LEFT JOIN cuenta_cobrar` | — |
| Generar cuenta | `POST /caja/generar-cuenta` | Confirmar generación de cuenta | `CALL sp_generar_cuenta_cobrar(...)` | Suma consumos + daños pendientes, aplica IGV 18%, genera `cuenta_cobrar_detalle` |
| Ver cuenta | `GET /caja/cuenta/<id_cuenta>` | Ver detalle, pagos y saldo | `SELECT` sobre `vw_cuenta_cobrar_resumen`, `cuenta_cobrar_detalle`, `pago_cuenta_cobrar` | — |
| Registrar pago | `POST /caja/cuenta/<id>/pago` | Registrar pago (parcial o total) | `CALL sp_registrar_pago_cuenta(...)` | Trigger `trg_cuenta_actualizar_saldo` recalcula saldo; si llega a 0, cuenta pasa a `PAGADA` |

## Capa base (`app/auth/routes.py`)

| Pantalla | Ruta Flask | Acción del usuario | SQL invocado | Efecto |
|---|---|---|---|---|
| Login | `GET/POST /login` | Ingresar usuario y contraseña | `SELECT` sobre `usuario`/`empleado`/`hotel` + `check_password_hash` | Inicializa `session` con el rol y el alcance (`id_hotel`) ya fijos en `usuario` |
