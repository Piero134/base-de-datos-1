-- =============================================================
--  01_Creacion_Tablas.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Proyecto: Sistema de gestión de reservas y estadías para una
--            cadena de hoteles turísticos.
--  Descripción: DDL completo — crea el schema y todas las tablas
--               en orden (padre antes que hijo). Sin FK en este
--               archivo; las FK e integridad referencial se
--               agregan en 02_Reglas_Integridad.sql.
--  Ejecutar: PRIMERO (orden 1 de 9)
-- =============================================================

DROP DATABASE IF EXISTS hotel_db;
CREATE DATABASE hotel_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_spanish_ci;

USE hotel_db;

-- -------------------------------------------------------------
--  1. GEOGRAFÍA
-- -------------------------------------------------------------
CREATE TABLE ubigeo (
    id_ubigeo    INT           NOT NULL AUTO_INCREMENT,
    codigo       VARCHAR(6)    NOT NULL COMMENT 'Código INEI de 6 dígitos',
    departamento VARCHAR(60)   NOT NULL,
    provincia    VARCHAR(60)   NOT NULL,
    distrito     VARCHAR(60)   NOT NULL,
    CONSTRAINT pk_ubigeo PRIMARY KEY (id_ubigeo)
) COMMENT = 'Catálogo de ubigeos (INEI)';

-- -------------------------------------------------------------
--  2. HOTEL Y PERSONAL
-- -------------------------------------------------------------
CREATE TABLE hotel (
    id_hotel    INT           NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(120)  NOT NULL,
    direccion   VARCHAR(200)  NOT NULL,
    telefono    VARCHAR(20)   NULL,
    email       VARCHAR(100)  NULL,
    id_ubigeo   INT           NOT NULL,
    activo      TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT pk_hotel PRIMARY KEY (id_hotel)
) COMMENT = 'Hoteles registrados en el sistema (cadena turística)';

CREATE TABLE cargo_empleado (
    id_cargo    INT           NOT NULL AUTO_INCREMENT,
    nombre      VARCHAR(80)   NOT NULL,
    CONSTRAINT pk_cargo_empleado PRIMARY KEY (id_cargo)
) COMMENT = 'Catálogo de cargos del personal';

CREATE TABLE empleado (
    id_empleado INT           NOT NULL AUTO_INCREMENT,
    id_hotel    INT           NOT NULL,
    id_cargo    INT           NOT NULL,
    nombres     VARCHAR(100)  NOT NULL,
    apellidos   VARCHAR(100)  NOT NULL,
    activo      TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT pk_empleado PRIMARY KEY (id_empleado)
) COMMENT = 'Personal del hotel';

-- -------------------------------------------------------------
--  3. PERSONA — supertype / subtipos (facturación / reservantes)
--     Separa a quien FACTURA (persona/cliente)
--     de quien físicamente se ALOJA (huésped).
-- -------------------------------------------------------------
CREATE TABLE tipo_documento (
    id_tipo_documento INT          NOT NULL AUTO_INCREMENT,
    nombre            VARCHAR(60)  NOT NULL,
    abreviatura       VARCHAR(10)  NOT NULL,
    CONSTRAINT pk_tipo_documento PRIMARY KEY (id_tipo_documento)
) COMMENT = 'Tipos de documento de identidad (DNI, RUC, Pasaporte…)';

CREATE TABLE persona (
    id_persona  INT           NOT NULL AUTO_INCREMENT,
    tipo        ENUM('NATURAL','JURIDICA') NOT NULL,
    telefono    VARCHAR(20)   NULL,
    email       VARCHAR(100)  NULL,
    id_ubigeo   INT           NULL,
    activo      TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT pk_persona PRIMARY KEY (id_persona)
) COMMENT = 'Supertype de persona natural y jurídica (para facturación)';

CREATE TABLE persona_natural (
    id_persona        INT           NOT NULL COMMENT 'PK y FK a persona',
    id_tipo_documento INT           NOT NULL,
    numero_documento  VARCHAR(20)   NOT NULL,
    nombres           VARCHAR(100)  NOT NULL,
    apellidos         VARCHAR(100)  NOT NULL,
    fecha_nacimiento  DATE          NOT NULL,
    genero            ENUM('M','F','OTRO') NOT NULL,
    nacionalidad      VARCHAR(60)   NOT NULL,
    CONSTRAINT pk_persona_natural PRIMARY KEY (id_persona)
) COMMENT = 'Subtipo: persona natural (cliente reservante o contacto)';

CREATE TABLE persona_juridica (
    id_persona          INT           NOT NULL COMMENT 'PK y FK a persona',
    ruc                 VARCHAR(11)   NOT NULL,
    razon_social        VARCHAR(150)  NOT NULL,
    nombre_comercial    VARCHAR(150)  NULL,
    representante_legal VARCHAR(150)  NOT NULL,
    giro_negocio        VARCHAR(100)  NULL,
    CONSTRAINT pk_persona_juridica PRIMARY KEY (id_persona)
) COMMENT = 'Subtipo: persona jurídica (empresa reservante/facturación)';

CREATE TABLE cliente (
    id_cliente      INT           NOT NULL AUTO_INCREMENT,
    id_persona      INT           NOT NULL,
    observaciones   TEXT          NULL,
    CONSTRAINT pk_cliente PRIMARY KEY (id_cliente)
) COMMENT = 'Entidad que reserva y/o paga (puede ser natural o jurídica)';

-- -------------------------------------------------------------
--  4. HUESPED — persona que se aloja físicamente.
--     Separada de CLIENTE por indicación del profesor:
--     "cliente = quien paga/factura; huésped = quien duerme".
--     Soporta huéspedes GENÉRICOS (placeholder) cuando el
--     titular reserva sin conocer aún los nombres de todos los
--     ocupantes. Se completan los datos reales antes
--     o durante el check-in.
-- -------------------------------------------------------------
CREATE TABLE huesped (
    id_huesped        INT           NOT NULL AUTO_INCREMENT,
    id_tipo_documento INT           NULL,
    numero_documento  VARCHAR(20)   NULL,
    nombres           VARCHAR(100)  NOT NULL,
    apellidos         VARCHAR(100)  NULL,
    fecha_nacimiento  DATE          NULL,
    genero            ENUM('M','F','OTRO') NULL,
    nacionalidad      VARCHAR(60)   NULL,
    telefono          VARCHAR(20)   NULL,
    email             VARCHAR(100)  NULL,
    es_generico       TINYINT(1)    NOT NULL DEFAULT 0
        COMMENT '1 = huésped placeholder pendiente de identificar',
    activo            TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT pk_huesped PRIMARY KEY (id_huesped)
) COMMENT = 'Persona física que ocupa la habitación. Distinto de CLIENTE.';

-- -------------------------------------------------------------
--  5. HABITACIONES
-- -------------------------------------------------------------
CREATE TABLE tipo_habitacion (
    id_tipo_habitacion  INT           NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(60)   NOT NULL,
    capacidad_base      TINYINT       NOT NULL COMMENT 'Define el máximo de huéspedes por habitación',
    descripcion         TEXT          NULL,
    CONSTRAINT pk_tipo_habitacion PRIMARY KEY (id_tipo_habitacion)
) COMMENT = 'Tipos de habitación';

CREATE TABLE habitacion (
    id_habitacion       INT           NOT NULL AUTO_INCREMENT,
    id_hotel            INT           NOT NULL,
    id_tipo_habitacion  INT           NOT NULL,
    estado              ENUM('DISPONIBLE','RESERVADA','OCUPADA','LIMPIEZA')
                        NOT NULL DEFAULT 'DISPONIBLE',
    numero              VARCHAR(10)   NOT NULL COMMENT 'Número o código de habitación',
    piso                TINYINT       NOT NULL,
    descripcion         TEXT          NULL,
    CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion)
) COMMENT = 'Habitaciones físicas del hotel';

-- -------------------------------------------------------------
--  6. TARIFAS
-- -------------------------------------------------------------
CREATE TABLE plan_tarifa (
    id_plan         INT           NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(80)   NOT NULL,
    descripcion     TEXT          NULL,
    fecha_inicio    DATE          NOT NULL,
    fecha_fin       DATE          NOT NULL,
    es_publico      TINYINT(1)    NOT NULL DEFAULT 1
        COMMENT '1 = tarifa pública detectable automáticamente por fecha (Regular, Temporada Alta). 0 = tarifa negociada/corporativa que solo se aplica si el operador la elige explícitamente (ej. convenio con una empresa), para evitar que el sistema la asigne por error a un cliente que no tiene ese convenio.',
    activo          TINYINT(1)    NOT NULL DEFAULT 1,
    CONSTRAINT pk_plan_tarifa PRIMARY KEY (id_plan)
) COMMENT = 'Planes tarifarios con vigencia definida';

CREATE TABLE tarifa_habitacion (
    id_tarifa           INT             NOT NULL AUTO_INCREMENT,
    id_plan             INT             NOT NULL,
    id_tipo_habitacion  INT             NOT NULL,
    precio_por_noche    DECIMAL(10,2)   NOT NULL,
    capacidad_maxima    TINYINT         NOT NULL,
    CONSTRAINT pk_tarifa_habitacion PRIMARY KEY (id_tarifa)
) COMMENT = 'Precio por noche según plan y tipo de habitación';

-- -------------------------------------------------------------
--  7. RESERVA
-- -------------------------------------------------------------
CREATE TABLE estado_reserva (
    id_estado_reserva   INT           NOT NULL AUTO_INCREMENT,
    nombre              VARCHAR(30)   NOT NULL
        COMMENT 'PENDIENTE | CONFIRMADA | CANCELADA | NO_SHOW | FINALIZADA',
    CONSTRAINT pk_estado_reserva PRIMARY KEY (id_estado_reserva)
) COMMENT = 'Estados del ciclo de vida de una reserva';

CREATE TABLE reserva (
    id_reserva          INT           NOT NULL AUTO_INCREMENT,
    id_cliente          INT           NOT NULL COMMENT 'Quien reserva / paga',
    id_hotel            INT           NOT NULL,
    id_estado_reserva   INT           NOT NULL,
    id_empleado         INT           NULL     COMMENT 'Empleado que tomó la reserva',
    id_cliente_contacto INT           NULL     COMMENT 'Contacto corporativo alternativo',
    canal               ENUM('DIRECTO','WEB','TELEFONO','AGENCIA','OTA') NOT NULL,
    fecha_reserva       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_checkin       DATE          NOT NULL,
    fecha_checkout      DATE          NOT NULL,
    fecha_limite_pago   DATE          NOT NULL,
    pagado              TINYINT(1)    NOT NULL DEFAULT 0,
    fecha_pago          DATETIME      NULL,
    monto_total         DECIMAL(12,2) NOT NULL DEFAULT 0.00
        COMMENT 'Calculado al crear la reserva y congelado',
    observaciones       TEXT          NULL,
    CONSTRAINT pk_reserva PRIMARY KEY (id_reserva)
) COMMENT = 'Cabecera de reserva de habitaciones';

CREATE TABLE reserva_detalle (
    id_detalle_reserva      INT             NOT NULL AUTO_INCREMENT,
    id_reserva              INT             NOT NULL,
    id_tipo_habitacion      INT             NOT NULL,
    id_plan                 INT             NOT NULL,
    cantidad_habitaciones   TINYINT         NOT NULL DEFAULT 1,
    precio_unitario         DECIMAL(10,2)   NOT NULL
        COMMENT 'Precio/noche al momento de reservar (congelado)',
    subtotal                DECIMAL(12,2)   NOT NULL
        COMMENT 'cantidad_habitaciones × precio_unitario × noches',
    CONSTRAINT pk_reserva_detalle PRIMARY KEY (id_detalle_reserva)
) COMMENT = 'Líneas de reserva: tipo + plan + cantidad + precio. Permite reservar varios tipos de habitación en una sola reserva (ej. 2 simples + 1 doble).';

-- -------------------------------------------------------------
--  8. PRE-ASIGNACIÓN CORPORATIVA
-- -------------------------------------------------------------
CREATE TABLE detalle_huesped_reserva (
    id_detalle_huesped  INT           NOT NULL AUTO_INCREMENT,
    id_detalle_reserva  INT           NOT NULL,
    id_huesped          INT           NOT NULL COMMENT 'Quién se alojará (puede ser un huésped genérico)',
    es_titular          TINYINT(1)    NOT NULL DEFAULT 0,
    CONSTRAINT pk_detalle_huesped_reserva PRIMARY KEY (id_detalle_huesped)
) COMMENT = 'Pre-asignación de huéspedes a líneas de reserva.';

-- -------------------------------------------------------------
--  9. ALOJAMIENTO
-- -------------------------------------------------------------
CREATE TABLE alojamiento (
    id_alojamiento          INT           NOT NULL AUTO_INCREMENT,
    id_reserva              INT           NOT NULL,
    id_detalle_reserva      INT           NOT NULL,
    id_habitacion           INT           NOT NULL,
    estado                  ENUM('ACTIVO','FINALIZADO','CANCELADO') NOT NULL DEFAULT 'ACTIVO',
    id_empleado_checkin     INT           NOT NULL,
    id_empleado_checkout    INT           NULL,
    fecha_checkin_real      DATETIME      NOT NULL,
    fecha_checkout_real     DATETIME      NULL,
    CONSTRAINT pk_alojamiento PRIMARY KEY (id_alojamiento)
) COMMENT = 'Ocupación real de una habitación: de check-in a check-out';

CREATE TABLE huesped_alojamiento (
    id_alojamiento     INT           NOT NULL,
    id_huesped         INT           NOT NULL,
    id_detalle_huesped INT           NULL
        COMMENT 'Trazabilidad opcional hacia la pre-asignación corporativa (detalle_huesped_reserva).',
    es_titular         TINYINT(1)    NOT NULL DEFAULT 0,
    fecha_registro     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fecha_salida_real  DATETIME      NULL
        COMMENT 'Salida individual del huésped.',
    CONSTRAINT pk_huesped_alojamiento PRIMARY KEY (id_alojamiento, id_huesped)
) COMMENT = 'Huéspedes que ocupan un alojamiento (el que duerme ≠ el que paga)';

-- -------------------------------------------------------------
--  10. SERVICIOS Y DAÑOS
-- -------------------------------------------------------------
CREATE TABLE categoria_servicio (
    id_categoria INT           NOT NULL AUTO_INCREMENT,
    nombre       VARCHAR(60)   NOT NULL,
    CONSTRAINT pk_categoria_servicio PRIMARY KEY (id_categoria)
) COMMENT = 'Catálogo de categorías de servicio (Ej: LAVANDERIA, RESTAURANTE, MINIBAR…)';

CREATE TABLE servicio (
    id_servicio     INT             NOT NULL AUTO_INCREMENT,
    nombre          VARCHAR(100)    NOT NULL,
    id_categoria    INT             NOT NULL,
    precio_unitario DECIMAL(10,2)   NOT NULL,
    activo          TINYINT(1)      NOT NULL DEFAULT 1,
    CONSTRAINT pk_servicio PRIMARY KEY (id_servicio)
) COMMENT = 'Catálogo de servicios adicionales del hotel';

CREATE TABLE consumo_servicio (
    id_consumo      INT             NOT NULL AUTO_INCREMENT,
    id_alojamiento  INT             NOT NULL,
    id_servicio     INT             NOT NULL,
    cantidad        TINYINT         NOT NULL DEFAULT 1,
    precio_unitario DECIMAL(10,2)   NOT NULL COMMENT 'Precio al momento del consumo',
    subtotal        DECIMAL(12,2)   NOT NULL,
    fecha_consumo   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_consumo_servicio PRIMARY KEY (id_consumo)
) COMMENT = 'Servicios consumidos durante un alojamiento';

CREATE TABLE danio (
    id_danio        INT             NOT NULL AUTO_INCREMENT,
    id_alojamiento  INT             NOT NULL,
    descripcion     TEXT            NOT NULL,
    costo           DECIMAL(10,2)   NOT NULL,
    fecha_reporte   DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    estado          ENUM('PENDIENTE','COBRADO','DISPENSADO') NOT NULL DEFAULT 'PENDIENTE',
    CONSTRAINT pk_danio PRIMARY KEY (id_danio)
) COMMENT = 'Daños en habitación reportados durante o tras el alojamiento';

-- -------------------------------------------------------------
--  11. CUENTA POR COBRAR
-- -------------------------------------------------------------
CREATE TABLE cuenta_cobrar (
    id_cuenta           INT             NOT NULL AUTO_INCREMENT,
    id_alojamiento      INT             NOT NULL,
    fecha_generacion    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    subtotal            DECIMAL(12,2)   NOT NULL,
    impuestos           DECIMAL(12,2)   NOT NULL DEFAULT 0.00,
    total               DECIMAL(12,2)   NOT NULL,
    saldo               DECIMAL(12,2)   NOT NULL
        COMMENT 'Inicia = total; baja hasta 0 conforme se registran pagos. Indicación del profesor.',
    estado              ENUM('PENDIENTE','PAGADA') NOT NULL DEFAULT 'PENDIENTE',
    CONSTRAINT pk_cuenta_cobrar PRIMARY KEY (id_cuenta)
) COMMENT = 'Cuenta por cobrar de consumos y daños durante la estadía (no incluye el hospedaje en sí, que se paga por adelantado en la reserva)';

CREATE TABLE cuenta_cobrar_detalle (
    id_detalle_cuenta   INT             NOT NULL AUTO_INCREMENT,
    id_cuenta           INT             NOT NULL,
    concepto            VARCHAR(150)    NOT NULL,
    cantidad            TINYINT         NOT NULL DEFAULT 1,
    precio_unitario     DECIMAL(10,2)   NOT NULL,
    subtotal            DECIMAL(12,2)   NOT NULL,
    CONSTRAINT pk_cuenta_cobrar_detalle PRIMARY KEY (id_detalle_cuenta)
) COMMENT = 'Líneas de detalle de una cuenta por cobrar';

-- -------------------------------------------------------------
--  12. PAGOS DE CUENTA POR COBRAR
--      Tabla nueva: permite registrar abonos parciales y mantener
--      trazabilidad de cómo se llegó al saldo actual (antes solo
--      existía el campo "saldo" sin historial de abonos).
-- -------------------------------------------------------------
CREATE TABLE pago_cuenta_cobrar (
    id_pago         INT             NOT NULL AUTO_INCREMENT,
    id_cuenta       INT             NOT NULL,
    monto           DECIMAL(12,2)   NOT NULL,
    metodo_pago     ENUM('EFECTIVO','TARJETA','TRANSFERENCIA','YAPE_PLIN') NOT NULL,
    fecha_pago      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    id_empleado     INT             NULL COMMENT 'Empleado de caja que recibe el pago',
    CONSTRAINT pk_pago_cuenta_cobrar PRIMARY KEY (id_pago)
) COMMENT = 'Historial de abonos/pagos aplicados a una cuenta por cobrar';
