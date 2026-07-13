from functools import wraps

from flask import Blueprint, flash, redirect, render_template, request, session, url_for
from werkzeug.security import check_password_hash

from app.db import query

bp = Blueprint("auth", __name__, template_folder="templates")


def _next_seguro(valor):
    """Solo acepta rutas relativas propias de la app (evita open-redirect)."""
    if valor and valor.startswith("/") and not valor.startswith("//"):
        return valor
    return None


def requiere_rol(*roles_permitidos):
    def decorator(f):
        @wraps(f)
        def wrapper(*args, **kwargs):
            if "rol" not in session:
                flash("Debes iniciar sesión para continuar.", "danger")
                return redirect(url_for("auth.login", next=request.path))
            if session["rol"] not in roles_permitidos:
                flash("No tienes permiso para acceder a esa sección con tu rol actual.", "danger")
                return redirect(url_for("auth.landing"))
            return f(*args, **kwargs)

        return wrapper

    return decorator


@bp.route("/login", methods=["GET", "POST"])
def login():
    next_url = _next_seguro(request.values.get("next"))

    if request.method == "POST":
        username = (request.form.get("username") or "").strip()
        password = request.form.get("password") or ""

        fila = query(
            """
            SELECT u.id_empleado, u.password_hash, u.activo, u.rol, u.id_hotel,
                   e.nombres, e.apellidos, h.nombre AS nombre_hotel
            FROM usuario u
            JOIN empleado e ON e.id_empleado = u.id_empleado
            LEFT JOIN hotel h ON h.id_hotel = u.id_hotel
            WHERE u.username = %s
            """,
            (username,),
        )
        if not fila or not fila[0]["activo"] or not check_password_hash(fila[0]["password_hash"], password):
            flash("Usuario o contraseña incorrectos.", "danger")
            return redirect(url_for("auth.login", next=next_url))

        u = fila[0]
        session["id_empleado"] = u["id_empleado"]
        session["nombre_empleado"] = f"{u['nombres']} {u['apellidos']}"
        session["rol"] = u["rol"]
        session["id_hotel"] = u["id_hotel"]
        session["nombre_hotel"] = u["nombre_hotel"]
        flash(f"Sesión iniciada como {session['nombre_empleado']} ({session['rol']}).", "success")
        return redirect(next_url or url_for("auth.landing"))

    return render_template("auth/login.html", next_url=next_url)


@bp.route("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada.", "success")
    return redirect(url_for("auth.login"))


@bp.route("/")
def landing():
    if "rol" not in session:
        return redirect(url_for("auth.login"))

    rol = session["rol"]
    kpis = {}

    id_hotel = session.get("id_hotel")
    nombre_hotel = session.get("nombre_hotel")

    if rol == "RECEPCION":
        kpis["reservas_pendientes_pago"] = query(
            "SELECT COUNT(*) AS n FROM vw_reservas_detalle WHERE pagado = 0 AND hotel = %s", (nombre_hotel,)
        )[0]["n"]
        kpis["alojamientos_activos"] = query(
            "SELECT COUNT(DISTINCT id_alojamiento) AS n FROM vw_alojamientos_activos WHERE hotel = %s",
            (nombre_hotel,),
        )[0]["n"]
        kpis["checkouts_pendientes"] = query(
            "SELECT COUNT(*) AS n FROM vw_checkouts_pendientes WHERE hotel = %s", (nombre_hotel,)
        )[0]["n"]

    elif rol == "CAJA":
        fila = query(
            """
            SELECT COUNT(*) AS n, COALESCE(SUM(cc.saldo), 0) AS monto
            FROM cuenta_cobrar cc
            JOIN alojamiento a ON a.id_alojamiento = cc.id_alojamiento
            JOIN habitacion h ON h.id_habitacion = a.id_habitacion
            WHERE cc.estado = 'PENDIENTE' AND h.id_hotel = %s
            """,
            (id_hotel,),
        )[0]
        kpis["cuentas_pendientes"] = fila["n"]
        kpis["monto_pendiente"] = fila["monto"]

    elif rol == "GERENCIA":
        ocup = query(
            """
            SELECT COALESCE(SUM(total_habitaciones), 0) AS total,
                   COALESCE(SUM(ocupadas), 0) AS ocupadas,
                   COALESCE(SUM(disponibles), 0) AS disponibles
            FROM vw_ocupacion_hotel WHERE id_hotel = %s
            """,
            (id_hotel,),
        )[0]
        kpis["habitaciones_total"] = ocup["total"]
        kpis["habitaciones_ocupadas"] = ocup["ocupadas"]
        kpis["habitaciones_disponibles"] = ocup["disponibles"]
        kpis["ocupacion_pct"] = round(ocup["ocupadas"] / ocup["total"] * 100, 1) if ocup["total"] else 0
        kpis["ingreso_total"] = query(
            "SELECT COALESCE(SUM(ingreso_total), 0) AS n FROM vw_ingresos_por_hotel WHERE id_hotel = %s",
            (id_hotel,),
        )[0]["n"]

        mes_actual = query(
            "SELECT mes, ingreso_mes, variacion_pct FROM vw_ingresos_mensuales WHERE id_hotel = %s ORDER BY mes DESC LIMIT 1",
            (id_hotel,),
        )
        kpis["mes_actual"] = mes_actual[0] if mes_actual else None
        kpis["top_clientes"] = query(
            "SELECT ranking, nombre_reservante, monto_total_gastado FROM vw_ranking_clientes ORDER BY ranking LIMIT 3"
        )

    elif rol == "ADMINISTRADOR":
        # hoteles_activos se deja global a propósito: `hotel` no tiene id_hotel
        # propio (es la entidad raíz), y el administrador debe poder ver que
        # existen otros hoteles en la cadena aunque solo gestione el suyo.
        kpis["hoteles_activos"] = query("SELECT COUNT(*) AS n FROM hotel WHERE activo = 1")[0]["n"]
        if id_hotel is None:
            # Alcance general (usuario.id_hotel NULL): cuenta a nivel de
            # toda la cadena, no de un solo hotel.
            kpis["habitaciones_registradas"] = query("SELECT COUNT(*) AS n FROM habitacion")[0]["n"]
            kpis["empleados_activos"] = query("SELECT COUNT(*) AS n FROM empleado WHERE activo = 1")[0]["n"]
        else:
            kpis["habitaciones_registradas"] = query(
                "SELECT COUNT(*) AS n FROM habitacion WHERE id_hotel = %s", (id_hotel,)
            )[0]["n"]
            kpis["empleados_activos"] = query(
                "SELECT COUNT(*) AS n FROM empleado WHERE activo = 1 AND id_hotel = %s", (id_hotel,)
            )[0]["n"]

    return render_template("auth/dashboard.html", rol=rol, kpis=kpis)
