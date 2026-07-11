from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.auth.routes import requiere_rol
from app.constants import CANALES
from app.db import call_procedure, execute, execute_transaction, query
from app.errors import ejecutar_con_flash
from app.huespedes import crear_huesped_desde_formulario

bp = Blueprint("reservas", __name__, url_prefix="/reservas", template_folder="templates")


def _reserva_de_mi_hotel(id_reserva):
    """Defensa en profundidad: además de filtrar los listados, verifica que
    un id_reserva recibido por URL/formulario pertenezca al hotel de la
    sesión antes de mostrarlo o de operar sobre él."""
    return bool(
        query("SELECT 1 FROM reserva WHERE id_reserva = %s AND id_hotel = %s", (id_reserva, session["id_hotel"]))
    )


@bp.route("/")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def listado():
    solo_pendientes = request.args.get("pagado") == "0"
    if solo_pendientes:
        filas = query(
            "SELECT * FROM vw_reservas_detalle WHERE pagado = 0 AND hotel = %s ORDER BY fecha_limite_pago",
            (session["nombre_hotel"],),
        )
    else:
        filas = query(
            "SELECT * FROM vw_reservas_detalle WHERE hotel = %s ORDER BY id_reserva DESC",
            (session["nombre_hotel"],),
        )
    return render_template("reservas/listado.html", reservas=filas, solo_pendientes=solo_pendientes)


@bp.route("/corporativas")
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def corporativas():
    # vw_reservas_corporativas no expone hotel; se resuelve el conjunto de
    # id_reserva del hotel de la sesión aparte y se filtra en Python.
    ids_de_mi_hotel = {
        f["id_reserva"] for f in query("SELECT id_reserva FROM reserva WHERE id_hotel = %s", (session["id_hotel"],))
    }
    filas = [
        f
        for f in query("SELECT * FROM vw_reservas_corporativas ORDER BY id_reserva")
        if f["id_reserva"] in ids_de_mi_hotel
    ]
    return render_template("reservas/corporativas.html", filas=filas)


def _pasos_reserva(id_reserva, tipo_persona, actual):
    """Breadcrumb dinámico de los pasos del flujo de reserva. 'Pre-asignación'
    solo aparece si la reserva es corporativa (persona jurídica)."""
    pasos = [
        {"label": "Reservas", "url": url_for("reservas.listado")},
        {"label": "Cabecera", "url": None},
        {"label": "Detalle", "url": None if actual == "detalle" else url_for("reservas.detalle", id_reserva=id_reserva)},
        {"label": "Pago", "url": None if actual == "pago" else url_for("reservas.pago", id_reserva=id_reserva)},
    ]
    if tipo_persona == "JURIDICA":
        pasos.append(
            {"label": "Pre-asignación", "url": None if actual == "preasignar" else url_for("reservas.preasignar", id_reserva=id_reserva)}
        )
    return pasos


def _contexto_nuevo():
    return {
        "clientes": query(
            "SELECT id_cliente, nombre_reservante, tipo_persona, documento FROM vw_reservante ORDER BY nombre_reservante"
        ),
        "tipos_documento": query("SELECT id_tipo_documento, nombre FROM tipo_documento ORDER BY nombre"),
        "canales": CANALES,
    }


@bp.route("/nuevo", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def nuevo():
    return render_template("reservas/nuevo.html", **_contexto_nuevo())


def _draft_reserva_desde_form(form):
    """Cabecera de reserva ya tecleada por el recepcionista (campos draft_*
    del formulario 'crear cliente'), para no perderla si el flujo se desvía
    a crear un cliente nuevo a mitad de camino."""
    return {
        "canal": form.get("draft_canal") or "",
        "fecha_checkin": form.get("draft_fecha_checkin") or "",
        "fecha_checkout": form.get("draft_fecha_checkout") or "",
        "fecha_limite_pago": form.get("draft_fecha_limite_pago") or "",
        "id_cliente_contacto": form.get("draft_id_cliente_contacto") or "",
        "observaciones": form.get("draft_observaciones") or "",
    }


@bp.route("/cliente/nuevo", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def cliente_nuevo():
    tipo = request.form["tipo"]
    telefono = request.form.get("telefono") or None
    email = request.form.get("email") or None
    draft_reserva = _draft_reserva_desde_form(request.form)

    if tipo == "NATURAL":
        ids = execute_transaction(
            [("INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', %s, %s)", (telefono, email))]
        )
        id_persona = ids[0]
        ok, lastrowids = ejecutar_con_flash(
            execute_transaction,
            [
                (
                    "INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, genero, nacionalidad) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (
                        id_persona,
                        request.form["id_tipo_documento"],
                        request.form["numero_documento"],
                        request.form["nombres"],
                        request.form["apellidos"],
                        request.form["fecha_nacimiento"],
                        request.form["genero"],
                        request.form["nacionalidad"],
                    ),
                ),
                ("INSERT INTO cliente (id_persona, observaciones) VALUES (%s, %s)", (id_persona, request.form.get("observaciones") or None)),
            ],
            on_success_msg="Cliente natural creado correctamente. Continúa completando la reserva.",
        )
    else:
        ids = execute_transaction(
            [("INSERT INTO persona (tipo, telefono, email) VALUES ('JURIDICA', %s, %s)", (telefono, email))]
        )
        id_persona = ids[0]
        ok, lastrowids = ejecutar_con_flash(
            execute_transaction,
            [
                (
                    "INSERT INTO persona_juridica (id_persona, ruc, razon_social, nombre_comercial, representante_legal, giro_negocio) "
                    "VALUES (%s, %s, %s, %s, %s, %s)",
                    (
                        id_persona,
                        request.form["ruc"],
                        request.form["razon_social"],
                        request.form.get("nombre_comercial") or None,
                        request.form["representante_legal"],
                        request.form.get("giro_negocio") or None,
                    ),
                ),
                ("INSERT INTO cliente (id_persona, observaciones) VALUES (%s, %s)", (id_persona, request.form.get("observaciones") or None)),
            ],
            on_success_msg="Cliente jurídico (empresa) creado correctamente. Continúa completando la reserva.",
        )

    if not ok:
        return render_template(
            "reservas/nuevo.html",
            seleccion_cliente=request.form,
            seleccion_reserva=draft_reserva,
            **_contexto_nuevo(),
        )

    id_cliente_nuevo = lastrowids[1]
    return render_template(
        "reservas/nuevo.html",
        seleccion_reserva={**draft_reserva, "id_cliente": id_cliente_nuevo},
        **_contexto_nuevo(),
    )


@bp.route("/nuevo", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def crear():
    id_cliente = request.form["id_cliente"]
    id_hotel = session["id_hotel"]
    id_cliente_contacto = request.form.get("id_cliente_contacto") or None
    canal = request.form["canal"]
    fecha_checkin = request.form["fecha_checkin"]
    fecha_checkout = request.form["fecha_checkout"]
    fecha_limite_pago = request.form["fecha_limite_pago"]
    observaciones = request.form.get("observaciones") or None

    ok, data = ejecutar_con_flash(
        call_procedure,
        "sp_registrar_reserva",
        (
            id_cliente, id_hotel, session["id_empleado"], id_cliente_contacto,
            canal, fecha_checkin, fecha_checkout, fecha_limite_pago, observaciones, 0,
        ),
        on_success_msg="Reserva creada. Ahora agrega las líneas de detalle.",
    )
    if not ok:
        return render_template(
            "reservas/nuevo.html", seleccion_reserva=request.form, **_contexto_nuevo()
        )

    _, out_values = data
    id_reserva = out_values[9]
    return redirect(url_for("reservas.detalle", id_reserva=id_reserva))


def _contexto_detalle(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        return None
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        return None

    lineas = query(
        """
        SELECT rd.id_detalle_reserva, th.nombre AS tipo_habitacion, pt.nombre AS plan,
               rd.cantidad_habitaciones, rd.precio_unitario, rd.subtotal
        FROM reserva_detalle rd
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
        JOIN plan_tarifa pt ON pt.id_plan = rd.id_plan
        WHERE rd.id_reserva = %s
        """,
        (id_reserva,),
    )
    return {
        "reserva": reserva[0],
        "lineas": lineas,
        "tipos": query("SELECT id_tipo_habitacion, nombre FROM tipo_habitacion ORDER BY nombre"),
        "planes": query("SELECT id_plan, nombre, es_publico FROM plan_tarifa WHERE activo = 1 ORDER BY nombre"),
        "pasos": _pasos_reserva(id_reserva, reserva[0]["tipo_persona"], "detalle"),
    }


@bp.route("/<int:id_reserva>/detalle", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def detalle(id_reserva):
    contexto = _contexto_detalle(id_reserva)
    if contexto is None:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    return render_template("reservas/detalle.html", **contexto)


@bp.route("/<int:id_reserva>/detalle", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def agregar_detalle(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    id_tipo_habitacion = request.form["id_tipo_habitacion"]
    id_plan = request.form.get("id_plan") or None
    cantidad = request.form["cantidad_habitaciones"]

    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_agregar_detalle_reserva",
        (id_reserva, id_tipo_habitacion, id_plan, cantidad),
        on_success_msg="Línea de detalle agregada. Agrega otra o continúa a confirmación de pago.",
    )
    if not ok:
        contexto = _contexto_detalle(id_reserva)
        if contexto is None:
            return redirect(url_for("reservas.listado"))
        return render_template("reservas/detalle.html", seleccion=request.form, **contexto)
    return redirect(url_for("reservas.detalle", id_reserva=id_reserva))


@bp.route("/<int:id_reserva>/pago", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def pago(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    pasos = _pasos_reserva(id_reserva, reserva[0]["tipo_persona"], "pago")
    return render_template("reservas/pago.html", reserva=reserva[0], pasos=pasos)


@bp.route("/<int:id_reserva>/pago", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def confirmar_pago(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    ejecutar_con_flash(
        call_procedure,
        "sp_confirmar_pago",
        (id_reserva,),
        on_success_msg="Pago confirmado. La reserva pasó a CONFIRMADA.",
    )
    return redirect(url_for("reservas.pago", id_reserva=id_reserva))


def _contexto_preasignar(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        return None
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        return None

    lineas = query(
        """
        SELECT rd.id_detalle_reserva, th.nombre AS tipo_habitacion, rd.cantidad_habitaciones
        FROM reserva_detalle rd
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
        WHERE rd.id_reserva = %s
        """,
        (id_reserva,),
    )
    huespedes = query(
        "SELECT id_huesped, nombres, apellidos, es_generico FROM huesped WHERE activo = 1 ORDER BY nombres"
    )
    preasignados = query(
        """
        SELECT dhr.id_detalle_huesped, dhr.id_detalle_reserva,
               CONCAT(h.nombres, ' ', COALESCE(h.apellidos, '')) AS huesped, dhr.es_titular
        FROM detalle_huesped_reserva dhr
        JOIN reserva_detalle rd ON rd.id_detalle_reserva = dhr.id_detalle_reserva
        JOIN huesped h ON h.id_huesped = dhr.id_huesped
        WHERE rd.id_reserva = %s
        """,
        (id_reserva,),
    )
    return {
        "reserva": reserva[0],
        "lineas": lineas,
        "huespedes": huespedes,
        "preasignados": preasignados,
        "tipos_documento": query("SELECT id_tipo_documento, nombre FROM tipo_documento ORDER BY nombre"),
        "pasos": _pasos_reserva(id_reserva, reserva[0]["tipo_persona"], "preasignar"),
    }


@bp.route("/<int:id_reserva>/preasignar", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def preasignar(id_reserva):
    contexto = _contexto_preasignar(id_reserva)
    if contexto is None:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    return render_template("reservas/preasignar.html", **contexto)


@bp.route("/<int:id_reserva>/preasignar", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def preasignar_post(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    id_detalle_reserva = request.form["id_detalle_reserva"]
    id_huesped = request.form["id_huesped"]
    es_titular = 1 if request.form.get("es_titular") else 0

    ok, _ = ejecutar_con_flash(
        execute,
        "INSERT INTO detalle_huesped_reserva (id_detalle_reserva, id_huesped, es_titular) VALUES (%s, %s, %s)",
        (id_detalle_reserva, id_huesped, es_titular),
        on_success_msg="Huésped pre-asignado. Agrega otro o vuelve al detalle cuando termines.",
    )
    if not ok:
        contexto = _contexto_preasignar(id_reserva)
        if contexto is None:
            return redirect(url_for("reservas.listado"))
        return render_template("reservas/preasignar.html", seleccion=request.form, **contexto)
    return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))


@bp.route("/huesped/nuevo", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def huesped_nuevo():
    id_reserva = request.form["id_reserva"]
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    ok, _ = crear_huesped_desde_formulario(request.form)
    if not ok:
        contexto = _contexto_preasignar(id_reserva)
        if contexto is None:
            return redirect(url_for("reservas.listado"))
        return render_template("reservas/preasignar.html", seleccion_huesped=request.form, **contexto)
    return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))
