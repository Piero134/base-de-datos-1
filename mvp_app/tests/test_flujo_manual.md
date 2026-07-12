# Checklist de verificación end-to-end — MVP Hotel

Replica el recorrido de `Diagramas/04_Flujo_MVP_Secuencia.puml`. Verificado
contra `hotel_db` real (MySQL) el 2026-07-06; los ítems de reservas/estadía se
re-verificaron el 2026-07-12 tras el rediseño de asignación de huéspedes por
tabla, y de nuevo el mismo día tras corregir el check-in a individual por
huésped (ver commits de esa fecha). Marcar de nuevo tras cambios importantes.

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
      + asignación de huésped, visible luego en `vw_reservas_corporativas`.
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
