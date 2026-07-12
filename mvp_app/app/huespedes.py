from app.db import execute, execute_transaction
from app.errors import ejecutar_con_flash


def crear_huesped_desde_formulario(form):
    """
    Da de alta un huésped a partir de un formulario compartido por las
    pantallas de reservas (pre-asignación corporativa) y estadía
    (check-in). huesped es solo un rol de ocupación — la identidad vive
    siempre en persona/persona_natural — así que, salvo que ya venga un
    id_persona (atajo "usar mis datos", cuando el huésped es la misma
    persona física que el cliente), primero se crea la persona natural y
    recién después el huesped que la referencia. Mismo patrón que
    reservas/routes.py:cliente_nuevo para dar de alta una persona natural.
    Devuelve (ok, id_huesped), igual que antes de este cambio.
    """
    id_persona = form.get("id_persona") or None

    if not id_persona:
        ids = execute_transaction(
            [
                (
                    "INSERT INTO persona (tipo, telefono, email) VALUES ('NATURAL', %s, %s)",
                    (form.get("telefono") or None, form.get("email") or None),
                )
            ]
        )
        id_persona = ids[0]
        ok, _ = ejecutar_con_flash(
            execute_transaction,
            [
                (
                    "INSERT INTO persona_natural (id_persona, id_tipo_documento, numero_documento, "
                    "nombres, apellidos, fecha_nacimiento, genero, nacionalidad) "
                    "VALUES (%s, %s, %s, %s, %s, %s, %s, %s)",
                    (
                        id_persona,
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

    return ejecutar_con_flash(
        execute,
        "INSERT INTO huesped (id_persona) VALUES (%s)",
        (id_persona,),
        on_success_msg="Huésped creado correctamente.",
    )
