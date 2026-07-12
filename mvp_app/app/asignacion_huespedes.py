from flask import url_for

from app.db import query


def construir_pasos_reserva(id_reserva, actual):
    """Stepper del flujo completo de una reserva, desde la cabecera hasta el
    check-in (que vive en el blueprint estadia, no en reservas). El status
    de cada paso es puramente ordinal respecto a `actual` -- no verifica si
    ese paso está realmente completo en la BD (ej. si ya se pagó), solo
    dónde está el usuario parado en la secuencia. La navegación real sigue
    sin ser lineal: cualquier paso conserva su link y se puede visitar
    fuera de orden."""
    definicion = [
        ("detalle", "Detalle", url_for("reservas.detalle", id_reserva=id_reserva)),
        ("pago", "Pago", url_for("reservas.pago", id_reserva=id_reserva)),
        ("preasignar", "Asignación de huéspedes", url_for("reservas.preasignar", id_reserva=id_reserva)),
        ("checkin", "Check-in", url_for("estadia.checkin_reserva", id_reserva=id_reserva)),
    ]
    orden = [clave for clave, _, _ in definicion]
    idx_actual = orden.index(actual) if actual in orden else -1

    pasos = [
        {"label": "Reservas", "url": url_for("reservas.listado"), "status": "done"},
        {"label": "Cabecera", "url": None, "status": "done"},
    ]
    for i, (clave, label, url) in enumerate(definicion):
        if i < idx_actual:
            status = "done"
        elif i == idx_actual:
            status = "current"
        else:
            status = "upcoming"
        pasos.append({"label": label, "url": None if clave == actual else url, "status": status})
    return pasos


def construir_grid_reserva(id_reserva, con_estado_estadia=False):
    """
    Arma la tabla de asignación de huéspedes de una reserva: por cada línea
    (tipo de habitación x cantidad) la subdivide en "habitaciones" de
    capacidad_base cupos cada una, rellenando con cupos vacíos hasta
    completar la capacidad total de la línea.

    La subdivisión en habitaciones NO se guarda en la BD (detalle_huesped_reserva
    no tiene una columna para eso): se calcula por posición, ordenando los
    cupos ya creados por id_detalle_huesped (PK autoincremental, orden
    estable). Si se borra un cupo intermedio, los cupos siguientes se
    "recompactan" a la habitación anterior -- comportamiento aceptado a
    cambio de no tocar el esquema.

    Si con_estado_estadia=True, además anota cada cupo identificado con su
    estado de check-in (vía huesped_alojamiento.id_detalle_huesped, que
    referencia el mismo cupo con el que se hizo el check-in).

    Devuelve una lista de líneas:
    [{id_detalle_reserva, id_tipo_habitacion, tipo_habitacion, capacidad_base,
      cantidad_habitaciones,
      habitaciones: [{n, slots: [{id_detalle_huesped, id_huesped, nombre,
                                   numero_documento, es_titular, estadia}],
                       tiene_titular, tiene_ocupantes, checkin_hecho, id_alojamiento}]}]
    """
    lineas_rows = query(
        """
        SELECT rd.id_detalle_reserva, rd.cantidad_habitaciones,
               th.id_tipo_habitacion, th.nombre AS tipo_habitacion, th.capacidad_base
        FROM reserva_detalle rd
        JOIN tipo_habitacion th ON th.id_tipo_habitacion = rd.id_tipo_habitacion
        WHERE rd.id_reserva = %s
        ORDER BY rd.id_detalle_reserva
        """,
        (id_reserva,),
    )
    if not lineas_rows:
        return []

    ids_detalle_reserva = tuple(l["id_detalle_reserva"] for l in lineas_rows)
    marcadores = ",".join(["%s"] * len(ids_detalle_reserva))

    cupos_rows = query(
        f"""
        SELECT dhr.id_detalle_huesped, dhr.id_detalle_reserva, dhr.id_huesped, dhr.es_titular,
               pn.nombres, pn.apellidos, pn.numero_documento
        FROM detalle_huesped_reserva dhr
        LEFT JOIN huesped h ON h.id_huesped = dhr.id_huesped
        LEFT JOIN persona_natural pn ON pn.id_persona = h.id_persona
        WHERE dhr.id_detalle_reserva IN ({marcadores})
        ORDER BY dhr.id_detalle_huesped ASC
        """,
        ids_detalle_reserva,
    )

    estadia_por_cupo = {}
    if con_estado_estadia and cupos_rows:
        ids_detalle_huesped = tuple(c["id_detalle_huesped"] for c in cupos_rows)
        marcadores2 = ",".join(["%s"] * len(ids_detalle_huesped))
        estadia_rows = query(
            f"""
            SELECT ha.id_detalle_huesped, ha.id_alojamiento, a.estado AS estado_alojamiento,
                   hab.numero AS numero_habitacion, hab.piso, ha.fecha_salida_real
            FROM huesped_alojamiento ha
            JOIN alojamiento a ON a.id_alojamiento = ha.id_alojamiento
            JOIN habitacion hab ON hab.id_habitacion = a.id_habitacion
            WHERE ha.id_detalle_huesped IN ({marcadores2})
            """,
            ids_detalle_huesped,
        )
        estadia_por_cupo = {e["id_detalle_huesped"]: e for e in estadia_rows}

    cupos_por_linea = {}
    for c in cupos_rows:
        cupos_por_linea.setdefault(c["id_detalle_reserva"], []).append(c)

    lineas = []
    for l in lineas_rows:
        capacidad = l["capacidad_base"]
        cupos = cupos_por_linea.get(l["id_detalle_reserva"], [])

        habitaciones = []
        for n in range(l["cantidad_habitaciones"]):
            slots = []
            for pos in range(capacidad):
                idx = n * capacidad + pos
                if idx < len(cupos):
                    c = cupos[idx]
                    slots.append(
                        {
                            "id_detalle_huesped": c["id_detalle_huesped"],
                            "id_huesped": c["id_huesped"],
                            "nombre": f'{c["nombres"]} {c["apellidos"]}' if c["nombres"] else None,
                            "numero_documento": c["numero_documento"],
                            "es_titular": bool(c["es_titular"]),
                            "estadia": estadia_por_cupo.get(c["id_detalle_huesped"]),
                        }
                    )
                else:
                    slots.append(
                        {
                            "id_detalle_huesped": None,
                            "id_huesped": None,
                            "nombre": None,
                            "numero_documento": None,
                            "es_titular": False,
                            "estadia": None,
                        }
                    )
            estadias_habitacion = [s["estadia"] for s in slots if s["estadia"]]
            habitaciones.append(
                {
                    "n": n + 1,
                    "slots": slots,
                    "tiene_titular": any(s["es_titular"] for s in slots),
                    "tiene_ocupantes": any(s["id_huesped"] for s in slots),
                    "checkin_hecho": bool(estadias_habitacion),
                    "id_alojamiento": estadias_habitacion[0]["id_alojamiento"] if estadias_habitacion else None,
                }
            )

        lineas.append(
            {
                "id_detalle_reserva": l["id_detalle_reserva"],
                "id_tipo_habitacion": l["id_tipo_habitacion"],
                "tipo_habitacion": l["tipo_habitacion"],
                "capacidad_base": capacidad,
                "cantidad_habitaciones": l["cantidad_habitaciones"],
                "habitaciones": habitaciones,
            }
        )

    return lineas
