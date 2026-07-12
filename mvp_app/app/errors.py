import re

import mysql.connector
from mysql.connector import errorcode
from flask import flash

# Errores de DRIVER (no de negocio) para los que damos un mensaje más claro
# que el crudo de MySQL, antes de caer al mensaje genérico. Los errores de
# negocio (SIGNAL SQLSTATE '45000', errno ER_SIGNAL_EXCEPTION) no pasan por
# este diccionario y se siguen mostrando tal cual los escribió el SP/trigger.
_MENSAJES_DRIVER = {
    errorcode.ER_WARN_DATA_OUT_OF_RANGE: "El valor ingresado está fuera del rango permitido para este campo.",
    errorcode.ER_DATA_TOO_LONG: "El valor ingresado es demasiado largo para este campo.",
}

# Restricciones CHECK (errno ER_CHECK_CONSTRAINT_VIOLATED) para las que
# damos un mensaje traducido en vez del nombre crudo de la restricción SQL.
_MENSAJES_CHECK = {
    "chk_reserva_fechas": "La fecha de check-out debe ser posterior a la fecha de check-in.",
    "chk_reserva_limite_pago": "La fecha límite de pago no puede ser posterior a la fecha de check-in.",
    "chk_reserva_monto": "El monto total de la reserva no puede ser negativo.",
}
_PATRON_CHECK = re.compile(r"Check constraint '([^']+)' is violated")

# Restricciones UNIQUE (errno ER_DUP_ENTRY) para las que damos un mensaje
# traducido en vez del "Duplicate entry ... for key ..." crudo de MySQL.
_MENSAJES_DUPLICADO = {
    "uq_pnatural_documento": "Ya existe una persona registrada con ese tipo y número de documento.",
    "uq_pjuridica_ruc": "Ya existe una empresa registrada con ese RUC.",
    "uq_cliente_persona": "Esta persona ya está registrada como cliente; selecciónala en vez de crearla de nuevo.",
}
_PATRON_DUPLICADO = re.compile(r"for key '(?:[\w]+\.)?([\w]+)'")


def _mensaje_para_error(err):
    if err.errno == errorcode.ER_CHECK_CONSTRAINT_VIOLATED:
        coincidencia = _PATRON_CHECK.search(err.msg or "")
        nombre = coincidencia.group(1) if coincidencia else None
        return _MENSAJES_CHECK.get(
            nombre, "Los datos ingresados no cumplen una regla de validez (revisa los valores relacionados)."
        )
    if err.errno == errorcode.ER_DUP_ENTRY:
        coincidencia = _PATRON_DUPLICADO.search(err.msg or "")
        nombre = coincidencia.group(1) if coincidencia else None
        return _MENSAJES_DUPLICADO.get(nombre, err.msg)
    return _MENSAJES_DRIVER.get(err.errno, err.msg)


def ejecutar_con_flash(func, *args, on_success_msg=None, **kwargs):
    """
    Ejecuta func(*args, **kwargs) (normalmente call_procedure o execute) y
    traduce cualquier error de MySQL a un flash message:
    - Errores de negocio (SIGNAL SQLSTATE '45000', lanzados por los
      procedimientos/triggers): se muestra el MESSAGE_TEXT tal cual lo
      escribió el SP, sin reinterpretarlo.
    - Errores de driver listados en _MENSAJES_DRIVER (rango/longitud fuera
      de límite), restricciones CHECK listadas en _MENSAJES_CHECK, o
      restricciones UNIQUE listadas en _MENSAJES_DUPLICADO: se traducen a
      un mensaje en español más claro.
    - Cualquier otro error de driver: se muestra err.msg crudo (comportamiento
      previo, sin cambios).

    Devuelve (ok: bool, resultado_o_None).
    """
    try:
        resultado = func(*args, **kwargs)
        if on_success_msg:
            flash(on_success_msg, "success")
        return True, resultado
    except mysql.connector.Error as err:
        flash(_mensaje_para_error(err), "danger")
        return False, None
