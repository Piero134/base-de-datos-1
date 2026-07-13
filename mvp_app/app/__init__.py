from flask import Flask, render_template

from app.badges import badge_class
from app.config import Config


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    app.jinja_env.filters["badge_class"] = badge_class

    from app.auth.routes import bp as auth_bp
    from app.disponibilidad.routes import bp as disponibilidad_bp
    from app.reservas.routes import bp as reservas_bp
    from app.estadia.routes import bp as estadia_bp
    from app.caja.routes import bp as caja_bp
    from app.reportes.routes import bp as reportes_bp
    from app.administracion.routes import bp as administracion_bp, habitaciones as vista_habitaciones

    app.register_blueprint(auth_bp)
    app.register_blueprint(disponibilidad_bp)
    app.register_blueprint(reservas_bp)
    app.register_blueprint(estadia_bp)
    app.register_blueprint(caja_bp)
    app.register_blueprint(reportes_bp)
    app.register_blueprint(administracion_bp)

    # Recepción usa la misma pantalla/lógica que administracion.habitaciones
    # (ver /admin/habitaciones) pero sin el prefijo /admin: para su rol no es
    # una pantalla "de administración", es su vista normal de habitaciones.
    app.add_url_rule(
        "/habitaciones", endpoint="habitaciones_recepcion", view_func=vista_habitaciones, methods=["GET", "POST"]
    )

    @app.errorhandler(404)
    def not_found(error):
        return render_template("errors/404.html"), 404

    @app.errorhandler(500)
    def server_error(error):
        return render_template("errors/500.html"), 500

    return app
