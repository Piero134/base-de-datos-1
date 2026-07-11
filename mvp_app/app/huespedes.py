from app.db import execute
from app.errors import ejecutar_con_flash


def crear_huesped_desde_formulario(form):
    """
    Inserta un huésped (real o genérico) a partir de un formulario con los
    campos compartidos por las pantallas de reservas (pre-asignación
    corporativa) y estadía (check-in). Devuelve (ok, resultado), igual que
    ejecutar_con_flash.
    """
    es_generico = form.get("es_generico") == "on"

    if es_generico:
        return ejecutar_con_flash(
            execute,
            "INSERT INTO huesped (nombres, es_generico) VALUES (%s, 1)",
            (form.get("nombres") or "Invitado",),
            on_success_msg="Huésped genérico creado; se completará más adelante.",
        )

    return ejecutar_con_flash(
        execute,
        """
        INSERT INTO huesped (id_tipo_documento, numero_documento, nombres, apellidos,
                              fecha_nacimiento, genero, nacionalidad, telefono, email)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        """,
        (
            form["id_tipo_documento"],
            form["numero_documento"],
            form["nombres"],
            form["apellidos"],
            form.get("fecha_nacimiento") or None,
            form.get("genero") or None,
            form.get("nacionalidad") or None,
            form.get("telefono") or None,
            form.get("email") or None,
        ),
        on_success_msg="Huésped creado correctamente.",
    )
