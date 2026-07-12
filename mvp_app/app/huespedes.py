from app.db import execute, execute_transaction, query
from app.errors import ejecutar_con_flash


def crear_huesped_desde_formulario(form):
    """
    Da de alta un huésped a partir de un formulario compartido por las
    pantallas de reservas (pre-asignación corporativa) y estadía
    (check-in). huesped es solo un rol de ocupación — la identidad vive
    siempre en persona/persona_natural — así que, si ya existe una
    persona_natural con el mismo tipo+número de documento, se reutiliza
    (la misma persona puede volver a hospedarse en distintas estadías);
    si no existe, se crea persona+persona_natural en una única transacción
    atómica y recién después el huesped que la referencia. Mismo patrón
    que reservas/routes.py:cliente_nuevo para dar de alta una persona
    natural. Devuelve (ok, id_huesped), igual que antes de este cambio.
    """
    existente = query(
        "SELECT id_persona FROM persona_natural WHERE id_tipo_documento = %s AND numero_documento = %s",
        (form["id_tipo_documento"], form["numero_documento"]),
    )

    if existente:
        id_persona = existente[0]["id_persona"]
    else:
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
        )
        if not ok:
            return False, None
        id_persona = ids[0]

    return ejecutar_con_flash(
        execute,
        "INSERT INTO huesped (id_persona) VALUES (%s)",
        (id_persona,),
        on_success_msg="Huésped creado correctamente.",
    )
