import re
import secrets

from flask import Blueprint, flash, redirect, render_template, request, session, url_for
from werkzeug.security import generate_password_hash

from app.auth.routes import requiere_rol
from app.db import call_procedure, execute, query
from app.errors import ejecutar_con_flash

bp = Blueprint("administracion", __name__, url_prefix="/admin", template_folder="templates")


def _primer_hotel_activo():
    fila = query("SELECT id_hotel FROM hotel WHERE activo = 1 ORDER BY nombre LIMIT 1")
    return fila[0]["id_hotel"] if fila else None


def _username_desde_hotel(nombre_hotel):
    base = re.sub(r"[^a-z0-9]+", "", nombre_hotel.lower())
    return f"{base[:20]}admin"


def _crear_admin_de_hotel(id_hotel_nuevo, nombre_hotel):
    """Se llama justo después de crear un hotel (solo alcance general): le
    da un perfil de administrador propio de inmediato, para que el hotel
    sea usable desde el día uno sin depender de que alguien se lo cree
    manualmente después. Encadena 2 INSERT secuenciales (mismo patrón no
    atómico que reservas.cliente_nuevo() usa para persona -> persona_natural)."""
    id_cargo_admin = query("SELECT id_cargo FROM cargo_empleado WHERE nombre = 'Administrador de Hotel'")[0]["id_cargo"]
    ok, id_empleado_nuevo = ejecutar_con_flash(
        execute,
        "INSERT INTO empleado (id_hotel, id_cargo, nombres, apellidos, activo) VALUES (%s, %s, 'Administrador', %s, 1)",
        (id_hotel_nuevo, id_cargo_admin, nombre_hotel),
    )
    if not ok:
        return
    username = _username_desde_hotel(nombre_hotel)
    password_temporal = secrets.token_urlsafe(6)
    ejecutar_con_flash(
        execute,
        "INSERT INTO usuario (id_empleado, username, password_hash, rol, id_hotel, activo) VALUES (%s, %s, %s, 'ADMINISTRADOR', %s, 1)",
        (id_empleado_nuevo, username, generate_password_hash(password_temporal), id_hotel_nuevo),
        on_success_msg=f"Hotel creado. Usuario administrador: {username} / contraseña temporal: {password_temporal} (anótala, no se vuelve a mostrar).",
    )


# ---------------------------------------------------------------------
# Hoteles
# ---------------------------------------------------------------------
@bp.route("/hoteles", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def hoteles():
    es_general = session["id_hotel"] is None

    if not es_general:
        # Admin de un solo hotel: no tiene sentido que gestione otros —
        # pantalla de solo lectura del propio.
        filas = query("SELECT * FROM hotel WHERE id_hotel = %s", (session["id_hotel"],))
        return render_template("administracion/hoteles.html", filas=filas, es_general=False)

    seleccion = None
    if request.method == "POST":
        ok, id_hotel_nuevo = ejecutar_con_flash(
            execute,
            """
            INSERT INTO hotel (nombre, direccion, telefono, email, id_ubigeo, activo)
            VALUES (%s, %s, %s, %s, %s, 1)
            """,
            (
                request.form["nombre"], request.form["direccion"],
                request.form.get("telefono") or None, request.form.get("email") or None,
                request.form["id_ubigeo"],
            ),
        )
        if ok:
            _crear_admin_de_hotel(id_hotel_nuevo, request.form["nombre"])
            return redirect(url_for("administracion.hoteles"))
        seleccion = request.form

    filas = query("SELECT * FROM hotel ORDER BY nombre")
    ubigeos = query("SELECT id_ubigeo, departamento, provincia, distrito FROM ubigeo ORDER BY departamento")
    return render_template(
        "administracion/hoteles.html", filas=filas, ubigeos=ubigeos, seleccion=seleccion, es_general=True
    )


@bp.route("/hoteles/<int:id_hotel>/editar", methods=["POST"])
@requiere_rol("ADMINISTRADOR")
def hotel_editar(id_hotel):
    if session["id_hotel"] is not None:
        flash("No tienes permiso para editar hoteles.", "danger")
        return redirect(url_for("administracion.hoteles"))
    ejecutar_con_flash(
        execute,
        "UPDATE hotel SET nombre=%s, direccion=%s, telefono=%s, email=%s, activo=%s WHERE id_hotel=%s",
        (
            request.form["nombre"], request.form["direccion"],
            request.form.get("telefono") or None, request.form.get("email") or None,
            1 if request.form.get("activo") else 0, id_hotel,
        ),
        on_success_msg="Hotel actualizado.",
    )
    return redirect(url_for("administracion.hoteles"))


# ---------------------------------------------------------------------
# Tipos de habitación
# ---------------------------------------------------------------------
@bp.route("/tipos-habitacion", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def tipos_habitacion():
    seleccion = None
    if request.method == "POST":
        ok, _ = ejecutar_con_flash(
            execute,
            "INSERT INTO tipo_habitacion (nombre, capacidad_base, descripcion) VALUES (%s, %s, %s)",
            (request.form["nombre"], request.form["capacidad_base"], request.form.get("descripcion") or None),
            on_success_msg="Tipo de habitación creado.",
        )
        if ok:
            return redirect(url_for("administracion.tipos_habitacion"))
        seleccion = request.form

    filas = query("SELECT * FROM tipo_habitacion ORDER BY nombre")
    return render_template("administracion/tipos_habitacion.html", filas=filas, seleccion=seleccion)


# ---------------------------------------------------------------------
# Habitaciones
# ---------------------------------------------------------------------
@bp.route("/habitaciones", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def habitaciones():
    es_general = session["id_hotel"] is None
    id_hotel_filtro = (request.args.get("id_hotel", type=int) or _primer_hotel_activo()) if es_general else session["id_hotel"]

    seleccion = None
    if request.method == "POST":
        id_hotel_nuevo = (request.form.get("id_hotel", type=int) or id_hotel_filtro) if es_general else session["id_hotel"]
        ok, _ = ejecutar_con_flash(
            execute,
            """
            INSERT INTO habitacion (id_hotel, id_tipo_habitacion, numero, piso, descripcion)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                id_hotel_nuevo, request.form["id_tipo_habitacion"],
                request.form["numero"], request.form["piso"], request.form.get("descripcion") or None,
            ),
            on_success_msg="Habitación creada.",
        )
        if ok:
            return redirect(url_for("administracion.habitaciones", id_hotel=id_hotel_nuevo))
        seleccion = request.form
        id_hotel_filtro = id_hotel_nuevo

    filas = query(
        """
        SELECT h.id_habitacion, ht.nombre AS hotel, th.nombre AS tipo, h.numero, h.piso, h.estado, h.descripcion
        FROM habitacion h
        JOIN hotel ht ON ht.id_hotel = h.id_hotel
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = h.id_tipo_habitacion
        WHERE h.id_hotel = %s
        ORDER BY h.numero
        """,
        (id_hotel_filtro,),
    )
    tipos = query("SELECT id_tipo_habitacion, nombre FROM tipo_habitacion ORDER BY nombre")
    hoteles = query("SELECT id_hotel, nombre FROM hotel WHERE activo = 1 ORDER BY nombre") if es_general else None
    return render_template(
        "administracion/habitaciones.html", filas=filas, tipos=tipos, seleccion=seleccion,
        hoteles=hoteles, id_hotel_filtro=id_hotel_filtro, es_general=es_general,
    )


def _habitacion_en_alcance(id_habitacion):
    if session["id_hotel"] is None:
        return bool(query("SELECT 1 FROM habitacion WHERE id_habitacion = %s", (id_habitacion,)))
    return bool(
        query(
            "SELECT 1 FROM habitacion WHERE id_habitacion = %s AND id_hotel = %s",
            (id_habitacion, session["id_hotel"]),
        )
    )


@bp.route("/habitaciones/<int:id_habitacion>/estado", methods=["POST"])
@requiere_rol("ADMINISTRADOR", "RECEPCION")
def habitacion_estado(id_habitacion):
    if not _habitacion_en_alcance(id_habitacion):
        flash("Habitación no encontrada.", "danger")
        return redirect(request.referrer or url_for("administracion.habitaciones"))
    nuevo_estado = request.form["estado"]
    ejecutar_con_flash(
        call_procedure,
        "sp_cambiar_estado_habitacion",
        (id_habitacion, nuevo_estado),
        on_success_msg="Estado de habitación actualizado.",
    )
    return redirect(request.referrer or url_for("administracion.habitaciones"))


# ---------------------------------------------------------------------
# Categorías de servicio
# ---------------------------------------------------------------------
@bp.route("/categorias-servicio", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def categorias_servicio():
    seleccion = None
    if request.method == "POST":
        ok, _ = ejecutar_con_flash(
            execute,
            "INSERT INTO categoria_servicio (nombre) VALUES (%s)",
            (request.form["nombre"],),
            on_success_msg="Categoría de servicio creada.",
        )
        if ok:
            return redirect(url_for("administracion.categorias_servicio"))
        seleccion = request.form

    filas = query("SELECT * FROM categoria_servicio ORDER BY nombre")
    return render_template("administracion/categorias_servicio.html", filas=filas, seleccion=seleccion)


# ---------------------------------------------------------------------
# Servicios
# ---------------------------------------------------------------------
@bp.route("/servicios", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def servicios():
    seleccion = None
    if request.method == "POST":
        ok, _ = ejecutar_con_flash(
            execute,
            "INSERT INTO servicio (nombre, id_categoria, precio_unitario, activo) VALUES (%s, %s, %s, 1)",
            (request.form["nombre"], request.form["id_categoria"], request.form["precio_unitario"]),
            on_success_msg="Servicio creado.",
        )
        if ok:
            return redirect(url_for("administracion.servicios"))
        seleccion = request.form

    filas = query(
        """
        SELECT s.id_servicio, s.nombre, cat.nombre AS categoria, s.precio_unitario, s.activo
        FROM servicio s
        JOIN categoria_servicio cat ON cat.id_categoria = s.id_categoria
        ORDER BY cat.nombre, s.nombre
        """
    )
    categorias = query("SELECT id_categoria, nombre FROM categoria_servicio ORDER BY nombre")
    return render_template("administracion/servicios.html", filas=filas, categorias=categorias, seleccion=seleccion)


# ---------------------------------------------------------------------
# Planes tarifarios
# ---------------------------------------------------------------------
@bp.route("/planes-tarifa", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def planes_tarifa():
    seleccion = None
    if request.method == "POST":
        ok, _ = ejecutar_con_flash(
            execute,
            """
            INSERT INTO plan_tarifa (nombre, descripcion, fecha_inicio, fecha_fin, es_publico, activo)
            VALUES (%s, %s, %s, %s, %s, 1)
            """,
            (
                request.form["nombre"], request.form.get("descripcion") or None,
                request.form["fecha_inicio"], request.form["fecha_fin"],
                1 if request.form.get("es_publico") else 0,
            ),
            on_success_msg="Plan tarifario creado.",
        )
        if ok:
            return redirect(url_for("administracion.planes_tarifa"))
        seleccion = request.form

    filas = query("SELECT * FROM plan_tarifa ORDER BY fecha_inicio DESC")
    return render_template("administracion/planes_tarifa.html", filas=filas, seleccion=seleccion)


# ---------------------------------------------------------------------
# Tarifas por tipo de habitación y plan
# ---------------------------------------------------------------------
@bp.route("/tarifas", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def tarifas():
    seleccion = None
    if request.method == "POST":
        ok, _ = ejecutar_con_flash(
            execute,
            """
            INSERT INTO tarifa_habitacion (id_plan, id_tipo_habitacion, precio_por_noche)
            VALUES (%s, %s, %s)
            """,
            (
                request.form["id_plan"], request.form["id_tipo_habitacion"],
                request.form["precio_por_noche"],
            ),
            on_success_msg="Tarifa creada.",
        )
        if ok:
            return redirect(url_for("administracion.tarifas"))
        seleccion = request.form

    filas = query(
        """
        SELECT tr.id_tarifa, pt.nombre AS plan, th.nombre AS tipo_habitacion,
               tr.precio_por_noche, th.capacidad_base
        FROM tarifa_habitacion tr
        JOIN plan_tarifa pt ON pt.id_plan = tr.id_plan
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = tr.id_tipo_habitacion
        ORDER BY pt.nombre, th.nombre
        """
    )
    planes = query("SELECT id_plan, nombre FROM plan_tarifa ORDER BY nombre")
    tipos = query("SELECT id_tipo_habitacion, nombre FROM tipo_habitacion ORDER BY nombre")
    return render_template(
        "administracion/tarifas.html", filas=filas, planes=planes, tipos=tipos, seleccion=seleccion
    )


# ---------------------------------------------------------------------
# Empleados
# ---------------------------------------------------------------------
@bp.route("/empleados", methods=["GET", "POST"])
@requiere_rol("ADMINISTRADOR")
def empleados():
    # id_hotel es elegible solo para el admin general (session["id_hotel"]
    # is None): un hotel recién creado ya nace con su propio admin (ver
    # _crear_admin_de_hotel), pero el admin general igual debe poder
    # gestionar empleados de cualquier hotel. Un admin de un solo hotel
    # queda siempre fijo al suyo — no tiene sentido que gestione otro.
    es_general = session["id_hotel"] is None
    id_hotel_filtro = (request.args.get("id_hotel", type=int) or _primer_hotel_activo()) if es_general else session["id_hotel"]

    seleccion = None
    if request.method == "POST":
        id_hotel_nuevo = (request.form.get("id_hotel", type=int) or id_hotel_filtro) if es_general else session["id_hotel"]
        ok, _ = ejecutar_con_flash(
            execute,
            """
            INSERT INTO empleado (id_hotel, id_cargo, nombres, apellidos, activo)
            VALUES (%s, %s, %s, %s, 1)
            """,
            (id_hotel_nuevo, request.form["id_cargo"], request.form["nombres"], request.form["apellidos"]),
            on_success_msg="Empleado creado.",
        )
        if ok:
            return redirect(url_for("administracion.empleados", id_hotel=id_hotel_nuevo))
        seleccion = request.form
        id_hotel_filtro = id_hotel_nuevo

    filas = query(
        """
        SELECT e.id_empleado, e.nombres, e.apellidos, c.nombre AS cargo, h.nombre AS hotel, e.activo
        FROM empleado e
        JOIN cargo_empleado c ON c.id_cargo = e.id_cargo
        JOIN hotel h ON h.id_hotel = e.id_hotel
        WHERE e.id_hotel = %s
        ORDER BY e.apellidos
        """,
        (id_hotel_filtro,),
    )
    cargos = query("SELECT id_cargo, nombre FROM cargo_empleado ORDER BY nombre")
    hoteles = query("SELECT id_hotel, nombre FROM hotel WHERE activo = 1 ORDER BY nombre") if es_general else None
    return render_template(
        "administracion/empleados.html", filas=filas, cargos=cargos, seleccion=seleccion,
        hoteles=hoteles, id_hotel_filtro=id_hotel_filtro, es_general=es_general,
    )
