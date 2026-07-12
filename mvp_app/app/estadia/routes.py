from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.auth.routes import requiere_rol
from app.db import call_procedure, query
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
    """Contexto de la pantalla de check-in de una reserva. Cada línea puede
    pedir varias habitaciones (cantidad_habitaciones > 1) y una reserva puede
    tener varias líneas: por eso se calcula cuántas unidades de cada línea ya
    tienen alojamiento creado (asignadas) vs cuántas faltan (pendientes), en
    vez de asumir que un solo check-in cierra el flujo."""
    if not _reserva_de_mi_hotel(id_reserva):
        return None
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        return None

    lineas = query(
        """
        SELECT rd.id_detalle_reserva, rd.id_tipo_habitacion, th.nombre AS tipo_habitacion,
               rd.cantidad_habitaciones
        FROM reserva_detalle rd
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
        WHERE rd.id_reserva = %s
        """,
        (id_reserva,),
    )
    asignadas_por_linea = {}
    for a in query(
        """
        SELECT a.id_alojamiento, a.id_detalle_reserva, h.numero, h.piso
        FROM alojamiento a
        JOIN habitacion h ON h.id_habitacion = a.id_habitacion
        WHERE a.id_reserva = %s
        ORDER BY a.id_alojamiento
        """,
        (id_reserva,),
    ):
        asignadas_por_linea.setdefault(a["id_detalle_reserva"], []).append(a)

    id_hotel = reserva[0]["hotel"]
    habitaciones_por_tipo = {}
    for linea in lineas:
        linea["asignadas"] = asignadas_por_linea.get(linea["id_detalle_reserva"], [])
        linea["pendientes"] = linea["cantidad_habitaciones"] - len(linea["asignadas"])
        if linea["pendientes"] > 0:
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

    completo = bool(lineas) and all(l["pendientes"] <= 0 for l in lineas)
    return {
        "reserva": reserva[0],
        "lineas": lineas,
        "habitaciones_por_tipo": habitaciones_por_tipo,
        "completo": completo,
        "huespedes_disponibles": query(
            """
            SELECT h.id_huesped, pn.nombres, pn.apellidos
            FROM huesped h
            JOIN persona_natural pn ON pn.id_persona = h.id_persona
            WHERE h.activo = 1
            ORDER BY pn.nombres
            """
        ),
        "tipos_documento": query("SELECT id_tipo_documento, nombre FROM tipo_documento ORDER BY nombre"),
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
    id_detalle_reserva = request.form["id_detalle_reserva"]
    id_habitacion = request.form["id_habitacion"]
    origen_huesped = request.form.get("origen_huesped", "existente")

    if origen_huesped == "nuevo":
        ok_huesped, id_huesped = crear_huesped_desde_formulario(request.form)
        if not ok_huesped:
            contexto = _contexto_checkin_reserva(id_reserva)
            if contexto is None:
                return redirect(url_for("estadia.checkin_listado"))
            return render_template(
                "estadia/checkin_reserva.html",
                seleccion_huesped=request.form,
                draft_id_detalle_reserva=id_detalle_reserva,
                draft_id_habitacion=id_habitacion,
                draft_origen_huesped="nuevo",
                **contexto,
            )
    else:
        id_huesped = request.form.get("id_huesped")

    # Check-in y asociación del huésped quedan en un solo paso atómico: una
    # habitación nunca debe quedar ocupada sin ningún huésped registrado.
    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_realizar_checkin_con_huesped",
        (id_reserva, id_detalle_reserva, id_habitacion, session["id_empleado"], id_huesped, None, 0),
        on_success_msg="Check-in registrado con el huésped asociado. Continúa con las habitaciones pendientes de esta reserva.",
    )
    contexto = _contexto_checkin_reserva(id_reserva)
    if contexto is None:
        return redirect(url_for("estadia.checkin_listado"))
    if not ok:
        return render_template(
            "estadia/checkin_reserva.html",
            draft_id_detalle_reserva=id_detalle_reserva,
            draft_id_habitacion=id_habitacion,
            draft_origen_huesped=origen_huesped,
            seleccion_huesped=request.form if origen_huesped == "nuevo" else None,
            **contexto,
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
