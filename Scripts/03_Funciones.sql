-- =============================================================
--  03_Funciones.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Funciones reutilizables para cálculo de noches,
--               disponibilidad, edad y precios vigentes. Se usan
--               en procedimientos, vistas y consultas del MVP.
--  Ejecutar: TERCERO (orden 3 de 9)
-- =============================================================

USE hotel_db;

DELIMITER $$

-- -------------------------------------------------------------
-- FN 1: fn_calcular_noches
-- Devuelve la cantidad de noches entre check-in y check-out.
-- Reutilizada en reserva_detalle, procedimientos y consultas
-- (evita repetir DATEDIFF en cada script).
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_calcular_noches$$
CREATE FUNCTION fn_calcular_noches(
    p_checkin DATE,
    p_checkout DATE
) RETURNS INT
    DETERMINISTIC
BEGIN
    RETURN DATEDIFF(p_checkout, p_checkin);
END$$

-- -------------------------------------------------------------
-- FN 2: fn_disponibilidad_tipo_habitacion
-- Calcula cuántas habitaciones de un tipo, en un hotel, están
-- realmente libres en un rango de fechas: total físicas menos
-- las que tienen un alojamiento ACTIVO cuyo rango de reserva se
-- solapa con el solicitado. Responde a la observación del
-- profesor sobre validar disponibilidad por período, no solo
-- por el estado puntual de la habitación.
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_disponibilidad_tipo_habitacion$$
CREATE FUNCTION fn_disponibilidad_tipo_habitacion(
    p_id_hotel INT,
    p_id_tipo_habitacion INT,
    p_fecha_checkin DATE,
    p_fecha_checkout DATE
) RETURNS INT
    READS SQL DATA
    DETERMINISTIC
BEGIN
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_ocupadas INT DEFAULT 0;

    SELECT COUNT(*) INTO v_total
    FROM habitacion h
    WHERE h.id_hotel = p_id_hotel
      AND h.id_tipo_habitacion = p_id_tipo_habitacion;

    SELECT COUNT(DISTINCT h.id_habitacion) INTO v_ocupadas
    FROM habitacion h
    JOIN alojamiento a ON a.id_habitacion = h.id_habitacion
    JOIN reserva r      ON r.id_reserva    = a.id_reserva
    WHERE h.id_hotel = p_id_hotel
      AND h.id_tipo_habitacion = p_id_tipo_habitacion
      AND a.estado = 'ACTIVO'
      AND r.fecha_checkin  < p_fecha_checkout
      AND r.fecha_checkout > p_fecha_checkin;

    RETURN v_total - v_ocupadas;
END$$

-- -------------------------------------------------------------
-- FN 3: fn_calcular_edad
-- Calcula la edad actual a partir de una fecha de nacimiento.
-- Útil para reportes y validaciones (ej. mayoría de edad del
-- titular de una reserva).
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_calcular_edad$$
CREATE FUNCTION fn_calcular_edad(
    p_fecha_nacimiento DATE
) RETURNS INT
    DETERMINISTIC
BEGIN
    IF p_fecha_nacimiento IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN TIMESTAMPDIFF(YEAR, p_fecha_nacimiento, CURDATE());
END$$

-- -------------------------------------------------------------
-- FN 4a: fn_plan_vigente
-- Dada una fecha de referencia (normalmente el check-in) y un
-- tipo de habitación, DETECTA AUTOMÁTICAMENTE qué plan tarifario
-- PÚBLICO corresponde (Regular vs. Temporada Alta, etc.), sin
-- que el operador tenga que indicarlo. Solo considera planes con
-- es_publico = 1: los planes negociados/corporativos (es_publico
-- = 0) quedan excluidos a propósito, porque aplican solo si el
-- operador los elige explícitamente para un cliente con convenio
-- (ver fn_precio_vigente). Si dos planes públicos se solapan en
-- fecha (ej. Regular cubre todo el año y Temporada Alta cubre
-- solo Semana Santa), gana el más ESPECÍFICO: el de menor
-- duración de vigencia; ante empate, el de fecha_inicio más
-- reciente.
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_plan_vigente$$
CREATE FUNCTION fn_plan_vigente(
    p_id_tipo_habitacion INT,
    p_fecha_referencia DATE
) RETURNS INT
    READS SQL DATA
    DETERMINISTIC
BEGIN
    DECLARE v_id_plan INT;

    SELECT pt.id_plan INTO v_id_plan
    FROM plan_tarifa pt
    JOIN tarifa_habitacion tr ON tr.id_plan = pt.id_plan
    WHERE tr.id_tipo_habitacion = p_id_tipo_habitacion
      AND pt.activo = 1
      AND pt.es_publico = 1
      AND p_fecha_referencia BETWEEN pt.fecha_inicio AND pt.fecha_fin
    ORDER BY DATEDIFF(pt.fecha_fin, pt.fecha_inicio) ASC,
             pt.fecha_inicio DESC
    LIMIT 1;

    RETURN v_id_plan;
END$$

-- -------------------------------------------------------------
-- FN 4b: fn_precio_vigente
-- Devuelve el precio por noche de un plan YA DETERMINADO (ya sea
-- porque lo detectó fn_plan_vigente, o porque el operador eligió
-- explícitamente un plan negociado/corporativo), validando que
-- ese plan esté vigente en la fecha de referencia. A diferencia
-- de fn_plan_vigente, aquí el id_plan es un dato de entrada, no
-- algo que la función decida — por eso sí acepta planes con
-- es_publico = 0 (corporativos).
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_precio_vigente$$
CREATE FUNCTION fn_precio_vigente(
    p_id_tipo_habitacion INT,
    p_id_plan INT,
    p_fecha_referencia DATE
) RETURNS DECIMAL(10,2)
    READS SQL DATA
    DETERMINISTIC
BEGIN
    DECLARE v_precio DECIMAL(10,2);

    SELECT tr.precio_por_noche INTO v_precio
    FROM tarifa_habitacion tr
    JOIN plan_tarifa pt ON pt.id_plan = tr.id_plan
    WHERE tr.id_tipo_habitacion = p_id_tipo_habitacion
      AND tr.id_plan = p_id_plan
      AND pt.activo = 1
      AND p_fecha_referencia BETWEEN pt.fecha_inicio AND pt.fecha_fin
    LIMIT 1;

    RETURN v_precio;
END$$

-- -------------------------------------------------------------
-- FN 5: fn_saldo_cuenta
-- Devuelve el saldo pendiente real de una cuenta por cobrar,
-- calculado como total menos la suma de pagos registrados en
-- pago_cuenta_cobrar. Sirve para auditar que el campo "saldo"
-- (mantenido por trigger) sea consistente con el historial de
-- pagos.
-- -------------------------------------------------------------
DROP FUNCTION IF EXISTS fn_saldo_cuenta$$
CREATE FUNCTION fn_saldo_cuenta(
    p_id_cuenta INT
) RETURNS DECIMAL(12,2)
    READS SQL DATA
    DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);

    SELECT total INTO v_total FROM cuenta_cobrar WHERE id_cuenta = p_id_cuenta;
    SELECT COALESCE(SUM(monto), 0) INTO v_pagado
    FROM pago_cuenta_cobrar WHERE id_cuenta = p_id_cuenta;

    RETURN v_total - v_pagado;
END$$

DELIMITER ;
