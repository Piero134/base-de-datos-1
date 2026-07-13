-- =============================================================
--  07_Roles_Permisos.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Roles de acceso alineados a las áreas del
--               negocio descritas en el contexto del sistema:
--               Recepción, Caja y Gerencia, más un rol de
--               Administrador. Aporta al proyecto porque limita
--               el acceso de cada perfil de usuario a solo lo
--               que necesita operar (principio de mínimo
--               privilegio).
--  Ejecutar: SÉPTIMO (orden 7 de 9) — opcional, requiere
--            privilegios de administración en el servidor MySQL.
-- =============================================================

USE hotel_db;

-- -------------------------------------------------------------
-- ROL: rol_administrador
-- Control total sobre la base de datos (soporte, migraciones).
-- -------------------------------------------------------------
DROP ROLE IF EXISTS rol_administrador;
CREATE ROLE rol_administrador;
GRANT ALL PRIVILEGES ON hotel_db.* TO rol_administrador;

-- -------------------------------------------------------------
-- ROL: rol_recepcion
-- Gestiona reservas, clientes, huéspedes, check-in/checkout y
-- disponibilidad de habitaciones.
-- -------------------------------------------------------------
DROP ROLE IF EXISTS rol_recepcion;
CREATE ROLE rol_recepcion;
GRANT SELECT ON hotel_db.* TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.cliente               TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.persona               TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.persona_natural        TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.persona_juridica       TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.reserva                TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.reserva_detalle        TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.detalle_huesped_reserva TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.alojamiento            TO rol_recepcion;
GRANT INSERT, UPDATE ON hotel_db.huesped_alojamiento    TO rol_recepcion;
GRANT UPDATE ON hotel_db.habitacion                     TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_registrar_reserva            TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_agregar_detalle_reserva      TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_confirmar_pago               TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_realizar_checkin             TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_agregar_huesped_alojamiento  TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_realizar_checkout            TO rol_recepcion;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_cambiar_estado_habitacion    TO rol_recepcion;

-- -------------------------------------------------------------
-- ROL: rol_caja
-- Gestiona consumos, daños, cuentas por cobrar y pagos.
-- -------------------------------------------------------------
DROP ROLE IF EXISTS rol_caja;
CREATE ROLE rol_caja;
GRANT SELECT ON hotel_db.* TO rol_caja;
GRANT INSERT, UPDATE ON hotel_db.consumo_servicio       TO rol_caja;
GRANT INSERT, UPDATE ON hotel_db.danio                  TO rol_caja;
GRANT INSERT, UPDATE ON hotel_db.cuenta_cobrar           TO rol_caja;
GRANT INSERT, UPDATE ON hotel_db.cuenta_cobrar_detalle   TO rol_caja;
GRANT INSERT             ON hotel_db.pago_cuenta_cobrar  TO rol_caja;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_registrar_consumo       TO rol_caja;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_registrar_danio         TO rol_caja;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_generar_cuenta_cobrar   TO rol_caja;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_registrar_pago_cuenta   TO rol_caja;

-- -------------------------------------------------------------
-- ROL: rol_gerencia
-- Solo lectura sobre datos y vistas de reporte/negocio.
-- -------------------------------------------------------------
DROP ROLE IF EXISTS rol_gerencia;
CREATE ROLE rol_gerencia;
GRANT SELECT ON hotel_db.* TO rol_gerencia;
GRANT EXECUTE ON PROCEDURE hotel_db.sp_resumen_ocupacion_hotel TO rol_gerencia;

-- -------------------------------------------------------------
-- Ejemplo de asignación de roles a usuarios (comentado; ajustar
-- usuario/host/contraseña según el entorno real de despliegue).
-- -------------------------------------------------------------
-- CREATE USER 'recepcion_lima'@'%' IDENTIFIED BY 'CambiarEstaClave!';
-- GRANT rol_recepcion TO 'recepcion_lima'@'%';
-- SET DEFAULT ROLE rol_recepcion TO 'recepcion_lima'@'%';
--
-- CREATE USER 'caja_lima'@'%' IDENTIFIED BY 'CambiarEstaClave!';
-- GRANT rol_caja TO 'caja_lima'@'%';
-- SET DEFAULT ROLE rol_caja TO 'caja_lima'@'%';
--
-- CREATE USER 'gerencia_general'@'%' IDENTIFIED BY 'CambiarEstaClave!';
-- GRANT rol_gerencia TO 'gerencia_general'@'%';
-- SET DEFAULT ROLE rol_gerencia TO 'gerencia_general'@'%';
