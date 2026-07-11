from flask import Blueprint, render_template, session

from app.auth.routes import requiere_rol
from app.db import call_procedure, query

bp = Blueprint("reportes", __name__, url_prefix="/reportes", template_folder="templates")


@bp.route("/ocupacion")
@requiere_rol("GERENCIA", "ADMINISTRADOR")
def ocupacion():
    id_hotel = session["id_hotel"]
    filas = query("SELECT * FROM vw_ocupacion_hotel WHERE id_hotel = %s ORDER BY tipo", (id_hotel,))
    result_sets, _ = call_procedure("sp_resumen_ocupacion_hotel", (id_hotel,))
    resumen = result_sets[0] if result_sets else []
    return render_template("reportes/ocupacion.html", filas=filas, resumen=resumen)


@bp.route("/ingresos")
@requiere_rol("GERENCIA", "ADMINISTRADOR")
def ingresos():
    filas = query(
        "SELECT * FROM vw_ingresos_por_hotel WHERE id_hotel = %s ORDER BY ingreso_total DESC",
        (session["id_hotel"],),
    )
    return render_template("reportes/ingresos.html", filas=filas)


@bp.route("/ranking-clientes")
@requiere_rol("GERENCIA", "ADMINISTRADOR")
def ranking():
    filas = query("SELECT * FROM vw_ranking_clientes ORDER BY ranking")
    return render_template("reportes/ranking.html", filas=filas)
