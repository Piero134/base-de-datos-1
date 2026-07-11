from functools import wraps

from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from app.constants import ROLES
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
        id_empleado = request.form.get("id_empleado")
        rol = request.form.get("rol")

        if not id_empleado or rol not in ROLES:
            flash("Selecciona un empleado y un rol válidos.", "danger")
            return redirect(url_for("auth.login", next=next_url))

        empleado = query(
            """
            SELECT e.id_empleado, e.nombres, e.apellidos, e.id_hotel,
                   c.nombre AS cargo, h.nombre AS hotel
            FROM empleado e
            JOIN cargo_empleado c ON c.id_cargo = e.id_cargo
            JOIN hotel h ON h.id_hotel = e.id_hotel
            WHERE e.id_empleado = %s AND e.activo = 1
            """,
            (id_empleado,),
        )
        if not empleado:
            flash("Empleado no encontrado o inactivo.", "danger")
            return redirect(url_for("auth.login", next=next_url))

        emp = empleado[0]
        session["id_empleado"] = emp["id_empleado"]
        session["nombre_empleado"] = f"{emp['nombres']} {emp['apellidos']}"
        session["id_hotel"] = emp["id_hotel"]
        session["nombre_hotel"] = emp["hotel"]
        session["rol"] = rol
        flash(f"Sesión iniciada como {session['nombre_empleado']} ({rol}).", "success")
        return redirect(next_url or url_for("auth.landing"))

    empleados = query(
        """
        SELECT e.id_empleado, e.id_hotel, e.nombres, e.apellidos, c.nombre AS cargo, h.nombre AS hotel
        FROM empleado e
        JOIN cargo_empleado c ON c.id_cargo = e.id_cargo
        JOIN hotel h ON h.id_hotel = e.id_hotel
        WHERE e.activo = 1
        ORDER BY h.nombre, e.apellidos
        """
    )
    hoteles = query("SELECT id_hotel, nombre FROM hotel WHERE activo = 1 ORDER BY nombre")
    return render_template(
        "auth/login.html", empleados=empleados, hoteles=hoteles, roles=ROLES, next_url=next_url
    )


@bp.route("/logout")
def logout():
    session.clear()
    flash("Sesión cerrada.", "success")
    return redirect(url_for("auth.login"))


@bp.route("/rol", methods=["POST"])
def cambiar_rol():
    """Cambia el rol de app activo sin cerrar sesión (el rol de app es
    independiente del cargo real del empleado, ver README)."""
    if "rol" not in session:
        return redirect(url_for("auth.login"))

    nuevo_rol = request.form.get("rol")
    if nuevo_rol not in ROLES:
        flash("Rol inválido.", "danger")
        return redirect(url_for("auth.landing"))

    session["rol"] = nuevo_rol
    flash(f"Rol activo cambiado a {nuevo_rol}.", "success")
    return redirect(url_for("auth.landing"))


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
        kpis["ingreso_total"] = query(
            "SELECT COALESCE(SUM(ingreso_total), 0) AS n FROM vw_ingresos_por_hotel WHERE id_hotel = %s",
            (id_hotel,),
        )[0]["n"]

    elif rol == "ADMINISTRADOR":
        # hoteles_activos se deja global a propósito: `hotel` no tiene id_hotel
        # propio (es la entidad raíz), y el administrador debe poder ver que
        # existen otros hoteles en la cadena aunque solo gestione el suyo.
        kpis["hoteles_activos"] = query("SELECT COUNT(*) AS n FROM hotel WHERE activo = 1")[0]["n"]
        kpis["habitaciones_registradas"] = query(
            "SELECT COUNT(*) AS n FROM habitacion WHERE id_hotel = %s", (id_hotel,)
        )[0]["n"]
        kpis["empleados_activos"] = query(
            "SELECT COUNT(*) AS n FROM empleado WHERE activo = 1 AND id_hotel = %s", (id_hotel,)
        )[0]["n"]

    return render_template("auth/dashboard.html", rol=rol, kpis=kpis)
