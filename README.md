# Sistema de Gestión de Reservas y Estadías — Cadena Hotelera

Proyecto grupal — curso **Base de Datos I** (UNMSM FISI). Base de datos relacional en MySQL 8.0
(`hotel_db`) con funciones, procedimientos almacenados, vistas, triggers y roles, más una interfaz
web mínima (Flask) que la invoca directamente, sin reimplementar lógica de negocio en la
aplicación.

## Caso de negocio

Gestión de reservas y estadías para una cadena de hoteles (Hotel San Marcos: Lima, Ica, Arequipa,
Cusco): reserva → confirmación de pago → check-in → consumo de servicios / daños → salida
individual o check-out → cuenta por cobrar → pago. Detalle completo en
[`Documentacion/01_Entregable1_Diseno_BD.md`](Documentacion/01_Entregable1_Diseno_BD.md) y en
[`Especificacion_MVP.md`](Especificacion_MVP.md).

## Stack técnico

| Componente | Elección |
|---|---|
| Base de datos | MySQL 8.0+, `utf8mb4` |
| Backend | Flask 3.x (Python), organizado en blueprints por módulo |
| Conector | `mysql-connector-python` |
| Frontend | HTML + Jinja2, sin frameworks JS |
| Config | `python-dotenv` (`.env`, no versionado) |

## Mapa del repositorio

```
Scripts/            9 scripts SQL, ejecutar en orden (01 → 09) para crear hotel_db
Diagramas/           Modelo conceptual, lógico, físico y diagrama de secuencia (PlantUML + PNG)
Documentacion/        Entregables formales de la directiva del curso (Fases I y II) + guion de video
Especificacion_MVP.md Casos de uso detallados del MVP y su mapeo a procedimientos/vistas
mvp_app/              Aplicación Flask (interfaz que invoca la base de datos)
```

| Si necesitas... | Ve a... |
|---|---|
| Diseño conceptual/lógico/físico y requisitos | `Documentacion/01_Entregable1_Diseno_BD.md` |
| Catálogo de funciones/procedimientos/vistas/triggers/roles y cláusulas SQL usadas | `Documentacion/02_Entregable2_Implementacion_SQL.md` |
| Guion para el video de sustentación | `Documentacion/03_Guion_Video_Demo.md` |
| Por qué no hay migración a un segundo SGBD | `Documentacion/04_Nota_Alcance_Fase3.md` |
| Auditoría UX/UI del MVP Flask (hallazgos, quick wins, plan por fases) | `Documentacion/05_Auditoria_UX_UI.md` (resumen) / [reporte interactivo](https://claude.ai/code/artifact/9de33166-8c52-4b67-93f0-2dcab3eb6783) |
| Casos de uso uno por uno (actor, flujo, SP/vista relacionado) | `Especificacion_MVP.md` |
| Checklist de pruebas end-to-end ya ejecutadas | `mvp_app/tests/test_flujo_manual.md` |
| Diagramas de navegación (pantallas, antes/después del rediseño de usabilidad) | `Diagramas/05_Flujo_Navegacion_Reservas.puml`, `06_..._Estadia.puml`, `07_..._Caja.puml` |
| Qué consulta SQL dispara cada pantalla/botón | `Documentacion/06_Mapa_Pantallas_SQL.md` |

## Puesta en marcha

### 1. Base de datos

Con un servidor MySQL 8.0+ corriendo localmente, ejecutar en orden (cliente de tu preferencia:
MySQL Workbench, `mysql` CLI, etc.):

```
Scripts/01_Creacion_Tablas.sql
Scripts/02_Reglas_Integridad.sql
Scripts/03_Funciones.sql
Scripts/04_Procedimientos.sql
Scripts/05_Vistas.sql
Scripts/06_Triggers.sql
Scripts/07_Roles_Permisos.sql   (opcional: requiere privilegios de administración)
Scripts/08_Carga_Datos.sql
Scripts/09_Consultas_MVP.sql    (opcional: solo consultas de verificación)
```

### 2. Aplicación (Windows / PowerShell)

```powershell
cd mvp_app
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
Copy-Item .env.example .env   # editar con tus credenciales reales de MySQL
python run.py
```

Abrir `http://127.0.0.1:5000/login`.

### 3. Credenciales de demo

El login es real (usuario + contraseña, `werkzeug.security` con hash `scrypt`), respaldado por la
tabla `usuario` (subtipo 1:1 de `empleado`: solo los empleados que necesitan acceso tienen fila
ahí, con su rol y su alcance ya fijos). Usuarios cargados por `08_Carga_Datos.sql`:

| username | Contraseña | Nombre | Rol | Alcance |
|---|---|---|---|---|
| `mtorres` | `demo1234` | María Torres Quispe | RECEPCION | Hotel San Marcos Lima |
| `grojas` | `demo1234` | Gabriela Rojas Injante | CAJA | Hotel San Marcos Lima |
| `rhuanca` | `demo1234` | Roberto Huanca Flores | GERENCIA | Hotel San Marcos Lima |
| `lparedes` | `demo1234` | Lissette Paredes Cano | ADMINISTRADOR | General (toda la cadena) |

`lparedes` es la administradora general: puede crear hoteles nuevos (cada uno nace con su propio
usuario administrador, generado automáticamente) y gestionar cualquier hotel de la cadena. Un
administrador de un solo hotel (como el que se auto-crea al dar de alta un hotel) solo ve y
gestiona los datos de su propio hotel.

## Mapeo a los criterios de evaluación

| # | Criterio | Cómo lo cubre el proyecto |
|---|---|---|
| 1 | Logro del producto planificado | Flujo end-to-end completo (reserva → pago → check-in → consumo/daño → salida → cuenta → pago) funcionando sobre datos reales; ver checklist en `mvp_app/tests/test_flujo_manual.md`. |
| 2 | Aplicación de herramientas para su desarrollo | 27 tablas normalizadas con FK/CHECK/UNIQUE, 6 funciones, 14 procedimientos, 14 vistas, 23 triggers, 4 roles MySQL, y una interfaz Flask que los invoca explícitamente (`CALL sp_...`, `SELECT FROM vw_...`). |
| 3 | Nivel de complejidad del proyecto (alcances) | Supertype/subtype persona natural/jurídica, separación cliente/huésped, cupos sin identificar en la asignación de huéspedes (huésped no es "genérico": la incertidumbre de "quién" vive en la reserva, nunca en la ocupación real), asignación de huéspedes por habitación vs. check-in real, autodetección de tarifa por fecha con reglas de especificidad, salida individual por huésped, cuentas con abonos parciales. |
| 4 | Cumplimiento de tareas y avances por fase | Los 9 scripts numerados corresponden 1:1 a las fases del curso (creación → integridad → funciones → procedimientos → vistas → triggers → roles → carga → consultas). Fase III (migración) excluida explícitamente por indicación del profesor — ver `Documentacion/04_Nota_Alcance_Fase3.md`. |
| 5 | Presentación y exposición | Guion de video en `Documentacion/03_Guion_Video_Demo.md`, calcado del diagrama de secuencia `Diagramas/04_Flujo_MVP_Secuencia.puml`. |
| 6 | Aportes, recomendaciones, experiencias | Decisiones de diseño documentadas y justificadas en `Documentacion/01_Entregable1_Diseno_BD.md` y en los comentarios de los propios scripts SQL. |
| 7 | Respuestas a consultas finales | Toda la base de datos, diagramas y documentación están versionados y organizados por tema para resolver preguntas puntuales durante la sustentación. |

## Reglas de diseño que se mantienen en todo el proyecto

- La aplicación **invoca**, no reimplementa: cálculo de IGV, disponibilidad, autodetección de
  tarifa, capacidad máxima de huéspedes y saldo de cuentas viven exclusivamente en la base de
  datos (funciones/procedimientos/triggers).
- Los errores de negocio (`SIGNAL SQLSTATE '45000'`) se muestran en la interfaz tal cual los
  redacta el procedimiento, sin reinterpretarlos.
- Todo acceso a datos desde la app usa consultas parametrizadas (`%s`), nunca concatenación de
  cadenas con datos de usuario.
