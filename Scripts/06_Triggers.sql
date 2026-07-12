-- =============================================================
--  06_Triggers.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Triggers de integridad operativa. Se incluyen
--               únicamente donde aportan valor real al negocio
--               (sincronización de estados/stock, inicialización
--               de saldos, validaciones que un CHECK no puede
--               expresar). Se evita lógica redundante con lo que
--               ya hacen los procedimientos almacenados; los
--               triggers aquí actúan como red de seguridad para
--               cualquier operación directa sobre las tablas.
--  Ejecutar: SEXTO (orden 6 de 9)
-- =============================================================

USE hotel_db;

DELIMITER $$

-- ──────────────────────────────────────────────────────────────
-- (Se eliminó el trigger que descontaba "stock_disponible" al
--  confirmar el pago: esa columna se eliminó de tipo_habitacion
--  porque, al ser un catálogo global no ligado a un hotel, un
--  contador único mezclaba la disponibilidad de todos los
--  hoteles y no servía para consultas por rango de fechas. La
--  disponibilidad real ahora se calcula siempre con
--  fn_disponibilidad_tipo_habitacion(); sp_confirmar_pago sigue
--  actualizando el estado de la reserva normalmente.)
-- ──────────────────────────────────────────────────────────────

-- ──────────────────────────────────────────────────────────────
-- T2. Al hacer CHECK-IN (insertar alojamiento):
--     → cambia el estado de la habitación a OCUPADA
--     Solo si la fila nace ACTIVO: una carga de datos histórica
--     puede insertar un alojamiento ya FINALIZADO/CANCELADO (una
--     estadía pasada), y en ese caso la habitación no debe quedar
--     marcada como ocupada por alguien que ya no está.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_checkin$$
CREATE TRIGGER trg_alojamiento_checkin
AFTER INSERT ON alojamiento
FOR EACH ROW
BEGIN
    IF NEW.estado = 'ACTIVO' THEN
        UPDATE habitacion
        SET estado = 'OCUPADA'
        WHERE id_habitacion = NEW.id_habitacion;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T3. Al hacer CHECK-OUT (alojamiento pasa a FINALIZADO):
--     → cambia el estado de la habitación a LIMPIEZA
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_checkout$$
CREATE TRIGGER trg_alojamiento_checkout
AFTER UPDATE ON alojamiento
FOR EACH ROW
BEGIN
    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'FINALIZADO' THEN
        UPDATE habitacion
        SET estado = 'LIMPIEZA'
        WHERE id_habitacion = NEW.id_habitacion;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T4. Al cancelar alojamiento:
--     → habitación vuelve a DISPONIBLE
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_cancelar$$
CREATE TRIGGER trg_alojamiento_cancelar
AFTER UPDATE ON alojamiento
FOR EACH ROW
BEGIN
    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'CANCELADO' THEN
        UPDATE habitacion
        SET estado = 'DISPONIBLE'
        WHERE id_habitacion = NEW.id_habitacion;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T3b (NUEVO). Regla "habitación libre solo cuando todos
--     salieron": antes de permitir que un alojamiento pase de
--     ACTIVO a FINALIZADO, exige que TODOS sus huéspedes tengan
--     fecha_salida_real registrada en huesped_alojamiento. Red de
--     seguridad para cualquier UPDATE directo sobre alojamiento
--     que no pase por sp_registrar_salida_huesped /
--     sp_realizar_checkout.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_checkout_validar$$
CREATE TRIGGER trg_alojamiento_checkout_validar
BEFORE UPDATE ON alojamiento
FOR EACH ROW
BEGIN
    DECLARE v_pendientes INT;

    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'FINALIZADO' THEN
        SELECT COUNT(*) INTO v_pendientes
        FROM huesped_alojamiento
        WHERE id_alojamiento = NEW.id_alojamiento
          AND fecha_salida_real IS NULL;

        IF v_pendientes > 0 THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede finalizar: aún hay huéspedes sin registrar su salida en esta habitación';
        END IF;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T5. Al crear cuenta_cobrar: garantiza saldo = total al inicio
--     (regla explícita del profesor: "el saldo tiene que ser
--     exactamente el mismo monto que la facturación").
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_cuenta_cobrar_insert$$
CREATE TRIGGER trg_cuenta_cobrar_insert
BEFORE INSERT ON cuenta_cobrar
FOR EACH ROW
BEGIN
    SET NEW.saldo = NEW.total;
END$$

-- ──────────────────────────────────────────────────────────────
-- T6. Validación: fecha_checkin_real no puede ser posterior o
--     igual a fecha_checkout_real en alojamiento.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_fechas_insert$$
CREATE TRIGGER trg_alojamiento_fechas_insert
BEFORE INSERT ON alojamiento
FOR EACH ROW
BEGIN
    IF NEW.fecha_checkout_real IS NOT NULL
       AND NEW.fecha_checkout_real <= NEW.fecha_checkin_real THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'fecha_checkout_real debe ser posterior a fecha_checkin_real';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_alojamiento_fechas_update$$
CREATE TRIGGER trg_alojamiento_fechas_update
BEFORE UPDATE ON alojamiento
FOR EACH ROW
BEGIN
    IF NEW.fecha_checkout_real IS NOT NULL
       AND NEW.fecha_checkout_real <= NEW.fecha_checkin_real THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'fecha_checkout_real debe ser posterior a fecha_checkin_real';
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T7 (NUEVO). Capacidad máxima de huéspedes por habitación.
--     Red de seguridad a nivel de tabla para la regla de negocio
--     comentada por el profesor: una doble admite máximo 2
--     personas, una simple máximo 1, etc. sp_agregar_huesped_
--     alojamiento ya valida esto, pero este trigger protege
--     también inserciones directas a huesped_alojamiento.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_huesped_alojamiento_capacidad$$
CREATE TRIGGER trg_huesped_alojamiento_capacidad
BEFORE INSERT ON huesped_alojamiento
FOR EACH ROW
BEGIN
    DECLARE v_capacidad TINYINT;
    DECLARE v_ocupantes INT;

    SELECT th.capacidad_base INTO v_capacidad
    FROM alojamiento a
    JOIN habitacion h ON h.id_habitacion = a.id_habitacion
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
    WHERE a.id_alojamiento = NEW.id_alojamiento;

    SELECT COUNT(*) INTO v_ocupantes
    FROM huesped_alojamiento
    WHERE id_alojamiento = NEW.id_alojamiento;

    IF v_ocupantes >= v_capacidad THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Se alcanzó la capacidad máxima de huéspedes para esta habitación';
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T8 (NUEVO). Al registrar un pago en pago_cuenta_cobrar:
--     → recalcula el saldo de la cuenta (total - pagos)
--     → marca la cuenta como PAGADA cuando el saldo llega a 0
--     Cumple la indicación del profesor: "cuando ya paga, ese
--     saldo es cero".
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_cuenta_actualizar_saldo$$
CREATE TRIGGER trg_cuenta_actualizar_saldo
AFTER INSERT ON pago_cuenta_cobrar
FOR EACH ROW
BEGIN
    UPDATE cuenta_cobrar
    SET saldo = fn_saldo_cuenta(NEW.id_cuenta),
        estado = IF(fn_saldo_cuenta(NEW.id_cuenta) <= 0, 'PAGADA', 'PENDIENTE')
    WHERE id_cuenta = NEW.id_cuenta;
END$$

-- ──────────────────────────────────────────────────────────────
-- T9 (NUEVO). Consistencia del discriminador persona.tipo:
--     una fila en persona_natural exige que su persona padre
--     tenga tipo = 'NATURAL'; una fila en persona_juridica exige
--     tipo = 'JURIDICA'. Antes no existía ninguna validación que
--     impidiera, por ejemplo, insertar el subtipo equivocado para
--     una persona ya marcada como NATURAL.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_pnatural_validar_tipo$$
CREATE TRIGGER trg_pnatural_validar_tipo
BEFORE INSERT ON persona_natural
FOR EACH ROW
BEGIN
    DECLARE v_tipo ENUM('NATURAL','JURIDICA');

    SELECT tipo INTO v_tipo FROM persona WHERE id_persona = NEW.id_persona;

    IF v_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La persona referenciada no existe';
    ELSEIF v_tipo <> 'NATURAL' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede registrar persona_natural para una persona marcada como JURIDICA';
    END IF;

    IF EXISTS (SELECT 1 FROM persona_juridica WHERE id_persona = NEW.id_persona) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Esta persona ya tiene un registro en persona_juridica; no puede tener ambos subtipos';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_pjuridica_validar_tipo$$
CREATE TRIGGER trg_pjuridica_validar_tipo
BEFORE INSERT ON persona_juridica
FOR EACH ROW
BEGIN
    DECLARE v_tipo ENUM('NATURAL','JURIDICA');

    SELECT tipo INTO v_tipo FROM persona WHERE id_persona = NEW.id_persona;

    IF v_tipo IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'La persona referenciada no existe';
    ELSEIF v_tipo <> 'JURIDICA' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede registrar persona_juridica para una persona marcada como NATURAL';
    END IF;

    IF EXISTS (SELECT 1 FROM persona_natural WHERE id_persona = NEW.id_persona) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Esta persona ya tiene un registro en persona_natural; no puede tener ambos subtipos';
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T10 (NUEVO). Bloquea cambiar persona.tipo si ya existe un
--     subtipo cargado con el tipo anterior (evita dejar
--     "huérfano" un registro en persona_natural/persona_juridica
--     al cambiar el discriminador).
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_persona_validar_cambio_tipo$$
CREATE TRIGGER trg_persona_validar_cambio_tipo
BEFORE UPDATE ON persona
FOR EACH ROW
BEGIN
    IF OLD.tipo <> NEW.tipo THEN
        IF OLD.tipo = 'NATURAL' AND EXISTS (SELECT 1 FROM persona_natural WHERE id_persona = OLD.id_persona) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede cambiar el tipo: existe un registro en persona_natural asociado';
        ELSEIF OLD.tipo = 'JURIDICA' AND EXISTS (SELECT 1 FROM persona_juridica WHERE id_persona = OLD.id_persona) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'No se puede cambiar el tipo: existe un registro en persona_juridica asociado';
        END IF;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T11 (NUEVO). reserva.monto_total siempre igual a
--     SUM(reserva_detalle.subtotal): antes solo lo mantenía
--     sp_agregar_detalle_reserva con un UPDATE manual, así que un
--     INSERT/UPDATE/DELETE directo sobre reserva_detalle (como hace
--     la propia carga de datos) lo dejaba desincronizado.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_reserva_detalle_monto_ai$$
CREATE TRIGGER trg_reserva_detalle_monto_ai
AFTER INSERT ON reserva_detalle
FOR EACH ROW
BEGIN
    UPDATE reserva
    SET monto_total = (SELECT COALESCE(SUM(subtotal), 0) FROM reserva_detalle WHERE id_reserva = NEW.id_reserva)
    WHERE id_reserva = NEW.id_reserva;
END$$

DROP TRIGGER IF EXISTS trg_reserva_detalle_monto_au$$
CREATE TRIGGER trg_reserva_detalle_monto_au
AFTER UPDATE ON reserva_detalle
FOR EACH ROW
BEGIN
    UPDATE reserva
    SET monto_total = (SELECT COALESCE(SUM(subtotal), 0) FROM reserva_detalle WHERE id_reserva = NEW.id_reserva)
    WHERE id_reserva = NEW.id_reserva;
END$$

DROP TRIGGER IF EXISTS trg_reserva_detalle_monto_ad$$
CREATE TRIGGER trg_reserva_detalle_monto_ad
AFTER DELETE ON reserva_detalle
FOR EACH ROW
BEGIN
    UPDATE reserva
    SET monto_total = (SELECT COALESCE(SUM(subtotal), 0) FROM reserva_detalle WHERE id_reserva = OLD.id_reserva)
    WHERE id_reserva = OLD.id_reserva;
END$$

-- ──────────────────────────────────────────────────────────────
-- T12 (NUEVO). cuenta_cobrar.subtotal/impuestos/total siempre
--     iguales a SUM(cuenta_cobrar_detalle.subtotal) + IGV 18%:
--     antes solo se calculaban una vez al generar la cuenta
--     (sp_generar_cuenta_cobrar) y nada los recalculaba si el
--     detalle cambiaba después.
-- ──────────────────────────────────────────────────────────────
-- saldo también se recalcula aquí (total - pagos ya registrados), no solo
-- en trg_cuenta_actualizar_saldo: si el detalle cambia, el saldo pendiente
-- cambia con él, y chk_cuenta_saldo (saldo <= total) exige que ambos
-- columnas se muevan juntas dentro del mismo UPDATE.
DROP TRIGGER IF EXISTS trg_cuenta_detalle_total_ai$$
CREATE TRIGGER trg_cuenta_detalle_total_ai
AFTER INSERT ON cuenta_cobrar_detalle
FOR EACH ROW
BEGIN
    DECLARE v_subtotal DECIMAL(12,2);
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);

    SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM cuenta_cobrar_detalle WHERE id_cuenta = NEW.id_cuenta;
    SET v_total = ROUND(v_subtotal * 1.18, 2);
    SELECT COALESCE(SUM(monto), 0) INTO v_pagado FROM pago_cuenta_cobrar WHERE id_cuenta = NEW.id_cuenta;

    UPDATE cuenta_cobrar
    SET subtotal = v_subtotal,
        impuestos = ROUND(v_subtotal * 0.18, 2),
        total = v_total,
        saldo = v_total - v_pagado
    WHERE id_cuenta = NEW.id_cuenta;
END$$

DROP TRIGGER IF EXISTS trg_cuenta_detalle_total_au$$
CREATE TRIGGER trg_cuenta_detalle_total_au
AFTER UPDATE ON cuenta_cobrar_detalle
FOR EACH ROW
BEGIN
    DECLARE v_subtotal DECIMAL(12,2);
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);

    SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM cuenta_cobrar_detalle WHERE id_cuenta = NEW.id_cuenta;
    SET v_total = ROUND(v_subtotal * 1.18, 2);
    SELECT COALESCE(SUM(monto), 0) INTO v_pagado FROM pago_cuenta_cobrar WHERE id_cuenta = NEW.id_cuenta;

    UPDATE cuenta_cobrar
    SET subtotal = v_subtotal,
        impuestos = ROUND(v_subtotal * 0.18, 2),
        total = v_total,
        saldo = v_total - v_pagado
    WHERE id_cuenta = NEW.id_cuenta;
END$$

DROP TRIGGER IF EXISTS trg_cuenta_detalle_total_ad$$
CREATE TRIGGER trg_cuenta_detalle_total_ad
AFTER DELETE ON cuenta_cobrar_detalle
FOR EACH ROW
BEGIN
    DECLARE v_subtotal DECIMAL(12,2);
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_pagado DECIMAL(12,2);

    SELECT COALESCE(SUM(subtotal), 0) INTO v_subtotal FROM cuenta_cobrar_detalle WHERE id_cuenta = OLD.id_cuenta;
    SET v_total = ROUND(v_subtotal * 1.18, 2);
    SELECT COALESCE(SUM(monto), 0) INTO v_pagado FROM pago_cuenta_cobrar WHERE id_cuenta = OLD.id_cuenta;

    UPDATE cuenta_cobrar
    SET subtotal = v_subtotal,
        impuestos = ROUND(v_subtotal * 0.18, 2),
        total = v_total,
        saldo = v_total - v_pagado
    WHERE id_cuenta = OLD.id_cuenta;
END$$

-- ──────────────────────────────────────────────────────────────
-- T13 (NUEVO). trg_cuenta_actualizar_saldo (T8) solo recalculaba el
--     saldo cuando se INSERTABA un pago; un pago corregido o
--     eliminado (operación real de caja) dejaba el saldo
--     desactualizado. Se agregan los mismos efectos para
--     UPDATE/DELETE sobre pago_cuenta_cobrar.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_cuenta_actualizar_saldo_au$$
CREATE TRIGGER trg_cuenta_actualizar_saldo_au
AFTER UPDATE ON pago_cuenta_cobrar
FOR EACH ROW
BEGIN
    UPDATE cuenta_cobrar
    SET saldo = fn_saldo_cuenta(NEW.id_cuenta),
        estado = IF(fn_saldo_cuenta(NEW.id_cuenta) <= 0, 'PAGADA', 'PENDIENTE')
    WHERE id_cuenta = NEW.id_cuenta;
END$$

DROP TRIGGER IF EXISTS trg_cuenta_actualizar_saldo_ad$$
CREATE TRIGGER trg_cuenta_actualizar_saldo_ad
AFTER DELETE ON pago_cuenta_cobrar
FOR EACH ROW
BEGIN
    UPDATE cuenta_cobrar
    SET saldo = fn_saldo_cuenta(OLD.id_cuenta),
        estado = IF(fn_saldo_cuenta(OLD.id_cuenta) <= 0, 'PAGADA', 'PENDIENTE')
    WHERE id_cuenta = OLD.id_cuenta;
END$$

-- ──────────────────────────────────────────────────────────────
-- T14 (NUEVO). El alcance de un usuario (usuario.id_hotel) debe
--     coincidir con el hotel de empleo, salvo para ADMINISTRADOR
--     (que puede ser general, id_hotel NULL, o estar asignado a un
--     hotel distinto del de empleo). Antes nada impedía que un
--     RECEPCION/CAJA/GERENCIA quedara con un alcance que no
--     correspondía a donde realmente trabaja.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_usuario_validar_alcance_bi$$
CREATE TRIGGER trg_usuario_validar_alcance_bi
BEFORE INSERT ON usuario
FOR EACH ROW
BEGIN
    DECLARE v_id_hotel_empleado INT;
    SELECT id_hotel INTO v_id_hotel_empleado FROM empleado WHERE id_empleado = NEW.id_empleado;
    IF NEW.rol <> 'ADMINISTRADOR' AND (NEW.id_hotel IS NULL OR NEW.id_hotel <> v_id_hotel_empleado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El alcance de este rol debe ser el mismo hotel donde trabaja el empleado';
    END IF;
END$$

DROP TRIGGER IF EXISTS trg_usuario_validar_alcance_bu$$
CREATE TRIGGER trg_usuario_validar_alcance_bu
BEFORE UPDATE ON usuario
FOR EACH ROW
BEGIN
    DECLARE v_id_hotel_empleado INT;
    SELECT id_hotel INTO v_id_hotel_empleado FROM empleado WHERE id_empleado = NEW.id_empleado;
    IF NEW.rol <> 'ADMINISTRADOR' AND (NEW.id_hotel IS NULL OR NEW.id_hotel <> v_id_hotel_empleado) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El alcance de este rol debe ser el mismo hotel donde trabaja el empleado';
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T15 (NUEVO). trg_valida_cupos_reserva — una línea de reserva
--     (reserva_detalle) reserva cantidad_habitaciones habitaciones
--     de un tipo con capacidad_base huéspedes cada una; el total de
--     cupos (identificados o no) en detalle_huesped_reserva para esa
--     línea nunca puede superar cantidad_habitaciones × capacidad_base.
--     Antes de este trigger nada limitaba cuántas filas se insertaban
--     por línea (hallazgo de la auditoría de app: reservas/routes.py
--     no validaba esto en ningún punto).
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_valida_cupos_reserva$$
CREATE TRIGGER trg_valida_cupos_reserva
BEFORE INSERT ON detalle_huesped_reserva
FOR EACH ROW
BEGIN
    DECLARE v_max INT;
    DECLARE v_actual INT;

    SELECT rd.cantidad_habitaciones * th.capacidad_base INTO v_max
    FROM reserva_detalle rd
    JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
    WHERE rd.id_detalle_reserva = NEW.id_detalle_reserva;

    SELECT COUNT(*) INTO v_actual
    FROM detalle_huesped_reserva
    WHERE id_detalle_reserva = NEW.id_detalle_reserva;

    IF v_actual >= v_max THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Se excede la capacidad de la línea de reserva.';
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T16 (NUEVO). reserva.estado pasa a FINALIZADA automáticamente
--     cuando termina el último alojamiento ACTIVO de esa reserva
--     (checkout completo de todas las habitaciones que sí llegaron
--     a tener check-in). Si la reserva reservó líneas que nunca
--     tuvieron check-in, no bloquea la finalización: se considera
--     terminada la estadía, no el cumplimiento de cada línea
--     reservada.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_reserva_finalizar$$
CREATE TRIGGER trg_reserva_finalizar
AFTER UPDATE ON alojamiento
FOR EACH ROW
BEGIN
    DECLARE v_activos INT;

    IF OLD.estado = 'ACTIVO' AND NEW.estado = 'FINALIZADO' THEN
        SELECT COUNT(*) INTO v_activos
        FROM alojamiento
        WHERE id_reserva = NEW.id_reserva AND estado = 'ACTIVO';

        IF v_activos = 0 THEN
            UPDATE reserva SET estado = 'FINALIZADA' WHERE id_reserva = NEW.id_reserva;
        END IF;
    END IF;
END$$

-- ──────────────────────────────────────────────────────────────
-- T17 (NUEVO). Una habitación física no puede tener más de un
--     alojamiento ACTIVO al mismo tiempo. sp_realizar_checkin ya
--     lo valida antes de insertar, pero ese chequeo se salta si
--     alguien inserta directo en `alojamiento` (carga de datos,
--     script manual, etc.); este trigger es la red de seguridad a
--     nivel de tabla, mismo espíritu que trg_huesped_alojamiento_
--     capacidad para huesped_alojamiento.
-- ──────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_alojamiento_habitacion_unica$$
CREATE TRIGGER trg_alojamiento_habitacion_unica
BEFORE INSERT ON alojamiento
FOR EACH ROW
BEGIN
    IF NEW.estado = 'ACTIVO' AND EXISTS (
        SELECT 1 FROM alojamiento
        WHERE id_habitacion = NEW.id_habitacion AND estado = 'ACTIVO'
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Esta habitación ya tiene un alojamiento activo.';
    END IF;
END$$

DELIMITER ;
