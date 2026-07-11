# Nota de alcance — Fase III (Migración a un segundo SGBD)

**Fecha:** 2026-07-07

La directiva del proyecto grupal (UNMSM FISI, Base de Datos I) contempla en su Fase III la
migración de la base de datos a un segundo SGBD (por ejemplo, de MySQL a PostgreSQL), junto con un
video de sustentación de 10 minutos.

**Esta migración fue explícitamente excluida del alcance de este proyecto por indicación directa
del profesor del curso.** Se deja esta nota para que quede constancia expresa de la decisión y no
se interprete, al revisar el repositorio o durante la sustentación, como un entregable omitido por
descuido.

En consecuencia:

- No existen scripts adaptados a un segundo motor (ej. PostgreSQL/PL-pgSQL) en este repositorio.
- No se documentan diferencias de dialecto SQL ni un proceso de migración de datos.
- El video de sustentación (`Documentacion/03_Guion_Video_Demo.md`) se mantiene como entregable,
  cubriendo únicamente el diseño, la implementación SQL y la demostración funcional del sistema
  sobre MySQL — sin el bloque de migración que originalmente contemplaba la Fase III.

El resto del proyecto (Fases I y II: diseño conceptual/lógico/físico, DDL, integridad referencial,
funciones, procedimientos almacenados, vistas, triggers, roles, y una interfaz funcional que los
invoca) está completo y verificado end-to-end contra datos reales, tal como exige la rúbrica de
evaluación para esas dos fases.
