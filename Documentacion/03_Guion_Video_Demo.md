# Guion — Video de sustentación (≈10 minutos)

Basado en el recorrido ya probado contra la base de datos real (ver
`mvp_app/tests/test_flujo_manual.md`) y en el diagrama de secuencia
`Diagramas/04_Flujo_MVP_Secuencia.puml`. El objetivo de cada bloque es que se vea, en una sola
corrida en vivo, el uso real de tablas, funciones, procedimientos, vistas, triggers y roles.

Antes de grabar: tener `hotel_db` recién cargada (los 9 scripts en orden) y la app corriendo
(`python run.py`) en una ventana visible junto a MySQL Workbench (o consola) para mostrar el
efecto en la base de datos cuando se mencione un trigger.

---

## 0. Apertura (0:00–1:00) — Caso de negocio

- Quiénes somos y qué problema resuelve el sistema: gestión de reservas y estadías para una
  cadena hotelera (mencionar las 4 sedes cargadas: Lima, Ica, Arequipa, Cusco).
- Una frase sobre el criterio de éxito del MVP: interfaz mínima pero con conectividad real y uso
  efectivo de SQL avanzado (no un CRUD trivial).

## 1. Diseño de la base de datos (1:00–3:00)

- Mostrar `Diagramas/Diagrama de Base de Datos/01_Modelo_Conceptual.png`: explicar brevemente
  persona (natural/jurídica), cliente vs. huésped, y por qué están separados. **Pendiente:** este
  PNG (y `02_Modelo_Logico.png`/`03_Modelo_Fisico.png`) todavía muestra `huesped` como tabla propia
  y no muestra `auditoria`; se eliminó `huesped` del esquema y se agregó `auditoria` (ver
  `01_Entregable1_Diseno_BD.md` sección 4) y hay que regenerar los diagramas antes de grabar.
- Mostrar `02_Modelo_Logico.png` → `03_Modelo_Fisico.png`: mencionar 27 tablas, tipos ENUM para
  estados, cupos sin identificar en reservas corporativas, plan público vs. corporativo.
- Un vistazo rápido a `Scripts/01_Creacion_Tablas.sql` y `02_Reglas_Integridad.sql` en el editor
  (no leer todo, solo mostrar que existe y está versionado).

## 2. Recorrido en vivo del flujo completo (3:00–8:00)

Seguir exactamente `Diagramas/04_Flujo_MVP_Secuencia.puml`, narrando qué procedimiento/función/
trigger se dispara en cada paso:

1. **Login** como Recepción.
2. **Disponibilidad** (UC-11): consultar un hotel/tipo/fechas → mencionar que usa
   `fn_disponibilidad_tipo_habitacion`, no un conteo hecho en la aplicación.
3. **Nueva reserva** (UC-01): crear cabecera (`sp_registrar_reserva`) y agregar una línea dejando
   el plan vacío → mostrar que autodetecta la tarifa correcta según la fecha
   (`fn_plan_vigente` + `fn_precio_vigente`), y el `monto_total` calculado.
4. **Confirmar pago** (UC-02): `sp_confirmar_pago` → mostrar en MySQL que el estado cambió a
   CONFIRMADA.
5. **Check-in** (UC-04): `sp_realizar_checkin` → mostrar en MySQL que la habitación pasó a OCUPADA
   (trigger `trg_alojamiento_checkin`) sin que la app lo haya hecho por su cuenta.
6. **Consumo y daño** (UC-05/06): `sp_registrar_consumo`, `sp_registrar_danio`.
7. **Salida individual** (UC-07): `sp_registrar_salida_huesped` → si se cargó un escenario con 2
   huéspedes, mostrar que la habitación sigue ACTIVA hasta que sale el último.
8. **Cuenta por cobrar y pago** (UC-09/10): `sp_generar_cuenta_cobrar` (mostrar el cálculo de IGV
   18 %) → `sp_registrar_pago_cuenta` con un pago parcial y luego el resto → mostrar que el trigger
   `trg_cuenta_actualizar_saldo` deja `saldo = 0` y `estado = PAGADA`.
9. **(Opcional, si hay tiempo)** Provocar un error de negocio a propósito (pedir más habitaciones
   de las disponibles, o pagar de más) y mostrar que el mensaje que aparece en pantalla es
   exactamente el `SIGNAL` que lanza el procedimiento — la interfaz no lo reinterpreta.

## 3. Reportes y roles (8:00–9:00)

- Cerrar sesión, entrar como Gerencia: el propio dashboard de inicio ya muestra la barra de
  ocupación, el ingreso del mes con su variación % y el top 3 de clientes — mostrar eso primero,
  después entrar a "Ingresos mensuales"/"Ocupación mensual" y señalar en pantalla las columnas
  `SUM() OVER`/`LAG() OVER` (acumulado del año, variación contra el mes anterior). Después
  `vw_ocupacion_hotel`, `vw_ingresos_por_hotel`, `vw_ranking_clientes` (esta última con `RANK()`).
- Desde Gerencia, entrar a "Auditoría" y mostrar el antes/después de un cambio real (ej. la
  cancelación de reserva o el pago hechos minutos antes en la demo) — señalar la columna Empleado
  (quién lo hizo) y explicar que sale de una variable de sesión MySQL que fija la app, no de adivinar
  el usuario de conexión. Entrar como Caja y mostrar que ahí la misma pantalla ya no ofrece el
  selector de tabla ni ninguna fila de reservas — solo cuentas por cobrar.
- Mostrar brevemente que un rol sin permiso (ej. Gerencia intentando entrar a Administración) es
  bloqueado — conecta con los roles de MySQL de `07_Roles_Permisos.sql`.
- **(Opcional, si hay tiempo)** Mostrar el `EVENT ev_procesar_reservas_vencidas` en MySQL Workbench
  (`SHOW EVENTS`) y explicar que cancela reservas vencidas / marca no-show una vez al día sin que la
  app lo dispare. Como no se puede esperar a que corra solo durante la grabación, ejecutarlo a mano
  (`CALL sp_procesar_reservas_vencidas(@c, @n); SELECT @c, @n;`) sobre una reserva de prueba vencida
  creada momentos antes, para mostrar el efecto en vivo.

## 4. Cierre — aportes y decisiones (9:00–10:00)

Mencionar 2–3 decisiones de diseño no obviamente triviales, como aporte propio justificado:

- Separación cliente/huésped, y cupos sin identificar en reservas corporativas (la incertidumbre
  de "quién" vive en la reserva, nunca en la ocupación real).
- Plan público (autodetectado) vs. corporativo (elegido explícitamente), con reglas de
  especificidad cuando dos planes públicos se solapan en fecha.
- Salida individual por huésped vs. checkout conjunto de la habitación.
- Abonos parciales con historial de pagos, en vez de solo un campo de saldo.
- Mantenimiento automático de reservas vencidas con `EVENT SCHEDULER` + un procedimiento con
  `CURSOR`/`HANDLER` (único del proyecto que itera fila por fila), en vez de depender de que alguien
  se acuerde de cancelar/marcar no-show a mano.
- Auditoría de cambios (`reserva`/`cuenta_cobrar`) con triggers + `JSON_OBJECT`, acotada por rol de
  forma distinta según a quién le sirve (Administrador/Gerencia ven todo, Caja solo lo que le toca
  conciliar) — y quién hizo el cambio sale de una variable de sesión MySQL que fija la app, no de
  adivinar el usuario de conexión (la app usa una sola cuenta de servicio para todos).

Cerrar indicando que la Fase III (migración a un segundo SGBD) fue excluida del alcance de este
proyecto por indicación expresa del profesor (ver `Documentacion/04_Nota_Alcance_Fase3.md`), para
que quede explícito y no genere dudas al evaluar.
