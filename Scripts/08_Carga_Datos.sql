-- =============================================================
--  08_Carga_Datos.sql
--  Base de datos: hotel_db
--  Motor: MySQL 8.0+
--  Descripción: Datos de prueba que recorren el flujo completo:
--               ubigeo → hotel → empleado → cliente → huésped
--               → reserva → alojamiento → servicios → cuenta →
--               pagos.
--
--  Escenarios cubiertos:
--    A) Reserva individual (persona natural) — flujo completo,
--       con cuenta por cobrar parcialmente pagada.
--    B) Reserva corporativa (empresa) con pre-asignación.
--    C) Reserva con huésped GENÉRICO (sin nombre aún).
--    D) Reservas en distintos estados: PENDIENTE, CANCELADA,
--       NO_SHOW, FINALIZADA (para poblar reportes e historial).
--    E) Consumo de servicios, daño y cuenta por cobrar pagada.
--    F/G) Ver comentarios en cada reserva.
--    H) Salida INDIVIDUAL por huésped: dos personas comparten una
--       doble, una se retira antes; la habitación permanece
--       ACTIVA hasta que la última persona registre su salida.
-- =============================================================

USE hotel_db;

SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================
--  1. UBIGEO
-- =============================================================
INSERT INTO ubigeo (id_ubigeo, codigo, departamento, provincia, distrito) VALUES
(1, '150101', 'Lima',     'Lima',     'Lima Cercado'),
(2, '150102', 'Lima',     'Lima',     'Miraflores'),
(3, '150103', 'Lima',     'Lima',     'San Isidro'),
(4, '040101', 'Arequipa', 'Arequipa', 'Arequipa'),
(5, '110101', 'Ica',      'Ica',      'Ica'),
(6, '150104', 'Lima',     'Lima',     'Barranco'),
(7, '150105', 'Lima',     'Lima',     'San Borja'),
(8, '080101', 'Cusco',    'Cusco',    'Cusco'),
(9, '210101', 'Puno',     'Puno',     'Puno');

-- =============================================================
--  2. HOTEL
-- =============================================================
INSERT INTO hotel (id_hotel, nombre, direccion, telefono, email, id_ubigeo, activo) VALUES
(1, 'Hotel San Marcos Lima',     'Av. Universitaria 1801, Lima',    '01-4251000',  'lima@hotelsanmarcos.pe',  1, 1),
(2, 'Hotel San Marcos Ica',      'Av. Los Maestros 350, Ica',       '056-231000',  'ica@hotelsanmarcos.pe',   5, 1),
(3, 'Hotel San Marcos Arequipa', 'Calle Mercaderes 120, Arequipa',  '054-221000',  'aqp@hotelsanmarcos.pe',   4, 1),
(4, 'Hotel San Marcos Cusco',    'Calle Plateros 250, Cusco',       '084-221100',  'cusco@hotelsanmarcos.pe', 8, 1);

-- =============================================================
--  3. CARGO EMPLEADO
-- =============================================================
INSERT INTO cargo_empleado (id_cargo, nombre) VALUES
(1, 'Recepcionista'),
(2, 'Gerente de Hotel'),
(3, 'Camarero/a'),
(4, 'Jefe de Reservas'),
(5, 'Conserje'),
(6, 'Cajero/a');

-- =============================================================
--  4. EMPLEADO
-- =============================================================
INSERT INTO empleado (id_empleado, id_hotel, id_cargo, nombres, apellidos, activo) VALUES
(1,  1, 1, 'María',    'Torres Quispe',   1),
(2,  1, 2, 'Roberto',  'Huanca Flores',   1),
(3,  1, 4, 'Lissette', 'Paredes Cano',    1),
(4,  1, 3, 'Juan',     'Soto Medina',     1),
(5,  1, 6, 'Gabriela', 'Rojas Injante',   1),
(6,  2, 1, 'Carla',    'Mendoza Ramos',   1),
(7,  2, 2, 'Álvaro',   'Ccopa Vargas',    1),
(8,  3, 1, 'Diana',    'Lazo Chávez',     1),
(9,  3, 6, 'Fernando', 'Aguilar Meza',    1),
(10, 4, 1, 'Katherine','Zúñiga Prado',    1),
(11, 4, 2, 'Sergio',   'Mamani Choque',   1);

-- =============================================================
--  5. TIPO DE DOCUMENTO
-- =============================================================
INSERT INTO tipo_documento (id_tipo_documento, nombre, abreviatura) VALUES
(1, 'Documento Nacional de Identidad', 'DNI'),
(2, 'Registro Único de Contribuyentes', 'RUC'),
(3, 'Pasaporte',                        'PASAP'),
(4, 'Carné de Extranjería',             'CE');

-- =============================================================
--  6. PERSONA (supertype)
-- =============================================================
INSERT INTO persona (id_persona, tipo, telefono, email, id_ubigeo, activo) VALUES
-- Personas naturales (clientes individuales)
(1,  'NATURAL',  '987654321',  'jose.garcia@gmail.com',        2, 1),
(2,  'NATURAL',  '912345678',  'ana.lopez@hotmail.com',        2, 1),
(3,  'NATURAL',  '965432187',  'carlos.mendoza@yahoo.com',     3, 1),
(4,  'NATURAL',  '955112233',  'lucia.ramos@gmail.com',        6, 1),
(5,  'NATURAL',  '944556677',  'pedro.villar@gmail.com',       7, 1),
(6,  'NATURAL',  '933221144',  'sofia.chavez@outlook.com',     1, 1),
(7,  'NATURAL',  '922334455',  'martin.rios@gmail.com',        2, 1),
(8,  'NATURAL',  '911223344',  'daniela.paz@gmail.com',        3, 1),
-- Personas jurídicas (empresas)
(9,  'JURIDICA', '01-6001000', 'contacto@corporacionabc.pe',   3, 1),
(10, 'JURIDICA', '01-5002000', 'admin@tecnoandes.com.pe',      1, 1),
(11, 'JURIDICA', '01-7003000', 'reservas@mineraaltiplano.pe',  9, 1);

-- =============================================================
--  7. PERSONA_NATURAL
-- =============================================================
INSERT INTO persona_natural
    (id_persona, id_tipo_documento, numero_documento,
     nombres, apellidos, fecha_nacimiento, genero, nacionalidad) VALUES
(1, 1, '45123678', 'José Luis', 'García Ríos',      '1990-03-15', 'M', 'Peruana'),
(2, 1, '47892341', 'Ana María', 'López Castillo',   '1995-07-22', 'F', 'Peruana'),
(3, 3, 'AB123456', 'Carlos',    'Mendoza Ruiz',     '1988-11-05', 'M', 'Colombiana'),
(4, 1, '46778812', 'Lucía',     'Ramos Delgado',    '1993-01-30', 'F', 'Peruana'),
(5, 1, '44112233', 'Pedro',     'Villar Sánchez',   '1985-05-18', 'M', 'Peruana'),
(6, 4, 'CE998877',  'Sofía',    'Chávez (extr.)',   '1991-09-09', 'F', 'Chilena'),
(7, 1, '43321122', 'Martín',    'Ríos Fernández',   '1987-12-25', 'M', 'Peruana'),
(8, 3, 'PZ445566',  'Daniela',  'Paz Guerrero',     '1996-04-02', 'F', 'Ecuatoriana');

-- =============================================================
--  8. PERSONA_JURIDICA
-- =============================================================
INSERT INTO persona_juridica
    (id_persona, ruc, razon_social, nombre_comercial,
     representante_legal, giro_negocio) VALUES
(9,  '20512345678', 'Corporación ABC S.A.C.',  'ABC Corp',       'Marco Delgado Vega',  'Consultoría empresarial'),
(10, '20598765432', 'TecnoAndes S.R.L.',       'TecnoAndes',     'Sofía Varela Ponce',  'Tecnología y sistemas'),
(11, '20611223344', 'Minera Altiplano S.A.',   'Minera Altiplano','Jorge Huamán Ticona','Minería');

-- =============================================================
--  9. CLIENTE
-- =============================================================
INSERT INTO cliente (id_cliente, id_persona, observaciones) VALUES
(1,  1,  'Cliente frecuente, prefiere piso alto'),
(2,  2,  NULL),
(3,  3,  'Huésped extranjero, requiere factura en dólares'),
(4,  4,  NULL),
(5,  5,  'Suele viajar por trabajo'),
(6,  6,  NULL),
(7,  7,  NULL),
(8,  8,  NULL),
(9,  9,  'Empresa con convenio corporativo'),
(10, 10, 'Empresa tecnológica, reservas grupales frecuentes'),
(11, 11, 'Reservas para personal de campamento minero');

-- =============================================================
--  10. HUESPED
--      Personas que físicamente se alojan. Pueden coincidir o no
--      con los clientes. Incluye un huésped GENÉRICO (es_generico=1)
--      para el caso discutido en asesoría: "resérvame, luego te
--      doy los nombres".
-- =============================================================
INSERT INTO huesped
    (id_huesped, id_tipo_documento, numero_documento,
     nombres, apellidos, fecha_nacimiento, genero,
     nacionalidad, telefono, email, es_generico, activo) VALUES
-- Huéspedes individuales (corresponden a clientes 1..8)
(1,  1, '45123678', 'José Luis', 'García Ríos',    '1990-03-15', 'M', 'Peruana',    '987654321', 'jose.garcia@gmail.com',   0, 1),
(2,  1, '47892341', 'Ana María', 'López Castillo', '1995-07-22', 'F', 'Peruana',    '912345678', 'ana.lopez@hotmail.com',   0, 1),
(3,  3, 'AB123456', 'Carlos',    'Mendoza Ruiz',   '1988-11-05', 'M', 'Colombiana', '965432187', 'carlos.mendoza@yahoo.com',0, 1),
(4,  1, '46778812', 'Lucía',     'Ramos Delgado',  '1993-01-30', 'F', 'Peruana',    '955112233', 'lucia.ramos@gmail.com',   0, 1),
(5,  1, '44112233', 'Pedro',     'Villar Sánchez', '1985-05-18', 'M', 'Peruana',    '944556677', 'pedro.villar@gmail.com',  0, 1),
(6,  1, '43321122', 'Martín',    'Ríos Fernández', '1987-12-25', 'M', 'Peruana',    '922334455', 'martin.rios@gmail.com',   0, 1),
-- Huéspedes corporativos (empleados de Corporación ABC)
(7,  1, '43210987', 'Ricardo',   'Salas Cueva',    '1985-06-10', 'M', 'Peruana',    '999111222', 'rsalas@corporacionabc.pe',0, 1),
(8,  1, '41098765', 'Patricia',  'Nuñez Apaza',    '1992-09-28', 'F', 'Peruana',    '999333444', 'pnunez@corporacionabc.pe',0, 1),
(9,  1, '48765432', 'Eduardo',   'Quispe Llanos',  '1987-02-14', 'M', 'Peruana',    '999555666', 'equispe@tecnoandes.com',  0, 1),
-- Huésped GENÉRICO: reserva del cliente 5 (Pedro Villar) aún sin
-- nombre del acompañante en la habitación doble.
(10, NULL, NULL, 'Invitado 1', NULL, NULL, NULL, NULL, NULL, NULL, 1, 1),
-- Huéspedes para el caso H (salida individual): Sofía viaja con
-- su hermano Diego a una doble en Ica; Diego se retira dos días
-- antes que Sofía, quien continúa hospedada.
(11, 1, '46001122', 'Sofía', 'Chávez Gutiérrez', '1994-02-20', 'F', 'Peruana', '933221144', 'sofia.chavez@outlook.com', 0, 1),
(12, 1, '47002233', 'Diego', 'Chávez Gutiérrez', '1996-08-11', 'M', 'Peruana', '933221145', 'diego.chavez@outlook.com', 0, 1);

-- =============================================================
--  11. TIPO_HABITACION
-- =============================================================
INSERT INTO tipo_habitacion
    (id_tipo_habitacion, nombre, capacidad_base, descripcion) VALUES
(1, 'Simple',      1, 'Habitación para 1 persona, cama 1.5 plazas'),
(2, 'Doble',       2, 'Habitación para 2 personas, cama queen o 2 simples'),
(3, 'Matrimonial', 2, 'Habitación para 2 personas, cama king'),
(4, 'Suite',       2, 'Suite junior con sala de estar y jacuzzi'),
(5, 'Familiar',    4, 'Habitación amplia para familias, 2 camas dobles');

-- =============================================================
--  12. HABITACION
-- =============================================================
INSERT INTO habitacion
    (id_habitacion, id_hotel, id_tipo_habitacion, estado, numero, piso, descripcion) VALUES
-- Hotel Lima (1)
(1,  1, 1, 'OCUPADA',    '101', 1, 'Vista al jardín'),
(2,  1, 1, 'OCUPADA',    '102', 1, 'Vista al jardín'),
(3,  1, 2, 'OCUPADA',    '201', 2, 'Vista a la calle'),
(4,  1, 2, 'OCUPADA',    '202', 2, 'Vista a la calle'),
(5,  1, 3, 'DISPONIBLE', '301', 3, 'Vista panorámica'),
(6,  1, 4, 'OCUPADA',    '401', 4, 'Suite premium, vista ciudad'),
(7,  1, 5, 'DISPONIBLE', '501', 5, 'Habitación familiar, 2 baños'),
(8,  1, 1, 'RESERVADA',  '103', 1, 'Vista interior'),
(9,  1, 2, 'RESERVADA',  '203', 2, 'Vista a la calle'),
-- Hotel Ica (2)
(10, 2, 1, 'DISPONIBLE', '101', 1, 'Vista al desierto'),
(11, 2, 2, 'OCUPADA',    '201', 2, 'Vista a la piscina'),
(12, 2, 3, 'DISPONIBLE', '301', 3, 'Vista al oasis'),
-- Hotel Arequipa (3)
(13, 3, 1, 'DISPONIBLE', '101', 1, 'Vista al volcán'),
(14, 3, 2, 'DISPONIBLE', '201', 2, 'Vista al centro histórico'),
-- Hotel Cusco (4)
(15, 4, 1, 'DISPONIBLE', '101', 1, 'Vista a la plaza'),
(16, 4, 4, 'DISPONIBLE', '401', 4, 'Suite con balcón colonial'),
(17, 4, 5, 'DISPONIBLE', '501', 5, 'Habitación familiar amplia');

-- =============================================================
--  13. PLAN_TARIFA
-- =============================================================
-- es_publico = 1 → se autodetecta por fecha (fn_plan_vigente).
-- es_publico = 0 → solo se aplica si el operador lo elige a
-- propósito (tarifa negociada con una empresa específica).
INSERT INTO plan_tarifa
    (id_plan, nombre, descripcion, fecha_inicio, fecha_fin, es_publico, activo) VALUES
(1, 'Tarifa Regular 2025',        'Tarifa estándar para el año 2025',                        '2025-01-01', '2025-12-31', 1, 1),
(2, 'Tarifa Temporada Alta 2025', 'Semana Santa, fiestas patrias, navidad y año nuevo',       '2025-03-28', '2025-04-07', 1, 1),
(3, 'Tarifa Corporativa ABC',     'Tarifa preferencial para Corporación ABC S.A.C.',          '2025-01-01', '2025-12-31', 0, 1),
(4, 'Tarifa Regular 2026',        'Tarifa estándar para el año 2026',                         '2026-01-01', '2026-12-31', 1, 1);

-- =============================================================
--  14. TARIFA_HABITACION
-- =============================================================
INSERT INTO tarifa_habitacion
    (id_tarifa, id_plan, id_tipo_habitacion, precio_por_noche, capacidad_maxima) VALUES
-- Plan Regular 2025
(1,  1, 1, 150.00, 1),
(2,  1, 2, 220.00, 2),
(3,  1, 3, 250.00, 2),
(4,  1, 4, 480.00, 2),
(5,  1, 5, 350.00, 4),
-- Plan Temporada Alta 2025
(6,  2, 1, 200.00, 1),
(7,  2, 2, 300.00, 2),
(8,  2, 3, 340.00, 2),
(9,  2, 4, 650.00, 2),
(10, 2, 5, 480.00, 4),
-- Plan Corporativo ABC
(11, 3, 1, 130.00, 1),
(12, 3, 2, 190.00, 2),
(13, 3, 3, 210.00, 2),
(14, 3, 4, 400.00, 2),
-- Plan Regular 2026
(15, 4, 1, 160.00, 1),
(16, 4, 2, 235.00, 2),
(17, 4, 3, 265.00, 2),
(18, 4, 4, 510.00, 2),
(19, 4, 5, 370.00, 4);

-- =============================================================
--  15. ESTADO_RESERVA
-- =============================================================
INSERT INTO estado_reserva (id_estado_reserva, nombre) VALUES
(1, 'PENDIENTE'),
(2, 'CONFIRMADA'),
(3, 'CANCELADA'),
(4, 'NO_SHOW'),
(5, 'FINALIZADA');

-- =============================================================
--  16. CATEGORIA_SERVICIO Y SERVICIO
-- =============================================================
INSERT INTO categoria_servicio (id_categoria, nombre) VALUES
(1, 'RESTAURANTE'),
(2, 'LAVANDERIA'),
(3, 'TRANSPORTE'),
(4, 'MINIBAR'),
(5, 'SPA'),
(6, 'ESTACIONAMIENTO');

INSERT INTO servicio (id_servicio, nombre, id_categoria, precio_unitario, activo) VALUES
(1, 'Servicio de cuarto (desayuno)', 1,  25.00, 1),
(2, 'Servicio de cuarto (almuerzo)', 1,  35.00, 1),
(3, 'Servicio de cuarto (cena)',     1,  40.00, 1),
(4, 'Lavandería (prenda)',           2,  12.00, 1),
(5, 'Transporte aeropuerto (ida)',   3,  80.00, 1),
(6, 'Minibar (recarga completa)',    4,  45.00, 1),
(7, 'Spa (sesión 60 min)',           5, 120.00, 1),
(8, 'Estacionamiento (por día)',     6,  30.00, 1);

-- =============================================================
--  17. RESERVAS
--  A: José García (cliente 1) — CONFIRMADA, en curso (check-in hecho)
--  B: Corporación ABC (cliente 9) — CONFIRMADA, corporativa
--  C: Ana López (cliente 2) — PENDIENTE de pago
--  D: Lucía Ramos (cliente 4) — CANCELADA
--  E: Martín Ríos (cliente 7) — NO_SHOW
--  F: Carlos Mendoza (cliente 3) — FINALIZADA (histórico, con cuenta pagada)
--  G: Pedro Villar (cliente 5) — CONFIRMADA con huésped genérico
-- =============================================================
INSERT INTO reserva
    (id_reserva, id_cliente, id_hotel, id_estado_reserva,
     id_empleado, id_cliente_contacto, canal,
     fecha_reserva, fecha_checkin, fecha_checkout,
     fecha_limite_pago, pagado, fecha_pago, monto_total, observaciones) VALUES
(1, 1, 1, 2, 3, NULL, 'DIRECTO',
   '2026-06-01 10:30:00', '2026-06-10', '2026-06-12',
   '2026-06-05', 1, '2026-06-03 14:00:00', 470.00, 'Cliente solicita cama king si disponible'),
(2, 9, 1, 2, 3, NULL, 'TELEFONO',
   '2026-06-05 09:00:00', '2026-06-15', '2026-06-18',
   '2026-06-10', 1, '2026-06-08 11:00:00', 1350.00, 'Reserva corporativa ABC — 3 noches, 3 habitaciones'),
(3, 2, 1, 1, 1, NULL, 'WEB',
   '2026-06-20 16:45:00', '2026-06-25', '2026-06-27',
   '2026-06-22', 0, NULL, 530.00, 'Suite 2 noches'),
(4, 4, 1, 3, 1, NULL, 'WEB',
   '2026-05-10 12:00:00', '2026-05-20', '2026-05-22',
   '2026-05-15', 0, NULL, 300.00, 'Cliente canceló por cambio de viaje'),
(5, 7, 1, 4, 4, NULL, 'AGENCIA',
   '2026-05-01 08:00:00', '2026-05-05', '2026-05-06',
   '2026-05-03', 1, '2026-05-02 10:00:00', 150.00, 'No se presentó (no-show), pago no reembolsable'),
(6, 3, 1, 5, 4, NULL, 'DIRECTO',
   '2026-04-01 09:00:00', '2026-04-10', '2026-04-13',
   '2026-04-05', 1, '2026-04-02 09:30:00', 750.00, 'Estadía finalizada, cuenta liquidada'),
(7, 5, 1, 2, 3, NULL, 'WEB',
   '2026-06-18 15:00:00', '2026-06-20', '2026-06-23',
   '2026-06-19', 1, '2026-06-18 15:20:00', 660.00, 'Doble para 2 personas, segundo huésped por confirmar'),
(8, 6, 2, 2, 6, NULL, 'DIRECTO',
   '2026-06-17 11:00:00', '2026-06-19', '2026-06-22',
   '2026-06-18', 1, '2026-06-17 11:30:00', 705.00, 'Caso H: salida individual — el acompañante se retira antes que la titular');

-- =============================================================
--  18. RESERVA_DETALLE
-- =============================================================
-- Reserva A: 1 doble (tipo 2), plan 4 — 2 noches × S/235 = 470
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(1, 1, 2, 4, 1, 235.00, 470.00);

-- Reserva B: 2 simples + 1 doble, plan 3 (corporativo ABC), 3 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(2, 2, 1, 3, 2, 130.00, 780.00),
(3, 2, 2, 3, 1, 190.00, 570.00);

-- Reserva C: 1 suite (tipo 4), plan 4, 2 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(4, 3, 4, 4, 1, 265.00, 530.00);

-- Reserva D (cancelada): 1 matrimonial, plan 1, 2 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(5, 4, 3, 1, 1, 150.00, 300.00);

-- Reserva E (no-show): 1 simple, plan 1, 1 noche
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(6, 5, 1, 1, 1, 150.00, 150.00);

-- Reserva F (finalizada): 1 doble, plan 1, 3 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(7, 6, 2, 1, 1, 250.00, 750.00);

-- Reserva G: 1 doble, plan 4, 3 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(8, 7, 2, 4, 1, 220.00, 660.00);

-- Reserva H: 1 doble (Ica), plan 4, 3 noches
INSERT INTO reserva_detalle
    (id_detalle_reserva, id_reserva, id_tipo_habitacion, id_plan,
     cantidad_habitaciones, precio_unitario, subtotal) VALUES
(9, 8, 2, 4, 1, 235.00, 705.00);

-- =============================================================
--  19. DETALLE_HUESPED_RESERVA
--      Solo Reserva B (corporativa): pre-asignación de empleados
-- =============================================================
-- id_cliente ya no se guarda aquí: el pagador de toda la reserva
-- (Corporación ABC, cliente 9) está en reserva.id_cliente.
INSERT INTO detalle_huesped_reserva
    (id_detalle_huesped, id_detalle_reserva, id_huesped, es_titular) VALUES
(1, 2, 7, 1),   -- Ricardo Salas → titular (una de las 2 simples)
(2, 2, 8, 0),   -- Patricia Nuñez (otra simple)
(3, 3, 9, 1);   -- Eduardo Quispe → titular de la doble

-- =============================================================
--  20. ALOJAMIENTO
--      A (reserva 1): ACTIVO, en curso.
--      F (reserva 6): FINALIZADO, histórico.
--      G (reserva 7): ACTIVO, con huésped genérico pendiente de
--                     identificar.
-- =============================================================
INSERT INTO alojamiento
    (id_alojamiento, id_reserva, id_detalle_reserva,
     id_habitacion, estado,
     id_empleado_checkin, id_empleado_checkout,
     fecha_checkin_real, fecha_checkout_real) VALUES
(1, 1, 1, 3,  'ACTIVO',     1, NULL, '2026-06-10 14:30:00', NULL),
(2, 6, 7, 14, 'FINALIZADO', 8, 8,    '2026-04-10 13:00:00', '2026-04-13 11:00:00'),
(3, 7, 8, 9,  'ACTIVO',     1, NULL, '2026-06-20 15:30:00', NULL),
(4, 8, 9, 11, 'ACTIVO',     6, NULL, '2026-06-19 15:00:00', NULL),
-- Escenario I: check-in real de la reserva corporativa (reserva 2).
(5, 2, 2, 1, 'ACTIVO', 3, NULL, '2026-06-15 14:00:00', NULL),  -- simple #1 (habitación 1)
(6, 2, 3, 4, 'ACTIVO', 3, NULL, '2026-06-15 14:10:00', NULL),  -- doble (habitación 4)
(7, 2, 2, 2, 'ACTIVO', 3, NULL, '2026-06-15 14:05:00', NULL);  -- simple #2 (habitación 2)
-- Alojamiento 4 sigue ACTIVO (aún no todos los huéspedes salieron;
-- ver huesped_alojamiento más abajo: Diego ya se retiró, Sofía no).

-- =============================================================
--  21. HUESPED_ALOJAMIENTO
-- =============================================================
-- La columna fecha_salida_real demuestra la salida INDIVIDUAL de
-- cada huésped (puede diferir del checkout general de la
-- habitación). id_detalle_huesped enlaza (cuando aplica) con la
-- pre-asignación corporativa de detalle_huesped_reserva, para
-- poder comparar "quién asignó la empresa" vs. "quién hizo
-- check-in" (ver vw_preasignacion_vs_checkin, escenario I). En el
-- alojamiento 2 (finalizado) se registra la salida igual a la
-- fecha_checkout_real de la habitación, ya que Carlos viajó solo.
-- En el alojamiento 3 (activo) ambos huéspedes siguen presentes
-- (fecha_salida_real = NULL).
INSERT INTO huesped_alojamiento
    (id_alojamiento, id_huesped, id_detalle_huesped, es_titular, fecha_registro, fecha_salida_real) VALUES
(1, 1,  NULL, 1, '2026-06-10 14:30:00', NULL),                    -- José García, solo, en la doble (activo)
(2, 3,  NULL, 1, '2026-04-10 13:00:00', '2026-04-13 11:00:00'),   -- Carlos Mendoza, estadía finalizada
(3, 5,  NULL, 1, '2026-06-20 15:30:00', NULL),                    -- Pedro Villar, titular (aún presente)
(3, 10, NULL, 0, '2026-06-20 15:30:00', NULL),                    -- Invitado 1 (genérico), aún presente
(4, 11, NULL, 1, '2026-06-19 15:00:00', NULL),                    -- Sofía, titular, continúa hospedada
(4, 12, NULL, 0, '2026-06-19 15:00:00', '2026-06-21 09:30:00'),   -- Diego, se retiró antes; la habitación NO se libera todavía
-- Escenario I: check-in real de la reserva corporativa. Ricardo y
-- Patricia hacen check-in tal como fueron pre-asignados
-- (COINCIDE); en la doble, en cambio, llega Patricia y no Eduardo
-- como se había pre-asignado (DIFERENTE) — el descuadre operativo
-- real que el profesor mencionó como riesgo en eventos corporativos.
(5, 7, 1, 1, '2026-06-15 14:00:00', NULL),   -- Ricardo Salas, coincide con dhr 1 (simple #1)
(7, 8, 2, 0, '2026-06-15 14:05:00', NULL),   -- Patricia Nuñez, coincide con dhr 2 (simple #2)
(6, 8, 3, 1, '2026-06-15 14:10:00', NULL);   -- Patricia hace check-in en la doble; dhr 3 pre-asignó a Eduardo → DIFERENTE

-- =============================================================
--  22. CONSUMO_SERVICIO
-- =============================================================
INSERT INTO consumo_servicio
    (id_consumo, id_alojamiento, id_servicio,
     cantidad, precio_unitario, subtotal, fecha_consumo) VALUES
-- Alojamiento 1 (José García, activo)
(1, 1, 1, 2, 25.00, 50.00, '2026-06-10 08:00:00'),
(2, 1, 3, 1, 40.00, 40.00, '2026-06-10 20:30:00'),
(3, 1, 4, 3, 12.00, 36.00, '2026-06-11 10:00:00'),
(4, 1, 6, 1, 45.00, 45.00, '2026-06-11 18:00:00'),
(5, 1, 8, 2, 30.00, 60.00, '2026-06-10 14:30:00'),
-- Alojamiento 2 (Carlos Mendoza, finalizado)
(6, 2, 1, 3, 25.00, 75.00, '2026-04-11 08:00:00'),
(7, 2, 7, 1, 120.00, 120.00, '2026-04-12 16:00:00');

-- =============================================================
--  23. DAÑO
-- =============================================================
INSERT INTO danio
    (id_danio, id_alojamiento, descripcion, costo, fecha_reporte, estado) VALUES
(1, 1, 'Mancha en la alfombra junto a la cama, requiere limpieza especializada', 80.00, '2026-06-11 09:00:00', 'PENDIENTE'),
(2, 2, 'Control remoto de TV extraviado', 60.00, '2026-04-13 10:30:00', 'COBRADO');

-- =============================================================
--  24. CUENTA_COBRAR
--      Cuenta 1 (alojamiento 1, aún activo): generada de forma
--        preliminar para consultas del MVP, PENDIENTE.
--      Cuenta 2 (alojamiento 2, finalizado): liquidada por
--        completo (saldo = 0) para demostrar el ciclo de pago.
-- =============================================================
INSERT INTO cuenta_cobrar
    (id_cuenta, id_alojamiento, fecha_generacion,
     subtotal, impuestos, total, saldo, estado) VALUES
(1, 1, '2026-06-11 20:00:00', 311.00, 55.98, 366.98, 366.98, 'PENDIENTE'),
(2, 2, '2026-04-13 11:30:00', 255.00, 45.90, 300.90, 300.90, 'PENDIENTE');

-- =============================================================
--  25. CUENTA_COBRAR_DETALLE
-- =============================================================
INSERT INTO cuenta_cobrar_detalle
    (id_detalle_cuenta, id_cuenta, concepto,
     cantidad, precio_unitario, subtotal) VALUES
(1, 1, 'Servicio de cuarto — desayuno',       2, 25.00, 50.00),
(2, 1, 'Servicio de cuarto — cena',           1, 40.00, 40.00),
(3, 1, 'Lavandería — prendas',                3, 12.00, 36.00),
(4, 1, 'Recarga de minibar',                  1, 45.00, 45.00),
(5, 1, 'Estacionamiento por día',              2, 30.00, 60.00),
(6, 1, 'Cargo por daño — limpieza alfombra',  1, 80.00, 80.00),
(7, 2, 'Servicio de cuarto — desayuno',       3, 25.00, 75.00),
(8, 2, 'Spa (sesión 60 min)',                 1, 120.00, 120.00),
(9, 2, 'Cargo por daño — control remoto',     1, 60.00, 60.00);

-- =============================================================
--  26. PAGO_CUENTA_COBRAR
--      La cuenta 2 se paga por completo en dos abonos (demuestra
--      el trigger trg_cuenta_actualizar_saldo).
-- =============================================================
INSERT INTO pago_cuenta_cobrar
    (id_pago, id_cuenta, monto, metodo_pago, fecha_pago, id_empleado) VALUES
(1, 2, 200.90, 'TARJETA',  '2026-04-13 11:45:00', 9),
(2, 2, 100.00, 'EFECTIVO', '2026-04-13 11:50:00', 9);

SET FOREIGN_KEY_CHECKS = 1;

-- =============================================================
--  Actualización manual del saldo/estado de la cuenta 2 y del
--  stock_disponible/estado de habitaciones, ya que los INSERT
--  masivos anteriores se hicieron directamente sobre las tablas
--  (sin pasar por los procedimientos) para poblar datos con
--  fechas específicas de forma controlada. En operación normal,
--  estos valores los mantienen los triggers y procedimientos
--  automáticamente.
-- =============================================================
UPDATE cuenta_cobrar
SET saldo = fn_saldo_cuenta(2),
    estado = IF(fn_saldo_cuenta(2) <= 0, 'PAGADA', 'PENDIENTE')
WHERE id_cuenta = 2;
