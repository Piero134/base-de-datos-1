-- =============================================================
--  10_Ejemplo_Flujo_Huespedes.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Flujo completo de "cupos vs. identidad" en una
--               reserva corporativa: la empresa reserva N
--               habitaciones sin saber todavía quién las ocupará
--               (detalle_huesped_reserva.id_huesped = NULL), se
--               resuelve la identidad de algunos cupos antes del
--               check-in, se sustituye uno a último momento, y se
--               hace el check-in final — que solo es posible con
--               un huésped ya identificado (huesped_alojamiento.
--               id_huesped nunca fue ni es nulable).
--               No reutiliza los IDs de 08_Carga_Datos.sql — usa
--               AUTO_INCREMENT en todo, así que puede ejecutarse
--               de forma aislada y repetible sobre la base ya
--               cargada.
--  Ejecutar: OPCIONAL, después de 09_Consultas_MVP.sql — no forma
--            parte del pipeline obligatorio (01→09).
-- =============================================================

USE hotel_db;

-- -------------------------------------------------------------
-- Paso 0: cliente corporativo que reserva (empresa nueva, para no
-- chocar con la Corporación ABC ya cargada en 08_Carga_Datos.sql).
-- -------------------------------------------------------------
INSERT INTO persona (tipo, telefono, email) VALUES ('JURIDICA', '01-4009000', 'reservas@construnorte.pe');
SET @id_persona_empresa = LAST_INSERT_ID();

INSERT INTO persona_juridica (id_persona, ruc, razon_social, representante_legal, giro_negocio)
VALUES (@id_persona_empresa, '20699887766', 'ConstruNorte S.A.C.', 'Elena Farfán Ríos', 'Construcción');

INSERT INTO cliente (id_persona, observaciones) VALUES (@id_persona_empresa, 'Cliente nuevo — ejemplo de flujo de cupos vs. identidad');
SET @id_cliente_empresa = LAST_INSERT_ID();

-- -------------------------------------------------------------
-- Paso 1: la empresa reserva 3 habitaciones simples del Hotel Lima
-- SIN saber todavía quién las ocupará — solo conoce la cantidad.
-- Se usan los procedimientos ya existentes (sp_registrar_reserva +
-- sp_agregar_detalle_reserva), igual que hace la app: la reserva en
-- sí no tiene nada de nuevo, lo nuevo empieza en el paso siguiente.
-- -------------------------------------------------------------
SET @id_reserva = NULL;
CALL sp_registrar_reserva(@id_cliente_empresa, 1, NULL, NULL, 'DIRECTO',
                           '2026-08-10', '2026-08-13', '2026-08-08',
                           'Reserva corporativa — ejemplo de cupos sin identificar', @id_reserva);

-- p_id_plan = NULL → se autodetecta "Tarifa Regular 2026" por fecha.
CALL sp_agregar_detalle_reserva(@id_reserva, 1, NULL, 3);
SET @id_detalle_reserva = LAST_INSERT_ID();

-- 3 cupos reservados, ninguno identificado todavía (id_huesped NULL).
-- La capacidad_base de "Simple" es 1 y cantidad_habitaciones es 3, así
-- que el máximo son exactamente 3 cupos: trg_valida_cupos_reserva ya
-- no deja insertar un 4º (ver el INSERT comentado al final de este
-- script).
INSERT INTO detalle_huesped_reserva (id_detalle_reserva, id_huesped, es_titular) VALUES
(@id_detalle_reserva, NULL, 1),
(@id_detalle_reserva, NULL, 0),
(@id_detalle_reserva, NULL, 0);

-- Los 3 cupos existen y son visibles en vw_reservas_corporativas
-- ("Sin identificar"), pero no se puede hacer check-in con ellos así.
SELECT * FROM vw_reservas_corporativas WHERE id_reserva = @id_reserva;

-- -------------------------------------------------------------
-- Paso 2: llega la lista de la empresa con 2 de los 3 nombres, antes
-- del check-in. Cada persona nueva primero necesita su fila en
-- persona/persona_natural (igual que hace la app en
-- huespedes.py::crear_huesped_desde_formulario) — recién ahí se
-- resuelve el cupo, con un UPDATE simple (id_huesped referencia
-- persona_natural.id_persona directo, no hay tabla huesped
-- intermedia).
-- -------------------------------------------------------------
INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', '955001122', 'jhilario@construnorte.pe');
SET @id_persona_1 = LAST_INSERT_ID();
INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, genero, nacionalidad)
VALUES (@id_persona_1, 1, '70011223', 'Jorge', 'Hilario Campos', '1989-04-12', 'M', 'Peruana');

INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', '955003344', 'mvargas@construnorte.pe');
SET @id_persona_2 = LAST_INSERT_ID();
INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, genero, nacionalidad)
VALUES (@id_persona_2, 1, '70022334', 'Milagros', 'Vargas Solano', '1993-08-30', 'F', 'Peruana');

-- Se resuelven 2 de los 3 cupos (el titular y uno de los
-- acompañantes). El tercero se deja sin resolver a propósito, para
-- la sustitución del paso 3.
SET @id_dhr_titular = (SELECT id_detalle_huesped FROM detalle_huesped_reserva
                        WHERE id_detalle_reserva = @id_detalle_reserva AND es_titular = 1);
SET @id_dhr_acomp1  = (SELECT MIN(id_detalle_huesped) FROM detalle_huesped_reserva
                        WHERE id_detalle_reserva = @id_detalle_reserva AND es_titular = 0);

UPDATE detalle_huesped_reserva SET id_huesped = @id_persona_1 WHERE id_detalle_huesped = @id_dhr_titular;
UPDATE detalle_huesped_reserva SET id_huesped = @id_persona_2 WHERE id_detalle_huesped = @id_dhr_acomp1;

-- 2 de 3 cupos ya muestran nombre; el tercero sigue "Sin identificar".
SELECT * FROM vw_reservas_corporativas WHERE id_reserva = @id_reserva;

-- -------------------------------------------------------------
-- Paso 3: sustitución de último momento — el titular avisa que Jorge
-- Hilario ya no viaja, lo reemplaza Renzo Quiroz. Es exactamente el
-- mismo UPDATE que la resolución del paso 2, solo que ahora sobre un
-- cupo que ya tenía un huésped asignado.
-- -------------------------------------------------------------
INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', '955005566', 'rquiroz@construnorte.pe');
SET @id_persona_3 = LAST_INSERT_ID();
INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, genero, nacionalidad)
VALUES (@id_persona_3, 1, '70033445', 'Renzo', 'Quiroz Bellido', '1991-11-02', 'M', 'Peruana');

UPDATE detalle_huesped_reserva SET id_huesped = @id_persona_3 WHERE id_detalle_huesped = @id_dhr_titular;

-- El titular ahora es Renzo Quiroz, no Jorge Hilario — Jorge sigue
-- existiendo como persona_natural (podría usarse en otra reserva),
-- solo dejó de estar asociado a este cupo.
SELECT * FROM vw_reservas_corporativas WHERE id_reserva = @id_reserva;

-- -------------------------------------------------------------
-- Paso 4: check-in del titular. Solo puede hacerse con un huésped ya
-- identificado — sp_realizar_checkin_con_huesped exige un id_huesped
-- concreto y nunca aceptó NULL, así que la garantía legal ("nunca
-- ocupación real sin identidad completa") no depende de este script:
-- ya la aplica el procedimiento, sin cambios.
-- -------------------------------------------------------------
-- La disponibilidad real se determina por ocupación (¿hay un alojamiento
-- ACTIVO en esa habitación ahora?), no por el campo cacheado
-- habitacion.estado — mismo criterio que usa la app (ver
-- estadia/routes.py:_contexto_checkin_reserva).
SET @id_habitacion_checkin = (
    SELECT h.id_habitacion FROM habitacion h
    WHERE h.id_hotel = 1 AND h.id_tipo_habitacion = 1
      AND NOT EXISTS (SELECT 1 FROM alojamiento a WHERE a.id_habitacion = h.id_habitacion AND a.estado = 'ACTIVO')
    LIMIT 1
);
SET @id_alojamiento = NULL;
CALL sp_realizar_checkin_con_huesped(@id_reserva, @id_detalle_reserva, @id_habitacion_checkin,
                                      1, @id_persona_3, @id_dhr_titular, @id_alojamiento);

-- Renzo Quiroz aparece con identidad completa; el check-in nunca
-- pudo haberse hecho con un cupo sin resolver.
SELECT * FROM vw_alojamientos_activos WHERE id_alojamiento = @id_alojamiento;
SELECT * FROM vw_preasignacion_vs_checkin WHERE id_reserva = @id_reserva;

-- -------------------------------------------------------------
-- Verificación: trg_valida_cupos_reserva rechaza un 4º cupo sobre la
-- misma línea (3 habitaciones simples = máximo 3 cupos). Descomentar
-- para probarlo — error esperado: 'Se excede la capacidad de la
-- línea de reserva.'
-- -------------------------------------------------------------
-- INSERT INTO detalle_huesped_reserva (id_detalle_reserva, id_huesped, es_titular)
-- VALUES (@id_detalle_reserva, NULL, 0);
