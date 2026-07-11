from flask import Blueprint, render_template, request, session

from app.auth.routes import requiere_rol
from app.db import query

bp = Blueprint("disponibilidad", __name__, url_prefix="/disponibilidad", template_folder="templates")


def _catalogos():
    tipos = query("SELECT id_tipo_habitacion, nombre FROM tipo_habitacion ORDER BY nombre")
    return tipos


@bp.route("/", methods=["GET"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def buscar():
    tipos = _catalogos()
    disponibles = query(
        "SELECT * FROM vw_habitaciones_disponibles WHERE id_hotel = %s ORDER BY numero", (session["id_hotel"],)
    )
    return render_template(
        "disponibilidad/buscar.html",
        tipos=tipos,
        disponibles=disponibles,
        resultado=None,
    )


@bp.route("/buscar", methods=["POST"])
@requiere_rol("RECEPCION", "ADMINISTRADOR")
def buscar_post():
    id_hotel = session["id_hotel"]
    id_tipo_habitacion = request.form["id_tipo_habitacion"]
    fecha_checkin = request.form["fecha_checkin"]
    fecha_checkout = request.form["fecha_checkout"]

    fila = query(
        "SELECT fn_disponibilidad_tipo_habitacion(%s, %s, %s, %s) AS disponibles",
        (id_hotel, id_tipo_habitacion, fecha_checkin, fecha_checkout),
    )
    resultado = fila[0]["disponibles"]

    tipos = _catalogos()
    disponibles = query(
        "SELECT * FROM vw_habitaciones_disponibles WHERE id_hotel = %s ORDER BY numero",
        (id_hotel,),
    )
    return render_template(
        "disponibilidad/buscar.html",
        tipos=tipos,
        disponibles=disponibles,
        resultado=resultado,
        seleccion=request.form,
    )
