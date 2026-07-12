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
de pago (antes solo se ocultaba el botón), y una octava tras agregar
cancelar/no-show de reserva y el bloqueo general de estados finales (ver
commits de esa fecha). Marcar
de nuevo tras cambios importantes.

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
- [x] **Pago de cuenta (UC-10):** pago parcial de 50.00 dejó saldo 62.10
      (estado PENDIENTE); intento de pagar 999.00 mostró el SIGNAL *"El
      monto del pago excede el saldo pendiente"*; pago final de 62.10 dejó
      saldo 0.00 y estado PAGADA (trigger `trg_cuenta_actualizar_saldo`).
- [x] **Reportes de gerencia (UC-12):** `vw_ocupacion_hotel`,
      `vw_ingresos_por_hotel`, `vw_ranking_clientes` y
      `sp_resumen_ocupacion_hotel(1)` reflejaron los datos correctamente.
- [x] **Administración (UC-13):** alta de un nuevo servicio (SPA — Masaje
      relajante) vía INSERT directo, visible de inmediato en el listado.
- [x] **Control de acceso por rol:** una sesión GERENCIA intentando entrar a
      `/admin/hoteles` fue redirigida a `/login` con mensaje de permiso
      denegado.

## Cómo volver a correr esta verificación

1. `cd mvp_app`, activar el venv, `python run.py`.
2. Repetir los pasos anteriores desde el navegador (o con `curl` + cookie
   jar por rol, como se hizo en esta sesión) contra `http://127.0.0.1:5000`.
3. Usar IDs reales de `hotel_db` (clientes, empleados, habitaciones
   DISPONIBLES) — se pueden consultar con `SELECT` directos si hace falta.
