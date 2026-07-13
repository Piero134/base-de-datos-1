from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.auth.routes import requiere_rol
from app.constants import METODOS_PAGO
from app.db import call_procedure, query
from app.errors import ejecutar_con_flash

bp = Blueprint("caja", __name__, url_prefix="/caja", template_folder="templates")

# vw_cuenta_cobrar_resumen no expone ninguna columna de hotel, así que estas
# dos pantallas (en vez de "SELECT * FROM vw_..." como el resto del proyecto)
# arman el mismo resultado con un JOIN directo a alojamiento/habitacion para
# poder filtrar por el hotel de la sesión. Mismas columnas que la vista.
_CUENTA_SELECT = """
    SELECT cc.id_cuenta, cc.id_alojamiento, cc.estado AS estado_cuenta, cc.subtotal,
           cc.impuestos, cc.total, cc.saldo AS saldo_pendiente, cc.total - cc.saldo AS ya_pagado,
           cc.fecha_generacion
    FROM cuenta_cobrar cc
    JOIN alojamiento a ON a.id_alojamiento = cc.id_alojamiento
    JOIN habitacion h ON h.id_habitacion = a.id_habitacion
"""


@bp.route("/cuentas")
@requiere_rol("CAJA", "ADMINISTRADOR")
def cuentas():
    estado = request.args.get("estado")
    if estado:
        filas = query(
            _CUENTA_SELECT + " WHERE h.id_hotel = %s AND cc.estado = %s ORDER BY cc.id_cuenta DESC",
            (session["id_hotel"], estado),
        )
    else:
        filas = query(_CUENTA_SELECT + " WHERE h.id_hotel = %s ORDER BY cc.id_cuenta DESC", (session["id_hotel"],))
    return render_template("caja/cuentas.html", filas=filas, estado=estado)


def _contexto_generar_cuenta():
    # Solo candidatos con algo real que cobrar (sp_generar_cuenta_cobrar
    # rechaza generar una cuenta en 0 si no hay consumos ni daños
    # pendientes); sin este filtro el cajero vería alojamientos que igual
    # fallarían al intentar generarles cuenta.
    return query(
        """
        SELECT a.id_alojamiento, ht.nombre AS hotel, h.numero AS habitacion, a.fecha_checkout_real
        FROM alojamiento a
        JOIN habitacion h ON h.id_habitacion = a.id_habitacion
        JOIN hotel ht ON ht.id_hotel = h.id_hotel
        LEFT JOIN cuenta_cobrar cc ON cc.id_alojamiento = a.id_alojamiento
        WHERE a.estado = 'FINALIZADO' AND cc.id_cuenta IS NULL AND ht.id_hotel = %s
          AND (
              EXISTS (SELECT 1 FROM consumo_servicio cs WHERE cs.id_alojamiento = a.id_alojamiento)
              OR EXISTS (SELECT 1 FROM danio d WHERE d.id_alojamiento = a.id_alojamiento AND d.estado = 'PENDIENTE')
          )
        ORDER BY a.fecha_checkout_real
        """,
        (session["id_hotel"],),
    )


@bp.route("/generar-cuenta")
@requiere_rol("CAJA", "ADMINISTRADOR")
def generar_cuenta_form():
    return render_template("caja/generar_cuenta.html", alojamientos=_contexto_generar_cuenta())


@bp.route("/generar-cuenta", methods=["POST"])
@requiere_rol("CAJA", "ADMINISTRADOR")
def generar_cuenta_post():
    id_alojamiento = request.form["id_alojamiento"]
    pertenece = query(
        """
        SELECT 1 FROM alojamiento a JOIN habitacion h ON h.id_habitacion = a.id_habitacion
        WHERE a.id_alojamiento = %s AND h.id_hotel = %s
        """,
        (id_alojamiento, session["id_hotel"]),
    )
    if not pertenece:
        flash("Alojamiento no encontrado.", "danger")
        return redirect(url_for("caja.generar_cuenta_form"))
    ok, data = ejecutar_con_flash(
        call_procedure,
        "sp_generar_cuenta_cobrar",
        (id_alojamiento, 0),
        on_success_msg="Cuenta por cobrar generada.",
    )
    if not ok:
        return render_template("caja/generar_cuenta.html", alojamientos=_contexto_generar_cuenta())

    _, out_values = data
    id_cuenta = out_values[1]
    return redirect(url_for("caja.ver_cuenta", id_cuenta=id_cuenta))


def _contexto_ver_cuenta(id_cuenta):
    cuenta = query(
        _CUENTA_SELECT + " WHERE cc.id_cuenta = %s AND h.id_hotel = %s", (id_cuenta, session["id_hotel"])
    )
    if not cuenta:
        return None
    return {
        "cuenta": cuenta[0],
        "detalle": query(
            "SELECT concepto, cantidad, precio_unitario, subtotal FROM cuenta_cobrar_detalle WHERE id_cuenta = %s",
            (id_cuenta,),
        ),
        "pagos": query(
            "SELECT monto, metodo_pago, fecha_pago FROM pago_cuenta_cobrar WHERE id_cuenta = %s ORDER BY fecha_pago",
            (id_cuenta,),
        ),
        "metodos": METODOS_PAGO,
    }


@bp.route("/cuenta/<int:id_cuenta>")
@requiere_rol("CAJA", "ADMINISTRADOR")
def ver_cuenta(id_cuenta):
    contexto = _contexto_ver_cuenta(id_cuenta)
    if contexto is None:
        flash("Cuenta no encontrada.", "danger")
        return redirect(url_for("caja.cuentas"))
    return render_template("caja/ver_cuenta.html", **contexto)


@bp.route("/cuenta/<int:id_cuenta>/pago", methods=["POST"])
@requiere_rol("CAJA", "ADMINISTRADOR")
def registrar_pago(id_cuenta):
    if _contexto_ver_cuenta(id_cuenta) is None:
        flash("Cuenta no encontrada.", "danger")
        return redirect(url_for("caja.cuentas"))
    monto = request.form["monto"]
    metodo_pago = request.form["metodo_pago"]
    ok, _ = ejecutar_con_flash(
        call_procedure,
        "sp_registrar_pago_cuenta",
        (id_cuenta, monto, metodo_pago, session["id_empleado"]),
        on_success_msg="Pago registrado correctamente.",
    )
    if not ok:
        contexto = _contexto_ver_cuenta(id_cuenta)
        if contexto is None:
            return redirect(url_for("caja.cuentas"))
        return render_template("caja/ver_cuenta.html", seleccion=request.form, **contexto)
    return redirect(url_for("caja.ver_cuenta", id_cuenta=id_cuenta))
