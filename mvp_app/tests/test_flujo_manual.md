# Checklist de verificación end-to-end — MVP Hotel

Replica el recorrido de `Diagramas/04_Flujo_MVP_Secuencia.puml`. Verificado
contra `hotel_db` real (MySQL) el 2026-07-06; los ítems de reservas/estadía se
re-verificaron el 2026-07-12 tras el rediseño de asignación de huéspedes por
tabla, de nuevo tras corregir el check-in a individual por huésped, una
tercera vez el mismo día tras exigir que el titular haga check-in primero y
retirar el alta de huéspedes desde estadía, una cuarta vez tras pasar la
confirmación de pago a ser responsabilidad exclusiva de Caja, una quinta
tras agregar filtros de búsqueda al listado de reservas y retirar la pantalla
"Reservas corporativas", una sexta el mismo día tras rediseñar el listado
de check-in como tabla plana buscable por titular, una séptima tras
bloquear también para Recepción el acceso directo a la URL de confirmación
de pago (antes solo se ocultaba el botón), una octava tras agregar
cancelar/no-show de reserva y el bloqueo general de estados finales, una
novena el mismo día tras quitar el stepper visual de pago/asignación/
check-in, una décima tras agregar el trigger de habitación única y
rediseñar "alojamientos activos" como tabla por habitación, y una
undécima tras eliminar la tabla `huesped` (rol puro sin datos propios,
reemplazado por FK directa a `persona_natural`) (ver commits de esa
fecha), una duodécima el mismo 2026-07-12 tras agregar la pantalla
      `/admin/usuarios` (alta de login para un empleado existente), y una
      decimotercera el mismo día tras dar a Recepción acceso a `/habitaciones`
      (ver estado + cambiarlo) y restringir las transiciones manuales de
      `sp_cambiar_estado_habitacion`, una decimocuarta tras rechazar
      generar cuentas por cobrar sin consumos ni daños pendientes, y una
      decimoquinta el 2026-07-13 tras corregir el bug de
      `fecha_salida_real` en `sp_agregar_huesped_alojamiento`, y una
      decimosexta el mismo día tras agregar edición (+ activar/desactivar
      donde aplica) a hoteles, tipos de habitación, categorías de
      servicio, servicios, planes tarifarios, tarifas y empleados, y una
      decimoséptima tras convertir "Agregar línea" (detalle de reserva) en
      ventana flotante. Marcar de nuevo tras cambios importantes.

- [x] **Precondición:** los 9 scripts (`01`→`09`) ya estaban cargados en
      `hotel_db` (14 procedimientos, 6 funciones, 14 vistas, datos de
      `08_Carga_Datos.sql`).
- [x] **Login:** `POST /login` con empleado + rol guarda la sesión y
      redirige según el rol (`auth.landing`).
- [x] **Disponibilidad (UC-11):** `fn_disponibilidad_tipo_habitacion` para
      Hotel Lima, tipo Simple, 2026-07-10→12 devolvió 3 habitaciones libres.
- [x] **Nueva reserva (UC-01):** `sp_registrar_reserva` + `sp_agregar_detalle_reserva`
      con plan vacío → autodetectó "Tarifa Regular 2026" y calculó
      265.00 × 1 hab. × 2 noches = 530.00 correctamente.
- [x] **Alta directa de cliente natural:** INSERT transaccional
      persona→persona_natural→cliente funcionó y el cliente apareció
      inmediatamente en el combo de `/reservas/nuevo`.
- [x] **Reserva corporativa (UC-03):** reserva para "Corporación ABC S.A.C."
      + asignación de huésped, visible luego en `vw_reservas_corporativas`
      (la vista se sigue usando por SQL directo; la pantalla web dedicada
      se retiró el 2026-07-12, reemplazada por el filtro de tipo de
      reservante en el listado).
- [x] **Filtros del listado de reservas (2026-07-12):** con reservas de
      ambos tipos de persona, filtrar por `tipo_persona=JURIDICA` mostró
      solo las de RUC; filtrar por documento/RUC parcial encontró la
      reserva correcta; filtrar por `estado` funcionó. `GET
      /reservas/corporativas` devolvió 404 (ruta eliminada). Caja siguió
      viendo solo pendientes de pago, sin el formulario de filtro.
- [x] **Asignación de huéspedes por habitación (UC-03, re-verificado
      2026-07-12):** en una línea "Doble x1" (capacidad 2), guardar la
      habitación sin marcar titular fue rechazado; con titular marcado se
      guardó `detalle_huesped_reserva` en una sola transacción. Aplica a
      reserva NATURAL, no solo JURIDICA.
- [x] **Bloqueo de línea nueva en reserva pagada (2026-07-12):**
      `sp_agregar_detalle_reserva` sobre una reserva con `pagado=1` rechazó
      con *"La reserva ya está pagada; no se pueden agregar más líneas."*
- [x] **Error de negocio propagado tal cual:** pedir 50 habitaciones Simple
      (solo hay 3 libres) mostró el mensaje SIGNAL exacto de
      `sp_agregar_detalle_reserva`: *"No hay disponibilidad suficiente de
      ese tipo de habitación en las fechas solicitadas"*. Un plan
      corporativo vigente solo en 2025 usado en una reserva 2026 mostró
      *"No existe tarifa vigente para ese tipo de habitación y plan en la
      fecha indicada"*.
- [x] **Confirmación de pago (UC-02):** `sp_confirmar_pago` cambió estado a
      CONFIRMADA; la reserva pasó a aparecer en el listado de check-in.
- [x] **Confirmación de pago es solo de Caja (UC-02, re-verificado
      2026-07-12):** con una reserva nueva sin pagar, RECEPCION no vio el
      botón "Confirmar pago" (solo un aviso de que es tarea de caja) y un
      `POST /reservas/<id>/pago` directo fue rechazado por rol; CAJA sí vio
      el botón, confirmó el pago sin errores y el redirect posterior no
      rebotó por falta de permiso (antes iba a `reservas.pago`, que
      redirige a `preasignar`, inaccesible para Caja; ahora va a
      `reservas.detalle`). El listado de CAJA mostró solo reservas
      pendientes de pago, sin el toggle "Todas" que sí tiene Recepción.
      `reservas/detalle.html` volvió al breadcrumb de texto simple (sin
      el stepper, que sigue en pago/asignación/check-in).
- [x] **Check-in (UC-04):** `sp_realizar_checkin` sobre habitación 301
      (DISPONIBLE) creó el alojamiento y el trigger `trg_alojamiento_checkin`
      la marcó OCUPADA.
- [x] **Agregar huésped (UC-04):** `sp_agregar_huesped_alojamiento` asoció
      al huésped titular sin exceder la capacidad.
- [x] **Check-in individual por huésped (UC-04, re-verificado
      2026-07-12):** con 2 huéspedes ya asignados a una habitación (uno
      titular), el check-in del primero creó el `alojamiento` con su
      `es_titular` real (no forzado a 1) y eligió la habitación física; el
      segundo se registró después con un solo clic, sin volver a elegir
      habitación. En la pantalla de asignación, el primer cupo quedó de
      solo lectura mientras el segundo seguía editable (se pudo cambiar de
      huésped sin tocar al ya registrado). Reintentar el check-in del mismo
      cupo ya registrado fue rechazado. Sin titular asignado, la pantalla
      de check-in no ofreció ningún botón para esa habitación.
- [x] **Reserva pagada salta la pantalla de pago (2026-07-12):**
      `GET /reservas/<id>/pago` sobre una reserva con `pagado=1` redirige
      directo a la asignación de huéspedes en vez de mostrar una pantalla
      de "pago confirmado" sin nada que hacer.
- [x] **El titular hace check-in primero (2026-07-12):** con titular +
      acompañante asignados, intentar el check-in del acompañante antes que
      el del titular fue rechazado tanto en la interfaz (sin botón de
      check-in visible para el acompañante) como en `checkin_post` vía POST
      directo (*"El titular de la habitación debe hacer check-in
      primero."*). Verificado visualmente con Playwright: sin el titular
      registrado, la fila del acompañante muestra el aviso en vez de un
      control; tras el check-in del titular, la tabla se ve limpia (se
      corrigió de paso un bug visual: el formulario del titular desbordaba
      la fila por falta de la clase `inline-form`, y el aviso de espera
      usaba por error el estilo de bloque `empty-state`).
- [x] **Habitación única por alojamiento activo + "alojamientos activos"
      rediseñado (UC-04b bis/UC-04d, 2026-07-12):** con un alojamiento
      `ACTIVO` ya creado para una habitación, un `INSERT` directo de un
      segundo alojamiento `ACTIVO` en la misma habitación (saltándose
      `sp_realizar_checkin`) fue rechazado por el nuevo trigger
      `trg_alojamiento_habitacion_unica` con *"Esta habitación ya tiene un
      alojamiento activo."*. `GET /estadia/activos` mostró una sola fila
      para ese alojamiento (antes una por huésped) con ambos huéspedes en
      la columna "Huéspedes" (titular primero, marcado "(titular)"),
      columnas Habitación/Tipo/Check-in/Huéspedes/Cliente pagador/botón
      "Ver alojamiento →". Verificado con `test_client` contra `hotel_db`
      real, con limpieza posterior de la reserva/alojamiento de prueba.
      **Nota (bug pre-existente, corregido el 2026-07-13 — ver más abajo):**
      al buscar huéspedes libres para la prueba se detectó que
      `sp_agregar_huesped_alojamiento` consideraba "activo en otro
      alojamiento" a un huésped que ya había hecho checkout individual
      (`fecha_salida_real` no nula) pero cuyo compañero de habitación
      todavía no se había retirado (el `alojamiento` seguía `ACTIVO` en
      conjunto) — el chequeo no filtraba por `fecha_salida_real IS NULL`.
- [x] **Eliminación de la tabla `huesped` — "huésped" pasa a ser un rol
      puro sobre `persona_natural`, sin tabla propia (UC-03/UC-04b,
      2026-07-12):** `detalle_huesped_reserva.id_huesped` y
      `huesped_alojamiento.id_huesped` ahora referencian directo a
      `persona_natural.id_persona` (FK repuntada, mismo nombre de
      columna). Se migró en vivo contra `hotel_db` real (`detalle_huesped_
      reserva`/`huesped_alojamiento` estaban en 0 filas por el borrado
      previo, así que no hubo datos que trasladar) y se actualizaron las 4
      vistas que hacían `JOIN huesped` (`vw_alojamientos_activos`,
      `vw_historial_estadias`, `vw_reservas_corporativas`,
      `vw_preasignacion_vs_checkin`) para saltar el hop intermedio.
      Verificado con `test_client`: (1) un cliente natural nuevo aparece
      YA MISMO en el selector de `preasignar.html`, sin ningún paso
      adicional (el problema original de esta sesión — "cuando creo un
      cliente no aparece como huésped" — queda resuelto de raíz, no con un
      parche); (2) "+ Huésped nuevo" (`crear_huesped_desde_formulario`)
      sigue funcionando igual; (3) el flujo completo reserva → pago →
      asignación → check-in → `vw_alojamientos_activos` →
      `vw_historial_estadias` funciona de punta a punta; (4) **el bug real
      de doble ocupación** (misma persona con dos filas de huésped
      distintas podía terminar en dos alojamientos activos a la vez, ver
      nota de la fila anterior) queda estructuralmente cerrado: se
      confirmó que un segundo check-in de la misma persona mientras sigue
      activa en otra habitación es rechazado por
      `sp_agregar_huesped_alojamiento`, ya que ahora solo puede existir un
      identificador por persona. Sin datos residuales tras la prueba.
      **Pendiente:** los diagramas `Diagramas/Diagrama de Base de Datos/
      01_Modelo_Conceptual.puml`/`02_Modelo_Logico.puml`/
      `03_Modelo_Fisico.puml` (y sus PNG) todavía muestran `huesped` como
      entidad separada — no se regeneraron en este incremento.
- [x] **Cancelar/no-show y bloqueo de estados finales (UC-01b/UC-04c,
      2026-07-12):** con una reserva `PENDIENTE`, Recepción canceló desde
      `detalle.html` (botón con diálogo de confirmación) y el estado pasó a
      `CANCELADA`; sobre esa misma reserva, `agregar_detalle`,
      `confirmar_pago`, `guardar_asignacion_linea` y `sp_realizar_checkin`
      fueron todos rechazados con el mensaje "La reserva está en un estado
      final...", y `detalle.html`/`preasignar.html`/`checkin_reserva.html`
      dejaron de mostrar sus formularios (solo un aviso). Marcar no-show
      funcionó con una reserva cuya `fecha_checkin` ya pasó y sin ningún
      check-in real; se rechazó si la fecha de check-in todavía no llegaba,
      y también se rechazó cancelar una reserva con huéspedes actualmente
      alojados (`alojamiento.estado = 'ACTIVO'`). Se verificó además que el
      trigger `trg_reserva_finalizar` pasa la reserva a `FINALIZADA`
      automáticamente en cuanto el checkout deja sin ningún alojamiento
      activo para esa reserva (probado con `sp_registrar_salida_huesped`
      sobre el único huésped). Verificado con `test_client` contra
      `hotel_db` real (con limpieza posterior de todas las reservas de
      prueba) y visualmente con Playwright (botones, diálogo de
      confirmación y mensaje final). De paso se quitó el breadcrumb/stepper
      de `reservas/detalle.html` (a pedido del usuario), que ya no
      recibía `pasos` desde `_contexto_detalle`.
- [x] **Stepper visual retirado de todas las vistas (2026-07-12):** ya no
      quedaba ningún caller de `construir_pasos_reserva` (se eliminó del
      código junto con el modo "stepper" de la macro `breadcrumb` y su CSS
      `.stepper`/`.step*`), así que `pago.html`, `preasignar.html` y
      `checkin_reserva.html` quedan sin ningún breadcrumb, igual que ya
      pasaba en `reservas/detalle.html`. Verificado con `test_client`: las
      tres pantallas responden 200 sin ningún rastro de "stepper" ni
      "breadcrumb" en el HTML; las pantallas que sí usan el breadcrumb de
      texto plano (`reservas/nuevo.html`, `caja/cuentas.html`) lo siguen
      mostrando sin cambios.
- [x] **Pago bloqueado por completo para Recepción (UC-02, 2026-07-12):**
      antes Recepción solo no veía el botón "Confirmar pago" dentro de
      `/reservas/<id>/pago` (podía igual entrar a la URL en modo lectura).
      Ahora, con una reserva sin pagar: en `detalle.html` ya no aparece
      ningún link hacia `/pago` (se reemplazó por un aviso de solo texto);
      el paso "Pago" del stepper se muestra sin link para Recepción; y
      entrar directo por URL (`GET` o `POST /reservas/<id>/pago`) redirige
      sin mostrar la pantalla, vía `requiere_rol("CAJA", "ADMINISTRADOR")`
      a nivel de ruta. Caja no se vio afectada: sigue viendo el link, la
      pantalla completa y el formulario de confirmación. Verificado con
      `test_client` contra `hotel_db` real.
- [x] **Listado de check-in como tabla plana buscable (2026-07-12):**
      `GET /estadia/checkin` ahora muestra una fila por habitación pendiente
      (no por reserva), con el titular, su documento y la reserva/reservante
      a la que pertenece; buscar "García" encontró tanto la fila cuyo
      titular se apellida García como la de un reservante con ese apellido.
      Cada fila con titular enlaza a `estadia/checkin/<id_reserva>#hab_...` y
      la página llega con esa habitación resaltada (`:target`, contorno
      dorado) gracias al ancla `id="hab_{id_detalle_reserva}_{n}"`; las
      filas sin titular enlazan en cambio a la asignación de huéspedes
      ("Falta titular →"). Verificado visualmente con Playwright.
- [x] **Alta de huéspedes retirada de estadía (2026-07-12):** `ver.html`
      (alojamiento activo) ya no muestra "Agregar huésped existente" ni
      "+ Huésped nuevo"; las rutas `POST /estadia/<id>/huespedes` y
      `POST /estadia/huesped/nuevo` fueron eliminadas.
- [x] **Un huésped no puede estar en dos estadías activas
      (UC-04b, 2026-07-12):** intentar hacer check-in de un huésped ya
      activo en otro alojamiento fue rechazado por
      `sp_agregar_huesped_alojamiento` con *"Este huésped ya está activo en
      otro alojamiento."*, revirtiendo también el `alojamiento` recién
      creado en la misma transacción (sin fila huérfana).
- [x] **Registro de personas en ventana flotante (2026-07-12):** los
      formularios de cliente nuevo y huésped nuevo abren como `<dialog>`
      (antes `<details>`) en `reservas/nuevo.html`, `reservas/preasignar.html`
      y `estadia/ver.html`; el submit real (creación de huésped) siguió
      funcionando igual.
- [x] **Consumo y daño (UC-05/06):** `sp_registrar_consumo` (2× desayuno =
      S/50) y `sp_registrar_danio` (S/45) quedaron reflejados en
      `vw_consumos_alojamiento` / el detalle del alojamiento.
- [x] **Salida individual (UC-07):** `sp_registrar_salida_huesped` con el
      único huésped finalizó automáticamente el alojamiento y el trigger
      `trg_alojamiento_checkout` puso la habitación en LIMPIEZA.
- [x] **Cuenta por cobrar (UC-09):** `sp_generar_cuenta_cobrar` calculó
      subtotal 95.00 + IGV 18% (17.10) = total 112.10, con detalle línea
      por línea (consumo + daño).
- [x] **No se genera cuenta sin gastos pendientes (2026-07-13):** de paso se
      encontró y limpió un residuo real de pruebas anteriores: el
      alojamiento #36 tenía una `cuenta_cobrar` en S/ 0.00 (sin detalle) de
      una sesión previa. Aplicado el `SIGNAL` nuevo en
      `sp_generar_cuenta_cobrar` (rechaza si `consumo_servicio` + `danio
      PENDIENTE` suman 0) contra `hotel_db` real: llamar al SP para ese
      mismo alojamiento (ya sin la cuenta vieja, sin consumos ni daños)
      dio *"Este alojamiento no tiene consumos ni daños pendientes; no hay
      nada que cobrar."*; insertando un consumo de prueba (Servicio de
      cuarto, S/25.00) el mismo alojamiento generó la cuenta correctamente
      (subtotal 25.00 + IGV 4.50 = total 29.50). `GET /caja/generar-cuenta`
      (`grojas`, CAJA hotel 1) ya no listó el alojamiento #36 como
      candidato mientras no tuvo gastos, y mostró el estado vacío
      actualizado. Datos de prueba (consumo + cuenta) borrados al terminar,
      dejando el alojamiento #36 finalizado y sin cuenta (su estado real).
- [x] **Corrección del bug de `fecha_salida_real` en
      `sp_agregar_huesped_alojamiento` (2026-07-13):** reproducido de punta
      a punta contra `hotel_db` real con el flujo de reserva completo (no
      solo el SP aislado): reserva A → check-in de persona 1 (titular) +
      persona 2 (acompañante) en hab. 202 (Doble) → salida individual de
      persona 1 (`sp_registrar_salida_huesped`, alojamiento sigue `ACTIVO`
      por persona 2) → reserva B → check-in de persona 1 en hab. 101 (otra
      habitación). Antes del fix esto fallaba con *"Este huésped ya está
      activo en otro alojamiento."*; con el `AND ha.fecha_salida_real IS
      NULL` agregado al `EXISTS` del SP, el segundo check-in de persona 1
      funcionó correctamente. Se verificó además que la protección real
      sigue intacta: una reserva C con persona 5 de titular en hab. 203
      (Doble) y un intento de agregar ahí a persona 2 —que sigue
      *genuinamente* activa en la hab. 202, sin salida registrada— fue
      rechazado con el mismo mensaje, como corresponde. Los 3
      reserva/alojamiento de prueba y sus `huesped_alojamiento` se
      borraron al terminar y las 3 habitaciones usadas volvieron a
      `DISPONIBLE`.
- [x] **Pago de cuenta (UC-10):** pago parcial de 50.00 dejó saldo 62.10
      (estado PENDIENTE); intento de pagar 999.00 mostró el SIGNAL *"El
      monto del pago excede el saldo pendiente"*; pago final de 62.10 dejó
      saldo 0.00 y estado PAGADA (trigger `trg_cuenta_actualizar_saldo`).
- [x] **Reportes de gerencia (UC-12):** `vw_ocupacion_hotel`,
      `vw_ingresos_por_hotel`, `vw_ranking_clientes` y
      `sp_resumen_ocupacion_hotel(1)` reflejaron los datos correctamente.
- [x] **Administración (UC-13):** alta de un nuevo servicio (SPA — Masaje
      relajante) vía INSERT directo, visible de inmediato en el listado.
- [x] **Alta de usuarios por el administrador (UC-13, 2026-07-12):** con
      `lparedes` (administrador general) en `/admin/usuarios?id_hotel=1`, se
      dio login RECEPCION a un empleado sin usuario (`jsoto`) — quedó con
      `id_hotel=1` (igual al de su empleado, por el trigger de alcance) y
      pudo loguearse de inmediato. Luego, sobre el hotel 2, se creó un
      ADMINISTRADOR acotado a ese hotel (`cmendoza`, sin marcar "administrador
      general") — quedó con `id_hotel=2`, no `NULL`. Al loguearse como
      `cmendoza`, `/admin/usuarios` se mostró fijo a su propio hotel, sin
      selector de hotel ni la sección "Administradores generales" (esa
      sección, y la fila del propio `lparedes`, solo las ve el administrador
      general). Una sesión GERENCIA (`rhuanca`) intentando `GET
      /admin/usuarios` fue redirigida, igual que con el resto de rutas de
      `/admin`. Verificado end-to-end con Playwright contra `hotel_db` real
      (capturas de pantalla revisadas); usuarios de prueba borrados al
      terminar.
- [x] **Recepción ve y cambia el estado de habitaciones de su hotel
      (2026-07-12):** con `mtorres` (RECEPCION, hotel 1), el link de nav
      "Habitaciones" apunta a `/habitaciones` (no `/admin/habitaciones`,
      mismo `view_func` registrado dos veces vía `app.add_url_rule`); la
      pantalla llega fija al propio hotel, sin selector de hotel y sin el
      formulario "Nueva habitación" (`puede_crear = rol == 'ADMINISTRADOR'`).
      Cambiar la habitación 101 de `LIMPIEZA` a `DISPONIBLE` funcionó y
      quedó reflejado de inmediato en la tabla. Una sesión CAJA (`grojas`)
      pidiendo `GET /admin/habitaciones` siguió bloqueada, sin cambios.
      Se corrigieron además las transiciones manuales de
      `sp_cambiar_estado_habitacion` (ver `Scripts/04_Procedimientos.sql`,
      aplicado en vivo contra `hotel_db`): rechaza poner `OCUPADA` a mano y
      rechaza tocar una habitación que ya está `OCUPADA` (con
      *"El estado OCUPADA solo lo controla el check-in/checkout; no se
      puede cambiar a mano."*, probado forzando el estado por UPDATE
      directo y confirmando el rechazo), rechaza "cambiar" al mismo estado
      (*"La habitación ya está en ese estado."*), y sigue permitiendo
      `DISPONIBLE ⇄ LIMPIEZA ⇄ RESERVADA` en cualquier combinación. El
      `<option>` `OCUPADA` se quitó del `<select>` del formulario y las
      habitaciones `OCUPADA` ya no muestran el formulario de cambio (solo
      un aviso de que se libera sola al hacer checkout). Verificado con
      Playwright y con llamadas directas al SP contra `hotel_db` real; la
      habitación de prueba quedó en su estado original al terminar.
- [x] **Control de acceso por rol:** una sesión GERENCIA intentando entrar a
      `/admin/hoteles` fue redirigida a `/login` con mensaje de permiso
      denegado.
- [x] **Edición completa de catálogos (UC-13, 2026-07-13):** se agregó un
      diálogo "Editar" por fila (mismo patrón `<dialog>` que cliente/huésped
      nuevo) a `hoteles` (el endpoint `hotel_editar` ya existía en el
      backend desde antes pero sin ningún botón en la pantalla que lo
      invocara — quedó conectado), `tipos-habitacion`, `categorias-servicio`,
      `servicios`, `planes-tarifa`, `tarifas` y `empleados`. Probado
      end-to-end con Playwright como `lparedes` (administrador general),
      editando y revirtiendo un valor real en cada pantalla contra
      `hotel_db`: teléfono de Hotel San Marcos Arequipa, descripción del
      tipo "Familiar", nombre de la categoría ESTACIONAMIENTO, activo del
      servicio "Servicio de cuarto (cena)" (con badge Sí/No cambiando en la
      tabla), activo del plan "Tarifa Corporativa ABC", precio de la
      tarifa Regular/Matrimonial (250.00 → 999.00 → 250.00), y activo del
      empleado Roberto Huanca Flores. También se probó que editar una
      tarifa para que choque con una combinación plan+tipo ya existente es
      rechazada con el mensaje amigable *"Ya existe una tarifa para ese
      plan y tipo de habitación."* (nueva entrada `uq_tarifa_plan_tipo` en
      `app/errors.py`, junto con 3 restricciones CHECK nuevas:
      `chk_capacidad_base`, `chk_tarifa_precio`, `chk_plan_fechas`, que ya
      existían en el schema pero no tenían mensaje traducido). No se
      agregó columna `activo` a `tipo_habitacion`, `categoria_servicio` ni
      `tarifa_habitacion` (no la tienen en el schema y no se justificaba
      un cambio de schema solo para esto): esas tres solo son editables,
      sin botón de baja. Verificado que la base quedó exactamente en su
      estado original al terminar (todas las filas de prueba comparadas
      antes/después).
- [x] **"Agregar línea" como ventana flotante (UC-01, 2026-07-13):**
      `reservas/detalle.html` reemplazó el formulario fijo bajo "Agregar
      línea" por un botón "+ Agregar línea" que abre un `<dialog>` (mismo
      patrón que "Cliente nuevo"/"Huésped nuevo"). Probado con Playwright
      contra una reserva `PENDIENTE` sin pagar creada para la prueba: el
      diálogo abre vacío, se completó y envió una línea real (Simple, 1
      habitación) que quedó reflejada en la tabla con el flash de éxito;
      un segundo intento con una cantidad exagerada (99 habitaciones) fue
      rechazado por `fn_disponibilidad_tipo_habitacion` vía
      `sp_agregar_detalle_reserva` con *"No hay disponibilidad suficiente
      de ese tipo de habitación en las fechas solicitadas"*, y el diálogo
      se reabrió solo (`data-autoopen`) con la cantidad "99" todavía
      tecleada en el campo, igual que ya pasaba con cliente/huésped nuevo.
      La reserva de prueba se borró al terminar.

## Cómo volver a correr esta verificación

1. `cd mvp_app`, activar el venv, `python run.py`.
2. Repetir los pasos anteriores desde el navegador (o con `curl` + cookie
   jar por rol, como se hizo en esta sesión) contra `http://127.0.0.1:5000`.
3. Usar IDs reales de `hotel_db` (clientes, empleados, habitaciones
   DISPONIBLES) — se pueden consultar con `SELECT` directos si hace falta.
