-- =============================================================
--  02_Reglas_Integridad.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Claves foráneas, índices, UNIQUE y CHECK.
--               Los TRIGGERS se movieron a 06_Triggers.sql para
--               respetar la separación de entregables pedida en
--               las directivas del curso.
--  Ejecutar: SEGUNDO (orden 2 de 9), después de
--            01_Creacion_Tablas.sql
-- =============================================================

USE hotel_db;

-- =============================================================
--  A. CLAVES FORÁNEAS
--     Convención de nombres: fk_<tabla_hija>_<tabla_padre>
-- =============================================================

-- ── hotel ────────────────────────────────────────────────────
ALTER TABLE hotel
    ADD CONSTRAINT fk_hotel_ubigeo
        FOREIGN KEY (id_ubigeo)  REFERENCES ubigeo (id_ubigeo)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── empleado ─────────────────────────────────────────────────
ALTER TABLE empleado
    ADD CONSTRAINT fk_empleado_hotel
        FOREIGN KEY (id_hotel)   REFERENCES hotel  (id_hotel)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_empleado_cargo
        FOREIGN KEY (id_cargo)   REFERENCES cargo_empleado (id_cargo)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── usuario ──────────────────────────────────────────────────
ALTER TABLE usuario
    ADD CONSTRAINT fk_usuario_empleado
        FOREIGN KEY (id_empleado) REFERENCES empleado (id_empleado)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_usuario_hotel
        FOREIGN KEY (id_hotel)    REFERENCES hotel (id_hotel)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── persona ───────────────────────────────────────────────────
ALTER TABLE persona
    ADD CONSTRAINT fk_persona_ubigeo
        FOREIGN KEY (id_ubigeo)  REFERENCES ubigeo (id_ubigeo)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ── persona_natural ───────────────────────────────────────────
ALTER TABLE persona_natural
    ADD CONSTRAINT fk_pnatural_persona
        FOREIGN KEY (id_persona)         REFERENCES persona        (id_persona)
        ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT fk_pnatural_tipo_doc
        FOREIGN KEY (id_tipo_documento)  REFERENCES tipo_documento (id_tipo_documento)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── persona_juridica ──────────────────────────────────────────
ALTER TABLE persona_juridica
    ADD CONSTRAINT fk_pjuridica_persona
        FOREIGN KEY (id_persona)         REFERENCES persona (id_persona)
        ON UPDATE CASCADE ON DELETE CASCADE;

-- ── cliente ───────────────────────────────────────────────────
ALTER TABLE cliente
    ADD CONSTRAINT fk_cliente_persona
        FOREIGN KEY (id_persona)         REFERENCES persona (id_persona)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── habitacion ────────────────────────────────────────────────
ALTER TABLE habitacion
    ADD CONSTRAINT fk_habitacion_hotel
        FOREIGN KEY (id_hotel)           REFERENCES hotel          (id_hotel)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_habitacion_tipo
        FOREIGN KEY (id_tipo_habitacion) REFERENCES tipo_habitacion (id_tipo_habitacion)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── tarifa_habitacion ─────────────────────────────────────────
ALTER TABLE tarifa_habitacion
    ADD CONSTRAINT fk_tarifa_plan
        FOREIGN KEY (id_plan)            REFERENCES plan_tarifa     (id_plan)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_tarifa_tipo_hab
        FOREIGN KEY (id_tipo_habitacion) REFERENCES tipo_habitacion (id_tipo_habitacion)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── reserva ───────────────────────────────────────────────────
ALTER TABLE reserva
    ADD CONSTRAINT fk_reserva_cliente
        FOREIGN KEY (id_cliente)         REFERENCES cliente       (id_cliente)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_reserva_hotel
        FOREIGN KEY (id_hotel)           REFERENCES hotel         (id_hotel)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_reserva_empleado
        FOREIGN KEY (id_empleado)        REFERENCES empleado      (id_empleado)
        ON UPDATE CASCADE ON DELETE SET NULL,
    ADD CONSTRAINT fk_reserva_contacto
        FOREIGN KEY (id_cliente_contacto) REFERENCES cliente      (id_cliente)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ── reserva_detalle ───────────────────────────────────────────
ALTER TABLE reserva_detalle
    ADD CONSTRAINT fk_rdetalle_reserva
        FOREIGN KEY (id_reserva)         REFERENCES reserva        (id_reserva)
        ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT fk_rdetalle_tipo_hab
        FOREIGN KEY (id_tipo_habitacion) REFERENCES tipo_habitacion (id_tipo_habitacion)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_rdetalle_plan
        FOREIGN KEY (id_plan)            REFERENCES plan_tarifa    (id_plan)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── detalle_huesped_reserva ───────────────────────────────────
-- id_huesped referencia persona_natural directo (no hay tabla huesped
-- intermedia): "huésped" es un rol que cualquier persona_natural puede
-- cumplir, no una identidad aparte. Ver comentario en 01_Creacion_Tablas.
ALTER TABLE detalle_huesped_reserva
    ADD CONSTRAINT fk_dhr_detalle_reserva
        FOREIGN KEY (id_detalle_reserva) REFERENCES reserva_detalle (id_detalle_reserva)
        ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT fk_dhr_huesped
        FOREIGN KEY (id_huesped)         REFERENCES persona_natural (id_persona)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── alojamiento ───────────────────────────────────────────────
ALTER TABLE alojamiento
    ADD CONSTRAINT fk_aloj_reserva
        FOREIGN KEY (id_reserva)          REFERENCES reserva         (id_reserva)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_aloj_detalle_reserva
        FOREIGN KEY (id_detalle_reserva)  REFERENCES reserva_detalle (id_detalle_reserva)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_aloj_habitacion
        FOREIGN KEY (id_habitacion)       REFERENCES habitacion      (id_habitacion)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_aloj_emp_checkin
        FOREIGN KEY (id_empleado_checkin) REFERENCES empleado        (id_empleado)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_aloj_emp_checkout
        FOREIGN KEY (id_empleado_checkout) REFERENCES empleado       (id_empleado)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ── huesped_alojamiento ───────────────────────────────────────
ALTER TABLE huesped_alojamiento
    ADD CONSTRAINT fk_haloj_alojamiento
        FOREIGN KEY (id_alojamiento)     REFERENCES alojamiento (id_alojamiento)
        ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT fk_haloj_huesped
        FOREIGN KEY (id_huesped)         REFERENCES persona_natural (id_persona)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_haloj_detalle_huesped
        FOREIGN KEY (id_detalle_huesped) REFERENCES detalle_huesped_reserva (id_detalle_huesped)
        ON UPDATE CASCADE ON DELETE SET NULL;

-- ── servicio ──────────────────────────────────────────────────
ALTER TABLE servicio
    ADD CONSTRAINT fk_servicio_categoria
        FOREIGN KEY (id_categoria) REFERENCES categoria_servicio (id_categoria)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── consumo_servicio ──────────────────────────────────────────
ALTER TABLE consumo_servicio
    ADD CONSTRAINT fk_consumo_alojamiento
        FOREIGN KEY (id_alojamiento)     REFERENCES alojamiento (id_alojamiento)
        ON UPDATE CASCADE ON DELETE RESTRICT,
    ADD CONSTRAINT fk_consumo_servicio
        FOREIGN KEY (id_servicio)        REFERENCES servicio    (id_servicio)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── danio ─────────────────────────────────────────────────────
ALTER TABLE danio
    ADD CONSTRAINT fk_danio_alojamiento
        FOREIGN KEY (id_alojamiento)     REFERENCES alojamiento (id_alojamiento)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── cuenta_cobrar ─────────────────────────────────────────────
ALTER TABLE cuenta_cobrar
    ADD CONSTRAINT fk_cuenta_alojamiento
        FOREIGN KEY (id_alojamiento)     REFERENCES alojamiento (id_alojamiento)
        ON UPDATE CASCADE ON DELETE RESTRICT;

-- ── cuenta_cobrar_detalle ─────────────────────────────────────
ALTER TABLE cuenta_cobrar_detalle
    ADD CONSTRAINT fk_cdetalle_cuenta
        FOREIGN KEY (id_cuenta)          REFERENCES cuenta_cobrar (id_cuenta)
        ON UPDATE CASCADE ON DELETE CASCADE;

-- ── pago_cuenta_cobrar ────────────────────────────────────────
ALTER TABLE pago_cuenta_cobrar
    ADD CONSTRAINT fk_pago_cuenta
        FOREIGN KEY (id_cuenta)          REFERENCES cuenta_cobrar (id_cuenta)
        ON UPDATE CASCADE ON DELETE CASCADE,
    ADD CONSTRAINT fk_pago_empleado
        FOREIGN KEY (id_empleado)        REFERENCES empleado (id_empleado)
        ON UPDATE CASCADE ON DELETE SET NULL;


-- =============================================================
--  B. RESTRICCIONES UNIQUE
--     (evitan duplicados de negocio no capturados por la PK)
-- =============================================================

-- Un mismo documento de identidad no puede repetirse para dos
-- personas naturales distintas.
ALTER TABLE persona_natural
    ADD CONSTRAINT uq_pnatural_documento
        UNIQUE (id_tipo_documento, numero_documento);

-- El RUC identifica de forma única a una persona jurídica.
ALTER TABLE persona_juridica
    ADD CONSTRAINT uq_pjuridica_ruc UNIQUE (ruc);

-- El número de habitación debe ser único dentro de cada hotel.
ALTER TABLE habitacion
    ADD CONSTRAINT uq_habitacion_hotel_numero
        UNIQUE (id_hotel, numero);

-- El nombre de un tipo de habitación no debe repetirse.
ALTER TABLE tipo_habitacion
    ADD CONSTRAINT uq_tipo_habitacion_nombre UNIQUE (nombre);

-- El username de acceso no debe repetirse.
ALTER TABLE usuario
    ADD CONSTRAINT uq_usuario_username UNIQUE (username);

-- Un mismo tipo de habitación no puede tener dos tarifas activas
-- para el mismo plan (evita ambigüedad de precio).
ALTER TABLE tarifa_habitacion
    ADD CONSTRAINT uq_tarifa_plan_tipo
        UNIQUE (id_plan, id_tipo_habitacion);

-- Los nombres de cargo no deben repetirse.
ALTER TABLE cargo_empleado
    ADD CONSTRAINT uq_cargo_nombre UNIQUE (nombre);

-- Los nombres de categoría de servicio no deben repetirse.
ALTER TABLE categoria_servicio
    ADD CONSTRAINT uq_categoria_servicio_nombre UNIQUE (nombre);

-- El correo de un hotel, si se registra, debe ser único.
ALTER TABLE hotel
    ADD CONSTRAINT uq_hotel_email UNIQUE (email);

-- No puede haber más de una cuenta por cobrar para el mismo alojamiento
-- (evita que sp_generar_cuenta_cobrar duplique la facturación si se
-- invoca dos veces sobre el mismo alojamiento).
ALTER TABLE cuenta_cobrar
    ADD CONSTRAINT uq_cuenta_alojamiento UNIQUE (id_alojamiento);

-- Una persona no puede tener dos registros de cliente distintos.
ALTER TABLE cliente
    ADD CONSTRAINT uq_cliente_persona UNIQUE (id_persona);

-- El código INEI de un ubigeo no debe repetirse.
ALTER TABLE ubigeo
    ADD CONSTRAINT uq_ubigeo_codigo UNIQUE (codigo);

-- Los nombres de tipo de documento no deben repetirse (mismo patrón que
-- el resto de catálogos de este archivo).
ALTER TABLE tipo_documento
    ADD CONSTRAINT uq_tipo_documento_nombre UNIQUE (nombre);

-- Un mismo huésped no puede quedar pre-asignado dos veces a la misma
-- línea de reserva.
ALTER TABLE detalle_huesped_reserva
    ADD CONSTRAINT uq_detalle_huesped_reserva UNIQUE (id_detalle_reserva, id_huesped);


-- =============================================================
--  C. ÍNDICES ADICIONALES
--     (las FK ya crean índices en las columnas referenciadas;
--      aquí se agregan los más usados en consultas operativas)
-- =============================================================

-- Búsqueda de habitaciones disponibles por hotel y tipo
CREATE INDEX idx_habitacion_estado
    ON habitacion (id_hotel, id_tipo_habitacion, estado);

-- Búsqueda de reservas por cliente y fechas
CREATE INDEX idx_reserva_cliente_fechas
    ON reserva (id_cliente, fecha_checkin, fecha_checkout);

-- Búsqueda de reservas por hotel y estado
CREATE INDEX idx_reserva_hotel_estado
    ON reserva (id_hotel, estado);

-- Búsqueda de alojamientos activos por habitación (clave para
-- calcular disponibilidad por rango de fechas)
CREATE INDEX idx_alojamiento_habitacion_estado
    ON alojamiento (id_habitacion, estado);

-- Tarifas vigentes por tipo de habitación
CREATE INDEX idx_tarifa_tipo_plan
    ON tarifa_habitacion (id_tipo_habitacion, id_plan);

-- Consumos por alojamiento y fecha
CREATE INDEX idx_consumo_aloj_fecha
    ON consumo_servicio (id_alojamiento, fecha_consumo);

-- Pagos por cuenta
CREATE INDEX idx_pago_cuenta
    ON pago_cuenta_cobrar (id_cuenta, fecha_pago);


-- =============================================================
--  D. CONSTRAINTS CHECK (MySQL 8.0.16+)
-- =============================================================

-- La fecha de checkout debe ser posterior al checkin en reserva
ALTER TABLE reserva
    ADD CONSTRAINT chk_reserva_fechas
        CHECK (fecha_checkout > fecha_checkin);

-- El monto total de reserva debe ser >= 0
ALTER TABLE reserva
    ADD CONSTRAINT chk_reserva_monto
        CHECK (monto_total >= 0);

-- La fecha límite de pago no puede ser posterior al check-in
ALTER TABLE reserva
    ADD CONSTRAINT chk_reserva_limite_pago
        CHECK (fecha_limite_pago <= fecha_checkin);

-- Los subtotales de detalle deben ser >= 0
ALTER TABLE reserva_detalle
    ADD CONSTRAINT chk_rdetalle_subtotal
        CHECK (subtotal >= 0 AND precio_unitario >= 0 AND cantidad_habitaciones > 0);

-- El saldo no puede ser negativo ni mayor al total
ALTER TABLE cuenta_cobrar
    ADD CONSTRAINT chk_cuenta_saldo
        CHECK (saldo >= 0 AND saldo <= total);

-- El total de la cuenta debe ser >= 0
ALTER TABLE cuenta_cobrar
    ADD CONSTRAINT chk_cuenta_total
        CHECK (total >= 0 AND subtotal >= 0 AND impuestos >= 0);

-- Los costos de daños no pueden ser negativos
ALTER TABLE danio
    ADD CONSTRAINT chk_danio_costo
        CHECK (costo >= 0);

-- El precio por noche en tarifas debe ser > 0
ALTER TABLE tarifa_habitacion
    ADD CONSTRAINT chk_tarifa_precio
        CHECK (precio_por_noche > 0);

-- La vigencia del plan debe ser coherente
ALTER TABLE plan_tarifa
    ADD CONSTRAINT chk_plan_fechas
        CHECK (fecha_fin >= fecha_inicio);

-- La capacidad base debe ser > 0
ALTER TABLE tipo_habitacion
    ADD CONSTRAINT chk_capacidad_base
        CHECK (capacidad_base > 0);

-- El monto de un pago debe ser positivo
ALTER TABLE pago_cuenta_cobrar
    ADD CONSTRAINT chk_pago_monto
        CHECK (monto > 0);

-- La salida individual de un huésped no puede ser anterior a su
-- registro en la habitación (coherencia de fechas por huésped).
ALTER TABLE huesped_alojamiento
    ADD CONSTRAINT chk_haloj_fecha_salida
        CHECK (fecha_salida_real IS NULL OR fecha_salida_real >= fecha_registro);
