import mysql.connector
from flask import current_app


def get_connection():
    cfg = current_app.config
    return mysql.connector.connect(
        host=cfg["DB_HOST"],
        port=cfg["DB_PORT"],
        database=cfg["DB_NAME"],
        user=cfg["DB_USER"],
        password=cfg["DB_PASSWORD"],
    )


def call_procedure(proc_name, params=()):
    """
    Invoca un procedimiento almacenado (CALL sp_...).

    params: tupla posicional en el orden exacto de la firma del SP. Para
    cada parámetro OUT, pasar un valor de relleno (0, None, etc.) — el
    conector mysql-connector-python lo reemplaza por el valor real de
    salida al terminar la llamada.

    Devuelve (result_sets, out_values):
      - result_sets: lista de listas de dict, una por cada SELECT que el
        SP haya producido internamente (ej. sp_resumen_ocupacion_hotel).
      - out_values: la tupla completa devuelta por cursor.callproc(), con
        los parámetros OUT ya resueltos en su misma posición.
    """
    # OJO: se usa un cursor NO dictionary aquí a propósito. Con
    # cursor(dictionary=True), cursor.callproc() de mysql-connector-python
    # devuelve un dict {"proc_arg1": ..., "proc_arg2": ...} en vez de la
    # tupla posicional documentada, lo que rompe la resolución de los
    # parámetros OUT (que se leen por índice). Los result sets sí se
    # convierten a dict manualmente más abajo, para que las plantillas
    # puedan seguir usando row.columna.
    conn = get_connection()
    cur = conn.cursor()
    try:
        out_values = cur.callproc(proc_name, params)
        result_sets = []
        for rs in cur.stored_results():
            columnas = [d[0] for d in rs.description]
            result_sets.append([dict(zip(columnas, fila)) for fila in rs.fetchall()])
        conn.commit()
        return result_sets, out_values
    except mysql.connector.Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def query(sql, params=None):
    """SELECT parametrizado (vistas, catálogos). Nunca usar con f-strings."""
    conn = get_connection()
    cur = conn.cursor(dictionary=True)
    try:
        cur.execute(sql, params or ())
        return cur.fetchall()
    finally:
        cur.close()
        conn.close()


def execute(sql, params=None):
    """INSERT/UPDATE directo parametrizado (altas de catálogo/maestros que
    no tienen procedimiento asociado). Devuelve el lastrowid."""
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql, params or ())
        conn.commit()
        return cur.lastrowid
    except mysql.connector.Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def call_procedures_en_transaccion(fabrica_llamadas):
    """
    Ejecuta varias llamadas CALL sp_... en una sola conexión/transacción,
    mismo espíritu que execute_transaction pero para procedimientos
    almacenados -- útil cuando una llamada necesita el OUT de la anterior
    (ej. crear un alojamiento y recién con su id_alojamiento adjuntar
    varios huéspedes, todo o nada).

    fabrica_llamadas: función que recibe un callable `ejecutar(proc_name,
    params) -> out_values` y orquesta las llamadas que necesite (puede usar
    el resultado de una para construir los params de la siguiente). Se hace
    commit solo si fabrica_llamadas termina sin lanzar; si lanza
    mysql.connector.Error, se hace rollback completo y se re-lanza.

    Devuelve lo que devuelva fabrica_llamadas.
    """
    conn = get_connection()
    cur = conn.cursor()

    def ejecutar(proc_name, params):
        out_values = cur.callproc(proc_name, params)
        for rs in cur.stored_results():
            rs.fetchall()
        return out_values

    try:
        resultado = fabrica_llamadas(ejecutar)
        conn.commit()
        return resultado
    except mysql.connector.Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


def execute_transaction(statements):
    """
    Ejecuta varias sentencias INSERT/UPDATE dentro de una sola transacción.
    statements: lista de tuplas (sql, params). Devuelve la lista de
    lastrowid de cada sentencia (útil para encadenar FKs, ej. persona ->
    persona_natural -> cliente).
    """
    conn = get_connection()
    cur = conn.cursor()
    lastrowids = []
    try:
        for sql, params in statements:
            cur.execute(sql, params or ())
            lastrowids.append(cur.lastrowid)
        conn.commit()
        return lastrowids
    except mysql.connector.Error:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
