-- =============================================================
--  04_Procedimientos.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Procedimientos almacenados que cubren el ciclo
--               de vida completo de una estadía: reserva → pago
--               → check-in → consumos/daños → check-out →
--               cuenta por cobrar → pago de cuenta.
--  Ejecutar: CUARTO (orden 4 de 9), requiere 03_Funciones.sql
-- =============================================================

USE hotel_db;

DELIMITER $$

-- -------------------------------------------------------------
-- SP 1: sp_registrar_reserva
-- Crea la cabecera de una reserva. El monto_total se calcula
-- después, a medida que se agregan líneas con
-- sp_agregar_detalle_reserva (una reserva puede combinar varios
-- tipos de habitación, ej. 2 simples + 1 doble, tal como se
-- discutió en la asesoría).
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_reserva$$
CREATE PROCEDURE sp_registrar_reserva(
    IN  p_id_cliente INT,
    IN  p_id_hotel INT,
    IN  p_id_empleado INT,
    IN  p_id_cliente_contacto INT,
    IN  p_canal ENUM('DIRECTO','WEB','TELEFONO','AGENCIA','OTA'),
    IN  p_fecha_checkin DATE,
    IN  p_fecha_checkout DATE,
    IN  p_fecha_limite_pago DATE,
    IN  p_observaciones TEXT,
    OUT p_id_reserva INT
)
BEGIN
    IF p_fecha_checkout <= p_fecha_checkin THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La fecha de checkout debe ser posterior al checkin';
    END IF;

    INSERT INTO reserva (
        id_cliente, id_hotel, estado, id_empleado,
        id_cliente_contacto, canal, fecha_checkin, fecha_checkout,
        fecha_limite_pago, pagado, monto_total, observaciones
    ) VALUES (
        p_id_cliente, p_id_hotel, 'PENDIENTE', p_id_empleado,
        p_id_cliente_contacto, p_canal, p_fecha_checkin, p_fecha_checkout,
        p_fecha_limite_pago, 0, 0.00, p_observaciones
    );

    SET p_id_reserva = LAST_INSERT_ID();
END$$

-- -------------------------------------------------------------
-- SP 2: sp_agregar_detalle_reserva
-- Agrega una línea (tipo de habitación + cantidad) a una reserva
-- existente, validando disponibilidad real por fecha
-- (fn_disponibilidad_tipo_habitacion) antes de comprometer el
-- cupo, y actualiza el monto_total de la cabecera.
--
-- p_id_plan es OPCIONAL:
--   - Si se pasa NULL, el plan se detecta automáticamente según
--     la fecha de check-in con fn_plan_vigente (Regular vs.
--     Temporada Alta, etc.) — así es como funciona por defecto
--     para un cliente sin convenio.
--   - Si se indica un id_plan explícito (ej. la tarifa
--     corporativa de un cliente con convenio), se usa ese plan
--     directamente vía fn_precio_vigente, sin pasar por la
--     autodetección (los planes negociados no se autodetectan a
--     propósito; ver es_publico en plan_tarifa).
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_agregar_detalle_reserva$$
CREATE PROCEDURE sp_agregar_detalle_reserva(
    IN p_id_reserva INT,
    IN p_id_tipo_habitacion INT,
    IN p_id_plan INT,
    IN p_cantidad_habitaciones TINYINT
)
BEGIN
    DECLARE v_id_hotel INT;
    DECLARE v_checkin DATE;
    DECLARE v_checkout DATE;
    DECLARE v_pagado TINYINT;
    DECLARE v_estado ENUM('PENDIENTE','CONFIRMADA','CANCELADA','NO_SHOW','FINALIZADA');
    DECLARE v_disponibles INT;
    DECLARE v_id_plan INT;
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_noches INT;
    DECLARE v_subtotal DECIMAL(12,2);

    SELECT id_hotel, fecha_checkin, fecha_checkout, pagado, estado
        INTO v_id_hotel, v_checkin, v_checkout, v_pagado, v_estado
    FROM reserva WHERE id_reserva = p_id_reserva;

    IF v_pagado = 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva ya está pagada; no se pueden agregar más líneas.';
    END IF;

    IF v_estado IN ('CANCELADA','NO_SHOW','FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva está en un estado final; no se pueden agregar más líneas.';
    END IF;

    SET v_disponibles = fn_disponibilidad_tipo_habitacion(
        v_id_hotel, p_id_tipo_habitacion, v_checkin, v_checkout);

    IF v_disponibles < p_cantidad_habitaciones THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No hay disponibilidad suficiente de ese tipo de habitación en las fechas solicitadas';
    END IF;

    SET v_id_plan = p_id_plan;
    IF v_id_plan IS NULL THEN
        SET v_id_plan = fn_plan_vigente(p_id_tipo_habitacion, v_checkin);
        IF v_id_plan IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No hay un plan tarifario público vigente para ese tipo de habitación en la fecha de check-in';
        END IF;
    END IF;

    SET v_precio = fn_precio_vigente(p_id_tipo_habitacion, v_id_plan, v_checkin);
    IF v_precio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No existe tarifa vigente para ese tipo de habitación y plan en la fecha indicada';
    END IF;

    SET v_noches = fn_calcular_noches(v_checkin, v_checkout);
    SET v_subtotal = v_precio * p_cantidad_habitaciones * v_noches;

    INSERT INTO reserva_detalle (
        id_reserva, id_tipo_habitacion, id_plan,
        cantidad_habitaciones, precio_unitario, subtotal
    ) VALUES (
        p_id_reserva, p_id_tipo_habitacion, v_id_plan,
        p_cantidad_habitaciones, v_precio, v_subtotal
    );

END$$

-- -------------------------------------------------------------
-- SP 3: sp_confirmar_pago
-- Confirma el pago total de una reserva y cambia su estado a
-- CONFIRMADA
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_confirmar_pago$$
CREATE PROCEDURE sp_confirmar_pago(
    IN p_id_reserva INT
)
BEGIN
    DECLARE v_pagado TINYINT;
    DECLARE v_estado ENUM('PENDIENTE','CONFIRMADA','CANCELADA','NO_SHOW','FINALIZADA');

    SELECT pagado, estado INTO v_pagado, v_estado FROM reserva WHERE id_reserva = p_id_reserva;

    IF v_pagado = 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La reserva ya se encuentra pagada';
    END IF;

    IF v_estado IN ('CANCELADA','NO_SHOW','FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva está en un estado final; no se puede confirmar el pago.';
    END IF;

    UPDATE reserva
    SET pagado = 1,
        fecha_pago = NOW(),
        estado = 'CONFIRMADA'
    WHERE id_reserva = p_id_reserva;
END$$

-- -------------------------------------------------------------
-- SP 4: sp_realizar_checkin
-- Registra el check-in real: crea el alojamiento para una línea
-- de reserva y una habitación física específica. El trigger
-- trg_alojamiento_checkin marca la habitación como OCUPADA.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_realizar_checkin$$
CREATE PROCEDURE sp_realizar_checkin(
    IN  p_id_reserva INT,
    IN  p_id_detalle_reserva INT,
    IN  p_id_habitacion INT,
    IN  p_id_empleado_checkin INT,
    OUT p_id_alojamiento INT
)
BEGIN
    DECLARE v_estado ENUM('PENDIENTE','CONFIRMADA','CANCELADA','NO_SHOW','FINALIZADA');

    SELECT estado INTO v_estado FROM reserva WHERE id_reserva = p_id_reserva;
    IF v_estado IN ('CANCELADA','NO_SHOW','FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva está en un estado final; no se puede hacer check-in.';
    END IF;

    -- La disponibilidad se decide por ocupación real (¿hay un alojamiento
    -- ACTIVO en esta habitación ahora mismo?), no por el campo cacheado
    -- habitacion.estado: ese campo tiene estados (RESERVADA, LIMPIEZA) que
    -- solo se liberan con una acción manual del ADMINISTRADOR y pueden
    -- quedar "pegados" aunque la habitación esté realmente libre.
    IF EXISTS (
        SELECT 1 FROM alojamiento
        WHERE id_habitacion = p_id_habitacion AND estado = 'ACTIVO'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La habitación ya se encuentra ocupada';
    END IF;

    INSERT INTO alojamiento (
        id_reserva, id_detalle_reserva, id_habitacion, estado,
        id_empleado_checkin, fecha_checkin_real
    ) VALUES (
        p_id_reserva, p_id_detalle_reserva, p_id_habitacion, 'ACTIVO',
        p_id_empleado_checkin, NOW()
    );

    SET p_id_alojamiento = LAST_INSERT_ID();
END$$

-- -------------------------------------------------------------
-- SP 5: sp_agregar_huesped_alojamiento
-- Asocia un huésped (siempre identificado — nunca hay ocupación real
-- sin identidad completa) a un alojamiento activo, validando que no
-- se exceda la capacidad máxima del tipo de habitación (regla de
-- negocio comentada por el profesor: "no puedes meter más de dos en
-- una doble").
--
-- p_id_detalle_huesped es OPCIONAL: si la línea de reserva tuvo
-- una pre-asignación corporativa (detalle_huesped_reserva), se
-- puede pasar aquí para dejar trazabilidad de "quién pre-asignó
-- la empresa" vs. "quién realmente hizo check-in", y el
-- procedimiento avisa (sin bloquear) si el huésped que hace
-- check-in no es el que fue pre-asignado para esa línea.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_agregar_huesped_alojamiento$$
CREATE PROCEDURE sp_agregar_huesped_alojamiento(
    IN p_id_alojamiento INT,
    IN p_id_huesped INT,
    IN p_es_titular TINYINT,
    IN p_id_detalle_huesped INT
)
BEGIN
    DECLARE v_capacidad TINYINT;
    DECLARE v_ocupantes_actuales INT;
    DECLARE v_id_huesped_preasignado INT;

    SELECT th.capacidad_base INTO v_capacidad
    FROM alojamiento a
    JOIN habitacion h ON h.id_habitacion = a.id_habitacion
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
    WHERE a.id_alojamiento = p_id_alojamiento;

    SELECT COUNT(*) INTO v_ocupantes_actuales
    FROM huesped_alojamiento
    WHERE id_alojamiento = p_id_alojamiento;

    IF v_ocupantes_actuales >= v_capacidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Se alcanzó la capacidad máxima de huéspedes para esta habitación';
    END IF;

    -- Un huésped no puede estar activo en dos alojamientos a la vez
    -- (dos estadías simultáneas de la misma persona). Se excluye el
    -- propio p_id_alojamiento para no bloquear un reintento sobre el
    -- mismo alojamiento (esa duplicidad ya la impide la PK compuesta).
    -- ha.fecha_salida_real IS NULL es imprescindible: sin este filtro,
    -- un huésped que ya registró su salida individual de OTRA habitación
    -- (pero esa habitación sigue ACTIVA porque quedan compañeros dentro)
    -- quedaba bloqueado para un nuevo check-in aunque ya no esté
    -- ocupando nada — bug detectado y corregido el 2026-07-13.
    IF EXISTS (
        SELECT 1
        FROM huesped_alojamiento ha
        JOIN alojamiento a ON a.id_alojamiento = ha.id_alojamiento
        WHERE ha.id_huesped = p_id_huesped
          AND a.estado = 'ACTIVO'
          AND ha.fecha_salida_real IS NULL
          AND a.id_alojamiento <> p_id_alojamiento
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este huésped ya está activo en otro alojamiento.';
    END IF;

    -- Validación no bloqueante: si se indicó una pre-asignación,
    -- verificar que corresponda al mismo huésped. Si no coincide,
    -- se deja constancia en el detalle de la reserva (observación)
    -- en vez de impedir el check-in, porque en la práctica sí puede
    -- cambiar quién ocupa la habitación a último momento.
    -- La existencia de la fila y su resolución se comprueban por
    -- separado: una pre-asignación real puede tener id_huesped NULL
    -- (cupo corporativo aún sin identificar), así que "no encontré
    -- valor" ya no sirve como señal de "la fila no existe".
    IF p_id_detalle_huesped IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM detalle_huesped_reserva WHERE id_detalle_huesped = p_id_detalle_huesped) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La pre-asignación indicada no existe';
        END IF;

        SELECT id_huesped INTO v_id_huesped_preasignado
        FROM detalle_huesped_reserva
        WHERE id_detalle_huesped = p_id_detalle_huesped;

        IF v_id_huesped_preasignado IS NOT NULL AND v_id_huesped_preasignado != p_id_huesped THEN
            UPDATE reserva r
            JOIN reserva_detalle rd ON rd.id_reserva = r.id_reserva
            JOIN detalle_huesped_reserva dhr ON dhr.id_detalle_reserva = rd.id_detalle_reserva
            SET r.observaciones = CONCAT_WS('\n', r.observaciones,
                CONCAT('Cambio en check-in: El cupo ', p_id_detalle_huesped, ' fue ocupado por huésped ID ', p_id_huesped, ' en lugar del pre-asignado ID ', v_id_huesped_preasignado))
            WHERE dhr.id_detalle_huesped = p_id_detalle_huesped;
        END IF;

    END IF;

    INSERT INTO huesped_alojamiento (id_alojamiento, id_huesped, id_detalle_huesped, es_titular)
    VALUES (p_id_alojamiento, p_id_huesped, p_id_detalle_huesped, p_es_titular);
END$$

-- -------------------------------------------------------------
-- SP 5b: sp_realizar_checkin_con_huesped
-- Envoltorio de sp_realizar_checkin + sp_agregar_huesped_alojamiento
-- en una sola llamada: un check-in nunca debe dejar una habitación
-- ocupada sin ningún huésped asociado (si no, no tiene sentido).
-- Al ser un solo CALL desde la app, ambos INSERT quedan en la misma
-- transacción — si el segundo falla (ej. capacidad excedida), el
-- alojamiento recién creado también se revierte.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_realizar_checkin_con_huesped$$
CREATE PROCEDURE sp_realizar_checkin_con_huesped(
    IN  p_id_reserva INT,
    IN  p_id_detalle_reserva INT,
    IN  p_id_habitacion INT,
    IN  p_id_empleado_checkin INT,
    IN  p_id_huesped INT,
    IN  p_id_detalle_huesped INT,
    OUT p_id_alojamiento INT
)
BEGIN
    DECLARE v_id_alojamiento INT;

    CALL sp_realizar_checkin(p_id_reserva, p_id_detalle_reserva, p_id_habitacion,
                              p_id_empleado_checkin, v_id_alojamiento);
    CALL sp_agregar_huesped_alojamiento(v_id_alojamiento, p_id_huesped, 1, p_id_detalle_huesped);

    SET p_id_alojamiento = v_id_alojamiento;
END$$

-- -------------------------------------------------------------
-- SP 6: sp_registrar_consumo
-- Registra el consumo de un servicio para un alojamiento activo,
-- calculando automáticamente el subtotal en base al precio
-- actual del servicio.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_consumo$$
CREATE PROCEDURE sp_registrar_consumo(
    IN p_id_alojamiento INT,
    IN p_id_servicio INT,
    IN p_cantidad TINYINT
)
BEGIN
    DECLARE v_precio DECIMAL(10,2);
    DECLARE v_subtotal DECIMAL(12,2);
    DECLARE v_estado_aloj ENUM('ACTIVO','FINALIZADO','CANCELADO');

    SELECT estado INTO v_estado_aloj FROM alojamiento WHERE id_alojamiento = p_id_alojamiento;
    IF v_estado_aloj IS NULL OR v_estado_aloj <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se pueden registrar consumos en alojamientos activos';
    END IF;

    SELECT precio_unitario INTO v_precio
    FROM servicio
    WHERE id_servicio = p_id_servicio AND activo = 1;

    IF v_precio IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Servicio no encontrado o inactivo';
    END IF;

    SET v_subtotal = v_precio * p_cantidad;

    INSERT INTO consumo_servicio (id_alojamiento, id_servicio, cantidad, precio_unitario, subtotal)
    VALUES (p_id_alojamiento, p_id_servicio, p_cantidad, v_precio, v_subtotal);
END$$

-- -------------------------------------------------------------
-- SP 7: sp_registrar_danio
-- Registra un daño asociado a un alojamiento.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_danio$$
CREATE PROCEDURE sp_registrar_danio(
    IN p_id_alojamiento INT,
    IN p_descripcion TEXT,
    IN p_costo DECIMAL(10,2)
)
BEGIN
    INSERT INTO danio (id_alojamiento, descripcion, costo, estado)
    VALUES (p_id_alojamiento, p_descripcion, p_costo, 'PENDIENTE');
END$$

-- -------------------------------------------------------------
-- SP 8a: sp_registrar_salida_huesped
-- Registra la salida INDIVIDUAL de un huésped de una habitación
-- (fecha_salida_real en huesped_alojamiento). En un hotel real
-- no todos los ocupantes de una habitación se retiran al mismo
-- tiempo (ej. un acompañante se va antes que el titular). Cuando
-- este es el ÚLTIMO huésped pendiente de salida en ese
-- alojamiento, el propio procedimiento finaliza el alojamiento
-- automáticamente (equivalente al check-out completo de la
-- habitación). El trigger trg_alojamiento_checkout pasa entonces
-- la habitación a LIMPIEZA.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_salida_huesped$$
CREATE PROCEDURE sp_registrar_salida_huesped(
    IN p_id_alojamiento INT,
    IN p_id_huesped INT,
    IN p_id_empleado_checkout INT
)
BEGIN
    DECLARE v_estado_aloj ENUM('ACTIVO','FINALIZADO','CANCELADO');
    DECLARE v_ya_salio DATETIME;
    DECLARE v_pendientes INT;

    SELECT estado INTO v_estado_aloj FROM alojamiento WHERE id_alojamiento = p_id_alojamiento;
    IF v_estado_aloj <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El alojamiento no está activo';
    END IF;

    SELECT fecha_salida_real INTO v_ya_salio
    FROM huesped_alojamiento
    WHERE id_alojamiento = p_id_alojamiento AND id_huesped = p_id_huesped;

    IF v_ya_salio IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Este huésped ya tiene registrada su salida';
    END IF;

    UPDATE huesped_alojamiento
    SET fecha_salida_real = NOW()
    WHERE id_alojamiento = p_id_alojamiento AND id_huesped = p_id_huesped;

    -- ¿Quedan huéspedes de esta habitación sin registrar salida?
    SELECT COUNT(*) INTO v_pendientes
    FROM huesped_alojamiento
    WHERE id_alojamiento = p_id_alojamiento AND fecha_salida_real IS NULL;

    IF v_pendientes = 0 THEN
        -- Era el último huésped en salir: se libera la habitación.
        UPDATE alojamiento
        SET estado = 'FINALIZADO',
            id_empleado_checkout = p_id_empleado_checkout,
            fecha_checkout_real = NOW()
        WHERE id_alojamiento = p_id_alojamiento;
    END IF;
END$$

-- -------------------------------------------------------------
-- SP 8b: sp_realizar_checkout
-- Finaliza directamente un alojamiento activo (checkout de toda
-- la habitación de una sola vez, ej. cuando todos los huéspedes
-- se retiran juntos). El trigger trg_alojamiento_checkout_validar
-- exige que TODOS los huéspedes ya tengan fecha_salida_real
-- registrada (individualmente, vía sp_registrar_salida_huesped)
-- antes de permitir esta finalización; si aún hay huéspedes
-- presentes, este procedimiento los marca como salidos en este
-- mismo instante para no bloquear el flujo simple de una sola
-- persona por habitación.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_realizar_checkout$$
CREATE PROCEDURE sp_realizar_checkout(
    IN p_id_alojamiento INT,
    IN p_id_empleado_checkout INT
)
BEGIN
    DECLARE v_estado ENUM('ACTIVO','FINALIZADO','CANCELADO');

    SELECT estado INTO v_estado FROM alojamiento WHERE id_alojamiento = p_id_alojamiento;
    IF v_estado <> 'ACTIVO' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Solo se puede hacer checkout de un alojamiento activo';
    END IF;

    -- Cierra la salida de cualquier huésped que aún no la tenga
    -- registrada (checkout conjunto de todos los ocupantes).
    UPDATE huesped_alojamiento
    SET fecha_salida_real = NOW()
    WHERE id_alojamiento = p_id_alojamiento
      AND fecha_salida_real IS NULL;

    UPDATE alojamiento
    SET estado = 'FINALIZADO',
        id_empleado_checkout = p_id_empleado_checkout,
        fecha_checkout_real = NOW()
    WHERE id_alojamiento = p_id_alojamiento;
END$$

-- -------------------------------------------------------------
-- SP 9: sp_generar_cuenta_cobrar
-- Genera automáticamente la cuenta por cobrar de un alojamiento
-- ya finalizado, sumando consumos de servicio + daños pendientes,
-- aplicando IGV (18%) y creando el detalle de línea por línea.
-- El trigger trg_cuenta_cobrar_insert inicializa saldo = total.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_generar_cuenta_cobrar$$
CREATE PROCEDURE sp_generar_cuenta_cobrar(
    IN  p_id_alojamiento INT,
    OUT p_id_cuenta INT
)
BEGIN
    DECLARE v_subtotal DECIMAL(12,2) DEFAULT 0;
    DECLARE v_impuestos DECIMAL(12,2) DEFAULT 0;
    DECLARE v_total DECIMAL(12,2) DEFAULT 0;

    IF EXISTS (SELECT 1 FROM cuenta_cobrar WHERE id_alojamiento = p_id_alojamiento) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Ya existe una cuenta por cobrar para este alojamiento';
    END IF;

    SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal
    FROM consumo_servicio WHERE id_alojamiento = p_id_alojamiento;

    SELECT v_subtotal + COALESCE(SUM(costo), 0) INTO v_subtotal
    FROM danio WHERE id_alojamiento = p_id_alojamiento AND estado = 'PENDIENTE';

    IF v_subtotal = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Este alojamiento no tiene consumos ni daños pendientes; no hay nada que cobrar.';
    END IF;

    SET v_impuestos = ROUND(v_subtotal * 0.18, 2);
    SET v_total = v_subtotal + v_impuestos;

    INSERT INTO cuenta_cobrar (id_alojamiento, subtotal, impuestos, total, saldo, estado)
    VALUES (p_id_alojamiento, v_subtotal, v_impuestos, v_total, v_total, 'PENDIENTE');

    SET p_id_cuenta = LAST_INSERT_ID();

    -- Detalle: una línea por cada consumo de servicio
    INSERT INTO cuenta_cobrar_detalle (id_cuenta, concepto, cantidad, precio_unitario, subtotal)
    SELECT p_id_cuenta, CONCAT(s.nombre), cs.cantidad, cs.precio_unitario, cs.subtotal
    FROM consumo_servicio cs
    JOIN servicio s ON s.id_servicio = cs.id_servicio
    WHERE cs.id_alojamiento = p_id_alojamiento;

    -- Detalle: una línea por cada daño pendiente
    INSERT INTO cuenta_cobrar_detalle (id_cuenta, concepto, cantidad, precio_unitario, subtotal)
    SELECT p_id_cuenta, CONCAT('Cargo por daño — ', d.descripcion), 1, d.costo, d.costo
    FROM danio d
    WHERE d.id_alojamiento = p_id_alojamiento AND d.estado = 'PENDIENTE';

    UPDATE danio SET estado = 'COBRADO'
    WHERE id_alojamiento = p_id_alojamiento AND estado = 'PENDIENTE';
END$$

-- -------------------------------------------------------------
-- SP 10: sp_registrar_pago_cuenta
-- Registra un abono/pago sobre una cuenta por cobrar. El
-- trigger trg_cuenta_actualizar_saldo (06_Triggers.sql) recalcula
-- el saldo y marca la cuenta como PAGADA cuando llega a 0, tal
-- como pidió el profesor ("saldo se convierte en cero").
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_registrar_pago_cuenta$$
CREATE PROCEDURE sp_registrar_pago_cuenta(
    IN p_id_cuenta INT,
    IN p_monto DECIMAL(12,2),
    IN p_metodo_pago ENUM('EFECTIVO','TARJETA','TRANSFERENCIA','YAPE_PLIN'),
    IN p_id_empleado INT
)
BEGIN
    DECLARE v_saldo DECIMAL(12,2);

    SELECT saldo INTO v_saldo FROM cuenta_cobrar WHERE id_cuenta = p_id_cuenta;

    IF p_monto > v_saldo THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'El monto del pago excede el saldo pendiente';
    END IF;

    INSERT INTO pago_cuenta_cobrar (id_cuenta, monto, metodo_pago, id_empleado)
    VALUES (p_id_cuenta, p_monto, p_metodo_pago, p_id_empleado);
END$$

-- -------------------------------------------------------------
-- SP 11: sp_cambiar_estado_habitacion
-- Cambio MANUAL de estado (limpieza/recepción marcando la
-- habitación lista, reservándola a mano, etc.). OCUPADA queda
-- fuera de este SP a propósito: ese estado lo controlan en
-- exclusiva trg_alojamiento_checkin/_checkout/_cancelar según la
-- ocupación real (ver 06_Triggers.sql); permitir tocarlo a mano
-- desincronizaría habitacion.estado de si hay o no un alojamiento
-- ACTIVO real en la habitación.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cambiar_estado_habitacion$$
CREATE PROCEDURE sp_cambiar_estado_habitacion(
    IN p_id_habitacion INT,
    IN p_nuevo_estado ENUM('DISPONIBLE','RESERVADA','OCUPADA','LIMPIEZA')
)
BEGIN
    DECLARE v_estado_actual VARCHAR(20);

    SELECT estado INTO v_estado_actual FROM habitacion WHERE id_habitacion = p_id_habitacion;

    IF v_estado_actual IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Habitación no encontrada.';
    END IF;

    IF v_estado_actual = 'OCUPADA' OR p_nuevo_estado = 'OCUPADA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El estado OCUPADA solo lo controla el check-in/checkout; no se puede cambiar a mano.';
    END IF;

    IF p_nuevo_estado = v_estado_actual THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La habitación ya está en ese estado.';
    END IF;

    UPDATE habitacion
    SET estado = p_nuevo_estado
    WHERE id_habitacion = p_id_habitacion;
END$$

-- -------------------------------------------------------------
-- SP 12: sp_resumen_ocupacion_hotel
-- Devuelve un resumen de la cantidad de habitaciones por estado
-- para un hotel específico.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_resumen_ocupacion_hotel$$
CREATE PROCEDURE sp_resumen_ocupacion_hotel(
    IN p_id_hotel INT
)
BEGIN
    SELECT
        h.estado,
        COUNT(*) AS cantidad
    FROM habitacion h
    WHERE h.id_hotel = p_id_hotel
    GROUP BY h.estado;
END$$

-- -------------------------------------------------------------
-- SP 13: sp_cancelar_reserva
-- Cancela una reserva que todavía no llegó a un estado final.
-- No se permite cancelar si hay huéspedes actualmente alojados
-- (alojamiento ACTIVO): una reserva con gente hospedada ya no es
-- "cancelable", es una estadía en curso.
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_cancelar_reserva$$
CREATE PROCEDURE sp_cancelar_reserva(
    IN p_id_reserva INT
)
BEGIN
    DECLARE v_estado ENUM('PENDIENTE','CONFIRMADA','CANCELADA','NO_SHOW','FINALIZADA');
    DECLARE v_alojados INT;

    SELECT estado INTO v_estado FROM reserva WHERE id_reserva = p_id_reserva;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva no encontrada';
    END IF;

    IF v_estado IN ('CANCELADA','NO_SHOW','FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva ya está en un estado final; no se puede cancelar.';
    END IF;

    SELECT COUNT(*) INTO v_alojados
    FROM alojamiento WHERE id_reserva = p_id_reserva AND estado = 'ACTIVO';

    IF v_alojados > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede cancelar: hay huéspedes actualmente alojados en esta reserva.';
    END IF;

    UPDATE reserva SET estado = 'CANCELADA' WHERE id_reserva = p_id_reserva;
END$$

-- -------------------------------------------------------------
-- SP 14: sp_marcar_no_show
-- Marca una reserva como NO_SHOW: el cliente no se presentó
-- después de su fecha de check-in prevista. Solo aplica si nunca
-- llegó a tener ningún check-in real (si ya hubo check-in, no fue
-- un no-show, es una estadía que ya empezó).
-- -------------------------------------------------------------
DROP PROCEDURE IF EXISTS sp_marcar_no_show$$
CREATE PROCEDURE sp_marcar_no_show(
    IN p_id_reserva INT
)
BEGIN
    DECLARE v_estado ENUM('PENDIENTE','CONFIRMADA','CANCELADA','NO_SHOW','FINALIZADA');
    DECLARE v_checkin DATE;
    DECLARE v_con_checkin INT;

    SELECT estado, fecha_checkin INTO v_estado, v_checkin FROM reserva WHERE id_reserva = p_id_reserva;
    IF v_estado IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Reserva no encontrada';
    END IF;

    IF v_estado IN ('CANCELADA','NO_SHOW','FINALIZADA') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La reserva ya está en un estado final; no se puede marcar como no-show.';
    END IF;

    IF CURDATE() <= v_checkin THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo se puede marcar como no-show después de la fecha de check-in prevista.';
    END IF;

    SELECT COUNT(*) INTO v_con_checkin
    FROM alojamiento WHERE id_reserva = p_id_reserva;

    IF v_con_checkin > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Esta reserva ya tuvo check-in; no corresponde marcarla como no-show.';
    END IF;

    UPDATE reserva SET estado = 'NO_SHOW' WHERE id_reserva = p_id_reserva;
END$$

DELIMITER ;
