-- =============================================================
--  09_Consultas_MVP.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Consultas SQL que usará el MVP para demostrar el
--               funcionamiento del sistema. Cada bloque indica
--               la funcionalidad que demuestra y aprovecha las
--               vistas, funciones y procedimientos ya creados.
--  Ejecutar: NOVENO (orden 9 de 9)
-- =============================================================

USE hotel_db;

-- =============================================================
-- 1. Mostrar habitaciones disponibles (estado puntual)
-- =============================================================
SELECT * FROM vw_habitaciones_disponibles
ORDER BY id_hotel, numero;

-- =============================================================
-- 1b. Disponibilidad REAL por rango de fechas (usa la función)
--     Ejemplo: ¿cuántas simples del Hotel Lima están libres del
--     25 al 27 de junio de 2026?
-- =============================================================
SELECT fn_disponibilidad_tipo_habitacion(1, 1, '2026-06-25', '2026-06-27') AS simples_disponibles;

-- =============================================================
-- 1c. Autodetección de plan y precio por fecha (sin indicar plan)
--     Ejemplo: tipo Doble en Semana Santa 2025 debe resolver a
--     "Tarifa Temporada Alta 2025" automáticamente, no a la
--     tarifa Regular (que también cubre esa fecha pero es menos
--     específica); el plan Corporativo (es_publico=0) nunca se
--     autodetecta.
-- =============================================================
SELECT
    fn_plan_vigente(2, '2025-04-01')                    AS plan_detectado,
    fn_precio_vigente(2, fn_plan_vigente(2, '2025-04-01'), '2025-04-01') AS precio_noche;

-- =============================================================
-- 2. Reservas pendientes de pago
-- =============================================================
SELECT * FROM vw_reservas_detalle
WHERE pagado = 0
ORDER BY fecha_limite_pago;

-- =============================================================
-- 3. Clientes hospedados actualmente (huéspedes con alojamiento activo)
-- =============================================================
SELECT * FROM vw_alojamientos_activos
ORDER BY hotel, habitacion;

-- =============================================================
-- 4. Historial de estadías (de un huésped puntual, ej. id_huesped = 1)
-- =============================================================
SELECT * FROM vw_historial_estadias
WHERE id_huesped = 1
ORDER BY fecha_checkin_real DESC;

-- =============================================================
-- 4b. Salida individual por huésped: en el alojamiento 4, Diego
--     ya registró su salida pero Sofía continúa hospedada — la
--     habitación sigue ACTIVA porque no todos han salido.
-- =============================================================
SELECT huesped, fecha_checkin_real, fecha_salida_huesped, fecha_checkout_habitacion, estado
FROM vw_historial_estadias
WHERE fecha_checkin_real = '2026-06-19 15:00:00'
ORDER BY fecha_salida_huesped IS NULL, huesped;

-- =============================================================
-- 5. Consumos por estadía (ej. alojamiento 1)
-- =============================================================
SELECT * FROM vw_consumos_alojamiento
WHERE id_alojamiento = 1
ORDER BY fecha_consumo;

-- =============================================================
-- 6. Daños registrados (pendientes de cobro)
-- =============================================================
SELECT * FROM vw_danios_pendientes
ORDER BY fecha_reporte;

-- =============================================================
-- 7. Cuenta final del cliente (ej. cuenta 1, con su detalle)
-- =============================================================
SELECT r.*
FROM vw_cuenta_cobrar_resumen r
WHERE r.id_cuenta = 1;

SELECT concepto, cantidad, precio_unitario, subtotal
FROM cuenta_cobrar_detalle
WHERE id_cuenta = 1;

-- =============================================================
-- 8. Ingresos por hotel (hospedaje confirmado + servicios)
-- =============================================================
SELECT * FROM vw_ingresos_por_hotel
ORDER BY ingreso_total DESC;

-- =============================================================
-- 9. Ranking de clientes (por monto total gastado)
-- =============================================================
SELECT * FROM vw_ranking_clientes
ORDER BY ranking;

-- =============================================================
-- 10. Ocupación por hotel (conteo de habitaciones por estado y tipo)
-- =============================================================
SELECT * FROM vw_ocupacion_hotel
ORDER BY id_hotel, tipo;

-- Alternativa vía procedimiento almacenado (resumen simple por hotel):
CALL sp_resumen_ocupacion_hotel(1);

-- =============================================================
-- 11. Reservas corporativas (empresas con pre-asignación de empleados)
-- =============================================================
SELECT * FROM vw_reservas_corporativas
ORDER BY id_reserva;

-- =============================================================
-- 11b. Asignación de huéspedes vs. check-in real: detecta si quien
--      efectivamente ocupó la habitación coincide con quien había
--      sido asignado en la reserva.
-- =============================================================
SELECT * FROM vw_preasignacion_vs_checkin
ORDER BY id_reserva, id_detalle_huesped;

-- =============================================================
-- 12. Check-outs pendientes (alojamientos activos cuya fecha de
--     salida planificada ya llegó o venció)
-- =============================================================
SELECT * FROM vw_checkouts_pendientes
ORDER BY checkout_planificado;

-- =============================================================
-- 13. Demostración del ciclo de negocio completo usando los
--     procedimientos almacenados (no solo SELECTs). Comentado
--     porque modifica datos; descomentar para probar en vivo.
-- =============================================================
/*
SET @id_reserva = NULL;
CALL sp_registrar_reserva(2, 1, 1, NULL, 'WEB', '2026-08-01', '2026-08-03', '2026-07-28', 'Reserva de prueba MVP', @id_reserva);
-- p_id_plan = NULL → el plan se autodetecta según fecha_checkin (fn_plan_vigente)
CALL sp_agregar_detalle_reserva(@id_reserva, 1, NULL, 1);
CALL sp_confirmar_pago(@id_reserva);

-- Ejemplo con plan explícito (tarifa corporativa, NO se autodetecta):
-- CALL sp_agregar_detalle_reserva(@id_reserva, 1, 3, 1);

SET @id_alojamiento = NULL;
CALL sp_realizar_checkin(@id_reserva, LAST_INSERT_ID(), 2, 1, @id_alojamiento);
CALL sp_agregar_huesped_alojamiento(@id_alojamiento, 2, 1, NULL);
CALL sp_registrar_consumo(@id_alojamiento, 1, 1);

-- Salida individual: si hubiera más de un huésped, cada uno se
-- retira con sp_registrar_salida_huesped(); la habitación se
-- libera automáticamente cuando el ÚLTIMO huésped registra su
-- salida. Con un solo huésped, esto ya finaliza el alojamiento:
CALL sp_registrar_salida_huesped(@id_alojamiento, 2, 1);
-- Alternativa (checkout conjunto de todos los ocupantes de una sola vez):
-- CALL sp_realizar_checkout(@id_alojamiento, 1);

SET @id_cuenta = NULL;
CALL sp_generar_cuenta_cobrar(@id_alojamiento, @id_cuenta);
CALL sp_registrar_pago_cuenta(@id_cuenta, 29.50, 'YAPE_PLIN', 1);

SELECT * FROM vw_cuenta_cobrar_resumen WHERE id_cuenta = @id_cuenta;
*/
