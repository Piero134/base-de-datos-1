-- =============================================================
--  05_Vistas.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Vistas que facilitan las consultas más frecuentes
--               del MVP, evitando repetir JOINs complejos.
--  Ejecutar: QUINTO (orden 5 de 9)
-- =============================================================

USE hotel_db;

-- -------------------------------------------------------------
-- V1. vw_reservante
-- Resuelve el nombre a mostrar de un cliente (natural o
-- jurídica) en un solo campo. Reutilizada por varias vistas.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_reservante AS
SELECT
    c.id_cliente,
    p.id_persona,
    p.tipo AS tipo_persona,
    CONCAT(COALESCE(pn.nombres, pj.razon_social), ' ', COALESCE(pn.apellidos, '')) AS nombre_reservante,
    COALESCE(pn.numero_documento, pj.ruc) AS documento
FROM cliente c
JOIN persona p ON p.id_persona = c.id_persona
LEFT JOIN persona_natural  pn ON pn.id_persona = p.id_persona
LEFT JOIN persona_juridica pj ON pj.id_persona = p.id_persona;

-- -------------------------------------------------------------
-- V2. vw_habitaciones_disponibles
-- Habitaciones cuyo estado puntual es DISPONIBLE, con hotel y
-- tipo. Para disponibilidad por rango de fechas usar
-- fn_disponibilidad_tipo_habitacion().
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_habitaciones_disponibles AS
SELECT
    h.id_habitacion,
    ht.id_hotel,
    ht.nombre AS hotel,
    h.numero,
    h.piso,
    th.id_tipo_habitacion,
    th.nombre AS tipo,
    th.capacidad_base,
    h.descripcion
FROM habitacion h
JOIN hotel ht           ON ht.id_hotel           = h.id_hotel
JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
WHERE h.estado = 'DISPONIBLE';

-- -------------------------------------------------------------
-- V3. vw_reservas_detalle
-- Reservas con su reservante, hotel, estado y totales.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_reservas_detalle AS
SELECT
    r.id_reserva,
    v.nombre_reservante,
    v.tipo_persona,
    ht.nombre AS hotel,
    er.nombre AS estado,
    r.canal,
    r.fecha_checkin,
    r.fecha_checkout,
    fn_calcular_noches(r.fecha_checkin, r.fecha_checkout) AS noches,
    r.monto_total,
    r.pagado,
    r.fecha_pago,
    r.fecha_limite_pago
FROM reserva r
JOIN vw_reservante v ON v.id_cliente = r.id_cliente
JOIN hotel ht         ON ht.id_hotel = r.id_hotel
JOIN estado_reserva er ON er.id_estado_reserva = r.id_estado_reserva;

-- -------------------------------------------------------------
-- V4. vw_alojamientos_activos
-- Quién está hospedado ahora mismo y en qué habitación.
-- -------------------------------------------------------------
-- Solo huéspedes que TODAVÍA están presentes: alojamiento activo
-- Y sin fecha_salida_real individual registrada (un acompañante
-- puede haberse retirado antes que el resto de la habitación).
CREATE OR REPLACE VIEW vw_alojamientos_activos AS
SELECT
    a.id_alojamiento,
    ht.nombre AS hotel,
    h.numero AS habitacion,
    h.piso,
    th.nombre AS tipo,
    CONCAT(hu.nombres, ' ', COALESCE(hu.apellidos, '')) AS huesped,
    hu.es_generico,
    IF(ha.es_titular, 'SÍ', 'NO') AS es_titular,
    a.fecha_checkin_real,
    v.nombre_reservante AS cliente_pagador
FROM alojamiento a
JOIN habitacion h            ON h.id_habitacion       = a.id_habitacion
JOIN hotel ht                ON ht.id_hotel           = h.id_hotel
JOIN tipo_habitacion th      ON th.id_tipo_habitacion = h.id_tipo_habitacion
JOIN huesped_alojamiento ha  ON ha.id_alojamiento     = a.id_alojamiento
                             AND ha.fecha_salida_real  IS NULL
JOIN huesped hu              ON hu.id_huesped         = ha.id_huesped
JOIN reserva r                ON r.id_reserva          = a.id_reserva
JOIN vw_reservante v          ON v.id_cliente          = r.id_cliente
WHERE a.estado = 'ACTIVO';

-- -------------------------------------------------------------
-- V5. vw_historial_estadias
-- Historial completo de alojamientos (activos e histéricos)
-- por huésped.
-- -------------------------------------------------------------
-- La salida de CADA huésped puede ser distinta de la del resto de
-- la habitación (fecha_salida_real); las noches se calculan por
-- huésped, no solo por el checkout general de la habitación.
CREATE OR REPLACE VIEW vw_historial_estadias AS
SELECT
    hu.id_huesped,
    CONCAT(hu.nombres, ' ', COALESCE(hu.apellidos, '')) AS huesped,
    ht.nombre AS hotel,
    h.numero AS habitacion,
    th.nombre AS tipo,
    a.fecha_checkin_real,
    ha.fecha_salida_real AS fecha_salida_huesped,
    a.fecha_checkout_real AS fecha_checkout_habitacion,
    DATEDIFF(COALESCE(ha.fecha_salida_real, NOW()), a.fecha_checkin_real) AS noches,
    a.estado
FROM huesped_alojamiento ha
JOIN huesped hu          ON hu.id_huesped         = ha.id_huesped
JOIN alojamiento a       ON a.id_alojamiento      = ha.id_alojamiento
JOIN habitacion h        ON h.id_habitacion       = a.id_habitacion
JOIN hotel ht            ON ht.id_hotel           = h.id_hotel
JOIN tipo_habitacion th  ON th.id_tipo_habitacion = h.id_tipo_habitacion;

-- -------------------------------------------------------------
-- V6. vw_consumos_alojamiento
-- Consumos de servicio por alojamiento.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_consumos_alojamiento AS
SELECT
    cs.id_alojamiento,
    cat.nombre AS categoria,
    s.nombre AS servicio,
    cs.cantidad,
    cs.precio_unitario,
    cs.subtotal,
    cs.fecha_consumo
FROM consumo_servicio cs
JOIN servicio s             ON s.id_servicio    = cs.id_servicio
JOIN categoria_servicio cat ON cat.id_categoria = s.id_categoria;

-- -------------------------------------------------------------
-- V7. vw_danios_pendientes
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_danios_pendientes AS
SELECT
    d.id_danio,
    ht.nombre AS hotel,
    h.numero AS habitacion,
    d.descripcion,
    d.costo,
    d.fecha_reporte,
    d.estado
FROM danio d
JOIN alojamiento a ON a.id_alojamiento = d.id_alojamiento
JOIN habitacion h  ON h.id_habitacion  = a.id_habitacion
JOIN hotel ht      ON ht.id_hotel      = h.id_hotel
WHERE d.estado = 'PENDIENTE';

-- -------------------------------------------------------------
-- V8. vw_cuenta_cobrar_resumen
-- Estado de cada cuenta por cobrar, con lo pagado y pendiente.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_cuenta_cobrar_resumen AS
SELECT
    cc.id_cuenta,
    cc.id_alojamiento,
    cc.estado AS estado_cuenta,
    cc.subtotal,
    cc.impuestos,
    cc.total,
    cc.saldo AS saldo_pendiente,
    cc.total - cc.saldo AS ya_pagado,
    cc.fecha_generacion
FROM cuenta_cobrar cc;

-- -------------------------------------------------------------
-- V9. vw_ingresos_por_hotel
-- Ingresos por hospedaje (reservas confirmadas) + servicios.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ingresos_por_hotel AS
SELECT
    ht.id_hotel,
    ht.nombre AS hotel,
    COUNT(DISTINCT r.id_reserva) AS reservas_confirmadas,
    SUM(r.monto_total) AS ingresos_hospedaje,
    COALESCE(SUM(cs_total.total_consumo), 0) AS ingresos_servicios,
    SUM(r.monto_total) + COALESCE(SUM(cs_total.total_consumo), 0) AS ingreso_total
FROM reserva r
JOIN hotel ht ON ht.id_hotel = r.id_hotel
LEFT JOIN (
    SELECT a.id_reserva, SUM(cs.subtotal) AS total_consumo
    FROM consumo_servicio cs
    JOIN alojamiento a ON a.id_alojamiento = cs.id_alojamiento
    GROUP BY a.id_reserva
) cs_total ON cs_total.id_reserva = r.id_reserva
WHERE r.id_estado_reserva = 2  -- CONFIRMADA
GROUP BY ht.id_hotel, ht.nombre;

-- -------------------------------------------------------------
-- V10. vw_ranking_clientes
-- Ranking de clientes por monto total gastado (hospedaje).
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ranking_clientes AS
SELECT
    v.id_cliente,
    v.nombre_reservante,
    v.tipo_persona,
    COUNT(r.id_reserva) AS total_reservas,
    SUM(r.monto_total) AS monto_total_gastado,
    RANK() OVER (ORDER BY SUM(r.monto_total) DESC) AS ranking
FROM reserva r
JOIN vw_reservante v ON v.id_cliente = r.id_cliente
WHERE r.id_estado_reserva IN (2, 5) -- CONFIRMADA o FINALIZADA
GROUP BY v.id_cliente, v.nombre_reservante, v.tipo_persona;

-- -------------------------------------------------------------
-- V11. vw_ocupacion_hotel
-- Estado agregado de habitaciones por hotel y tipo.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_ocupacion_hotel AS
SELECT
    ht.id_hotel,
    ht.nombre AS hotel,
    th.nombre AS tipo,
    COUNT(h.id_habitacion) AS total_habitaciones,
    SUM(h.estado = 'DISPONIBLE') AS disponibles,
    SUM(h.estado = 'RESERVADA')  AS reservadas,
    SUM(h.estado = 'OCUPADA')    AS ocupadas,
    SUM(h.estado = 'LIMPIEZA')   AS en_limpieza
FROM habitacion h
JOIN hotel ht           ON ht.id_hotel           = h.id_hotel
JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
GROUP BY ht.id_hotel, ht.nombre, th.nombre;

-- -------------------------------------------------------------
-- V12. vw_reservas_corporativas
-- Reservas hechas por personas jurídicas, con la pre-asignación
-- de huéspedes (empleados de la empresa).
-- -------------------------------------------------------------
-- Nota: la empresa que paga se obtiene de reserva.id_cliente (a
-- través de reserva_detalle), NO desde detalle_huesped_reserva:
-- esa tabla ya no guarda id_cliente porque toda la reserva
-- comparte un único pagador, definido a nivel de cabecera.
CREATE OR REPLACE VIEW vw_reservas_corporativas AS
SELECT
    r.id_reserva,
    pj.razon_social AS empresa,
    th.nombre AS tipo_habitacion,
    rd.cantidad_habitaciones,
    CONCAT(hu.nombres, ' ', COALESCE(hu.apellidos, '')) AS huesped_asignado,
    hu.numero_documento,
    IF(dhr.es_titular, 'SÍ', 'NO') AS es_titular
FROM detalle_huesped_reserva dhr
JOIN reserva_detalle  rd  ON rd.id_detalle_reserva = dhr.id_detalle_reserva
JOIN reserva          r   ON r.id_reserva          = rd.id_reserva
JOIN tipo_habitacion  th  ON th.id_tipo_habitacion = rd.id_tipo_habitacion
JOIN huesped          hu  ON hu.id_huesped         = dhr.id_huesped
JOIN cliente          c   ON c.id_cliente          = r.id_cliente
JOIN persona          p   ON p.id_persona          = c.id_persona
JOIN persona_juridica pj  ON pj.id_persona         = p.id_persona;

-- -------------------------------------------------------------
-- V14 (NUEVA). vw_preasignacion_vs_checkin
-- Compara, para reservas corporativas con pre-asignación, quién
-- fue asignado por la empresa (detalle_huesped_reserva) contra
-- quién realmente hizo check-in (huesped_alojamiento), usando el
-- enlace de trazabilidad id_detalle_huesped. Responde al punto
-- que el profesor mencionó en la asesoría sobre controlar quién
-- ocupa cada habitación en reservas grupales/corporativas.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_preasignacion_vs_checkin AS
SELECT
    dhr.id_detalle_huesped,
    r.id_reserva,
    th.nombre AS tipo_habitacion,
    CONCAT(hu_pre.nombres, ' ', COALESCE(hu_pre.apellidos, '')) AS huesped_preasignado,
    ha.id_alojamiento,
    CONCAT(hu_real.nombres, ' ', COALESCE(hu_real.apellidos, '')) AS huesped_checkin_real,
    IF(dhr.id_huesped = ha.id_huesped, 'COINCIDE', 'DIFERENTE') AS coincidencia
FROM detalle_huesped_reserva dhr
JOIN reserva_detalle rd ON rd.id_detalle_reserva = dhr.id_detalle_reserva
JOIN reserva r          ON r.id_reserva          = rd.id_reserva
JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
JOIN huesped hu_pre     ON hu_pre.id_huesped      = dhr.id_huesped
LEFT JOIN huesped_alojamiento ha ON ha.id_detalle_huesped = dhr.id_detalle_huesped
LEFT JOIN huesped hu_real        ON hu_real.id_huesped    = ha.id_huesped;

-- -------------------------------------------------------------
-- V13. vw_checkouts_pendientes
-- Alojamientos activos cuya fecha de checkout planificada
-- (según la reserva) ya venció o vence hoy.
-- -------------------------------------------------------------
CREATE OR REPLACE VIEW vw_checkouts_pendientes AS
SELECT
    a.id_alojamiento,
    ht.nombre AS hotel,
    h.numero AS habitacion,
    r.fecha_checkout AS checkout_planificado,
    a.fecha_checkin_real,
    v.nombre_reservante AS cliente
FROM alojamiento a
JOIN reserva r        ON r.id_reserva = a.id_reserva
JOIN habitacion h     ON h.id_habitacion = a.id_habitacion
JOIN hotel ht         ON ht.id_hotel = h.id_hotel
JOIN vw_reservante v  ON v.id_cliente = r.id_cliente
WHERE a.estado = 'ACTIVO'
  AND r.fecha_checkout <= CURDATE();
