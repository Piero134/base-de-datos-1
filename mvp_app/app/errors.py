import mysql.connector
from flask import flash


def ejecutar_con_flash(func, *args, on_success_msg=None, **kwargs):
    """
    Ejecuta func(*args, **kwargs) (normalmente call_procedure o execute) y
    traduce cualquier error de negocio de MySQL (SIGNAL SQLSTATE '45000',
    lanzado por los procedimientos/triggers) a un flash message, mostrando
    el MESSAGE_TEXT tal cual lo escribió el SP, sin reinterpretarlo.

    Devuelve (ok: bool, resultado_o_None).
    """
    try:
        resultado = func(*args, **kwargs)
        if on_success_msg:
            flash(on_success_msg, "success")
        return True, resultado
    except mysql.connector.Error as err:
        flash(err.msg, "danger")
        return False, None
