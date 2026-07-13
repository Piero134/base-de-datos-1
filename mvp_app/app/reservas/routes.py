from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.auth.routes import requiere_rol
from app.constants import CANALES, ESTADOS_RESERVA, ESTADOS_RESERVA_TERMINALES
from app.asignacion_huespedes import construir_grid_reserva
from app.db import call_procedure, execute_transaction, query
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


def _query_reservas(condiciones, parametros, orden):
    # vw_reservas_detalle no expone tipo_persona/documento del reservante
    # (solo vw_reservante los tiene), así que en vez de tocar la vista se
    # arma aquí el mismo resultado uniendo reserva + vw_reservante + hotel
    # directamente -- una sola query reusada tanto para Caja (fija) como
    # para Recepción/Administrador (con filtros).
    return query(
        f"""
        SELECT r.id_reserva, v.nombre_reservante, v.tipo_persona, v.documento, ht.nombre AS hotel,
               r.estado, r.canal, r.fecha_checkin, r.fecha_checkout,
               fn_calcular_noches(r.fecha_checkin, r.fecha_checkout) AS noches,
               r.monto_total, r.pagado, r.fecha_pago, r.fecha_limite_pago
        FROM reserva r
        JOIN vw_reservante v ON v.id_cliente = r.id_cliente
        JOIN hotel ht ON ht.id_hotel = r.id_hotel
        WHERE {' AND '.join(condiciones)}
        ORDER BY {orden}
        """,
        tuple(parametros),
    )


@bp.route("/")
@requiere_rol("RECEPCION", "CAJA", "ADMINISTRADOR")
def listado():
    if session["rol"] == "CAJA":
        # Caja solo confirma pagos: siempre pendientes de pago, sin filtros
        # (a diferencia de Recepción/Administrador, que sí pueden buscar).
        filas = _query_reservas(
            ["ht.nombre = %s", "r.pagado = 0"], [session["nombre_hotel"]], "r.fecha_limite_pago"
        )
        return render_template("reservas/listado.html", reservas=filas, filtros=None, estados=ESTADOS_RESERVA)

    filtros = {
        "tipo_persona": request.args.get("tipo_persona") or "",
        "documento": request.args.get("documento") or "",
        "estado": request.args.get("estado") or "",
    }
    condiciones = ["ht.nombre = %s"]
    parametros = [session["nombre_hotel"]]
    if filtros["tipo_persona"]:
        condiciones.append("v.tipo_persona = %s")
        parametros.append(filtros["tipo_persona"])
    if filtros["documento"]:
        condiciones.append("v.documento LIKE %s")
        parametros.append(f"%{filtros['documento']}%")
    if filtros["estado"]:
        condiciones.append("r.estado = %s")
        parametros.append(filtros["estado"])

    filas = _query_reservas(condiciones, parametros, "r.id_reserva DESC")
    return render_template("reservas/listado.html", reservas=filas, filtros=filtros, estados=ESTADOS_RESERVA)


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
        existente = query(
            "SELECT id_persona FROM persona_natural WHERE id_tipo_documento = %s AND numero_documento = %s",
            (request.form["id_tipo_documento"], request.form["numero_documento"]),
        )
        if existente:
            # La persona ya existe (p.ej. ya fue huésped antes): se reutiliza
            # su id_persona en vez de intentar crear un duplicado que
            # chocaría con uq_pnatural_documento.
            statements = [
                (
                    "INSERT INTO cliente (id_persona, observaciones) VALUES (%s, %s)",
                    (existente[0]["id_persona"], request.form.get("observaciones") or None),
                )
            ]
        else:
            statements = [
                ("INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', %s, %s)", (telefono, email)),
                (
                    "INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, nombres, apellidos, fecha_nacimiento, genero, nacionalidad) "
                    "VALUES (LAST_INSERT_ID(), %s, %s, %s, %s, %s, %s, %s)",
                    (
                        request.form["id_tipo_documento"],
                        request.form["numero_documento"],
                        request.form["nombres"],
                        request.form["apellidos"],
                        request.form["fecha_nacimiento"],
                        request.form["genero"],
                        request.form["nacionalidad"],
                    ),
                ),
                (
                    "INSERT INTO cliente (id_persona, observaciones) VALUES (LAST_INSERT_ID(), %s)",
                    (request.form.get("observaciones") or None,),
                ),
            ]
        ok, lastrowids = ejecutar_con_flash(
            execute_transaction,
            statements,
            on_success_msg="Cliente natural creado correctamente. Continúa completando la reserva.",
        )
    else:
        existente = query("SELECT id_persona FROM persona_juridica WHERE ruc = %s", (request.form["ruc"],))
        if existente:
            statements = [
                (
                    "INSERT INTO cliente (id_persona, observaciones) VALUES (%s, %s)",
                    (existente[0]["id_persona"], request.form.get("observaciones") or None),
                )
            ]
        else:
            statements = [
                ("INSERT INTO persona (tipo, telefono, email) VALUES ('JURIDICA', %s, %s)", (telefono, email)),
                (
                    "INSERT INTO persona_juridica (id_persona, ruc, razon_social, nombre_comercial, representante_legal, giro_negocio) "
                    "VALUES (LAST_INSERT_ID(), %s, %s, %s, %s, %s)",
                    (
                        request.form["ruc"],
                        request.form["razon_social"],
                        request.form.get("nombre_comercial") or None,
                        request.form["representante_legal"],
                        request.form.get("giro_negocio") or None,
                    ),
                ),
                (
                    "INSERT INTO cliente (id_persona, observaciones) VALUES (LAST_INSERT_ID(), %s)",
                    (request.form.get("observaciones") or None,),
                ),
            ]
        ok, lastrowids = ejecutar_con_flash(
            execute_transaction,
            statements,
            on_success_msg="Cliente jurídico (empresa) creado correctamente. Continúa completando la reserva.",
        )

    if not ok:
        return render_template(
            "reservas/nuevo.html",
            seleccion_cliente=request.form,
            seleccion_reserva=draft_reserva,
            **_contexto_nuevo(),
        )

    id_cliente_nuevo = lastrowids[-1]
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
        "es_terminal": reserva[0]["estado"] in ESTADOS_RESERVA_TERMINALES,
    }


@bp.route("/<int:id_reserva>/detalle", methods=["GET"])
@requiere_rol("RECEPCION", "CAJA", "ADMINISTRADOR")
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
@requiere_rol("CAJA", "ADMINISTRADOR")
def pago(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    if reserva[0]["pagado"]:
        # Ya no hay nada que confirmar en esta pantalla; se salta directo al
        # siguiente paso real del flujo.
        return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))
    if reserva[0]["estado"] in ESTADOS_RESERVA_TERMINALES:
        flash("La reserva está en un estado final; ya no se puede confirmar el pago.", "danger")
        return redirect(url_for("reservas.detalle", id_reserva=id_reserva))
    return render_template("reservas/pago.html", reserva=reserva[0])


@bp.route("/<int:id_reserva>/pago", methods=["POST"])
@requiere_rol("CAJA", "ADMINISTRADOR")
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
    # No a reservas.pago: una vez pagada esa pantalla ya no tiene nada que
    # mostrar y redirige a preasignar, que CAJA no puede ver.
    return redirect(url_for("reservas.detalle", id_reserva=id_reserva))


@bp.route("/<int:id_reserva>/cancelar", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def cancelar_reserva(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    ejecutar_con_flash(
        call_procedure,
        "sp_cancelar_reserva",
        (id_reserva,),
        on_success_msg="Reserva cancelada.",
    )
    return redirect(url_for("reservas.detalle", id_reserva=id_reserva))


@bp.route("/<int:id_reserva>/no-show", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def marcar_no_show(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    ejecutar_con_flash(
        call_procedure,
        "sp_marcar_no_show",
        (id_reserva,),
        on_success_msg="Reserva marcada como no-show.",
    )
    return redirect(url_for("reservas.detalle", id_reserva=id_reserva))


def _contexto_preasignar(id_reserva):
    if not _reserva_de_mi_hotel(id_reserva):
        return None
    reserva = query("SELECT * FROM vw_reservas_detalle WHERE id_reserva = %s", (id_reserva,))
    if not reserva:
        return None

    return {
        "reserva": reserva[0],
        "lineas": construir_grid_reserva(id_reserva, con_estado_estadia=True),
        "huespedes": query(
            """
            SELECT pn.id_persona AS id_huesped, pn.nombres, pn.apellidos
            FROM persona_natural pn
            JOIN persona p ON p.id_persona = pn.id_persona
            WHERE p.activo = 1
            ORDER BY pn.nombres
            """
        ),
        "tipos_documento": query("SELECT id_tipo_documento, nombre FROM tipo_documento ORDER BY nombre"),
        "es_terminal": reserva[0]["estado"] in ESTADOS_RESERVA_TERMINALES,
    }


@bp.route("/<int:id_reserva>/preasignar", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def preasignar(id_reserva):
    contexto = _contexto_preasignar(id_reserva)
    if contexto is None:
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))
    return render_template("reservas/preasignar.html", **contexto)


@bp.route("/<int:id_reserva>/asignacion/<int:id_detalle_reserva>", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def guardar_asignacion_linea(id_reserva, id_detalle_reserva):
    """Guarda de una vez toda una línea de la tabla de asignación (todas sus
    habitaciones/cupos): por cada habitación, valida que si tiene algún
    huésped asignado también tenga un titular marcado (obligatorio, una
    habitación con gente no puede quedar sin titular), y recién si toda la
    línea es válida guarda los cambios en una sola transacción. El check-in
    es individual por huésped (ver estadia.checkin_post), así que el
    bloqueo también es por cupo: un cupo con check-in ya hecho no se toca,
    pero sus compañeros de habitación que todavía no hicieron check-in
    siguen siendo editables."""
    if not _reserva_de_mi_hotel(id_reserva):
        flash("Reserva no encontrada.", "danger")
        return redirect(url_for("reservas.listado"))

    reserva = query("SELECT estado FROM reserva WHERE id_reserva = %s", (id_reserva,))
    if reserva and reserva[0]["estado"] in ESTADOS_RESERVA_TERMINALES:
        flash("La reserva está en un estado final; no se pueden asignar huéspedes.", "danger")
        return redirect(url_for("reservas.detalle", id_reserva=id_reserva))

    linea = next(
        (l for l in construir_grid_reserva(id_reserva, con_estado_estadia=True) if l["id_detalle_reserva"] == id_detalle_reserva),
        None,
    )
    if linea is None:
        flash("Línea de reserva no encontrada.", "danger")
        return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))

    statements = []
    for hab in linea["habitaciones"]:
        n = hab["n"]
        # Si el titular de esta habitación ya hizo check-in, su cupo queda
        # bloqueado y el titular ya está fijado: no hace falta (ni se debe
        # permitir) marcar otro entre los cupos todavía editables.
        titular_ya_fijado = any(s["estadia"] and s["es_titular"] for s in hab["slots"])
        titular_pos = None if titular_ya_fijado else (request.form.get(f"titular_{n}") or None)

        nuevos = {}
        for pos, slot in enumerate(hab["slots"], start=1):
            if slot["estadia"]:
                continue  # cupo con check-in ya hecho: no se edita
            valor = request.form.get(f"huesped_{n}_{pos}") or None
            nuevos[pos] = (slot["id_detalle_huesped"], int(valor) if valor else None)

        ocupados = [pos for pos, (_, id_huesped) in nuevos.items() if id_huesped]

        if not titular_ya_fijado:
            if titular_pos and int(titular_pos) not in ocupados:
                flash(f"Habitación {n} de {linea['tipo_habitacion']}: el titular marcado no tiene huésped asignado.", "danger")
                return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))
            if ocupados and not titular_pos:
                flash(f"Habitación {n} de {linea['tipo_habitacion']}: falta marcar un titular.", "danger")
                return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))

        for pos, (id_detalle_huesped, id_huesped) in nuevos.items():
            es_titular = 1 if titular_pos and int(titular_pos) == pos else 0
            if id_detalle_huesped:
                statements.append(
                    (
                        "UPDATE detalle_huesped_reserva SET id_huesped = %s, es_titular = %s WHERE id_detalle_huesped = %s",
                        (id_huesped, es_titular, id_detalle_huesped),
                    )
                )
            elif id_huesped:
                statements.append(
                    (
                        "INSERT INTO detalle_huesped_reserva (id_detalle_reserva, id_huesped, es_titular) VALUES (%s, %s, %s)",
                        (id_detalle_reserva, id_huesped, es_titular),
                    )
                )

    if not statements:
        flash("No hubo cambios para guardar (o todos los cupos de esta línea ya tienen check-in).", "warning")
        return redirect(url_for("reservas.preasignar", id_reserva=id_reserva))

    ejecutar_con_flash(execute_transaction, statements, on_success_msg="Asignación de huéspedes guardada.")
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
