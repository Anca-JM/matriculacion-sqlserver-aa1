/* ADMINISTRACION DE BASES DE DATOS - Actividad Autonoma U1-T2
   Implementacion de vistas, funciones, procedimientos y triggers en el sistema de gestion de matriculas.
   Motor: SQL Server 2022 Express (localhost\SQLEXPRESS), ejecutado en SSMS 22   Autor: Marquez Villarroel Jafet Eliut
   Orden: 0) base y tablas  1) vistas  2) funciones  3) procedimientos  4) triggers  5) pruebas de exito y de error  6) innovacion */

/* ======================================================================
   0. BASE DE DATOS, TABLAS DE LA ACTIVIDAD ANTERIOR, TABLAS NUEVAS (Auditoria_Matriculas, Historial_Cupos) E INDICES
   ====================================================================== */

/* =====================================================================
   ADMINISTRACION DE BASES DE DATOS - Actividad Autonoma U1-T2
   Vistas, funciones, procedimientos almacenados y triggers en el
   sistema de gestion de matriculas.
   Motor: SQL Server 2022 Express (localhost\SQLEXPRESS), SSMS 22
   Bloque 0: base de datos, tablas de la actividad anterior y tablas nuevas
   ===================================================================== */
USE master;
GO
IF DB_ID('MatriculaDB_AA2') IS NOT NULL
BEGIN
    ALTER DATABASE MatriculaDB_AA2 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE MatriculaDB_AA2;
END
GO
CREATE DATABASE MatriculaDB_AA2;
GO
USE MatriculaDB_AA2;
GO

/* ---------- Tablas base (actividad anterior) ---------- */
CREATE TABLE dbo.Estudiantes (
    estudiante_id INT IDENTITY(1,1) CONSTRAINT PK_Estudiantes PRIMARY KEY,
    nombre        NVARCHAR(100) NOT NULL,
    cedula        CHAR(10)      NOT NULL CONSTRAINT UQ_Estudiantes_cedula UNIQUE,
    facultad      NVARCHAR(60)  NOT NULL
);

CREATE TABLE dbo.Asignaturas (
    asignatura_id     INT IDENTITY(1,1) CONSTRAINT PK_Asignaturas PRIMARY KEY,
    nombre_materia    NVARCHAR(80) NOT NULL CONSTRAINT UQ_Asignaturas_nombre UNIQUE,
    docente           NVARCHAR(80) NOT NULL,
    cupos_disponibles INT          NOT NULL CONSTRAINT CK_cupos_no_negativos CHECK (cupos_disponibles >= 0)
);

CREATE TABLE dbo.Registros_Matricula (
    registro_id    INT IDENTITY(1,1) CONSTRAINT PK_Registros PRIMARY KEY,
    estudiante_id  INT          NOT NULL CONSTRAINT FK_Reg_Estudiante FOREIGN KEY REFERENCES dbo.Estudiantes(estudiante_id),
    asignatura_id  INT          NOT NULL CONSTRAINT FK_Reg_Asignatura FOREIGN KEY REFERENCES dbo.Asignaturas(asignatura_id),
    fecha_registro DATETIME2(0) NOT NULL CONSTRAINT DF_Reg_fecha DEFAULT SYSDATETIME(),
    estado         VARCHAR(10)  NOT NULL CONSTRAINT CK_Reg_estado CHECK (estado IN ('CONFIRMADA','PENDIENTE')),
    CONSTRAINT UQ_Reg_estudiante_materia UNIQUE (estudiante_id, asignatura_id)
);
CREATE NONCLUSTERED INDEX IX_Reg_asignatura ON dbo.Registros_Matricula (asignatura_id) INCLUDE (estudiante_id, estado);
GO

/* ---------- Tablas nuevas de esta actividad ---------- */
-- Bitacora de matriculas y retiros. registro_id NO es llave foranea: el registro de un
-- retiro se borra, pero su rastro de auditoria debe conservarse.
CREATE TABLE dbo.Auditoria_Matriculas (
    auditoria_id  INT IDENTITY(1,1) CONSTRAINT PK_Auditoria PRIMARY KEY,
    registro_id   INT           NOT NULL,
    accion        NVARCHAR(20)  NOT NULL CONSTRAINT CK_Auditoria_accion CHECK (accion IN (N'MATRICULACIÓN', N'RETIRO')),
    usuario       SYSNAME       NOT NULL CONSTRAINT DF_Auditoria_usuario DEFAULT SUSER_SNAME(),
    fecha         DATETIME2(0)  NOT NULL CONSTRAINT DF_Auditoria_fecha DEFAULT SYSDATETIME(),
    estudiante_id INT           NULL,      -- datos extra para que la bitacora sea detallada
    asignatura_id INT           NULL,
    equipo        NVARCHAR(128) NULL CONSTRAINT DF_Auditoria_equipo DEFAULT HOST_NAME()
);

CREATE TABLE dbo.Historial_Cupos (
    historial_id  INT IDENTITY(1,1) CONSTRAINT PK_Historial PRIMARY KEY,
    asignatura_id INT          NOT NULL CONSTRAINT FK_Historial_Asignatura FOREIGN KEY REFERENCES dbo.Asignaturas(asignatura_id),
    cupo_anterior INT          NOT NULL,
    cupo_nuevo    INT          NOT NULL,
    fecha_cambio  DATETIME2(0) NOT NULL CONSTRAINT DF_Historial_fecha DEFAULT SYSDATETIME(),
    usuario       SYSNAME      NOT NULL CONSTRAINT DF_Historial_usuario DEFAULT SUSER_SNAME()
);
GO

/* ---------- Innovacion: indices para las consultas de auditoria e historial ---------- */
-- La bitacora crece con cada matricula; consultar "que hizo un estudiante" sin indice obliga a leer toda la tabla.
CREATE NONCLUSTERED INDEX IX_Auditoria_estudiante ON dbo.Auditoria_Matriculas (estudiante_id, fecha) INCLUDE (accion, registro_id, asignatura_id);
CREATE NONCLUSTERED INDEX IX_Historial_asignatura ON dbo.Historial_Cupos (asignatura_id, fecha_cambio) INCLUDE (cupo_anterior, cupo_nuevo);
GO
/* ---------- Datos de prueba (ficticios), cargados ANTES de crear los triggers ---------- */
INSERT INTO dbo.Estudiantes (nombre, cedula, facultad) VALUES
 (N'Estudiante 1', '0600000001', N'Ingeniería'),
 (N'Estudiante 2', '0600000002', N'Ingeniería'),
 (N'Estudiante 3', '0600000003', N'Ingeniería'),
 (N'Estudiante 4', '0600000004', N'Ciencias de la Salud'),
 (N'Estudiante 5', '0600000005', N'Ciencias Políticas'),
 (N'Estudiante 6', '0600000006', N'Ingeniería');

INSERT INTO dbo.Asignaturas (nombre_materia, docente, cupos_disponibles) VALUES
 (N'Administración de Bases de Datos', N'Docente A', 5),
 (N'Machine Learning 1',               N'Docente B', 3),
 (N'Metaheurísticas',                  N'Docente C', 2),
 (N'Métodos Numéricos',                N'Docente D', 4),
 (N'Analítica de Datos',               N'Docente A', 6),
 (N'Inglés B1',                        N'Docente E', 10),
 (N'Estadística',                      N'Docente B', 0),    -- materia sin cupos (para las pruebas de error)
 (N'Sistemas Operativos',              N'Docente C', 8);

-- Matriculas iniciales coherentes con los cupos (la materia 7 tiene 3 inscritos y 0 cupos)
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES
 (2,1,'CONFIRMADA'), (3,1,'CONFIRMADA'), (2,2,'CONFIRMADA'),
 (4,5,'CONFIRMADA'), (5,5,'CONFIRMADA'),
 (2,7,'CONFIRMADA'), (3,7,'CONFIRMADA'), (4,7,'CONFIRMADA');
GO

/* ---------- Verificacion del bloque ---------- */
SET NOCOUNT ON;
SELECT t.name AS tabla, SUM(p.rows) AS filas
FROM sys.tables t JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
GROUP BY t.name ORDER BY t.name;
SELECT name AS indice_creado, OBJECT_NAME(object_id) AS tabla FROM sys.indexes WHERE name IN ('IX_Reg_asignatura','IX_Auditoria_estudiante','IX_Historial_asignatura');
GO

/* ======================================================================
   1. VISTAS
   ====================================================================== */

/* =====================================================================
   Bloque 1: VISTAS
   ===================================================================== */
USE MatriculaDB_AA2;
GO

/* Vista_OfertaAcademica: materias con cupos (> 0), docente y porcentaje de ocupacion.
   Ocupacion % = inscritos / (inscritos + cupos libres) * 100  (la capacidad total es inscritos + libres). */
CREATE OR ALTER VIEW dbo.Vista_OfertaAcademica
AS
SELECT  a.asignatura_id,
        a.nombre_materia          AS materia,
        a.docente                 AS docente,
        a.cupos_disponibles       AS cupos_libres,
        ISNULL(i.inscritos, 0)    AS inscritos,
        CAST(100.0 * ISNULL(i.inscritos, 0)
             / NULLIF(ISNULL(i.inscritos, 0) + a.cupos_disponibles, 0) AS DECIMAL(5,2)) AS porcentaje_ocupacion
FROM    dbo.Asignaturas a
LEFT JOIN (SELECT asignatura_id, COUNT(*) AS inscritos
           FROM dbo.Registros_Matricula
           GROUP BY asignatura_id) i ON i.asignatura_id = a.asignatura_id
WHERE   a.cupos_disponibles > 0;
GO
/* Vista_DetalleMatricula: consolida estudiante, facultad, materia y fecha (las 3 tablas principales). */
CREATE OR ALTER VIEW dbo.Vista_DetalleMatricula
AS
SELECT  r.registro_id,
        e.estudiante_id,
        e.nombre          AS estudiante,
        e.facultad        AS facultad,
        a.asignatura_id,
        a.nombre_materia  AS materia,
        a.docente         AS docente,
        r.fecha_registro  AS fecha_registro,
        r.estado          AS estado
FROM    dbo.Registros_Matricula r
JOIN    dbo.Estudiantes e ON e.estudiante_id = r.estudiante_id
JOIN    dbo.Asignaturas a ON a.asignatura_id = r.asignatura_id;
GO

/* Vista_EstudiantesSaturados: estudiantes con MAS de 5 materias matriculadas (para Bienestar Estudiantil). */
CREATE OR ALTER VIEW dbo.Vista_EstudiantesSaturados
AS
SELECT  e.estudiante_id,
        e.nombre            AS estudiante,
        e.facultad          AS facultad,
        COUNT(r.registro_id) AS materias_matriculadas
FROM    dbo.Estudiantes e
JOIN    dbo.Registros_Matricula r ON r.estudiante_id = e.estudiante_id
GROUP BY e.estudiante_id, e.nombre, e.facultad
HAVING  COUNT(r.registro_id) > 5;
GO

/* ---------- Verificacion del bloque ---------- */
SELECT name AS vista_creada, create_date FROM sys.views WHERE is_ms_shipped = 0 ORDER BY name;
GO

/* ======================================================================
   2. FUNCIONES
   ====================================================================== */

/* =====================================================================
   Bloque 2: FUNCIONES
   ===================================================================== */
USE MatriculaDB_AA2;
GO

/* fn_CalcularCostoMatricula (escalar): $15 por cada materia en la que el estudiante esta inscrito. */
CREATE OR ALTER FUNCTION dbo.fn_CalcularCostoMatricula (@estudiante_id INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @costo_por_materia DECIMAL(10,2) = 15.00;   -- regla de negocio en un solo lugar
    DECLARE @materias INT;

    SELECT @materias = COUNT(*)
    FROM   dbo.Registros_Matricula
    WHERE  estudiante_id = @estudiante_id;

    RETURN @materias * @costo_por_materia;
END;
GO

/* fn_VerificarDisponibilidad (escalar): 1 si la asignatura tiene cupos, 0 si no (o si no existe). */
CREATE OR ALTER FUNCTION dbo.fn_VerificarDisponibilidad (@asignatura_id INT)
RETURNS BIT
AS
BEGIN
    DECLARE @hay BIT = 0;

    IF EXISTS (SELECT 1 FROM dbo.Asignaturas
               WHERE asignatura_id = @asignatura_id AND cupos_disponibles > 0)
        SET @hay = 1;

    RETURN @hay;
END;
GO

/* fn_ListaClase (de tabla, en linea): nombre y cedula de los estudiantes inscritos en una asignatura. */
CREATE OR ALTER FUNCTION dbo.fn_ListaClase (@asignatura_id INT)
RETURNS TABLE
AS
RETURN
(
    SELECT  e.nombre AS estudiante,
            e.cedula AS cedula
    FROM    dbo.Registros_Matricula r
    JOIN    dbo.Estudiantes e ON e.estudiante_id = r.estudiante_id
    WHERE   r.asignatura_id = @asignatura_id
);
GO

/* ---------- Verificacion del bloque ---------- */
SELECT name AS funcion_creada,
       CASE type WHEN 'FN' THEN 'escalar' WHEN 'IF' THEN 'de tabla (en linea)' END AS tipo, create_date
FROM sys.objects WHERE type IN ('FN','IF') AND is_ms_shipped = 0 ORDER BY name;
GO

/* ======================================================================
   3. PROCEDIMIENTOS ALMACENADOS
   ====================================================================== */

/* =====================================================================
   Bloque 3: PROCEDIMIENTOS ALMACENADOS
   Todos validan parametros, trabajan dentro de una transaccion (todo o nada)
   y manejan errores con TRY/CATCH.
   ===================================================================== */
USE MatriculaDB_AA2;
GO

/* sp_InscribirAsignatura: verifica disponibilidad, inserta el registro y resta el cupo en un solo proceso. */
CREATE OR ALTER PROCEDURE dbo.sp_InscribirAsignatura
    @estudiante_id INT,
    @asignatura_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;               -- cualquier error en ejecucion revierte toda la transaccion

    BEGIN TRY
        -- 1) Validacion de parametros
        IF NOT EXISTS (SELECT 1 FROM dbo.Estudiantes WHERE estudiante_id = @estudiante_id)
            THROW 50001, 'El estudiante indicado no existe.', 1;
        IF NOT EXISTS (SELECT 1 FROM dbo.Asignaturas WHERE asignatura_id = @asignatura_id)
            THROW 50002, 'La asignatura indicada no existe.', 1;

        BEGIN TRANSACTION;

            -- 2) Lee el cupo con UPDLOCK: quien lo lee lo reserva, el siguiente espera (evita vender el mismo cupo dos veces)
            DECLARE @cupos INT;
            SELECT @cupos = cupos_disponibles
            FROM   dbo.Asignaturas WITH (UPDLOCK, ROWLOCK)
            WHERE  asignatura_id = @asignatura_id;

            IF @cupos <= 0
                THROW 50003, 'No hay cupos disponibles en la asignatura.', 1;

            IF EXISTS (SELECT 1 FROM dbo.Registros_Matricula
                       WHERE estudiante_id = @estudiante_id AND asignatura_id = @asignatura_id)
                THROW 50004, 'El estudiante ya esta matriculado en esta asignatura.', 1;

            -- 3) Inserta la matricula y resta el cupo (el trigger de auditoria registra el INSERT)
            INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
            VALUES (@estudiante_id, @asignatura_id, 'CONFIRMADA');

            UPDATE dbo.Asignaturas
            SET    cupos_disponibles = cupos_disponibles - 1
            WHERE  asignatura_id = @asignatura_id;

        COMMIT TRANSACTION;

        SELECT 'OK: matricula confirmada' AS resultado,
               @estudiante_id AS estudiante_id, @asignatura_id AS asignatura_id,
               @cupos - 1 AS cupos_restantes;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;                       -- se vuelve a lanzar el error original para quien llama
    END CATCH
END;
GO

/* sp_RetirarAsignatura: elimina el registro, devuelve el cupo y registra la accion en la auditoria. */
CREATE OR ALTER PROCEDURE dbo.sp_RetirarAsignatura
    @estudiante_id INT,
    @asignatura_id INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

            DECLARE @registro_id INT;
            SELECT @registro_id = registro_id
            FROM   dbo.Registros_Matricula WITH (UPDLOCK)
            WHERE  estudiante_id = @estudiante_id AND asignatura_id = @asignatura_id;

            IF @registro_id IS NULL
                THROW 50005, 'El estudiante no esta matriculado en esa asignatura.', 1;

            DELETE FROM dbo.Registros_Matricula WHERE registro_id = @registro_id;

            UPDATE dbo.Asignaturas
            SET    cupos_disponibles = cupos_disponibles + 1
            WHERE  asignatura_id = @asignatura_id;

            INSERT INTO dbo.Auditoria_Matriculas (registro_id, accion, estudiante_id, asignatura_id)
            VALUES (@registro_id, N'RETIRO', @estudiante_id, @asignatura_id);

        COMMIT TRANSACTION;

        SELECT 'OK: retiro realizado' AS resultado, @registro_id AS registro_eliminado;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

/* sp_ReporteCargaDocente: cuantos estudiantes tiene cada docente en todas sus materias. */
CREATE OR ALTER PROCEDURE dbo.sp_ReporteCargaDocente
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        ;WITH por_materia AS (
            SELECT  a.asignatura_id, a.docente, a.cupos_disponibles,
                    ISNULL(i.inscritos, 0) AS inscritos
            FROM    dbo.Asignaturas a
            LEFT JOIN (SELECT asignatura_id, COUNT(*) AS inscritos
                       FROM dbo.Registros_Matricula GROUP BY asignatura_id) i ON i.asignatura_id = a.asignatura_id
        )
        SELECT  docente,
                COUNT(*)               AS materias_a_cargo,
                SUM(inscritos)         AS estudiantes_a_cargo,
                SUM(cupos_disponibles) AS cupos_libres
        FROM    por_materia
        GROUP BY docente
        ORDER BY estudiantes_a_cargo DESC, docente;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

/* ---------- Verificacion del bloque ---------- */
SELECT name AS procedimiento_creado, create_date FROM sys.procedures WHERE is_ms_shipped = 0 ORDER BY name;
GO

/* ======================================================================
   4. TRIGGERS
   ====================================================================== */

/* =====================================================================
   Bloque 4: TRIGGERS
   Los tres estan escritos para trabajar con VARIAS filas a la vez (usan las tablas
   inserted y deleted como conjuntos, no variables escalares).
   ===================================================================== */
USE MatriculaDB_AA2;
GO

/* tr_AuditoriaMatricula_Insert: despues de cada INSERT en Registros_Matricula guarda el log. */
CREATE OR ALTER TRIGGER dbo.tr_AuditoriaMatricula_Insert
ON dbo.Registros_Matricula
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.Auditoria_Matriculas (registro_id, accion, usuario, fecha, estudiante_id, asignatura_id)
    SELECT  i.registro_id, N'MATRICULACIÓN', SUSER_SNAME(), SYSDATETIME(), i.estudiante_id, i.asignatura_id
    FROM    inserted i;
END;
GO

/* tr_ValidarCupoNegativo (INSTEAD OF UPDATE): impide cualquier actualizacion que deje un cupo por debajo de cero.
   Si todo esta bien, aplica el UPDATE por su cuenta (el original queda reemplazado por el trigger). */
CREATE OR ALTER TRIGGER dbo.tr_ValidarCupoNegativo
ON dbo.Asignaturas
INSTEAD OF UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM inserted WHERE cupos_disponibles < 0)
        THROW 50010, 'Operacion rechazada: el cupo de una asignatura no puede ser menor que cero.', 1;

    UPDATE a
    SET    a.nombre_materia    = i.nombre_materia,
           a.docente           = i.docente,
           a.cupos_disponibles = i.cupos_disponibles
    FROM   dbo.Asignaturas a
    JOIN   inserted i ON i.asignatura_id = a.asignatura_id;
END;
GO

/* tr_LogCambioCupo: cuando cambia el cupo de una asignatura (por ejemplo, un administrador lo edita a mano),
   guarda el valor anterior y el nuevo en Historial_Cupos. */
CREATE OR ALTER TRIGGER dbo.tr_LogCambioCupo
ON dbo.Asignaturas
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(cupos_disponibles) RETURN;       -- solo interesa si se toco la columna del cupo

    INSERT INTO dbo.Historial_Cupos (asignatura_id, cupo_anterior, cupo_nuevo, fecha_cambio, usuario)
    SELECT  d.asignatura_id, d.cupos_disponibles, i.cupos_disponibles, SYSDATETIME(), SUSER_SNAME()
    FROM    deleted d
    JOIN    inserted i ON i.asignatura_id = d.asignatura_id
    WHERE   d.cupos_disponibles <> i.cupos_disponibles;
END;
GO

/* ---------- Verificacion del bloque ---------- */
SELECT t.name AS trigger_creado, OBJECT_NAME(t.parent_id) AS tabla,
       CASE WHEN t.is_instead_of_trigger = 1 THEN 'INSTEAD OF' ELSE 'AFTER' END AS momento,
       CASE WHEN OBJECTPROPERTY(t.object_id,'ExecIsInsertTrigger')=1 THEN 'INSERT' ELSE 'UPDATE' END AS evento
FROM sys.triggers t WHERE t.is_ms_shipped = 0 ORDER BY t.name;
GO

/* ======================================================================
   5. PRUEBAS DE EXITO Y DE ERROR (ejecutar en este orden; cada una cambia el estado que usa la siguiente)
   ====================================================================== */


-- ################ T00_objetos ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== Objetos programables creados en MatriculaDB_AA2 ===';
SELECT CASE type WHEN 'V' THEN 'VISTA' WHEN 'FN' THEN 'FUNCION ESCALAR' WHEN 'IF' THEN 'FUNCION DE TABLA' WHEN 'P' THEN 'PROCEDIMIENTO' WHEN 'TR' THEN 'TRIGGER' END AS tipo,
       name AS objeto
FROM sys.objects
WHERE type IN ('V','FN','IF','P','TR')
ORDER BY CASE type WHEN 'V' THEN 1 WHEN 'FN' THEN 2 WHEN 'IF' THEN 3 WHEN 'P' THEN 4 ELSE 5 END, name;

PRINT '=== Tablas de la actividad ===';
SELECT name AS tabla FROM sys.tables ORDER BY name;
GO

-- ################ T01_vistas_estado_inicial ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== Vista_OfertaAcademica (solo materias con cupos > 0) ===';
SELECT * FROM dbo.Vista_OfertaAcademica ORDER BY asignatura_id;

PRINT '=== Vista_DetalleMatricula ===';
SELECT registro_id, estudiante, facultad, materia, fecha_registro, estado FROM dbo.Vista_DetalleMatricula ORDER BY registro_id;

PRINT '=== Vista_EstudiantesSaturados (todavia nadie pasa de 5 materias) ===';
SELECT * FROM dbo.Vista_EstudiantesSaturados;
GO

-- ################ T02_inscripcion_exitosa ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== ANTES: cupos de la materia 1 y registros del estudiante 1 ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;
SELECT COUNT(*) AS registros_del_estudiante_1 FROM dbo.Registros_Matricula WHERE estudiante_id = 1;

PRINT '=== EXEC dbo.sp_InscribirAsignatura @estudiante_id = 1, @asignatura_id = 1 ===';
EXEC dbo.sp_InscribirAsignatura @estudiante_id = 1, @asignatura_id = 1;

PRINT '=== DESPUES: el cupo bajo y el registro existe ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 1;
SELECT registro_id, estudiante_id, asignatura_id, estado FROM dbo.Registros_Matricula WHERE estudiante_id = 1;

PRINT '=== Lo que hicieron los TRIGGERS automaticamente ===';
PRINT 'Auditoria_Matriculas (tr_AuditoriaMatricula_Insert):';
SELECT auditoria_id, registro_id, accion, usuario, fecha, estudiante_id, asignatura_id FROM dbo.Auditoria_Matriculas ORDER BY auditoria_id DESC;
PRINT 'Historial_Cupos (tr_LogCambioCupo):';
SELECT historial_id, asignatura_id, cupo_anterior, cupo_nuevo, fecha_cambio FROM dbo.Historial_Cupos ORDER BY historial_id DESC;
GO

-- ################ T03_saturacion_y_vistas ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== Inscribo al estudiante 1 en las materias 2, 3, 4, 5 y 6 con el procedimiento ===';
EXEC dbo.sp_InscribirAsignatura 1, 2;
EXEC dbo.sp_InscribirAsignatura 1, 3;
EXEC dbo.sp_InscribirAsignatura 1, 4;
EXEC dbo.sp_InscribirAsignatura 1, 5;
EXEC dbo.sp_InscribirAsignatura 1, 6;

PRINT '=== Vista_EstudiantesSaturados (el estudiante 1 ya tiene 6 materias) ===';
SELECT * FROM dbo.Vista_EstudiantesSaturados;

PRINT '=== Vista_DetalleMatricula del estudiante 1 ===';
SELECT registro_id, estudiante, facultad, materia, fecha_registro FROM dbo.Vista_DetalleMatricula WHERE estudiante_id = 1 ORDER BY registro_id;

PRINT '=== Vista_OfertaAcademica despues de las inscripciones ===';
SELECT * FROM dbo.Vista_OfertaAcademica ORDER BY asignatura_id;
GO

-- ################ T04_funciones ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== fn_CalcularCostoMatricula (15 dolares por materia) ===';
SELECT estudiante_id, nombre,
       dbo.fn_CalcularCostoMatricula(estudiante_id) AS costo_a_pagar
FROM dbo.Estudiantes ORDER BY estudiante_id;

PRINT '=== fn_VerificarDisponibilidad (1 = hay cupos, 0 = no hay) ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles,
       dbo.fn_VerificarDisponibilidad(asignatura_id) AS hay_cupo
FROM dbo.Asignaturas ORDER BY asignatura_id;
SELECT dbo.fn_VerificarDisponibilidad(99) AS asignatura_inexistente_99;

PRINT '=== fn_ListaClase (funcion de tabla) ===';
PRINT 'Lista de la asignatura 1:';
SELECT * FROM dbo.fn_ListaClase(1);
PRINT 'Lista de la asignatura 7:';
SELECT * FROM dbo.fn_ListaClase(7);
GO

-- ################ T05_retiro_y_reporte ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== ANTES del retiro: costo del estudiante 1 y cupos de la materia 6 ===';
SELECT dbo.fn_CalcularCostoMatricula(1) AS costo_antes;
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 6;

PRINT '=== EXEC dbo.sp_RetirarAsignatura @estudiante_id = 1, @asignatura_id = 6 ===';
EXEC dbo.sp_RetirarAsignatura @estudiante_id = 1, @asignatura_id = 6;

PRINT '=== DESPUES: cupo devuelto, costo menor y deja de estar saturado ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id = 6;
SELECT dbo.fn_CalcularCostoMatricula(1) AS costo_despues;
SELECT COUNT(*) AS estudiantes_saturados FROM dbo.Vista_EstudiantesSaturados;

PRINT '=== Auditoria: ultimas acciones (el retiro lo registra el procedimiento) ===';
SELECT TOP 3 auditoria_id, registro_id, accion, usuario, fecha, estudiante_id, asignatura_id FROM dbo.Auditoria_Matriculas ORDER BY auditoria_id DESC;

PRINT '=== EXEC dbo.sp_ReporteCargaDocente ===';
EXEC dbo.sp_ReporteCargaDocente;
GO

-- ################ T06_pruebas_de_error ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
DECLARE @msg NVARCHAR(400);

PRINT '--- Error 1: matricular en una materia SIN cupos (materia 7) con el procedimiento ---';
BEGIN TRY EXEC dbo.sp_InscribirAsignatura 5, 7; END TRY
BEGIN CATCH PRINT 'RECHAZADO -> ' + ERROR_MESSAGE(); END CATCH

PRINT '--- Error 2: matricula duplicada (estudiante 1 ya esta en la materia 1) ---';
BEGIN TRY EXEC dbo.sp_InscribirAsignatura 1, 1; END TRY
BEGIN CATCH PRINT 'RECHAZADO -> ' + ERROR_MESSAGE(); END CATCH

PRINT '--- Error 3: estudiante inexistente (99) ---';
BEGIN TRY EXEC dbo.sp_InscribirAsignatura 99, 1; END TRY
BEGIN CATCH PRINT 'RECHAZADO -> ' + ERROR_MESSAGE(); END CATCH

PRINT '--- Error 4: retirar a quien no esta matriculado ---';
BEGIN TRY EXEC dbo.sp_RetirarAsignatura 6, 3; END TRY
BEGIN CATCH PRINT 'RECHAZADO -> ' + ERROR_MESSAGE(); END CATCH

PRINT '--- Error 5: un administrador intenta dejar el cupo de la materia 3 en -1 (tr_ValidarCupoNegativo) ---';
BEGIN TRY UPDATE dbo.Asignaturas SET cupos_disponibles = -1 WHERE asignatura_id = 3; END TRY
BEGIN CATCH PRINT 'TRIGGER -> ' + ERROR_MESSAGE(); END CATCH

PRINT '--- Error 6: matricula "a mano" sin usar el procedimiento, en la materia 7 (0 cupos) ---';
BEGIN TRY
    BEGIN TRANSACTION;
        INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (5, 7, 'CONFIRMADA');
        UPDATE dbo.Asignaturas SET cupos_disponibles = cupos_disponibles - 1 WHERE asignatura_id = 7;   -- el trigger lo impide
    COMMIT;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    PRINT 'TRIGGER -> ' + ERROR_MESSAGE() + '  (se hizo ROLLBACK del INSERT tambien)';
END CATCH

PRINT '=== Verificacion: nada cambio por los intentos fallidos ===';
SELECT asignatura_id, nombre_materia, cupos_disponibles FROM dbo.Asignaturas WHERE asignatura_id IN (3, 7);
SELECT COUNT(*) AS registros_del_estudiante_5_en_materia_7 FROM dbo.Registros_Matricula WHERE estudiante_id = 5 AND asignatura_id = 7;
GO

-- ################ T07_trigger_cambio_manual_cupo ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
PRINT '=== Historial_Cupos ANTES (solo lo que hicieron los procedimientos) ===';
SELECT COUNT(*) AS filas_historial FROM dbo.Historial_Cupos;

PRINT '=== Un administrador cambia a mano el cupo de la materia 7 (0 -> 12) ===';
UPDATE dbo.Asignaturas SET cupos_disponibles = 12 WHERE asignatura_id = 7;

PRINT '=== Un UPDATE de varias filas (todas las materias del Docente A, +2 cupos) ===';
UPDATE dbo.Asignaturas SET cupos_disponibles = cupos_disponibles + 2 WHERE docente = N'Docente A';

PRINT '=== Un UPDATE que NO toca el cupo (cambia solo el docente) no deja huella ===';
UPDATE dbo.Asignaturas SET docente = N'Docente A' WHERE asignatura_id = 1;

PRINT '=== Historial_Cupos: valor anterior y nuevo de cada cambio manual ===';
SELECT h.historial_id, h.asignatura_id, a.nombre_materia, h.cupo_anterior, h.cupo_nuevo, h.fecha_cambio
FROM dbo.Historial_Cupos h JOIN dbo.Asignaturas a ON a.asignatura_id = h.asignatura_id
WHERE h.historial_id > (SELECT MAX(historial_id) - 3 FROM dbo.Historial_Cupos)
ORDER BY h.historial_id;

-- restablezco el cupo de la materia 7 para no alterar las demas pruebas
UPDATE dbo.Asignaturas SET cupos_disponibles = 0 WHERE asignatura_id = 7;
GO

/* ======================================================================
   6. INNOVACION: indices de auditoria, seguridad frente a inyeccion SQL, costo de los triggers con 20 000 estudiantes y funcion de tabla frente a vista
   ====================================================================== */


-- ################ T11_innovacion_indice_auditoria ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
/* Innovacion: indice IX_Auditoria_estudiante. Se llena la auditoria con 20 000 matriculas (los triggers hacen el trabajo)
   y se consulta la historia de UN estudiante: primero forzando a leer toda la tabla y luego con el indice. */
BEGIN TRANSACTION;

INSERT INTO dbo.Estudiantes (nombre, cedula, facultad)
SELECT TOP (20000) N'Prueba ' + CAST(x.n AS NVARCHAR(10)), RIGHT('0000000000' + CAST(3000000 + x.n AS VARCHAR(10)), 10), N'Ingeniería'
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;

INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)      -- el trigger genera 20 000 filas de auditoria
SELECT estudiante_id, 8, 'CONFIRMADA' FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %';

SELECT COUNT(*) AS filas_en_auditoria FROM dbo.Auditoria_Matriculas;
DECLARE @est INT = (SELECT MIN(estudiante_id) + 15000 FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');

SET STATISTICS IO ON;
PRINT '=== SIN usar el indice (se fuerza a leer toda la tabla por su clave primaria) ===';
SELECT auditoria_id, registro_id, accion, fecha FROM dbo.Auditoria_Matriculas WITH (INDEX(PK_Auditoria)) WHERE estudiante_id = @est;

PRINT '=== CON el indice IX_Auditoria_estudiante ===';
SELECT auditoria_id, registro_id, accion, fecha FROM dbo.Auditoria_Matriculas WITH (INDEX(IX_Auditoria_estudiante)) WHERE estudiante_id = @est;
SET STATISTICS IO OFF;

ROLLBACK TRANSACTION;
PRINT 'ROLLBACK ejecutado: la base quedo igual que antes de la prueba.';
GO

-- ################ T08_seguridad_inyeccion_sql ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
/* ---- Entrada maliciosa tipica de un ataque de inyeccion SQL ---- */
DECLARE @entrada NVARCHAR(100) = N'x'' OR ''1''=''1';
PRINT 'Texto que escribe el atacante en el formulario: ' + @entrada;

PRINT '';
PRINT '=== A) Consulta VULNERABLE: el texto se pega dentro de la sentencia ===';
DECLARE @sql NVARCHAR(400) = N'SELECT nombre, cedula FROM dbo.Estudiantes WHERE nombre = ''' + @entrada + N'''';
PRINT 'Sentencia que llega al motor: ' + @sql;
EXEC (@sql);                       -- devuelve a TODOS los estudiantes (fuga de datos)

PRINT '=== B) Misma busqueda CON PARAMETRO (como trabajan los procedimientos) ===';
EXEC sp_executesql N'SELECT nombre, cedula FROM dbo.Estudiantes WHERE nombre = @n', N'@n NVARCHAR(100)', @n = @entrada;
PRINT '(0 filas: el texto se trata como un dato, nunca como codigo)';

PRINT '';
PRINT '=== C) Ataque contra el procedimiento: se intenta colar un DROP TABLE en el parametro ===';
BEGIN TRY
    EXEC dbo.sp_InscribirAsignatura @estudiante_id = '1; DROP TABLE dbo.Estudiantes; --', @asignatura_id = 1;
END TRY
BEGIN CATCH
    PRINT 'RECHAZADO -> ' + ERROR_MESSAGE();
END CATCH
SELECT COUNT(*) AS estudiantes_que_siguen_existiendo FROM dbo.Estudiantes;

PRINT '';
PRINT '=== D) Permisos: un usuario de secretaria solo puede EJECUTAR procedimientos ===';
IF DATABASE_PRINCIPAL_ID('usr_secretaria') IS NOT NULL DROP USER usr_secretaria;
CREATE USER usr_secretaria WITHOUT LOGIN;
GRANT EXECUTE ON dbo.sp_InscribirAsignatura TO usr_secretaria;
GRANT EXECUTE ON dbo.sp_RetirarAsignatura  TO usr_secretaria;
GRANT SELECT  ON dbo.Vista_OfertaAcademica TO usr_secretaria;

EXECUTE AS USER = 'usr_secretaria';
    PRINT 'Como usr_secretaria, UPDATE directo sobre la tabla:';
    BEGIN TRY UPDATE dbo.Asignaturas SET cupos_disponibles = 999 WHERE asignatura_id = 1; END TRY
    BEGIN CATCH PRINT 'DENEGADO -> ' + ERROR_MESSAGE(); END CATCH
    PRINT 'Como usr_secretaria, ejecutar el procedimiento autorizado:';
    EXEC dbo.sp_InscribirAsignatura 6, 8;
REVERT;
DROP USER usr_secretaria;
GO

-- ################ T09_rendimiento_triggers_20000 ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
/* Simulacion de la hora pico con 20 000 estudiantes. Todo ocurre dentro de una transaccion que se
   revierte al final, asi la base de datos queda como estaba. */
DECLARE @t0 DATETIME2, @ms_con INT, @ms_sin INT, @ms_lote INT, @ms_lote_sin INT, @n INT = 20000;

BEGIN TRANSACTION;

-- 20 000 estudiantes de prueba
INSERT INTO dbo.Estudiantes (nombre, cedula, facultad)
SELECT TOP (@n) N'Prueba ' + CAST(x.n AS NVARCHAR(10)), RIGHT('0000000000' + CAST(1000000 + x.n AS VARCHAR(10)), 10), N'Ingeniería'
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;

-- Matriculas UNA por UNA (como llegan en la hora pico) CON el trigger de auditoria activo
DECLARE @i INT = (SELECT MIN(estudiante_id) FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');
DECLARE @fin INT = @i + @n - 1;
SET @t0 = SYSDATETIME();
WHILE @i <= @fin
BEGIN
    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (@i, 8, 'CONFIRMADA');
    SET @i += 1;
END
SET @ms_con = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
DECLARE @aud_con INT = (SELECT COUNT(*) FROM dbo.Auditoria_Matriculas);

-- Limpio y repito SIN el trigger
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 8 AND estudiante_id >= (SELECT MIN(estudiante_id) FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');
DISABLE TRIGGER dbo.tr_AuditoriaMatricula_Insert ON dbo.Registros_Matricula;
SET @i = (SELECT MIN(estudiante_id) FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');
SET @t0 = SYSDATETIME();
WHILE @i <= @fin
BEGIN
    INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado) VALUES (@i, 8, 'CONFIRMADA');
    SET @i += 1;
END
SET @ms_sin = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

-- Insercion en LOTE (una sola sentencia con 20 000 filas): sin y con trigger
DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 8 AND estudiante_id >= (SELECT MIN(estudiante_id) FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');
SET @t0 = SYSDATETIME();
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
SELECT estudiante_id, 8, 'CONFIRMADA' FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %';
SET @ms_lote_sin = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

DELETE FROM dbo.Registros_Matricula WHERE asignatura_id = 8 AND estudiante_id >= (SELECT MIN(estudiante_id) FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %');
ENABLE TRIGGER dbo.tr_AuditoriaMatricula_Insert ON dbo.Registros_Matricula;
SET @t0 = SYSDATETIME();
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
SELECT estudiante_id, 8, 'CONFIRMADA' FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %';
SET @ms_lote = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());

SELECT  @n AS matriculas,
        @ms_sin AS ms_una_por_una_SIN_trigger,
        @ms_con AS ms_una_por_una_CON_trigger,
        @ms_con - @ms_sin AS sobrecosto_ms,
        CAST(100.0 * (@ms_con - @ms_sin) / NULLIF(@ms_sin, 0) AS DECIMAL(6,1)) AS sobrecosto_pct,
        CAST(1.0 * (@ms_con - @ms_sin) / @n AS DECIMAL(8,4)) AS ms_extra_por_matricula;
SELECT  @ms_lote_sin AS ms_en_lote_SIN_trigger, @ms_lote AS ms_en_lote_CON_trigger;
SELECT  @aud_con AS filas_de_auditoria_generadas_en_la_1ra_prueba;

ROLLBACK TRANSACTION;
PRINT 'ROLLBACK ejecutado: la base quedo igual que antes de la prueba.';
SELECT COUNT(*) AS estudiantes_despues_del_rollback FROM dbo.Estudiantes;
GO

-- ################ T10_funcion_de_tabla_vs_vista ################
USE MatriculaDB_AA2;
SET NOCOUNT ON;
/* Comparacion con volumen: la lista de clase de una materia con 20 000 inscritos, obtenida
   (A) con la funcion de tabla fn_ListaClase y (B) filtrando la vista Vista_DetalleMatricula.
   Se hace dentro de una transaccion que se revierte al final. */
BEGIN TRANSACTION;

INSERT INTO dbo.Estudiantes (nombre, cedula, facultad)
SELECT TOP (20000) N'Prueba ' + CAST(x.n AS NVARCHAR(10)), RIGHT('0000000000' + CAST(2000000 + x.n AS VARCHAR(10)), 10), N'Ingeniería'
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b) x;

DISABLE TRIGGER dbo.tr_AuditoriaMatricula_Insert ON dbo.Registros_Matricula;   -- solo para cargar rapido los datos de prueba
INSERT INTO dbo.Registros_Matricula (estudiante_id, asignatura_id, estado)
SELECT estudiante_id, 8, 'CONFIRMADA' FROM dbo.Estudiantes WHERE nombre LIKE N'Prueba %';
ENABLE TRIGGER dbo.tr_AuditoriaMatricula_Insert ON dbo.Registros_Matricula;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

PRINT '=== A) Funcion de tabla: SELECT estudiante, cedula FROM dbo.fn_ListaClase(8) ===';
SELECT estudiante, cedula INTO #a FROM dbo.fn_ListaClase(8);

PRINT '=== B) Vista: SELECT ... FROM dbo.Vista_DetalleMatricula WHERE asignatura_id = 8 ===';
SELECT estudiante, estudiante_id INTO #b FROM dbo.Vista_DetalleMatricula WHERE asignatura_id = 8;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
SELECT (SELECT COUNT(*) FROM #a) AS filas_funcion, (SELECT COUNT(*) FROM #b) AS filas_vista;

DROP TABLE #a, #b;
ROLLBACK TRANSACTION;
PRINT 'ROLLBACK ejecutado: la base quedo igual que antes de la prueba.';
GO

-- ################ 05_innovacion_reporte_historial (procedimiento extra de innovacion) ################
USE MatriculaDB_AA2;
GO
/* Innovacion funcional: sp_ReporteHistorialCupos.
   Historial_Cupos guarda TODO cambio de cupo (matriculas, retiros y ajustes de un administrador). Este reporte
   los separa por origen probable (segun cuanto cambio el cupo) para ver rapido cuales fueron ajustes manuales.
   Parametro opcional: sin valor muestra todas las asignaturas; con un id, solo esa. */
CREATE OR ALTER PROCEDURE dbo.sp_ReporteHistorialCupos
    @asignatura_id INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        IF @asignatura_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Asignaturas WHERE asignatura_id = @asignatura_id)
            THROW 50020, 'La asignatura indicada no existe.', 1;

        ;WITH cambios AS (
            SELECT  h.historial_id, h.asignatura_id, h.cupo_anterior, h.cupo_nuevo, h.fecha_cambio,
                    h.cupo_nuevo - h.cupo_anterior AS diferencia,
                    CASE h.cupo_nuevo - h.cupo_anterior
                         WHEN -1 THEN N'Matricula'
                         WHEN  1 THEN N'Retiro'
                         ELSE N'Ajuste manual' END AS origen_probable
            FROM    dbo.Historial_Cupos h
            WHERE   @asignatura_id IS NULL OR h.asignatura_id = @asignatura_id
        )
        SELECT  c.historial_id, a.nombre_materia AS materia, c.cupo_anterior AS antes, c.cupo_nuevo AS despues,
                c.diferencia, c.origen_probable, c.fecha_cambio
        FROM    cambios c
        JOIN    dbo.Asignaturas a ON a.asignatura_id = c.asignatura_id
        WHERE   c.origen_probable = N'Ajuste manual'
        ORDER BY c.historial_id;

        SELECT  CASE h.cupo_nuevo - h.cupo_anterior WHEN -1 THEN N'Matricula' WHEN 1 THEN N'Retiro' ELSE N'Ajuste manual' END AS origen,
                COUNT(*) AS cambios
        FROM    dbo.Historial_Cupos h
        WHERE   @asignatura_id IS NULL OR h.asignatura_id = @asignatura_id
        GROUP BY CASE h.cupo_nuevo - h.cupo_anterior WHEN -1 THEN N'Matricula' WHEN 1 THEN N'Retiro' ELSE N'Ajuste manual' END
        ORDER BY cambios DESC;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

SET NOCOUNT ON;
PRINT '=== Reporte de todas las asignaturas: ajustes manuales y resumen por origen ===';
EXEC dbo.sp_ReporteHistorialCupos;
PRINT '=== Solo la asignatura 7 (Estadistica) ===';
EXEC dbo.sp_ReporteHistorialCupos @asignatura_id = 7;
PRINT '=== Prueba de error: asignatura 99 no existe ===';
BEGIN TRY
    EXEC dbo.sp_ReporteHistorialCupos @asignatura_id = 99;
END TRY
BEGIN CATCH
    PRINT 'Rechazado: ' + ERROR_MESSAGE();
END CATCH
GO
