ESTADO_BADGE = {
    # habitacion.estado
    "DISPONIBLE": "badge-good",
    "RESERVADA": "badge-warning",
    "OCUPADA": "badge-danger",
    "LIMPIEZA": "badge-warning",
    # estado_reserva.nombre
    "PENDIENTE": "badge-warning",
    "CONFIRMADA": "badge-info",
    "CANCELADA": "badge-danger",
    "NO_SHOW": "badge-danger",
    "FINALIZADA": "badge-good",
    # alojamiento.estado
    "ACTIVO": "badge-info",
    "FINALIZADO": "badge-good",
    "CANCELADO": "badge-danger",
    # danio.estado
    "COBRADO": "badge-good",
    "DISPENSADO": "badge-neutral",
    # cuenta_cobrar.estado
    "PAGADA": "badge-good",
}


def badge_class(estado):
    """Filtro Jinja: mapea un estado de negocio (ENUM de la BD) a la clase
    CSS semántica correspondiente (.badge-good/.badge-warning/.badge-danger/
    .badge-info/.badge-neutral), para que las tablas muestren el estado como
    color en vez de solo texto plano."""
    return ESTADO_BADGE.get(estado, "badge-neutral")
