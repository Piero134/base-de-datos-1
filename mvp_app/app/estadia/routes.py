from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.asignacion_huespedes import construir_grid_reserva, construir_pasos_reserva
from app.auth.routes import requiere_rol
from app.db import call_procedure, call_procedures_en_transaccion, query
from app.errors import ejecutar_con_flash
from app.huespedes import crear_huesped_desde_formulario

bp = Blueprint("estadia", __name__, url_prefix="/estadia", template_folder="templates")


def _reserva_de_mi_hotel(id_reserva):
    return bool(
        query("SELECT 1 FROM reserva WHERE id_reserva = %s AND id_hotel = %s", (id_reserva, session["id_hotel"]))
    )


def _alojamiento_de_mi_hotel(id_alojamiento):
    return bool(
        query(
            """
            SELECT 1 FROM alojamiento a
            JOIN habitacion h ON h.id_habitacion = a.id_habitacion
            WHERE a.id_alojamiento = %s AND h.id_hotel = %s
            """,
            (id_alojamiento, session["id_hotel"]),
        )
    )


@bp.route("/activos")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def activos():
    filas = query(
        "SELECT * FROM vw_alojamientos_activos WHERE hotel = %s ORDER BY hotel, habitacion",
        (session["nombre_hotel"],),
    )
    return render_template("estadia/activos.html", filas=filas)


@bp.route("/danios-pendientes")
@requiere_rol("RECEPCION", "CAJA", "ADMINISTRADOR")
def danios_pendientes():
    filas = query(
        "SELECT * FROM vw_danios_pendientes WHERE hotel = %s ORDER BY fecha_reporte",
        (session["nombre_hotel"],),
    )
    # vw_danios_pendientes no expone id_alojamiento; se resuelve aparte solo
    # para poder enlazar cada fila a la pantalla del alojamiento.
    id_alojamiento_por_danio = {
        d["id_danio"]: d["id_alojamiento"]
        for d in query(
            """
            SELECT d.id_danio, d.id_alojamiento
            FROM danio d
            JOIN alojamiento a ON a.id_alojamiento = d.id_alojamiento
            JOIN habitacion h ON h.id_habitacion = a.id_habitacion
            WHERE d.estado = 'PENDIENTE' AND h.id_hotel = %s
            """,
            (session["id_hotel"],),
        )
    }
    for f in filas:
        f["id_alojamiento"] = id_alojamiento_por_danio.get(f["id_danio"])
    return render_template("estadia/danios_pendientes.html", filas=filas)


@bp.route("/checkouts-pendientes")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def checkouts_pendientes():
    filas = query(
        "SELECT * FROM vw_checkouts_pendientes WHERE hotel = %s ORDER BY checkout_planificado",
        (session["nombre_hotel"],),
    )
    return render_template("estadia/checkouts_pendientes.html", filas=filas)


@bp.route("/historial")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def historial():
    id_huesped = request.args.get("id_huesped")
    if id_huesped:
        filas = query(
            "SELECT * FROM vw_historial_estadias WHERE hotel = %s AND id_huesped = %s ORDER BY fecha_checkin_real DESC",
            (session["nombre_hotel"], id_huesped),
        )
    else:
        filas = query(
            "SELECT * FROM vw_historial_estadias WHERE hotel = %s ORDER BY fecha_checkin_real DESC",
            (session["nombre_hotel"],),
        )
    return render_template("estadia/historial.html", filas=filas, id_huesped=id_huesped)


# ---------------------------------------------------------------------
# Check-in (UC-04)
# ---------------------------------------------------------------------
@bp.route("/checkin")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def checkin_listado():
    reservas = query(
        "SELECT * FROM vw_reservas_detalle WHERE estado = 'CONFIRMADA' AND hotel = %s ORDER BY fecha_checkin",
        (session["nombre_hotel"],),
    )
    return render_template("estadia/checkin_listado.html", reservas=reservas)


def _contexto_checkin_reserva(id_reserva):
    """Contexto de la pantalla de check-in: reusa la misma tabla de
    asignación de huéspedes de reservas (construir_grid_reserva), agrupada
    por habitación dentro de cada línea. El check-in se hace por habitación
    completa (no huésped por huésped): una habitación solo puede recibir
    check-in si ya tiene su titular asignado en la pantalla de reservas."""
    if not _reserva_de_mi_hotel(id_reserva):
        return None
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        return None

    lineas = construir_grid_reserva(id_reserva, con_estado_estadia=True)

    id_hotel = reserva[0]["hotel"]
    habitaciones_por_tipo = {}
    completo = bool(lineas)
    for linea in lineas:
        if any(not h["checkin_hecho"] for h in linea["habitaciones"]):
            completo = False
            # Disponibilidad por ocupación real (¿hay un alojamiento ACTIVO
            # en esa habitación ahora?), no por el campo cacheado
            # habitacion.estado — ver sp_realizar_checkin.
            habitaciones_por_tipo[linea["id_detalle_reserva"]] = query(
                """
                SELECT h.id_habitacion, h.numero, h.piso
                FROM habitacion h
                JOIN hotel ht ON ht.id_hotel = h.id_hotel
                WHERE ht.nombre = %s AND h.id_tipo_habitacion = %s
                  AND NOT EXISTS (
                      SELECT 1 FROM alojamiento a
                      WHERE a.id_habitacion = h.id_habitacion AND a.estado = 'ACTIVO'
                  )
                ORDER BY h.numero
                """,
                (id_hotel, linea["id_tipo_habitacion"]),
            )

    return {
        "reserva": reserva[0],
        "lineas": lineas,
        "habitaciones_por_tipo": habitaciones_por_tipo,
        "completo": completo,
        "pasos": construir_pasos_reserva(id_reserva, "checkin"),
    }


@bp.route("/checkin/<int:id_reserva>")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def checkin_reserva(id_reserva):
    contexto = _contexto_checkin_reserva(id_reserva)
    if contexto is None:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("estadia.checkin_listado"))
    return render_template("estadia/checkin_reserva.html", **contexto)


@bp.route("/checkin", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def checkin_post():
    id_reserva = request.form["id_reserva"]
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("estadia.checkin_listado"))
    id_detalle_reserva = int(request.form["id_detalle_reserva"])
    n_habitacion = int(request.form["n_habitacion"])
    id_habitacion = request.form["id_habitacion"]

    linea = next(
        (l for l in construir_grid_reserva(id_reserva, con_estado_estadia=True) if l["id_detalle_reserva"] == id_detalle_reserva),
        None,
    )
    hab = next((h for h in linea["habitaciones"] if h["n"] == n_habitacion), None) if linea else None
    if hab is None:
        flash("Habitación de la reserva no encontrada.", "danger")
        return redirect(url_for("estadia.checkin_reserva", id_reserva=id_reserva))
    if hab["checkin_hecho"]:
        flash("Esta habitación ya tiene check-in registrado.", "danger")
        return redirect(url_for("estadia.checkin_reserva", id_reserva=id_reserva))
    if not hab["tiene_titular"]:
        flash("Esta habitación todavía no tiene un titular asignado; complétalo en la asignación de huéspedes antes del check-in.", "danger")
        return redirect(url_for("estadia.checkin_reserva", id_reserva=id_reserva))

    huespedes_habitacion = [
        (slot["id_huesped"], slot["id_detalle_huesped"], 1 if slot["es_titular"] else 0)
        for slot in hab["slots"]
        if slot["id_huesped"]
    ]

    def orquestar(ejecutar):
        out_checkin = ejecutar(
            "sp_realizar_checkin",
            (id_reserva, id_detalle_reserva, id_habitacion, session["id_empleado"], 0),
        )
        id_alojamiento = out_checkin[-1]
        for id_huesped, id_detalle_huesped, es_titular in huespedes_habitacion:
            ejecutar("sp_agregar_huesped_alojamiento", (id_alojamiento, id_huesped, es_titular, id_detalle_huesped))
        return id_alojamiento

    ejecutar_con_flash(
        call_procedures_en_transaccion,
        orquestar,
        on_success_msg="Check-in registrado con todos los huéspedes de la habitación. Continúa con las habitaciones pendientes de esta reserva.",
    )
    return redirect(url_for("estadia.checkin_reserva", id_reserva=id_reserva))


# ---------------------------------------------------------------------
# Pantalla principal de un alojamiento activo: huéspedes, consumos,
# daños, salida individual y checkout (UC-05 a UC-08).
# ---------------------------------------------------------------------
def _contexto_ver(id_alojamiento):
    aloj = query(
        """
        SELECT a.id_alojamiento, a.estado, a.fecha_checkin_real, a.fecha_checkout_real,
               ht.nombre AS hotel, h.numero AS habitacion, h.piso, th.nombre AS tipo,
               th.capacidad_base
        FROM alojamiento a
        JOIN habitacion h ON h.id_habitacion = a.id_habitacion
        JOIN hotel ht ON ht.id_hotel = h.id_hotel
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
        WHERE a.id_alojamiento = %s AND ht.id_hotel = %s
        """,
        (id_alojamiento, session["id_hotel"]),
    )
    if not aloj:
        return None

    huespedes = query(
        """
        SELECT ha.id_huesped, CONCAT(pn.nombres, ' ', pn.apellidos) AS huesped,
               ha.es_titular, ha.fecha_registro, ha.fecha_salida_real
        FROM huesped_alojamiento ha
        JOIN huesped h ON h.id_huesped = ha.id_huesped
        JOIN persona_natural pn ON pn.id_persona = h.id_persona
        WHERE ha.id_alojamiento = %s
        ORDER BY ha.fecha_salida_real IS NOT NULL, ha.fecha_registro
        """,
        (id_alojamiento,),
    )
    return {
        "aloj": aloj[0],
        "huespedes": huespedes,
        "huespedes_disponibles": query(
            """
            SELECT h.id_huesped, pn.nombres, pn.apellidos
            FROM huesped h
            JOIN persona_natural pn ON pn.id_persona = h.id_persona
            WHERE h.activo = 1
              AND NOT EXISTS (
                  SELECT 1 FROM huesped_alojamiento ha
                  JOIN alojamiento a ON a.id_alojamiento = ha.id_alojamiento
                  WHERE ha.id_huesped = h.id_huesped AND a.estado = 'ACTIVO'
              )
            ORDER BY pn.nombres
            """
        ),
        "tipos_documento": query("SELECT id_tipo_documento, nombre FROM tipo_documento ORDER BY nombre"),
        "consumos": query(
            "SELECT * FROM vw_consumos_alojamiento WHERE id_alojamiento = %s ORDER BY fecha_consumo", (id_alojamiento,)
        ),
        "servicios": query(
            """
            SELECT s.id_servicio, s.nombre, cat.nombre AS categoria, s.precio_unitario
            FROM servicio s
            JOIN categoria_servicio cat ON cat.id_categoria = s.id_categoria
            WHERE s.activo = 1
            ORDER BY cat.nombre, s.nombre
            """
        ),
        "danios": query(
            "SELECT id_danio, descripcion, costo, fecha_reporte, estado FROM danio WHERE id_alojamiento = %s ORDER BY fecha_reporte",
            (id_alojamiento,),
        ),
    }


def _totales_ver(contexto):
    """Totales de consumos y daños pendientes, para mostrar un resumen antes
    de confirmar el checkout (en vez de un confirm() genérico sin cifras)."""
    total_consumos = sum(float(c["subtotal"]) for c in contexto["consumos"])
    total_danios = sum(float(d["costo"]) for d in contexto["danios"] if d["estado"] == "PENDIENTE")
    return total_consumos, total_danios


@bp.route("/<int:id_alojamiento>")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def ver(id_alojamiento):
    contexto = _contexto_ver(id_alojamiento)
    if contexto is None:
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    total_consumos, total_danios = _totales_ver(contexto)
    return render_template("estadia/ver.html", total_consumos=total_consumos, total_danios=total_danios, **contexto)


@bp.route("/<int:id_alojamiento>/huespedes", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def agregar_huesped(id_alojamiento):
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    id_huesped = request.form["id_huesped"]
    es_titular = 1 if request.form.get("es_titular") else 0

    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_agregar_huesped_alojamiento",
        (id_alojamiento, id_huesped, es_titular, None),
        on_success_msg="Huésped agregado al alojamiento.",
    )
    if not ok:
        contexto = _contexto_ver(id_alojamiento)
        if contexto is None:
            return redirect(url_for("estadia.activos"))
        total_consumos, total_danios = _totales_ver(contexto)
        return render_template("estadia/ver.html", total_consumos=total_consumos, total_danios=total_danios, **contexto)
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))


@bp.route("/huesped/nuevo", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def huesped_nuevo():
    id_alojamiento = request.form["id_alojamiento"]
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    ok, _ = crear_huesped_desde_formulario(request.form)
    if not ok:
        contexto = _contexto_ver(id_alojamiento)
        if contexto is None:
            return redirect(url_for("estadia.activos"))
        total_consumos, total_danios = _totales_ver(contexto)
        return render_template("estadia/ver.html", seleccion_huesped=request.form, total_consumos=total_consumos, total_danios=total_danios, **contexto)
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))


@bp.route("/<int:id_alojamiento>/consumo", methods=["POST"])
@requiere_rol("RECEPCION", "CAJA", "ADMINISTRADOR")
def registrar_consumo(id_alojamiento):
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    id_servicio = request.form["id_servicio"]
    cantidad = request.form["cantidad"]
    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_registrar_consumo",
        (id_alojamiento, id_servicio, cantidad),
        on_success_msg="Consumo registrado.",
    )
    if not ok:
        contexto = _contexto_ver(id_alojamiento)
        if contexto is None:
            return redirect(url_for("estadia.activos"))
        total_consumos, total_danios = _totales_ver(contexto)
        return render_template("estadia/ver.html", seleccion_consumo=request.form, total_consumos=total_consumos, total_danios=total_danios, **contexto)
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))


@bp.route("/<int:id_alojamiento>/danio", methods=["POST"])
@requiere_rol("RECEPCION", "CAJA", "ADMINISTRADOR")
def registrar_danio(id_alojamiento):
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    descripcion = request.form["descripcion"]
    costo = request.form["costo"]
    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_registrar_danio",
        (id_alojamiento, descripcion, costo),
        on_success_msg="Daño registrado.",
    )
    if not ok:
        contexto = _contexto_ver(id_alojamiento)
        if contexto is None:
            return redirect(url_for("estadia.activos"))
        total_consumos, total_danios = _totales_ver(contexto)
        return render_template("estadia/ver.html", seleccion_danio=request.form, total_consumos=total_consumos, total_danios=total_danios, **contexto)
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))


@bp.route("/<int:id_alojamiento>/salida-huesped", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def salida_huesped(id_alojamiento):
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    id_huesped = request.form["id_huesped"]
    ejecutar_con_flash(
        call_procedure,
        "sp_registrar_salida_huesped",
        (id_alojamiento, id_huesped, session["id_empleado"]),
        on_success_msg="Salida de huésped registrada.",
    )
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))


@bp.route("/<int:id_alojamiento>/checkout", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def checkout(id_alojamiento):
    if not _alojamiento_de_mi_hotel(id_alojamiento):
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("estadia.activos"))
    ejecutar_con_flash(
        call_procedure,
        "sp_realizar_checkout",
        (id_alojamiento, session["id_empleado"]),
        on_success_msg="Check-out realizado. La habitación pasó a LIMPIEZA.",
    )
    return redirect(url_for("estadia.ver", id_alojamiento=id_alojamiento))
