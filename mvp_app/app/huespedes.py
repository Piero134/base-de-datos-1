from app.db import execute_transaction, query
from app.errors import ejecutar_con_flash


def crear_huesped_desde_formulario(form):
    """
    Da de alta (o reutiliza) la persona_natural que va a ocupar un cupo,
    a partir de un formulario compartido por las pantallas de reservas
    (pre-asignación corporativa) y estadía (check-in). "Huésped" es un
    rol, no una identidad aparte: cualquier persona_natural puede
    cumplirlo, así que este alta es simplemente la de la persona. Si ya
    existe una persona_natural con el mismo tipo+número de documento, se
    reutiliza (la misma persona puede volver a hospedarse en distintas
    estadías); si no existe, se crea persona+persona_natural en una
    única transacción atómica. Mismo patrón que
    reservas/routes.py:cliente_nuevo. Devuelve (ok, id_persona).
    """
    existente = query(
        "SELECT id_persona FROM persona_natural WHERE id_tipo_documento = %s AND numero_documento = %s",
        (form["id_tipo_documento"], form["numero_documento"]),
    )

    if existente:
        return True, existente[0]["id_persona"]

    ok, ids = ejecutar_con_flash(
        execute_transaction,
        [
            (
                "INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', %s, %s)",
                (form.get("telefono") or None, form.get("email") or None),
            ),
            (
                "INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, "
                "nombres, apellidos, fecha_nacimiento, genero, nacionalidad) "
                "VALUES (LAST_INSERT_ID(), %s, %s, %s, %s, %s, %s, %s)",
                (
                    form["id_tipo_documento"],
                    form["numero_documento"],
                    form["nombres"],
                    form["apellidos"],
                    form["fecha_nacimiento"],
                    form["genero"],
                    form["nacionalidad"],
                ),
            ),
        ],
        on_success_msg="Huésped creado correctamente.",
    )
    if not ok:
        return False, None
    return True, ids[0]
